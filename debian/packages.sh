#!/bin/bash

# Package Installation Script
# Installs required system packages for server-connector

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/../lib/common.sh" 2>/dev/null || {
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    NC='\033[0m'
    log_info() { echo -e "${GREEN}[INFO]${NC} $1" >&2; }
    log_warn() { echo -e "${YELLOW}[WARN]${NC} $1" >&2; }
    log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
    log_success() { echo -e "${GREEN}[OK]${NC} $1" >&2; }
    error_exit() { log_error "$1"; exit "${2:-1}"; }
    detect_os() {
        # shellcheck source=/dev/null
        source /etc/os-release
        export OS_ID="$ID"
        export os_version
        os_version=$(echo "$VERSION_ID" | cut -d '.' -f1)
    }
}

if declare -f on_error >/dev/null 2>&1; then
    trap 'on_error $LINENO' ERR
else
    trap 'log_error "packages.sh failed at line $LINENO"; exit 1' ERR
fi

detect_os

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

apt_log=$(mktemp)

log_info "Updating package lists..."
if ! apt-get update -qq >"$apt_log" 2>&1; then
    log_error "apt-get update failed"
    tail -n 30 "$apt_log" >&2 || true
    rm -f "$apt_log"
    error_exit "Failed to update package lists"
fi

if [[ "$OS_ID" == "debian" ]]; then
    log_info "Fixing broken packages (if any)..."
    apt-get --fix-broken install -y -qq >>"$apt_log" 2>&1 || true
fi

log_info "Installing ${#PACKAGES[@]} required packages (this may take a few minutes)..."
if ! DEBIAN_FRONTEND=noninteractive apt-get install -y "${PACKAGES[@]}" >"$apt_log" 2>&1; then
    log_error "Package installation failed. Last output:"
    tail -n 60 "$apt_log" >&2 || true
    rm -f "$apt_log"
    error_exit "Failed to install required packages"
fi
rm -f "$apt_log"

log_info "Configuring git..."
git config --global credential.helper store || log_warn "Failed to configure git credential helper"

log_success "Package installation completed"
