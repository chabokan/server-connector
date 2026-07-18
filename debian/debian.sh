#!/bin/bash

# Debian Setup Script
# Configures Debian server for server-connector

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/../lib/common.sh" 2>/dev/null || {
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    NC='\033[0m'
    log_info() { echo -e "${GREEN}[INFO]${NC} $1" >&2; }
    log_warn() { echo -e "${YELLOW}[WARN]${NC} $1" >&2; }
    log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; exit 1; }
    log_success() { echo -e "${GREEN}[OK]${NC} $1" >&2; }
    log_step() { echo -e "${CYAN}${BOLD}[$1/$2]${NC} $3" >&2; }
    error_exit() { log_error "$1"; exit "${2:-1}"; }
    on_error() { log_error "Failed at line ${1:-unknown}: ${BASH_COMMAND:-unknown}"; exit 1; }
}

trap 'on_error $LINENO' ERR

TOTAL_STEPS=5
print_banner "Debian setup (${os_version:-?})" 2>/dev/null || true

log_step 1 "$TOTAL_STEPS" "Updating apt and installing packages..."
apt-get update -qq
bash /var/server-connector/debian/packages.sh

log_step 2 "$TOTAL_STEPS" "Installing Docker and node-manager..."
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/../lib/docker.sh" || error_exit "Failed to source docker.sh"
install_docker "debian" "$os_version"
setup_node_manager "debian" "$os_version"

log_step 3 "$TOTAL_STEPS" "Applying system settings..."
bash /var/server-connector/debian/settings.sh

log_step 4 "$TOTAL_STEPS" "Configuring firewall..."
bash /var/server-connector/utilities/firewall.sh

log_step 5 "$TOTAL_STEPS" "Connecting node to hub..."
bash /var/server-connector/utilities/final.sh

log_success "Debian setup completed successfully!"
