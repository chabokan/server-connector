#!/bin/bash

# Package Installation Script
# Installs required system packages for server-connector

set -euo pipefail

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh" 2>/dev/null || {
    # Fallback
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    NC='\033[0m'
    log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
    log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
    log_error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
}

# Detect OS
detect_os

# Package list (removed duplicates like net-tools and htop)
PACKAGES=(
    iptables-persistent
    sqlite3
    pigz
    default-mysql-client
    nano
    jq
    vsftpd
    vim
    htop
    net-tools
    iputils-ping
    apache2-utils
    rkhunter
    supervisor
    fail2ban
    wget
    zip
    nmap
    git
    letsencrypt
    build-essential
    iftop
    dnsutils
    python3-venv
    python3-pip
    dsniff
    grepcidr
    iotop
    rsync
    atop
    software-properties-common
    curl
    ca-certificates
    gnupg
)

log_info "Updating package lists..."
apt-get update -qq

# Fix broken packages for Debian
if [[ "$OS_ID" == "debian" ]]; then
    log_info "Fixing broken packages..."
    apt-get --fix-broken install -y -qq || true
fi

log_info "Installing required packages..."
DEBIAN_FRONTEND=noninteractive apt-get install -y "${PACKAGES[@]}" || {
    log_error "Failed to install some packages. Please check the error messages above."
}

# Configure git
log_info "Configuring git..."
git config --global credential.helper store || log_warn "Failed to configure git credential helper"

log_info "Package installation completed successfully"
