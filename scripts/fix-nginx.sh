#!/bin/bash
set -e

echo "Zulip Nginx Configuration Fixer"
echo "==============================="

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi

NGINX_CONF="/etc/nginx/nginx.conf"
NGINX_SITES="/etc/nginx/sites-enabled"
ZULIP_CONF="/etc/nginx/sites-available/zulip"

echo "Checking Nginx configuration..."

# Check if Nginx is installed
if ! command -v nginx &> /dev/null; then
    echo "Nginx is not installed. Installing..."
    apt-get update
    apt-get install -y nginx
fi

# Check if Nginx service is running
echo "Checking Nginx service status..."
if ! systemctl is-active --quiet nginx; then
    echo "Nginx service is not running. Starting..."
    systemctl start nginx
fi

# Check if there's a conflict with SSL shared memory zone
if grep -q "ssl_session_cache.*shared:SSL:" "$NGINX_CONF"; then
    echo "Found SSL shared memory zone in main Nginx config."
    echo "Checking for conflicts in site configs..."
    if grep -r "ssl_session_cache.*shared:SSL:" "$NGINX_SITES" | grep -v "#"; then
        echo "Conflict found! Removing ssl_session_cache from Zulip config..."
        sed -i '/ssl_session_cache.*shared:SSL:/d' "$ZULIP_CONF"
    fi
fi

# Check if the Zulip site is enabled
if [ ! -L "$NGINX_SITES/zulip" ]; then
    echo "Zulip site is not enabled. Enabling..."
    ln -sf "$ZULIP_CONF" "$NGINX_SITES/zulip"
fi

# Test the Nginx configuration
echo "Testing Nginx configuration..."
if ! nginx -t; then
    echo "Nginx configuration is invalid. Checking error logs..."
    cat /var/log/nginx/error.log | tail -n 50
    exit 1
fi

# Reload Nginx to apply the changes
echo "Reloading Nginx..."
systemctl reload nginx

# Check if the socket file exists
ZULIP_DIR="/home/zulip"
CURRENT_DEPLOY="${ZULIP_DIR}/deployments/current"
SOCKET_PATH="${CURRENT_DEPLOY}/uwsgi.socket"

if [ ! -S "$SOCKET_PATH" ]; then
    echo "Socket file not found. Starting Zulip services..."
    su zulip -c "${CURRENT_DEPLOY}/scripts/restart-server"
fi

echo "Checking Zulip supervisor services..."
supervisorctl status all | grep -E 'zulip-django|zulip-tornado'

echo "Nginx configuration has been fixed. Try accessing your Zulip server now."
echo "If issues persist, check these logs:"
echo "- Nginx error log: /var/log/nginx/error.log"
echo "- Zulip error log: /var/log/zulip/errors.log" 