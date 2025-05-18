#!/bin/bash
set -e

# This script handles the creation of /srv/zulip.git directory
# with special handling for the case where it already exists

ZULIP_GIT_DIR="/srv/zulip.git"

if [ -d "$ZULIP_GIT_DIR" ]; then
    echo "Directory $ZULIP_GIT_DIR already exists."
    echo "Moving existing directory to $ZULIP_GIT_DIR.bak"
    
    # Remove any old backup if it exists
    if [ -d "$ZULIP_GIT_DIR.bak" ]; then
        rm -rf "$ZULIP_GIT_DIR.bak"
    fi
    
    # Move the current directory to backup
    mv "$ZULIP_GIT_DIR" "$ZULIP_GIT_DIR.bak"
fi

# Create the directory fresh
mkdir -p "$ZULIP_GIT_DIR"
echo "Successfully created $ZULIP_GIT_DIR"

# Set proper permissions
chown -R zulip:zulip "$ZULIP_GIT_DIR" 