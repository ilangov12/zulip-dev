#!/bin/bash
set -e

echo "Nginx Configuration Fix for Zulip"
echo "================================="

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi

# Backup original Nginx config
BACKUP_DIR="/var/backups/nginx-$(date +%Y%m%d%H%M%S)"
echo "Creating backup of Nginx configuration in $BACKUP_DIR"
mkdir -p "$BACKUP_DIR"
cp -r /etc/nginx/* "$BACKUP_DIR/"

# Check if Zulip config exists
NGINX_CONF="/etc/nginx/sites-available/zulip"
if [ ! -f "$NGINX_CONF" ]; then
  echo "ERROR: Zulip Nginx configuration not found at $NGINX_CONF"
  exit 1
fi

echo "Checking Nginx configuration..."
UWSGI_SOCKET=$(grep -o "unix:.*\.socket" "$NGINX_CONF" | head -1 | sed 's/unix://g' || echo "")

if [ -z "$UWSGI_SOCKET" ]; then
  echo "Could not find uWSGI socket path in Nginx configuration."
  echo "Looking for default socket location..."
  UWSGI_SOCKET="/home/zulip/deployments/current/uwsgi.socket"
else
  echo "Found uWSGI socket path: $UWSGI_SOCKET"
fi

# Create or fix socket directory
SOCKET_DIR=$(dirname "$UWSGI_SOCKET")
echo "Making sure socket directory exists with proper permissions..."
mkdir -p "$SOCKET_DIR"
chown -R zulip:zulip "$SOCKET_DIR"
chmod -R 755 "$SOCKET_DIR"

# Fix common Nginx misconfigurations
echo "Checking for common Nginx misconfigurations..."

# Ensure proxy_read_timeout is long enough
if grep -q "proxy_read_timeout" "$NGINX_CONF"; then
  echo "Updating proxy_read_timeout to 1200s..."
  sed -i 's/proxy_read_timeout [0-9]\+s;/proxy_read_timeout 1200s;/g' "$NGINX_CONF"
else
  echo "Adding proxy_read_timeout setting..."
  sed -i '/server {/a \    proxy_read_timeout 1200s;' "$NGINX_CONF"
fi

# Fix potential upstream configuration
if grep -q "upstream django {" "$NGINX_CONF"; then
  echo "Updating upstream django configuration..."
  # Replace entire upstream django block
  sed -i '/upstream django {/,/}/c\upstream django {\n    server unix:'"$UWSGI_SOCKET"' fail_timeout=30s;\n}' "$NGINX_CONF"
fi

# Fix proxy buffer settings if needed
if ! grep -q "proxy_buffer_size" "$NGINX_CONF"; then
  echo "Adding proxy buffer settings..."
  sed -i '/server {/a \    proxy_buffer_size 4k;\n    proxy_buffers 8 4k;' "$NGINX_CONF"
fi

# Ensure error logs are enabled
if ! grep -q "error_log" "$NGINX_CONF"; then
  echo "Adding error log configuration..."
  sed -i '/server {/a \    error_log /var/log/nginx/zulip-error.log;' "$NGINX_CONF"
fi

# Fix static file serving
echo "Checking static file configuration..."
STATIC_ROOT="/home/zulip/prod-static"
if grep -q "location /static" "$NGINX_CONF"; then
  echo "Updating static file location block..."
  sed -i '/location \/static/,/}/c\    location /static {\n        alias '"$STATIC_ROOT"';\n        expires 30d;\n    }' "$NGINX_CONF"
else
  echo "Adding static file location block..."
  sed -i '/server {/a \    location /static {\n        alias '"$STATIC_ROOT"';\n        expires 30d;\n    }' "$NGINX_CONF"
fi

# Fix client_max_body_size
if grep -q "client_max_body_size" "$NGINX_CONF"; then
  echo "Updating client_max_body_size..."
  sed -i 's/client_max_body_size [0-9]\+m;/client_max_body_size 100m;/g' "$NGINX_CONF"
else
  echo "Adding client_max_body_size setting..."
  sed -i '/server {/a \    client_max_body_size 100m;' "$NGINX_CONF"
fi

# Ensure the site is enabled
if [ ! -L /etc/nginx/sites-enabled/zulip ]; then
  echo "Enabling Zulip site..."
  ln -sf /etc/nginx/sites-available/zulip /etc/nginx/sites-enabled/zulip
fi

# Remove default site if it exists
if [ -L /etc/nginx/sites-enabled/default ]; then
  echo "Removing default site..."
  rm -f /etc/nginx/sites-enabled/default
fi

# Test Nginx configuration
echo "Testing Nginx configuration..."
nginx -t

if [ $? -eq 0 ]; then
  echo "Nginx configuration is valid. Restarting Nginx..."
  systemctl restart nginx
  
  # Now restart Zulip services
  echo "Restarting Zulip services..."
  su zulip -c '/home/zulip/deployments/current/scripts/restart-server'
else
  echo "ERROR: Nginx configuration is invalid. Check the errors above."
  echo "Restoring from backup..."
  cp -r "$BACKUP_DIR"/* /etc/nginx/
  exit 1
fi

# Check if services are running
echo "Checking service status..."
systemctl status nginx | grep Active
supervisorctl status all | grep -E 'zulip-django|zulip-tornado'

echo ""
echo "Configuration complete. If you're still seeing 502 errors, try these steps:"
echo "1. Check if the socket file exists: ls -l $UWSGI_SOCKET"
echo "2. Check Nginx error logs: tail -n 50 /var/log/nginx/error.log"
echo "3. Check Zulip error logs: tail -n 50 /var/log/zulip/errors.log"
echo "4. Try accessing the site again" 