#!/bin/bash

# Remote Mesh Router Setup Script
# This script executes the router setup script on a remote host
# by piping it directly to the remote shell with environment variables

set -e  # Exit on error

# Load environment variables from .env file if it exists
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"
LOCAL_SCRIPT="${SCRIPT_DIR}/scripts/router_setup.sh"
TEMP_SCRIPT="/tmp/router_setup_$(date +%s).sh"

# Load default values from .env file if it exists
if [ -f "$ENV_FILE" ]; then
    # Export variables from .env file
    set -a
    source "$ENV_FILE"
    set +a
else
    echo "Warning: .env file not found. Using default values."
    # Set default values
    REMOTE_USER="root"
    REMOTE_HOST=""
fi

# Display usage information
usage() {
    echo "Usage: $0 -h HOST [-u USER]"
    echo "  -h HOST     Remote hostname or IP address (required)"
    echo "  -u USER     SSH username (default: root)"
    exit 1
}

# Parse command line arguments
while getopts "h:u:" opt; do
    case $opt in
        h) REMOTE_HOST="$OPTARG" ;;
        u) REMOTE_USER="$OPTARG" ;;
        *) usage ;;
    esac
done

# Validate required parameters
if [ -z "$REMOTE_HOST" ]; then
    echo "Error: Remote host is required"
    usage
fi

# Check if local script exists
if [ ! -f "$LOCAL_SCRIPT" ]; then
    echo "Error: Local script '$LOCAL_SCRIPT' not found"
    exit 1
fi

# Create a temporary script with the main script content
cat "$LOCAL_SCRIPT" > "$TEMP_SCRIPT"

echo "Executing router setup on $REMOTE_USER@$REMOTE_HOST..."

# Build environment variable string for SSH
ENV_VARS=""
if [ -f "$ENV_FILE" ]; then
    # Read .env file and format variables for SSH command
    while IFS= read -r line || [ -n "$line" ]; do
        # Skip comments and empty lines
        [ -z "$line" ] && continue
        [[ "$line" =~ ^# ]] && continue
        
        # Escape special characters in the value
        var_name="${line%%=*}"
        var_value="${line#*=}"
        # Remove surrounding quotes if they exist
        var_value="${var_value%\"}"
        var_value="${var_value#\"}"
        var_value="${var_value%\'}"
        var_value="${var_value#\'}"
        
        # Add to environment variables
        ENV_VARS+="$var_name='$var_value' "
    done < "$ENV_FILE"
fi

# Execute the script on remote host with environment variables
ssh "$REMOTE_USER@$REMOTE_HOST" "$ENV_VARS ash -s" < "$TEMP_SCRIPT"

# Clean up
rm -f "$TEMP_SCRIPT"

echo "Remote mesh router setup completed!"

# Usage example:
# ./remote_mesh_router_setup.sh -h 192.168.1.1 -u root
