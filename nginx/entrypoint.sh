#!/bin/sh

set -e

PUBLIC_IP="${PUBLIC_IP:-}"
DOMAIN="${DOMAIN}"
if [ -z "$DOMAIN" ]; then
	DOMAIN="${PUBLIC_IP}.nip.io"
fi

if [ -z "$DOMAIN" ]; then
    echo "No PUBLIC_IP or DOMAIN set."
    exit 1
fi

EMAIL="${LETSENCRYPT_EMAIL:-admin@example.com}"
CERT_DIR="/etc/letsencrypt/live/$DOMAIN"

DYNAMIC_DIR="/etc/nginx/nextcloud"
HTTP_ENABLED_DIR="$DYNAMIC_DIR/enabled/http"
HTTPS_ENABLED_DIR="$DYNAMIC_DIR/enabled/https"
CERT_LINK_DIR="$DYNAMIC_DIR/certs"
SNIPPET_DIR="/etc/nginx/conf.d"

start_nginx() {
    echo "Starting nginx..."
    exec nginx -g "daemon off;"
}

has_certificate() {
    [ -n "$DOMAIN" ] &&
        [ -f "$CERT_DIR/fullchain.pem" ] &&
        [ -f "$CERT_DIR/privkey.pem" ]
}

# Create server_name alias
if [ -n "$DOMAIN" ]; then
    server_names="$DOMAIN localhost"
else
    server_names="localhost"
fi
mkdir -p "$DYNAMIC_DIR"
printf 'server_name %s;\n' "$server_names" > "$DYNAMIC_DIR/server_name.conf"

# Link server config
mkdir -p "$CERT_LINK_DIR"
ln -sf "$CERT_DIR/fullchain.pem" "$CERT_LINK_DIR/fullchain.pem"
ln -sf "$CERT_DIR/privkey.pem" "$CERT_LINK_DIR/privkey.pem"
ln -sf /etc/nginx/nextcloud.conf /etc/nginx/sites-enabled/nextcloud

# Cert renewal
echo "Checking for existing certificates..."
if has_certificate; then
    echo "Certificate found for $DOMAIN"
    certbot renew --quiet --agree-tos --non-interactive 2>/dev/null || true
else
    echo "No certificate found. Preparing for certificate issuance..."
    nginx -t 2>&1 || true
    nginx -g "daemon off;" &
    NGINX_PID=$!
    sleep 3
    echo "Requesting certificate for $DOMAIN..."
    certbot certonly \
        --webroot \
        -w /var/www/html \
        -d "$DOMAIN" \
        --email "$EMAIL" \
        --agree-tos \
        --non-interactive \
        --no-eff-email \
        2>&1 || {
        echo "Failed to obtain certificate"
        kill $NGINX_PID 2>/dev/null || true
        exit 1
    }
    kill $NGINX_PID 2>/dev/null || true
    wait $NGINX_PID 2>/dev/null || true
fi

echo "Starting nginx with HTTPS..."
nginx -t 2>&1 || true
start_nginx
