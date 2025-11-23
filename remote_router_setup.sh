#!/bin/bash

# Remote Mesh Router Setup Script
# This script executes the make_mesh_router_mx4200.sh script on a remote host
# by piping it directly to the remote shell

set -e  # Exit on error

# Default values
REMOTE_USER="root"
REMOTE_HOST=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_SCRIPT="${SCRIPT_DIR}/scripts/router_setup.sh"

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
    echo "Please make sure the script exists in your home directory"
    exit 1
fi

echo "Executing mesh router setup on $REMOTE_USER@$REMOTE_HOST..."

# Pipe the script directly to the remote shell
ssh "$REMOTE_USER@$REMOTE_HOST" 'ash -s' < "$LOCAL_SCRIPT"

echo "Remote mesh router setup completed!"

# Usage example:
# ./remote_mesh_router_setup.sh -h 192.168.1.1 -u root
