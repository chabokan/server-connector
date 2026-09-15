#!/bin/bash

# System Settings Configuration Script
# Configures system-wide settings, cron jobs, and services

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
    restart_service() {
        systemctl restart "$1" 2>/dev/null || service "$1" restart 2>/dev/null || true
    }
}

if declare -f on_error >/dev/null 2>&1; then
    trap 'on_error $LINENO' ERR
else
    trap 'log_error "settings.sh failed at line $LINENO"; exit 1' ERR
fi

DISABLE_IPV6="${DISABLE_IPV6:-1}"
if [[ "$DISABLE_IPV6" == "1" ]]; then
    log_info "Disabling IPv6..."
    sysctl -w net.ipv6.conf.all.disable_ipv6=1 >/dev/null 2>&1 || log_warn "Failed to disable IPv6 on all interfaces"
    sysctl -w net.ipv6.conf.default.disable_ipv6=1 >/dev/null 2>&1 || log_warn "Failed to disable IPv6 on default"
    sysctl -w net.ipv6.conf.lo.disable_ipv6=1 >/dev/null 2>&1 || log_warn "Failed to disable IPv6 on loopback"
    # Persist across reboot
    cat > /etc/sysctl.d/99-disable-ipv6.conf <<'EOF'
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOF
    sysctl --system >/dev/null 2>&1 || true
    log_success "IPv6 disabled"
fi

log_info "Configuring iptables-persistent..."
debconf-set-selections <<EOF 2>/dev/null || log_warn "Failed to set debconf selections"
iptables-persistent iptables-persistent/autosave_v4 boolean true
iptables-persistent iptables-persistent/autosave_v6 boolean true
EOF

log_info "Creating required directories..."
mkdir -p /builds /storage /backups
chmod 755 /builds /storage /backups

log_info "Configuring cron jobs..."

if [[ -f /var/ch-manager/update_core.sh ]]; then
    cat > /etc/cron.d/update-core <<'EOF'
0 3 * * * root flock /var/lock/chabokan-server-queue.lock bash /var/ch-manager/update_core.sh >> /var/log/update-core.log 2>&1
EOF
    chmod 644 /etc/cron.d/update-core
    log_info "Core update cron job configured"
fi

# Safer daily pull (working-tree aware) — package reinstall is weekly, not daily
cat > /etc/cron.d/update-packages <<'EOF'
0 6 * * * root git -C /var/server-connector pull --ff-only >> /var/log/update-packages.log 2>&1
0 7 * * 0 root bash /var/server-connector/debian/packages.sh >> /var/log/update-packages.log 2>&1
EOF
chmod 644 /etc/cron.d/update-packages
log_info "Package update cron jobs configured (pull daily, packages weekly)"

if [[ -d /var/ch-manager ]] && [[ -f /var/ch-manager/server-queue.py ]]; then
    if [[ -f /var/ch-manager/venv/bin/activate ]]; then
        QUEUE_CMD="cd /var/ch-manager && source venv/bin/activate && python3 server-queue.py"
    else
        QUEUE_CMD="cd /var/ch-manager && python3 server-queue.py"
    fi

    cat > /etc/cron.d/server-queue <<EOF
SHELL=/bin/bash
BASH_ENV=/.env
*/1 * * * * root flock -n /var/lock/chabokan-server-queue.lock bash -c '$QUEUE_CMD' >> /var/log/server-queue.log 2>&1
EOF
    chmod 644 /etc/cron.d/server-queue
    log_info "Server queue cron job configured"
fi

restart_service cron

# Configure vsftpd
log_info "Configuring vsftpd..."
if [[ -f /var/server-connector/configs/vsftpd.conf ]]; then
    cp /var/server-connector/configs/vsftpd.conf /etc/vsftpd.conf
    sed -i 's,\r,,;s, *$,,' /etc/vsftpd.conf
    # Align with IPv6 disable: force IPv4 listen
    if [[ "$DISABLE_IPV6" == "1" ]]; then
        sed -i 's/^listen=.*/listen=YES/' /etc/vsftpd.conf
        sed -i 's/^listen_ipv6=.*/listen_ipv6=NO/' /etc/vsftpd.conf
    fi
    chmod 644 /etc/vsftpd.conf
    log_success "vsftpd configuration updated"
else
    log_warn "vsftpd.conf not found, skipping vsftpd configuration"
fi

log_info "Restarting services..."
restart_service vsftpd

CLEANUP_CONFIGS="${CLEANUP_CONFIGS:-0}"
if [[ "$CLEANUP_CONFIGS" == "1" ]]; then
    log_info "Cleaning up temporary config files..."
    rm -f /var/server-connector/configs/vsftpd.conf
fi

log_success "System settings configuration completed"
