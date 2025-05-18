#!/bin/bash
set -e

echo "Zulip 502 Error Fix Tool"
echo "========================"

# Ensure we're running as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi

# Function to check logs
check_logs() {
  echo "Checking recent error logs..."
  
  echo "=== NGINX ERROR LOGS ==="
  if [ -f /var/log/nginx/error.log ]; then
    tail -n 50 /var/log/nginx/error.log | grep -i "error\|failed\|permission\|denied" || echo "No obvious errors found in nginx error log"
  else
    echo "Nginx error log not found"
  fi
  
  echo ""
  echo "=== ZULIP SERVER LOGS ==="
  if [ -d /var/log/zulip ]; then
    find /var/log/zulip -name "*.log" -type f -exec grep -l "error\|exception\|failed" {} \; | xargs -r tail -n 20 || echo "No obvious errors found in Zulip logs"
  else
    echo "Zulip logs directory not found, creating it..."
    mkdir -p /var/log/zulip
    chown -R zulip:zulip /var/log/zulip
    chmod -R 755 /var/log/zulip
  fi
}

# Restart all services
restart_all_services() {
  echo "Restarting all Zulip services..."
  supervisorctl stop all
  sleep 2
  systemctl restart nginx
  supervisorctl start all
  sleep 5
}

# Find and fix socket paths
fix_socket_paths() {
  echo "Checking for Django/uWSGI socket path..."
  
  SOCKET_PATH=$(grep -r "upstream django" /etc/nginx -l | xargs grep -o "unix:.*socket" | head -n1 | sed 's/unix://g' || echo "")
  
  if [ -z "$SOCKET_PATH" ]; then
    echo "Could not find Django socket path in Nginx config. Searching for it in the filesystem..."
    SOCKET_PATH=$(find /home/zulip/deployments -name "*.socket" 2>/dev/null | head -n1 || echo "")
    
    if [ -z "$SOCKET_PATH" ]; then
      echo "Could not find any socket files. This is concerning."
    else
      echo "Found potential socket: $SOCKET_PATH"
    fi
  else
    echo "Found Django socket path in Nginx config: $SOCKET_PATH"
  fi
  
  if [ -n "$SOCKET_PATH" ]; then
    echo "Checking if socket exists..."
    if [ ! -S "$SOCKET_PATH" ]; then
      echo "Socket does not exist. This is why you're getting a 502 error."
      SOCKET_DIR=$(dirname "$SOCKET_PATH")
      
      echo "Making sure the socket directory exists with proper permissions..."
      mkdir -p "$SOCKET_DIR"
      chown -R zulip:zulip "$SOCKET_DIR"
      chmod -R 755 "$SOCKET_DIR"
      
      echo "Restarting services to recreate the socket..."
      restart_all_services
      
      if [ ! -S "$SOCKET_PATH" ]; then
        echo "Socket still doesn't exist after restart. This suggests a deeper issue."
      else
        echo "Socket successfully created!"
      fi
    else
      echo "Socket exists. Checking permissions..."
      ls -la "$SOCKET_PATH"
      
      echo "Ensuring proper socket ownership and permissions..."
      chown zulip:zulip "$SOCKET_PATH"
      chmod 755 "$SOCKET_PATH"
    fi
  fi
}

# Check memory and system resources
check_resources() {
  echo "Checking system resources..."
  
  echo "=== MEMORY USAGE ==="
  free -m
  
  echo ""
  echo "=== DISK SPACE ==="
  df -h
  
  echo ""
  echo "=== CPU LOAD ==="
  uptime
  
  MEM_FREE=$(free -m | grep "Mem:" | awk '{print $4}')
  if [ "$MEM_FREE" -lt 200 ]; then
    echo "WARNING: System is low on memory. This could cause services to fail."
    echo "Consider adding more RAM or swap space."
  fi
}

# Fix known production settings issues
fix_settings() {
  echo "Checking production settings..."
  
  SETTINGS_FILE="/etc/zulip/settings.py"
  if [ -f "$SETTINGS_FILE" ]; then
    # Make sure debug is off in production
    if grep -q "^DEBUG = True" "$SETTINGS_FILE"; then
      echo "DEBUG is set to True in production. Setting it to False..."
      sed -i 's/^DEBUG = True/DEBUG = False/' "$SETTINGS_FILE"
    fi
    
    # Ensure ALLOWED_HOSTS includes the domain
    DOMAIN=$(grep "^EXTERNAL_HOST" "$SETTINGS_FILE" | cut -d "'" -f 2)
    if [ -n "$DOMAIN" ]; then
      if ! grep -q "^ALLOWED_HOSTS.*$DOMAIN" "$SETTINGS_FILE"; then
        echo "Adding $DOMAIN to ALLOWED_HOSTS..."
        if grep -q "^ALLOWED_HOSTS" "$SETTINGS_FILE"; then
          sed -i "s/^ALLOWED_HOSTS.*/ALLOWED_HOSTS = ['$DOMAIN', 'localhost']/" "$SETTINGS_FILE"
        else
          echo "ALLOWED_HOSTS = ['$DOMAIN', 'localhost']" >> "$SETTINGS_FILE"
        fi
      fi
    fi
    
    echo "Setting proper ownership of settings file..."
    chown zulip:zulip "$SETTINGS_FILE"
  else
    echo "Settings file not found at $SETTINGS_FILE"
  fi
}

# Check for and fix static files issues
fix_static_files() {
  echo "Checking static files..."
  
  STATIC_DIR="/home/zulip/prod-static"
  if [ ! -d "$STATIC_DIR" ]; then
    echo "Static directory not found. Creating it..."
    mkdir -p "$STATIC_DIR"
    chown -R zulip:zulip "$STATIC_DIR"
  else
    echo "Making sure static files have the right permissions..."
    chown -R zulip:zulip "$STATIC_DIR"
    chmod -R 755 "$STATIC_DIR"
  fi
  
  # Rebuild static files
  echo "Rebuilding static files..."
  CURRENT_DEPLOY=$(readlink -f /home/zulip/deployments/current)
  if [ -d "$CURRENT_DEPLOY" ]; then
    cd "$CURRENT_DEPLOY"
    su zulip -c "./manage.py collectstatic --noinput"
  else
    echo "Could not find current deployment directory"
  fi
}

# Check ssl configuration
check_ssl() {
  echo "Checking SSL certificates..."
  
  if [ -f /etc/ssl/certs/zulip.combined-chain.crt ] && [ -f /etc/ssl/private/zulip.key ]; then
    echo "SSL certificates exist. Checking validity..."
    openssl x509 -noout -dates -in /etc/ssl/certs/zulip.combined-chain.crt
  else
    echo "SSL certificates not found at the expected location."
    echo "This could cause issues if SSL is enabled in the Nginx configuration."
  fi
}

# Main function to run all checks and fixes
main() {
  echo "Starting comprehensive 502 error diagnosis..."
  
  # Create a backup of Nginx configuration files
  mkdir -p /var/backups/nginx-$(date +%Y%m%d%H%M%S)
  cp -r /etc/nginx/* /var/backups/nginx-$(date +%Y%m%d%H%M%S)/
  
  # Run all checks and fixes
  check_logs
  echo ""
  
  fix_socket_paths
  echo ""
  
  check_resources
  echo ""
  
  fix_settings
  echo ""
  
  fix_static_files
  echo ""
  
  check_ssl
  echo ""
  
  # Final restart
  echo "Performing final restart of all services..."
  restart_all_services
  
  echo ""
  echo "All diagnostics and fixes completed."
  echo "Checking final status of services..."
  supervisorctl status all
  systemctl status nginx | grep "Active:"
  
  echo ""
  echo "If you're still seeing a 502 error, please check:"
  echo "1. If all services show as RUNNING"
  echo "2. Check if the socket files exist and have proper permissions"
  echo "3. Examine the Nginx and Zulip logs for more specific errors"
  echo ""
  echo "You can also try rerunning this script with debug output:"
  echo "bash -x $0"
}

# Run everything
main 