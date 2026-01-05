#!/bin/bash

# Firewall Configuration Script
# Configures iptables rules for server security

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

log_info "Flushing existing iptables rules..."
iptables -t filter -F DOCKER-USER 2>/dev/null || log_warn "DOCKER-USER chain not found"
iptables -t filter -F INPUT

host_ip=$(hostname -I | awk '{print $1}')
log_info "Host IP: $host_ip"

# Fetch allowed IPs from remote source
ALLOWED_IPS_URL="${ALLOWED_IPS_URL:-https://chabokan.net/ips.txt}"
log_info "Fetching allowed IP list from $ALLOWED_IPS_URL..."

temp_file=$(mktemp)
response=$(curl -s -w "%{http_code}" -o "$temp_file" --max-time 10 --connect-timeout 5 "$ALLOWED_IPS_URL" || echo "000")

if [ "$response" -eq 200 ] && [[ -s "$temp_file" ]]; then
    select_ip=$(cat "$temp_file")
    rm -f "$temp_file"
    log_info "Retrieved IP list, adding rules..."
    
    # Add allowed IPs to both chains
    while IFS= read -r ip || [[ -n "$ip" ]]; do
        [[ -z "$ip" ]] && continue
        iptables -A INPUT -s "$ip" -p tcp -m tcp -j ACCEPT
        iptables -A DOCKER-USER -s "$ip" -p tcp -m tcp -j ACCEPT 2>/dev/null || true
    done <<< "$select_ip"
else
    log_warn "Failed to retrieve IP list (HTTP $response). Proceeding with local network rules only."
    rm -f "$temp_file"
fi

# Local networks to allow
LOCAL_NETWORKS=(
    "$host_ip/32"
    "127.0.0.0/8"
    "10.0.0.0/8"
    "172.16.0.0/12"
    "192.168.0.0/16"
)

# Ports to block
BLOCKED_PORTS=(
    9990 3000 9000 8000 8081 8080 9093 9090 9100
)

# Add rules for INPUT and DOCKER-USER chains
for chain in INPUT DOCKER-USER; do
    # Allow local networks
    for network in "${LOCAL_NETWORKS[@]}"; do
        iptables -A $chain -s "$network" -p tcp -m tcp -j ACCEPT
    done
    
    # Block dangerous ports
    for port in "${BLOCKED_PORTS[@]}"; do
        iptables -A $chain -p tcp -m tcp --dport "$port" -j DROP
    done
done

# Block HTTP on DOCKER-USER only
iptables -A DOCKER-USER -p tcp -m tcp --dport 80 -j DROP

# Return rule for DOCKER-USER chain
iptables -A DOCKER-USER -j RETURN

# Save rules
log_info "Saving iptables rules..."
mkdir -p /etc/iptables
if iptables-save > /etc/iptables/rules.v4 2>/dev/null; then
    log_info "Rules saved to /etc/iptables/rules.v4"
else
    log_warn "Failed to save rules to /etc/iptables/rules.v4"
fi

log_info "Firewall configuration completed successfully"
