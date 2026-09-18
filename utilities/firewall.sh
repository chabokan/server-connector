#!/bin/bash

# Firewall Configuration Script
# Configures iptables rules for server security

set -euo pipefail

# Host jobs run without a login shell; sshd and iptables are often in sbin.
export PATH="/usr/sbin:/sbin:${PATH}"

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
}

if declare -f on_error >/dev/null 2>&1; then
    trap 'on_error $LINENO' ERR
else
    trap 'log_error "firewall.sh failed at line $LINENO"; exit 1' ERR
fi

ensure_docker_user_chain() {
    if ! iptables -t filter -L DOCKER-USER -n >/dev/null 2>&1; then
        log_info "Creating DOCKER-USER chain..."
        iptables -t filter -N DOCKER-USER 2>/dev/null || true
        # Hook into FORWARD if Docker has not already done so
        if ! iptables -t filter -C FORWARD -j DOCKER-USER >/dev/null 2>&1; then
            iptables -t filter -I FORWARD -j DOCKER-USER 2>/dev/null || true
        fi
    fi
}

ssh_ports=()
if command -v sshd >/dev/null 2>&1; then
    while IFS= read -r port; do
        [[ "$port" =~ ^[0-9]+$ ]] || continue
        (( 10#$port >= 1 && 10#$port <= 65535 )) || continue
        ssh_ports+=("$port")
    done < <(sshd -T 2>/dev/null | awk '$1 == "port" {print $2}')
fi

# A systemd SSH socket may listen on a different port from sshd_config.
if [[ -n "${SSH_CONNECTION:-}" ]]; then
    read -r _ _ _ connected_port <<< "$SSH_CONNECTION"
    if [[ "${connected_port:-}" =~ ^[0-9]+$ ]] &&
       (( 10#$connected_port >= 1 && 10#$connected_port <= 65535 )); then
        ssh_ports+=("$connected_port")
    fi
fi

if (( ${#ssh_ports[@]} == 0 )); then
    error_exit "Could not detect the existing SSH port; firewall rules were not changed"
fi

log_info "Preparing firewall chains..."
ensure_docker_user_chain

log_info "Flushing existing custom rules (INPUT + DOCKER-USER)..."
iptables -t filter -F DOCKER-USER 2>/dev/null || log_warn "DOCKER-USER chain not available yet"
iptables -t filter -F INPUT

# Keep established sessions (including current SSH) alive after flush
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || \
    iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT -i lo -j ACCEPT

# Preserve new SSH connections on the existing port(s) after flushing INPUT.
while IFS= read -r port; do
    iptables -A INPUT -p tcp --dport "$port" -j ACCEPT
    log_info "Keeping SSH port $port open"
done < <(printf '%s\n' "${ssh_ports[@]}" | sort -nu)

host_ip=$(hostname -I | awk '{print $1}')
log_info "Host IP: $host_ip"

ALLOWED_IPS_URL="${ALLOWED_IPS_URL:-https://chabokan.net/ips.txt}"
log_info "Fetching allowed IP list from $ALLOWED_IPS_URL..."

temp_file=$(mktemp)
http_code=$(curl -sS -w "%{http_code}" -o "$temp_file" --max-time 15 --connect-timeout 5 "$ALLOWED_IPS_URL" 2>/dev/null || true)
[[ "$http_code" =~ ^[0-9]{3}$ ]] || http_code="000"

if [[ "$http_code" == "200" ]] && [[ -s "$temp_file" ]]; then
    select_ip=$(cat "$temp_file")
    rm -f "$temp_file"
    ip_count=$(echo "$select_ip" | grep -c '[^[:space:]]' || echo 0)
    log_info "Retrieved IP list ($ip_count entries), adding rules..."

    while IFS= read -r ip || [[ -n "$ip" ]]; do
        [[ -z "$ip" ]] && continue
        [[ "$ip" =~ ^# ]] && continue
        iptables -A INPUT -s "$ip" -p tcp -m tcp -j ACCEPT
        iptables -A DOCKER-USER -s "$ip" -p tcp -m tcp -j ACCEPT 2>/dev/null || true
    done <<< "$select_ip"
else
    log_warn "Failed to retrieve IP list (HTTP ${http_code}). Proceeding with local network rules only."
    rm -f "$temp_file"
fi

LOCAL_NETWORKS=(
    "$host_ip/32"
    "127.0.0.0/8"
    "10.0.0.0/8"
    "172.16.0.0/12"
    "192.168.0.0/16"
)

BLOCKED_PORTS=(
    9990 3000 9000 8000 8081 8080 9093 9090 9100
)

for chain in INPUT DOCKER-USER; do
    if [[ "$chain" == "DOCKER-USER" ]] && ! iptables -t filter -L DOCKER-USER -n >/dev/null 2>&1; then
        log_warn "Skipping DOCKER-USER rules — chain missing"
        continue
    fi

    for network in "${LOCAL_NETWORKS[@]}"; do
        iptables -A "$chain" -s "$network" -p tcp -m tcp -j ACCEPT 2>/dev/null || true
    done

    for port in "${BLOCKED_PORTS[@]}"; do
        iptables -A "$chain" -p tcp -m tcp --dport "$port" -j DROP 2>/dev/null || true
    done
done

if iptables -t filter -L DOCKER-USER -n >/dev/null 2>&1; then
    iptables -A DOCKER-USER -p tcp -m tcp --dport 80 -j DROP
    iptables -A DOCKER-USER -j RETURN
fi

log_info "Saving iptables rules..."
mkdir -p /etc/iptables
if iptables-save > /etc/iptables/rules.v4 2>/dev/null; then
    log_success "Rules saved to /etc/iptables/rules.v4"
else
    log_warn "Failed to save rules to /etc/iptables/rules.v4"
fi

# Best-effort restore on boot via netfilter-persistent
if command_exists netfilter-persistent; then
    netfilter-persistent save 2>/dev/null || true
fi

log_success "Firewall configuration completed"
