#!/bin/sh

set -e

PUBLIC_IP="${PUBLIC_IP:-}"
EMAIL="${LETSENCRYPT_EMAIL:-admin@example.com}"
DOMAIN="${PUBLIC_IP}.nip.io"

CERT_DIR="/etc/letsencrypt/live/$DOMAIN"

start_nginx() {
    echo "Starting nginx..."
    exec nginx -g "daemon off;"
}

if [ -z "$PUBLIC_IP" ]; then
    echo "No PUBLIC_IP set, starting nginx with static config..."
    start_nginx
fi

generate_config() {
    if [ -f "$CERT_DIR/fullchain.pem" ] && [ -f "$CERT_DIR/privkey.pem" ]; then
        SSL_AVAILABLE=1
    else
        SSL_AVAILABLE=0
    fi

    cat > /etc/nginx/conf.d/nextcloud.conf << EOF
upstream php-handler {
    server app:9000;
}

server {
    listen 80;
    server_name ${PUBLIC_IP} ${PUBLIC_IP}.nip.io ${PUBLIC_IP}.sslip.io localhost;
    server_tokens off;
    root /var/www/html;
    client_max_body_size 10G;
    types {
        application/octet-stream bin;
    }
    default_type application/octet-stream;

    location ^~ /.well-known/acme-challenge/ {
        try_files \$uri =404;
    }

    location / {
EOF
    if [ "$SSL_AVAILABLE" -eq 1 ]; then
        cat >> /etc/nginx/conf.d/nextcloud.conf << EOF
        return 301 https://\$host\$request_uri;
    }

    location ~ \.php(?:\$|/) {
        return 404;
    }
EOF
    else
        cat >> /etc/nginx/conf.d/nextcloud.conf << EOF
        try_files \$uri \$uri/ /index.php\$request_uri;
    }

    location ~ \.php(?:\$|/) {
        fastcgi_split_path_info ^(.+?\.php)(/.*)\$;
        set \$path_info \$fastcgi_path_info;
        try_files \$fastcgi_script_name =404;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param PATH_INFO \$path_info;
        fastcgi_param HTTPS \$https if_not_empty;
        fastcgi_pass php-handler;
        fastcgi_intercept_errors on;
        fastcgi_request_buffering off;
    }
EOF
    fi
    cat >> /etc/nginx/conf.d/nextcloud.conf << EOF
}
EOF

    if [ "$SSL_AVAILABLE" -eq 1 ]; then
        cat >> /etc/nginx/conf.d/nextcloud.conf << EOF

server {
    listen 443 ssl;
    http2 on;
    server_name ${PUBLIC_IP} ${PUBLIC_IP}.nip.io ${PUBLIC_IP}.sslip.io localhost;

    ssl_certificate /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    server_tokens off;

    root /var/www/html;
    client_max_body_size 10G;
    client_body_timeout 3600s;
    fastcgi_buffers 64 4K;
    types {
        application/octet-stream bin;
    }
    default_type application/octet-stream;

    gzip on;
    gzip_vary on;
    gzip_comp_level 4;
    gzip_min_length 256;
    gzip_proxied expired no-cache no-store private no_last_modified no_etag auth;
    gzip_types application/atom+xml text/javascript application/javascript application/json application/ld+json application/manifest+json application/rss+xml application/vnd.geo+json application/vnd.ms-fontobject application/wasm application/x-font-ttf application/x-web-app-manifest+json font/opentype image/bmp image/svg+xml image/x-icon text/cache-manifest text/css text/plain text/vcard text/vnd.rim.location.xloc text/vtt text/x-component text/x-cross-domain-policy;

    add_header Referrer-Policy                   "no-referrer"       always;
    add_header X-Content-Type-Options            ""                  always;
    add_header X-Download-Options               "noopen"            always;
    add_header X-Frame-Options                  "SAMEORIGIN"        always;
    add_header X-Permitted-Cross-Domain-Policies "none"              always;
    add_header X-Robots-Tag                     "noindex, nofollow" always;
    add_header Strict-Transport-Security        "max-age=31536000; includeSubDomains" always;

    fastcgi_hide_header X-Powered-By;

    index index.php index.html /index.php\$request_uri;

    location = / {
        if ( \$http_user_agent ~ ^DavClnt ) {
            return 302 /remote.php/webdav/\$is_args\$args;
        }
    }

    location = /robots.txt {
        allow all;
        log_not_found off;
        access_log off;
    }

    location ^~ /.well-known {
        allow all;
        location ~ ^/\.well-known/(?:carddav|caldav) {
            return 301 \$scheme://\$host/remote.php/dav;
        }
        location ~ ^/\.well-known/(?:acme-challenge|pki-validation) {
            try_files \$uri \$uri/ =404;
        }
        try_files \$uri \$uri/ =404;
    }

    location ~ ^/(?:build|tests|config|lib|3rdparty|templates|data)(?:\$|/)  {
        return 404;
    }
    location ~ ^/(?:\.|autotest|occ|issue|indie|db_|console) {
        return 404;
    }

    location ~ \.php(?:\$|/) {
        rewrite ^/(?!index|remote|public|cron|core\/ajax\/update|status|ocs\/v[12]|updater\/.+|ocs-provider\/.+|.+\/richdocumentscode(_arm64)?\/proxy) /index.php\$request_uri;
        fastcgi_split_path_info ^(.+?\.php)(/.*)\$;
        set \$path_info \$fastcgi_path_info;
        try_files \$fastcgi_script_name =404;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param PATH_INFO \$path_info;
        fastcgi_param HTTPS on;
        fastcgi_param modHeadersAvailable true;
        fastcgi_param front_controller_active true;
        fastcgi_pass php-handler;
        fastcgi_intercept_errors on;
        fastcgi_request_buffering off;
        fastcgi_max_temp_file_size 0;
    }

    location ~ \.(?:css|js|mjs|svg|gif|png|jpg|ico|wasm|tflite|map|ogg|flac)\$ {
        try_files \$uri /index.php\$request_uri;
        add_header Cache-Control                     "public, max-age=15778463, immutable";
        add_header Referrer-Policy                   "no-referrer"       always;
        add_header X-Content-Type-Options            "";
        add_header X-Download-Options               "noopen"            always;
        add_header X-Frame-Options                  "SAMEORIGIN"        always;
        add_header X-Permitted-Cross-Domain-Policies "none"              always;
        add_header X-Robots-Tag                     "noindex, nofollow" always;
        add_header Strict-Transport-Security        "max-age=31536000; includeSubDomains" always;
        access_log off;
    }

    location ~ \.woff2?\$ {
        try_files \$uri /index.php\$request_uri;
        expires 7d;
        access_log off;
    }

    location /remote {
        return 301 \$scheme://\$host/remote.php\$request_uri;
    }

    location / {
        try_files \$uri \$uri/ /index.php\$request_uri;
    }
}
EOF
    fi
}

rm -f /etc/nginx/conf.d/*.conf.bak /etc/nginx/conf.d/default.conf 2>/dev/null || true

echo "Checking for existing certificates..."
if [ -f "$CERT_DIR/fullchain.pem" ] && [ -f "$CERT_DIR/privkey.pem" ]; then
    echo "Certificate found for $DOMAIN"
    certbot renew --quiet --agree-tos --non-interactive 2>/dev/null || true
else
    echo "No certificate found. Preparing for certificate issuance..."
    generate_config
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

echo "Applying configuration..."
generate_config
nginx -t 2>&1 || true
start_nginx
