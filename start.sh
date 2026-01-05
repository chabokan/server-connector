#!/bin/bash

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Check root user
[[ $EUID -ne 0 ]] && log_error "Please run command with root privilege" && exit 1

set -e

# Unset proxy variables
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY

# Setup base DNS
log_info "Configuring base DNS servers..."
if [[ -f /etc/resolv.conf ]]; then
    rm -f /etc/resolv.conf
fi
cat >/etc/resolv.conf <<EOF
options timeout:1
nameserver 8.8.8.8
nameserver 1.1.1.1
EOF
log_success "Base DNS configured"

# Get TOKEN
if [[ "$1" != '' ]]; then
    TOKEN=$1
else
    read -p "$(echo -e ${GREEN}Enter TOKEN: ${NC})" TOKEN
fi
export TOKEN

# Get HUB_URL
if [[ "$2" != '' ]]; then
    HUB_URL=$2
else
    read -p "$(echo -e ${GREEN}Enter HUB URL (ex:hub.chabokan.net): ${NC})" HUB_URL
fi
export HUB_URL

# Set timezone
log_info "Setting timezone to Asia/Tehran..."
TZ=Asia/Tehran
if [[ -d /usr/share/zoneinfo/$TZ ]]; then
    ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone
    log_success "Timezone set to Asia/Tehran"
else
    log_warn "Timezone $TZ not found, skipping timezone setup"
fi

# Detect server IP and country
log_info "Detecting server IP address..."
SERVER_IP=$(hostname -I | awk '{print $1}')
if [[ -z "$SERVER_IP" ]]; then
    log_error "Cannot detect server IP address"
    exit 1
fi

log_info "Checking server country..."
IP_CHECK_URL="https://api.country.is/$SERVER_IP"
CHECK_IP=$(curl -s --max-time 10 --connect-timeout 5 "$IP_CHECK_URL" 2>/dev/null || echo "")

if [[ -z "$CHECK_IP" ]] || echo "$CHECK_IP" | grep -q "\"error\""; then
    log_error "IP address not found or API error"
    exit 1
fi

COUNTRY=$(echo "$CHECK_IP" | grep -o -P '"country":"\K[^"]+' | tr -d \" || echo "")
if [[ -z "$COUNTRY" ]]; then
    log_warn "Could not parse country from API response"
    COUNTRY="UNKNOWN"
fi
export COUNTRY

log_success "Server IP: ${SERVER_IP}"
log_success "Server Country: ${COUNTRY}"

# Handle Iran-specific configuration
if [ "$COUNTRY" = "IR" ]; then
    log_info "Iranian server detected, applying special configuration..."
    
    if [[ "$2" != '' ]]; then
        TYPE_OF_CONNECT=$2
    fi

    log_info "Updating DDNS..."
    curl -s --max-time 10 "https://ddns.shecan.ir/update?password=1e24cbe0ff267c08" >/dev/null 2>&1 || log_warn "DDNS update failed"
    log_info "Adding Server IP to Our System, Please Wait ..."
    sleep 90
    
    log_info "Configuring Shecan DNS servers..."
    rm -f /etc/resolv.conf
    cat >/etc/resolv.conf <<EOF
options timeout:1
nameserver 178.22.122.101
nameserver 185.51.200.1
EOF
    log_success "Shecan DNS configured"
fi

# Check OS and set release variable
log_info "Detecting operating system..."
if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    release=$ID
elif [[ -f /usr/lib/os-release ]]; then
    source /usr/lib/os-release
    release=$ID
else
    log_error "Failed to check the system OS, please contact the server author!"
    exit 1
fi

os_version=""
export os_version=$(grep -i version_id /etc/os-release | cut -d \" -f2 | cut -d . -f1)

log_info "Detected OS: $release $os_version"

# Validate OS version
if [[ "${release}" == "ubuntu" ]]; then
    if [[ ${os_version} -lt 20 ]]; then
        log_error "Please use Ubuntu 20 or higher"
        exit 1
    fi
elif [[ "${release}" == "debian" ]]; then
    if [[ ${os_version} -lt 11 ]]; then
        log_error "Please use Debian 11 or higher"
        exit 1
    fi
else
    log_error "Your operating system is not supported by this script."
    echo "Please ensure you are using one of the following supported operating systems:"
    echo "- Ubuntu 20.04+"
    echo "- Debian 11+"
    exit 1
fi

log_success "OS version validated"

# Prepare installation directory
log_info "Preparing installation directory..."
rm -fr /var/server-connector/
cd /var

# Install git and clone repository (common for both OS)
log_info "Updating package lists..."
apt update -y
log_info "Installing git..."
apt install git -y
log_info "Cloning server-connector repository..."
git clone https://github.com/chabokan/server-connector.git
log_success "Repository cloned"

# Run OS-specific setup
if [ "$release" = "ubuntu" ]; then
    log_info "Starting Ubuntu setup..."
    bash /var/server-connector/debian/ubuntu.sh
elif [ "$release" = "debian" ]; then
    log_info "Starting Debian setup..."
    bash /var/server-connector/debian/debian.sh
fi

log_success "Setup completed successfully!"
