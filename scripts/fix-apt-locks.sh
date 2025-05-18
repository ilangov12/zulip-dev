#!/bin/bash
set -e

echo "APT Lock Resolution Script"
echo "=========================="

# Check if apt is locked
echo "Checking for apt locks..."
if [ -f /var/lib/apt/lists/lock ]; then
    echo "Found /var/lib/apt/lists/lock"
    
    # Find the process holding the lock
    LOCK_PID=$(fuser /var/lib/apt/lists/lock 2>/dev/null || echo "")
    
    if [ -n "$LOCK_PID" ]; then
        echo "Process $LOCK_PID is holding the lock."
        echo "Checking if the process is still running..."
        
        if ps -p $LOCK_PID > /dev/null; then
            echo "Process is still running. Waiting for it to complete (up to 5 minutes)..."
            
            # Wait for up to 5 minutes
            for i in {1..300}; do
                if ! ps -p $LOCK_PID > /dev/null; then
                    echo "Process completed."
                    break
                fi
                if [ $i -eq 300 ]; then
                    echo "Process is taking too long. You may want to kill it with:"
                    echo "kill $LOCK_PID"
                    echo "Or forcefully remove the locks (only if sure):"
                    echo "rm -f /var/lib/apt/lists/lock /var/lib/dpkg/lock /var/lib/dpkg/lock-frontend"
                    exit 1
                fi
                sleep 1
            done
        else
            echo "Process is not running anymore. The lock is stale."
            echo "Removing the lock file..."
            rm -f /var/lib/apt/lists/lock
        fi
    else
        echo "No process is holding the lock. It may be stale."
        echo "Removing the lock file..."
        rm -f /var/lib/apt/lists/lock
    fi
fi

# Check other common lock files
if [ -f /var/lib/dpkg/lock ]; then
    echo "Found /var/lib/dpkg/lock"
    LOCK_PID=$(fuser /var/lib/dpkg/lock 2>/dev/null || echo "")
    
    if [ -n "$LOCK_PID" ]; then
        echo "Process $LOCK_PID is holding the lock."
        if ps -p $LOCK_PID > /dev/null; then
            echo "Process is still running. This could be an active installation."
            echo "Please wait for it to complete or investigate further."
            exit 1
        else
            echo "Process is not running anymore. The lock is stale."
            echo "Removing the lock file..."
            rm -f /var/lib/dpkg/lock
        fi
    else
        echo "No process is holding the lock. It may be stale."
        echo "Removing the lock file..."
        rm -f /var/lib/dpkg/lock
    fi
fi

if [ -f /var/lib/dpkg/lock-frontend ]; then
    echo "Found /var/lib/dpkg/lock-frontend"
    LOCK_PID=$(fuser /var/lib/dpkg/lock-frontend 2>/dev/null || echo "")
    
    if [ -n "$LOCK_PID" ]; then
        echo "Process $LOCK_PID is holding the lock."
        if ps -p $LOCK_PID > /dev/null; then
            echo "Process is still running. This could be an active installation."
            echo "Please wait for it to complete or investigate further."
            exit 1
        else
            echo "Process is not running anymore. The lock is stale."
            echo "Removing the lock file..."
            rm -f /var/lib/dpkg/lock-frontend
        fi
    else
        echo "No process is holding the lock. It may be stale."
        echo "Removing the lock file..."
        rm -f /var/lib/dpkg/lock-frontend
    fi
fi

echo "Lock check and cleanup completed."
echo "You can now run the installation again:"
echo "cd /home/ilangodvops && ./zulip-server/scripts/setup/install --certbot --email=elango@wyzmindz.com --hostname=dzulip.dev-ops.forum" 