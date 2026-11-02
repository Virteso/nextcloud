#!/bin/sh

set -e

DOMAIN="${LETSENCRYPT_DOMAIN:-example.com}"
CERT_DIR="/etc/letsencrypt/live/$DOMAIN"
EMAIL="${LETSENCRYPT_EMAIL:-admin@example.com}"
# Function to start nginx
start_nginx() {
    echo "Starting nginx..."
    exec nginx -g "daemon off;"
}

# Production mode: manage certificates
echo "Managing certificates..."

# Check if certificate exists and is valid
if [ -f "$CERT_DIR/fullchain.pem" ] && [ -f "$CERT_DIR/privkey.pem" ]; then
    echo "Certificate found for $DOMAIN"

    # Try to renew certificate (runs renewal checks, only renews if needed)
    echo "Checking certificate renewal..."
    certbot renew \
        --nginx \
        --quiet \
        --agree-tos \
        --non-interactive \
        2>/dev/null || true

    start_nginx
else
    echo "No certificate found. Starting temporary nginx for certificate generation..."

    # Start nginx in background so certbot-nginx can inspect and update the live server config
    nginx -g "daemon off;" &
    NGINX_PID=$!

    # Wait for nginx to start
    sleep 2

    # Run certbot with the nginx plugin
    echo "Requesting certificate for $DOMAIN..."
    certbot certonly \
        --nginx \
        -d "$DOMAIN" \
        -d "www.$DOMAIN" \
        --email "$EMAIL" \
        --agree-tos \
        --non-interactive \
        --no-eff-email \
        2>&1 || {
        echo "Failed to obtain certificate"
        kill $NGINX_PID 2>/dev/null || true
        exit 1
    }

    echo "Certificate obtained successfully"

    # Stop background nginx
    kill $NGINX_PID 2>/dev/null || true
    wait $NGINX_PID 2>/dev/null || true

    # Start nginx normally
    start_nginx
fi
