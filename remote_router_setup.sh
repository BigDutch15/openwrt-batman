#!/bin/bash

# Remote Mesh Router Setup Script
# This script executes the router setup script on a remote host
# by piping it directly to the remote shell with environment variables

set -e  # Exit on error

# Load environment variables from .env file if it exists
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"
LOCAL_SCRIPT=""
TEMP_SCRIPT=""

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
    echo "Usage: $0 -h HOST [-u USER] [-t ROUTER_TYPE]"
    echo "  -h HOST         Remote hostname or IP address (required)"
    echo "  -u USER         SSH username (default: root)"
    echo "  -t ROUTER_TYPE  Router type (optional, will prompt if not provided)"
    echo ""
    echo "Supported router types:"
    echo "  1) Linksys MX4200v1"
    echo "  2) Linksys WRT1900ACSv1"
    exit 1
}

# Parse command line arguments
ROUTER_TYPE=""
while getopts "h:u:t:" opt; do
    case $opt in
        h) REMOTE_HOST="$OPTARG" ;;
        u) REMOTE_USER="$OPTARG" ;;
        t) ROUTER_TYPE="$OPTARG" ;;
        *) usage ;;
    esac
done

# Validate required parameters
if [ -z "$REMOTE_HOST" ]; then
    echo "Error: Remote host is required"
    usage
fi

# Prompt for router type if not provided
if [ -z "$ROUTER_TYPE" ]; then
    echo "Select router type:"
    echo "  1) Linksys MX4200v1"
    echo "  2) Linksys WRT1900ACSv1"
    read -p "Enter selection (1 or 2): " selection
    
    case $selection in
        1)
            ROUTER_TYPE="MX4200v1"
            ;;
        2)
            ROUTER_TYPE="WRT1900ACSv1"
            ;;
        *)
            echo "Error: Invalid selection"
            exit 1
            ;;
    esac
fi

# Set script path based on router type
case "$ROUTER_TYPE" in
    MX4200v1|mx4200v1|1)
        LOCAL_SCRIPT="${SCRIPT_DIR}/scripts/Linksys_MX4200v1_setup.sh"
        ROUTER_MODEL="Linksys MX4200v1"
        ;;
    WRT1900ACSv1|wrt1900acsv1|2)
        LOCAL_SCRIPT="${SCRIPT_DIR}/scripts/Linksys_WRT1900ACSv1_setup.sh"
        ROUTER_MODEL="Linksys WRT1900ACSv1"
        ;;
    *)
        echo "Error: Unknown router type '$ROUTER_TYPE'"
        echo "Supported types: MX4200v1, WRT1900ACSv1"
        exit 1
        ;;
esac

# Set temp script path
TEMP_SCRIPT="/tmp/router_setup_$(date +%s).sh"

# Check if local script exists
if [ ! -f "$LOCAL_SCRIPT" ]; then
    echo "Error: Local script '$LOCAL_SCRIPT' not found"
    exit 1
fi

echo "Selected router: $ROUTER_MODEL"

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

# Usage examples:
# ./remote_router_setup.sh -h 192.168.1.1 -u root
# ./remote_router_setup.sh -h 192.168.1.1 -u root -t MX4200v1
# ./remote_router_setup.sh -h 192.168.1.1 -u root -t WRT1900ACSv1
