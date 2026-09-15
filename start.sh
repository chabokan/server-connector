#!/bin/bash

# Server Connector — bootstrap entry point
# Usage: bash start.sh <TOKEN> <HUB_URL>
# Optional env: DEBUG=1, NO_COLOR=1, SHECAN_DDNS_PASSWORD=..., DDNS_WAIT_SECONDS=90

set -euo pipefail

# Resolve script directory when run from a clone; bootstrap path has no lib yet
BOOTSTRAP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)"

# Minimal logging until common.sh is available (curl|bash bootstrap)
_bootstrap_log() { echo -e "$1" >&2; }
log_info()    { _bootstrap_log "\033[0;32m[INFO]\033[0m $1"; }
log_warn()    { _bootstrap_log "\033[0;33m[WARN]\033[0m $1"; }
log_error()   { _bootstrap_log "\033[0;31m[ERROR]\033[0m $1"; }
log_success() { _bootstrap_log "\033[0;32m[OK]\033[0m $1"; }
error_exit()  { log_error "$1"; exit "${2:-1}"; }

if [[ $EUID -ne 0 ]]; then
    error_exit "Please run this script as root (sudo or root user)."
fi

# Prefer local common.sh when present (dev / already cloned)
if [[ -n "${BOOTSTRAP_DIR}" ]] && [[ -f "${BOOTSTRAP_DIR}/lib/common.sh" ]]; then
    # shellcheck source=/dev/null
    source "${BOOTSTRAP_DIR}/lib/common.sh"
fi

trap 'log_error "Bootstrap failed at line $LINENO: $BASH_COMMAND"; exit 1' ERR

export INSTALL_LOG="${INSTALL_LOG:-/var/log/server-connector-install.log}"
mkdir -p "$(dirname "$INSTALL_LOG")" 2>/dev/null || true
touch "$INSTALL_LOG" 2>/dev/null || true

print_banner "Chabokan Server Connector" 2>/dev/null || true
log_info "Starting server-connector bootstrap..."
log_info "Install log: $INSTALL_LOG"

# Unset proxy variables
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY || true

# Get TOKEN
if [[ -n "${1:-}" ]]; then
    TOKEN=$1
else
    read -r -p "$(echo -e "\033[0;32mEnter TOKEN: \033[0m")" TOKEN </dev/tty || \
        error_exit "No terminal available for TOKEN prompt; pass TOKEN and HUB_URL as arguments"
fi
export TOKEN

# Get HUB_URL
if [[ -n "${2:-}" ]]; then
    HUB_URL=$2
else
    read -r -p "$(echo -e "\033[0;32mEnter HUB URL (ex: hub.chabokan.net): \033[0m")" HUB_URL </dev/tty || \
        error_exit "No terminal available for HUB_URL prompt; pass TOKEN and HUB_URL as arguments"
fi
if declare -f normalize_hub_url >/dev/null 2>&1; then
    HUB_URL=$(normalize_hub_url "$HUB_URL") || error_exit "Invalid HUB_URL"
else
    HUB_URL="${HUB_URL#https://}"
    HUB_URL="${HUB_URL%/}"
    [[ "$HUB_URL" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?(:[0-9]{1,5})?$ ]] || \
        error_exit "HUB_URL must be an HTTPS hostname or origin without a path"
    if [[ "$HUB_URL" == *:* ]]; then
        HUB_PORT="${HUB_URL##*:}"
        (( 10#$HUB_PORT >= 1 && 10#$HUB_PORT <= 65535 )) || \
            error_exit "HUB_URL port must be between 1 and 65535"
    fi
fi
export HUB_URL

# Optional third arg reserved for future use (e.g. connect type) — never reuse $2
TYPE_OF_CONNECT="${3:-${TYPE_OF_CONNECT:-}}"
export TYPE_OF_CONNECT

if declare -f validate_token >/dev/null 2>&1; then
    validate_token "$TOKEN"
    validate_url "$HUB_URL"
    validate_python
else
    [[ -z "$TOKEN" ]] && error_exit "TOKEN cannot be empty"
    [[ ${#TOKEN} -lt 8 ]] && error_exit "TOKEN is too short (minimum 8 characters)"
    [[ -z "$HUB_URL" ]] && error_exit "HUB_URL cannot be empty"
    python3 -c 'import sys; sys.exit(0 if (3, 9) <= sys.version_info[:2] <= (3, 13) else 1)' || \
        error_exit "node-manager requires host Python 3.9 through 3.13"
fi

# Setup base DNS after validating inputs
if declare -f setup_dns >/dev/null 2>&1; then
    setup_dns "8.8.8.8" "1.1.1.1"
else
    log_info "Configuring base DNS servers..."
    rm -f /etc/resolv.conf
    cat >/etc/resolv.conf <<EOF
options timeout:2 attempts:3 rotate
nameserver 8.8.8.8
nameserver 1.1.1.1
EOF
    log_success "Base DNS configured"
fi

# Set timezone
log_info "Setting timezone to Asia/Tehran..."
TZ_NAME=Asia/Tehran
if [[ -d /usr/share/zoneinfo/$TZ_NAME ]]; then
    ln -snf "/usr/share/zoneinfo/$TZ_NAME" /etc/localtime && echo "$TZ_NAME" > /etc/timezone
    log_success "Timezone set to Asia/Tehran"
else
    log_warn "Timezone $TZ_NAME not found, skipping timezone setup"
fi

# Detect server IP and country
log_info "Detecting server IP address..."
if declare -f get_server_ip >/dev/null 2>&1; then
    SERVER_IP=$(get_server_ip)
else
    SERVER_IP=$(hostname -I | awk '{print $1}')
    [[ -z "$SERVER_IP" ]] && error_exit "Cannot detect server IP address"
fi
export SERVER_IP

if declare -f detect_country >/dev/null 2>&1; then
    detect_country "$SERVER_IP"
else
    log_info "Checking server country..."
    CHECK_IP=$(curl -s --max-time 10 --connect-timeout 5 "https://api.country.is/$SERVER_IP" 2>/dev/null || echo "")
    if [[ -z "$CHECK_IP" ]] || echo "$CHECK_IP" | grep -q "\"error\""; then
        log_warn "IP country lookup failed — continuing as UNKNOWN (non-IR path)"
        COUNTRY="UNKNOWN"
    else
        COUNTRY=$(echo "$CHECK_IP" | sed -n 's/.*"country"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
        [[ -z "$COUNTRY" ]] && COUNTRY="UNKNOWN"
    fi
    export COUNTRY
fi

log_success "Server IP: ${SERVER_IP}"
log_success "Server Country: ${COUNTRY}"

# Handle Iran-specific configuration
if [[ "$COUNTRY" == "IR" ]]; then
    log_info "Iranian server detected — applying Shecan / DDNS configuration..."

    SHECAN_DDNS_PASSWORD="${SHECAN_DDNS_PASSWORD:-5941a36d2c3a2091}"
    DDNS_WAIT_SECONDS="${DDNS_WAIT_SECONDS:-90}"

    log_info "Updating Shecan DDNS..."
    if curl -sS --max-time 15 "https://ddns.shecan.ir/update?password=${SHECAN_DDNS_PASSWORD}" >/dev/null 2>&1; then
        log_success "DDNS update request sent"
    else
        log_warn "DDNS update failed — continuing; DNS propagation wait may not help"
    fi

    if declare -f wait_with_countdown >/dev/null 2>&1; then
        wait_with_countdown "$DDNS_WAIT_SECONDS" "Waiting for IP registration / DDNS propagation"
    else
        log_info "Waiting ${DDNS_WAIT_SECONDS}s for IP registration..."
        sleep "$DDNS_WAIT_SECONDS"
    fi

    if declare -f setup_dns >/dev/null 2>&1; then
        setup_dns "${SHECAN_DNS_PRIMARY:-178.22.122.101}" "${SHECAN_DNS_SECONDARY:-185.51.200.1}"
    else
        log_info "Configuring Shecan DNS servers..."
        rm -f /etc/resolv.conf
        cat >/etc/resolv.conf <<EOF
options timeout:2 attempts:3 rotate
nameserver 178.22.122.101
nameserver 185.51.200.1
EOF
        log_success "Shecan DNS configured"
    fi
fi

# Detect and validate OS
log_info "Detecting operating system..."
if declare -f validate_os >/dev/null 2>&1; then
    validate_os
    release="$OS_ID"
else
    if [[ -f /etc/os-release ]]; then
        # shellcheck source=/dev/null
        source /etc/os-release
        release=$ID
    elif [[ -f /usr/lib/os-release ]]; then
        # shellcheck source=/dev/null
        source /usr/lib/os-release
        release=$ID
    else
        error_exit "Failed to detect the system OS"
    fi
    export os_version
    os_version=$(grep -i version_id /etc/os-release | cut -d '"' -f2 | cut -d '.' -f1)
    if [[ "$release" == "ubuntu" && ${os_version} -lt 20 ]]; then
        error_exit "Please use Ubuntu 20 or higher"
    elif [[ "$release" == "debian" && ${os_version} -lt 11 ]]; then
        error_exit "Please use Debian 11 or higher"
    elif [[ "$release" != "ubuntu" && "$release" != "debian" ]]; then
        error_exit "Unsupported OS. Use Ubuntu 20.04+ or Debian 11+"
    fi
fi

log_success "OS validated: ${release:-$OS_ID} ${os_version}"

TOKEN_MASKED=$(declare -f mask_secret >/dev/null 2>&1 && mask_secret "$TOKEN" || echo "****")
if declare -f print_summary >/dev/null 2>&1; then
    print_summary "$SERVER_IP" "$COUNTRY" "${release:-$OS_ID} ${os_version}" "$HUB_URL" "$TOKEN_MASKED"
fi

# Prepare installation directory
log_info "Preparing installation directory..."
if [[ -e /var/server-connector ]] && [[ ! -d /var/server-connector/.git ]]; then
    error_exit "/var/server-connector exists but is not a git checkout; refusing to overwrite it"
fi
cd /var

log_info "Updating package lists..."
apt-get update -y -qq

log_info "Installing git..."
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq git curl ca-certificates

if [[ -d /var/server-connector/.git ]]; then
    log_info "Updating existing server-connector checkout..."
    git -C /var/server-connector pull --ff-only || error_exit "Connector checkout has local changes or update failed"
else
    log_info "Cloning server-connector repository..."
    git clone --depth 1 https://github.com/chabokan/server-connector.git /var/server-connector || \
        error_exit "Failed to clone server-connector repository"
fi

# Load full common library from the cloned tree
# shellcheck source=/dev/null
source /var/server-connector/lib/common.sh
export INSTALL_LOG
trap 'on_error $LINENO' ERR

# Run OS-specific setup
case "${release:-$OS_ID}" in
    ubuntu)
        log_info "Starting Ubuntu setup..."
        bash /var/server-connector/debian/ubuntu.sh
        ;;
    debian)
        log_info "Starting Debian setup..."
        bash /var/server-connector/debian/debian.sh
        ;;
    *)
        error_exit "Unsupported OS after clone: ${release:-$OS_ID}"
        ;;
esac

echo "" >&2
print_banner "Setup completed successfully" 2>/dev/null || log_success "Setup completed successfully!"
log_success "Install log saved to: $INSTALL_LOG"
