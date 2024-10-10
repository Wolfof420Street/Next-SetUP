#!/bin/bash

# Check if domain name is passed as an argument
if [ $# -lt 1 ]; then
    echo "Usage: $0 <domain_name>"
    exit 1
fi

# Variables
DOMAIN_NAME=$1
GITHUB_REPO_URL="git@github.com:Wolfof420Street/Phishing-clone.git"
NEXT_APP_DIR="/var/www/nextapp"
VPS_IP=$(curl -s http://checkip.amazonaws.com)
PORT=$(shuf -i 3000-3999 -n 1)

# Update system and install dependencies
apt update && apt upgrade -y
apt install -y git curl nginx build-essential ufw

# Install Node.js (if not installed)
if ! command -v node &> /dev/null; then
    curl -fsSL https://deb.nodesource.com/setup_16.x | bash -
    apt install -y nodejs
fi

# Install PM2 globally for running the Node app
npm install -g pm2

# Clone the private GitHub repository (using deploy key for access)
if [ -d "$NEXT_APP_DIR" ]; then
    echo "Directory $NEXT_APP_DIR already exists. Pulling latest changes."
    cd $NEXT_APP_DIR
    git pull
else
    echo "Cloning repository..."
    mkdir -p ~/.ssh
    echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIE7/3PWrQ21afYBC0jcgGJZM5FtgC0J9hFhR0zyHvN+G billodida420@gmail.com" > ~/.ssh/id_ed25519
    chmod 600 ~/.ssh/id_ed25519
    ssh-keyscan github.com >> ~/.ssh/known_hosts
    eval "$(ssh-agent -s)"
    ssh-add ~/.ssh/id_ed25519

    if ! git clone $GITHUB_REPO_URL $NEXT_APP_DIR; then
        echo "Failed to clone repository"
        exit 1
    fi
fi

cd $NEXT_APP_DIR

# Install Node.js dependencies
npm install

# Build the Next.js application
npm run build
if [ $? -ne 0 ]; then
    echo "Failed to build the Next.js app"
    exit 1
fi

# Set up Nginx reverse proxy
cat > /etc/nginx/sites-available/$DOMAIN_NAME <<EOL
server {
    listen 80;
    server_name $DOMAIN_NAME www.$DOMAIN_NAME;

    location / {
        proxy_pass http://localhost:$PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
    }

    location /_next/static {
        alias $NEXT_APP_DIR/.next/static;
        expires 1y;
        access_log off;
    }

    location /public {
        alias $NEXT_APP_DIR/public;
        expires 1y;
        access_log off;
    }
}
EOL

# Enable Nginx site and restart
ln -s /etc/nginx/sites-available/$DOMAIN_NAME /etc/nginx/sites-enabled/
nginx -t && systemctl restart nginx

# Set up UFW firewall
ufw allow OpenSSH
ufw allow 'Nginx Full'
ufw --force enable

# Start the Node.js app with PM2
pm2 start npm --name "$DOMAIN_NAME" -- start -- --port $PORT
pm2 startup systemd -u $(whoami) --hp $(eval echo ~$USER)
pm2 save

# Install and set up SSL with Certbot
apt install -y certbot python3-certbot-nginx
certbot --nginx -d $DOMAIN_NAME -d www.$DOMAIN_NAME --non-interactive --agree-tos --email admin@$DOMAIN_NAME

# Add cron job for Certbot renewals
echo "0 0 * * * certbot renew --quiet" | crontab -

echo "Setup complete! Your NextJS app should now be running at https://$DOMAIN_NAME"
