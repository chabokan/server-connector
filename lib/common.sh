#!/bin/bash

# Common functions and variables for server-connector
# This file provides shared utilities across all scripts

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1" >&2
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

log_debug() {
    if [[ "${DEBUG:-0}" == "1" ]]; then
        echo -e "${BLUE}[DEBUG]${NC} $1" >&2
    fi
}

# Error handling
error_exit() {
    log_error "$1"
    exit "${2:-1}"
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check root privileges
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error_exit "This script must be run as root. Please use sudo or run as root user."
    fi
}

# Validate input
validate_token() {
    local token="$1"
    if [[ -z "$token" ]]; then
        error_exit "TOKEN cannot be empty"
    fi
    if [[ ${#token} -lt 8 ]]; then
        error_exit "TOKEN is too short (minimum 8 characters)"
    fi
}

validate_url() {
    local url="$1"
    if [[ -z "$url" ]]; then
        error_exit "HUB_URL cannot be empty"
    fi
    # Basic URL validation
    if [[ ! "$url" =~ ^[a-zA-Z0-9][a-zA-Z0-9\.-]*[a-zA-Z0-9]$ ]] && [[ ! "$url" =~ ^https?:// ]]; then
        log_warn "HUB_URL format may be invalid: $url"
    fi
}

# Detect OS
detect_os() {
    local os_release_file=""
    
    if [[ -f /etc/os-release ]]; then
        os_release_file="/etc/os-release"
    elif [[ -f /usr/lib/os-release ]]; then
        os_release_file="/usr/lib/os-release"
    else
        error_exit "Cannot detect operating system. /etc/os-release and /usr/lib/os-release not found."
    fi
    
    source "$os_release_file"
    export OS_ID="$ID"
    export OS_VERSION_ID="$VERSION_ID"
    
    # Extract major version number
    export os_version=$(grep -i version_id "$os_release_file" | cut -d '"' -f2 | cut -d '.' -f1)
    
    log_info "Detected OS: $OS_ID $os_version"
}

# Validate OS version
validate_os() {
    detect_os
    
    case "$OS_ID" in
        ubuntu)
            if [[ ${os_version} -lt 20 ]]; then
                error_exit "Ubuntu 20.04 or higher is required. Detected: $os_version"
            fi
            ;;
        debian)
            if [[ ${os_version} -lt 11 ]]; then
                error_exit "Debian 11 or higher is required. Detected: $os_version"
            fi
            ;;
        *)
            error_exit "Unsupported operating system: $OS_ID. Supported: Ubuntu 20.04+, Debian 11+"
            ;;
    esac
}

# Get server IP
get_server_ip() {
    local ip
    ip=$(hostname -I | awk '{print $1}')
    
    if [[ -z "$ip" ]]; then
        error_exit "Cannot detect server IP address"
    fi
    
    echo "$ip"
}

# Detect country from IP
detect_country() {
    local server_ip="$1"
    local ip_check_url="https://api.country.is/$server_ip"
    local response
    local country
    
    log_info "Detecting server country..."
    
    if ! command_exists curl; then
        log_warn "curl not found, cannot detect country. Assuming non-IR."
        export COUNTRY="UNKNOWN"
        return 0
    fi
    
    response=$(curl -s --max-time 10 --connect-timeout 5 "$ip_check_url" 2>/dev/null || echo "")
    
    if [[ -z "$response" ]] || echo "$response" | grep -q "\"error\""; then
        log_warn "Could not detect country from IP. Assuming non-IR."
        export COUNTRY="UNKNOWN"
        return 0
    fi
    
    country=$(echo "$response" | grep -o -P '"country":"\K[^"]+' | tr -d '"' || echo "")
    
    if [[ -z "$country" ]]; then
        log_warn "Could not parse country from API response. Assuming non-IR."
        export COUNTRY="UNKNOWN"
    else
        export COUNTRY="$country"
        log_info "Server country detected: $COUNTRY"
    fi
}

# Setup DNS
setup_dns() {
    local dns_servers=("$@")
    
    if [[ ${#dns_servers[@]} -eq 0 ]]; then
        dns_servers=("8.8.8.8" "1.1.1.1")
    fi
    
    log_info "Setting up DNS servers: ${dns_servers[*]}"
    
    # Backup existing resolv.conf if it exists
    if [[ -f /etc/resolv.conf ]]; then
        cp /etc/resolv.conf /etc/resolv.conf.backup.$(date +%s) 2>/dev/null || true
    fi
    
    cat > /etc/resolv.conf <<EOF
options timeout:2 attempts:3 rotate
$(for dns in "${dns_servers[@]}"; do echo "nameserver $dns"; done)
EOF
    
    log_info "DNS configuration updated"
}

# Retry function
retry_command() {
    local max_attempts="${1:-3}"
    local delay="${2:-5}"
    local attempt=1
    shift 2
    
    while [[ $attempt -le $max_attempts ]]; do
        log_debug "Attempt $attempt/$max_attempts: $*"
        if "$@"; then
            return 0
        fi
        if [[ $attempt -lt $max_attempts ]]; then
            log_warn "Command failed, retrying in ${delay}s..."
            sleep "$delay"
        fi
        ((attempt++))
    done
    
    log_error "Command failed after $max_attempts attempts: $*"
    return 1
}

# Safe service restart
restart_service() {
    local service="$1"
    
    if ! systemctl is-enabled "$service" >/dev/null 2>&1; then
        log_warn "Service $service is not enabled, skipping restart"
        return 0
    fi
    
    log_info "Restarting service: $service"
    if systemctl restart "$service" 2>/dev/null; then
        log_info "Service $service restarted successfully"
    else
        log_warn "Failed to restart service $service (may not exist or may use different init system)"
        # Try service command as fallback
        service "$service" restart 2>/dev/null || true
    fi
}

