#!/bin/bash
set -e

echo "Zulip-Nginx Diagnostic and Fix Tool"
echo "==================================="

# Check if supervisor is running
echo "Checking if supervisor is running..."
if ! systemctl is-active --quiet supervisor; then
    echo "Supervisor is not running. Starting supervisor..."
    systemctl start supervisor
    sleep 5
fi

# Check if nginx is running
echo "Checking Nginx status..."
if ! systemctl is-active --quiet nginx; then
    echo "Nginx is not running. Starting nginx..."
    systemctl start nginx
    sleep 2
fi

# Check Zulip services via supervisor
echo "Checking Zulip services status..."
SUPERVISOR_STATUS=$(supervisorctl status all)
echo "$SUPERVISOR_STATUS"

# Look for any services in FATAL state
if echo "$SUPERVISOR_STATUS" | grep -q FATAL; then
    echo "Found services in FATAL state. Attempting to restart them..."
    supervisorctl restart all
    sleep 5
fi

# Check if Django and Tornado are running
if ! echo "$SUPERVISOR_STATUS" | grep -q "zulip-django.*RUNNING"; then
    echo "Django is not running. Attempting to restart..."
    supervisorctl restart zulip-django
    sleep 5
fi

if ! echo "$SUPERVISOR_STATUS" | grep -q "zulip-tornado.*RUNNING"; then
    echo "Tornado is not running. Attempting to restart..."
    supervisorctl restart zulip-tornado
    sleep 5
fi

# Check nginx configuration
echo "Checking Nginx configuration..."
nginx -t

# Test if the Unix socket for Django is working
DJANGO_SOCKET_PATH=$(grep -r "upstream django" /etc/nginx/sites-available/ | grep -o "unix:.*socket" | head -1 || echo "")
if [ -n "$DJANGO_SOCKET_PATH" ]; then
    SOCKET_PATH=$(echo "$DJANGO_SOCKET_PATH" | sed 's/unix://g')
    echo "Checking Django socket: $SOCKET_PATH"
    if [ ! -S "$SOCKET_PATH" ]; then
        echo "Django socket does not exist. This may be causing the 502 error."
        echo "Trying to restart Django service..."
        supervisorctl restart zulip-django
        sleep 5
    fi
fi

# Check for connectivity between Nginx and Django
echo "Testing connection to Django backend..."
if ! curl --unix-socket "$SOCKET_PATH" http://localhost/health-check 2>/dev/null; then
    echo "Cannot connect to Django through the socket."
    echo "Restarting both Nginx and all Zulip services..."
    systemctl restart nginx
    supervisorctl restart all
    sleep 10
fi

# Set proper permissions on /var/log/zulip
echo "Setting proper permissions on log directory..."
if [ -d "/var/log/zulip" ]; then
    chown -R zulip:zulip /var/log/zulip
    chmod -R 755 /var/log/zulip
else
    echo "Warning: /var/log/zulip directory does not exist"
    mkdir -p /var/log/zulip
    chown -R zulip:zulip /var/log/zulip
    chmod -R 755 /var/log/zulip
fi

# Execute the Zulip restart script
echo "Running Zulip restart script..."
su zulip -c '/home/zulip/deployments/current/scripts/restart-server'

echo ""
echo "Diagnosis complete. Service status:"
supervisorctl status all
systemctl status nginx | grep "Active:"
echo ""
echo "If the server is still showing a 502 error, check the logs:"
echo "- Nginx error logs: tail -n 50 /var/log/nginx/error.log"
echo "- Zulip server logs: tail -n 50 /var/log/zulip/server.log"
echo ""
echo "You might need to manually check the following:"
echo "1. Ensure socket files exist and have correct permissions"
echo "2. Check memory usage (free -m) to see if the server is running out of memory"
echo "3. Check for SELinux or AppArmor issues if applicable" 