#!/bin/bash

# Debian Setup Script
# Configures Debian server for server-connector

set -euo pipefail

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh" 2>/dev/null || {
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    NC='\033[0m'
    log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
    log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
    log_error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
}

# Error handling
trap 'log_error "An error occurred. Please check the logs and try again."' ERR

# Common setup steps
log_info "Updating system packages..."
apt-get update -qq

log_info "Installing required packages..."
bash /var/server-connector/debian/packages.sh

# Install Docker
source "${SCRIPT_DIR}/../lib/docker.sh" 2>/dev/null || {
    log_error "Failed to source docker.sh. Please ensure lib/docker.sh exists."
}
install_docker "debian" "$os_version"

# Setup node-manager
setup_node_manager "debian" "$os_version"

# Run configuration scripts
log_info "Running system configuration..."
bash /var/server-connector/debian/settings.sh

log_info "Configuring firewall..."
bash /var/server-connector/utilities/firewall.sh

log_info "Finalizing connection..."
bash /var/server-connector/utilities/finall.sh

log_info "Debian setup completed successfully!"
