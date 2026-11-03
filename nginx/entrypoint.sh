#!/bin/sh

set -e

PUBLIC_IP="${PUBLIC_IP:-}"
EMAIL="${LETSENCRYPT_EMAIL:-admin@example.com}"
DOMAIN="${PUBLIC_IP}.nip.io"

CERT_DIR="/etc/letsencrypt/live/$DOMAIN"
# Function to start nginx
start_nginx() {
    echo "Starting nginx..."
    exec nginx -g "daemon off;"
}

# Generate nginx config with SSL if we have a domain/IP
if [ -n "$PUBLIC_IP" ]; then
    cat > /etc/nginx/conf.d/nextcloud.conf << EOF
server {
    listen 80;
    server_name ${PUBLIC_IP} ${PUBLIC_IP}.nip.io ${PUBLIC_IP}.sslip.io localhost;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name ${PUBLIC_IP} ${PUBLIC_IP}.nip.io ${PUBLIC_IP}.sslip.io localhost;

    ssl_certificate /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;

    client_max_body_size 10G;

    location / {
        proxy_pass http://app:80;

        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        proxy_request_buffering off;
        proxy_buffering off;

        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
    }
}
EOF
else
    cat > /etc/nginx/conf.d/nextcloud.conf << EOF
server {
    listen 80;
    server_name _;

    client_max_body_size 10G;

    location / {
        proxy_pass http://app:80;

        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        proxy_request_buffering off;
        proxy_buffering off;

        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
    }
}
EOF
    start_nginx
fi

# Production mode: manage certificates for IP-based domain
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

    # Create a temporary HTTP config for certbot
    cat > /etc/nginx/conf.d/nextcloud.conf << EOF
server {
    listen 80;
    server_name ${PUBLIC_IP} ${PUBLIC_IP}.nip.io ${PUBLIC_IP}.sslip.io localhost;
    client_max_body_size 10G;
    location / {
        proxy_pass http://app:80;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

    # Start nginx in background
    nginx -g "daemon off;" &
    NGINX_PID=$!

    # Wait for nginx to start
    sleep 2

    # Run certbot with the nginx plugin
    echo "Requesting certificate for $DOMAIN..."
    certbot certonly \
        --nginx \
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

    echo "Certificate obtained successfully"

    # Stop background nginx
    kill $NGINX_PID 2>/dev/null || true
    wait $NGINX_PID 2>/dev/null || true

    # Generate final config with SSL
    cat > /etc/nginx/conf.d/nextcloud.conf << EOF
server {
    listen 80;
    server_name ${PUBLIC_IP} ${PUBLIC_IP}.nip.io ${PUBLIC_IP}.sslip.io localhost;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name ${PUBLIC_IP} ${PUBLIC_IP}.nip.io ${PUBLIC_IP}.sslip.io localhost;

    ssl_certificate /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;

    client_max_body_size 10G;

    location / {
        proxy_pass http://app:80;

        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        proxy_request_buffering off;
        proxy_buffering off;

        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
    }
}
EOF

    # Start nginx normally
    start_nginx
fi
