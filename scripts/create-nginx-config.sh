#!/bin/bash
set -e

echo "Zulip Nginx Configuration Creator"
echo "================================="

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi

# Default paths
NGINX_AVAILABLE_DIR="/etc/nginx/sites-available"
NGINX_ENABLED_DIR="/etc/nginx/sites-enabled"
ZULIP_CONF="${NGINX_AVAILABLE_DIR}/zulip"
DOMAIN="dzulip.dev-ops.forum"  # Default domain - can be changed
ZULIP_DIR="/home/zulip"
CURRENT_DEPLOY="${ZULIP_DIR}/deployments/current"
SOCKET_PATH="${CURRENT_DEPLOY}/uwsgi.socket"
SSL_DIR="/etc/ssl"
SSL_CERT="${SSL_DIR}/certs/zulip.combined-chain.crt"
SSL_KEY="${SSL_DIR}/private/zulip.key"

# Check if installation completed properly
if [ ! -d "$CURRENT_DEPLOY" ]; then
  echo "ERROR: Zulip doesn't seem to be properly installed at $CURRENT_DEPLOY"
  echo "Please ensure Zulip is installed correctly before running this script."
  exit 1
fi

# Create directories if they don't exist
mkdir -p "$NGINX_AVAILABLE_DIR" "$NGINX_ENABLED_DIR"

# Backup original Nginx config if it exists
if [ -f "$ZULIP_CONF" ]; then
  BACKUP_DIR="/var/backups/nginx-$(date +%Y%m%d%H%M%S)"
  echo "Backing up existing Nginx configuration to $BACKUP_DIR"
  mkdir -p "$BACKUP_DIR"
  cp -r "$ZULIP_CONF" "$BACKUP_DIR/"
fi

echo "Creating Nginx configuration for Zulip..."

# Create socket directory
SOCKET_DIR=$(dirname "$SOCKET_PATH")
mkdir -p "$SOCKET_DIR"
chown -R zulip:zulip "$SOCKET_DIR"
chmod -R 755 "$SOCKET_DIR"

# Create a fresh Nginx configuration
cat > "$ZULIP_CONF" <<EOL
upstream django {
    server unix:${SOCKET_PATH} fail_timeout=30s;
}

server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN};

    # Redirect all HTTP requests to HTTPS
    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name ${DOMAIN};

    ssl_certificate ${SSL_CERT};
    ssl_certificate_key ${SSL_KEY};

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5:!RC4;
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;

    # Logs
    access_log /var/log/nginx/zulip.access.log;
    error_log /var/log/nginx/zulip-error.log;

    # Important server configuration
    client_max_body_size 100m;
    proxy_read_timeout 1200s;
    proxy_buffer_size 4k;
    proxy_buffers 8 4k;

    # Security headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    add_header X-Frame-Options DENY;

    # Static file serving
    location /static/ {
        alias ${ZULIP_DIR}/prod-static/;
        expires 30d;
    }

    # Favicon handling
    location /favicon.ico {
        alias ${ZULIP_DIR}/prod-static/favicon.ico;
    }

    # Main app handling
    location / {
        proxy_pass http://django;
        include /etc/nginx/proxy_params;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
    }
}
EOL

# Ensure proxy_params exists
if [ ! -f /etc/nginx/proxy_params ]; then
  echo "Creating proxy_params file..."
  cat > /etc/nginx/proxy_params <<EOL
proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto \$scheme;
proxy_set_header X-Real-IP \$remote_addr;
EOL
fi

# Enable the site
echo "Enabling Zulip site..."
ln -sf "$ZULIP_CONF" "${NGINX_ENABLED_DIR}/zulip"

# Remove default site if it exists
if [ -f "${NGINX_ENABLED_DIR}/default" ]; then
  echo "Removing default site..."
  rm -f "${NGINX_ENABLED_DIR}/default"
fi

# Test Nginx configuration
echo "Testing Nginx configuration..."
nginx -t

if [ $? -eq 0 ]; then
  echo "Nginx configuration is valid. Restarting Nginx..."
  systemctl restart nginx
  
  # Now restart Zulip services
  echo "Restarting Zulip services..."
  su zulip -c "${CURRENT_DEPLOY}/scripts/restart-server"
else
  echo "ERROR: Nginx configuration is invalid. Check the errors above."
  if [ -f "$BACKUP_DIR/zulip" ]; then
    echo "Restoring from backup..."
    cp "$BACKUP_DIR/zulip" "$ZULIP_CONF"
  fi
  exit 1
fi

# Create test file to verify serving of static content
STATIC_TEST_DIR="${ZULIP_DIR}/prod-static/test"
mkdir -p "$STATIC_TEST_DIR"
echo "Testing static file serving..." > "${STATIC_TEST_DIR}/test.txt"
chown -R zulip:zulip "${ZULIP_DIR}/prod-static"
chmod -R 755 "${ZULIP_DIR}/prod-static"

echo ""
echo "Configuration complete! You can test the static file serving by visiting:"
echo "https://${DOMAIN}/static/test/test.txt"
echo ""
echo "If you're still seeing 502 errors, try these steps:"
echo "1. Check if the socket file exists: ls -l ${SOCKET_PATH}"
echo "2. Check Nginx error logs: tail -n 50 /var/log/nginx/zulip-error.log"
echo "3. Check Zulip error logs: tail -n 50 /var/log/zulip/errors.log"
echo "4. Try accessing the site again"
echo ""
echo "You can check if Nginx and Zulip services are running with:"
echo "systemctl status nginx"
echo "supervisorctl status all | grep -E 'zulip-django|zulip-tornado'" 