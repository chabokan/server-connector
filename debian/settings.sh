#!/bin/bash

# System Settings Configuration Script
# Configures system-wide settings, cron jobs, and services

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
    restart_service() {
        systemctl restart "$1" 2>/dev/null || service "$1" restart 2>/dev/null || true
    }
}

# Disable IPv6 (optional - can be configured)
DISABLE_IPV6="${DISABLE_IPV6:-1}"
if [[ "$DISABLE_IPV6" == "1" ]]; then
    log_info "Disabling IPv6..."
    sysctl -w net.ipv6.conf.all.disable_ipv6=1 >/dev/null 2>&1 || log_warn "Failed to disable IPv6 on all interfaces"
    sysctl -w net.ipv6.conf.default.disable_ipv6=1 >/dev/null 2>&1 || log_warn "Failed to disable IPv6 on default"
    sysctl -w net.ipv6.conf.lo.disable_ipv6=1 >/dev/null 2>&1 || log_warn "Failed to disable IPv6 on loopback"
    sysctl -p >/dev/null 2>&1 || true
    log_info "IPv6 disabled"
fi

# Configure iptables-persistent
log_info "Configuring iptables-persistent..."
debconf-set-selections <<EOF 2>/dev/null || log_warn "Failed to set debconf selections"
iptables-persistent iptables-persistent/autosave_v4 boolean true
iptables-persistent iptables-persistent/autosave_v6 boolean true
EOF

# Create required directories
log_info "Creating required directories..."
mkdir -p /builds /storage /backups
chmod 755 /builds /storage /backups

# Setup cron jobs
log_info "Configuring cron jobs..."

# Update core script (if exists)
if [[ -f /var/ch-manager/update_core.sh ]]; then
    cat > /etc/cron.d/update-core <<'EOF'
0 3 * * * root bash /var/ch-manager/update_core.sh >> /var/log/update-core.log 2>&1
EOF
    chmod 644 /etc/cron.d/update-core
    log_info "Core update cron job configured"
fi

# Update packages and repository
cat > /etc/cron.d/update-packages <<'EOF'
0 6 * * * root git --git-dir=/var/server-connector/.git pull >> /var/log/update-packages.log 2>&1
0 7 * * * root bash /var/server-connector/debian/packages.sh >> /var/log/update-packages.log 2>&1
EOF
chmod 644 /etc/cron.d/update-packages
log_info "Package update cron jobs configured"

# Server queue (if node-manager is installed)
if [[ -d /var/ch-manager ]] && [[ -f /var/ch-manager/server-queue.py ]]; then
    # Determine if using venv or system python
    if [[ -f /var/ch-manager/venv/bin/activate ]]; then
        QUEUE_CMD="cd /var/ch-manager && source venv/bin/activate && python3 server-queue.py"
    else
        QUEUE_CMD="cd /var/ch-manager && python3 server-queue.py"
    fi
    
    cat > /etc/cron.d/server-queue <<EOF
SHELL=/bin/bash
BASH_ENV=/.env
*/1 * * * * root $QUEUE_CMD >> /var/log/server-queue.log 2>&1
EOF
    chmod 644 /etc/cron.d/server-queue
    log_info "Server queue cron job configured"
fi

# Restart cron service
restart_service cron

# Configure vsftpd
log_info "Configuring vsftpd..."
if [[ -f /var/server-connector/configs/vsftpd.conf ]]; then
    cp /var/server-connector/configs/vsftpd.conf /etc/vsftpd.conf
    # Remove Windows line endings and trailing spaces
    sed -i 's,\r,,;s, *$,,' /etc/vsftpd.conf
    chmod 644 /etc/vsftpd.conf
    log_info "vsftpd configuration updated"
else
    log_warn "vsftpd.conf not found, skipping vsftpd configuration"
fi

# Configure SSH
log_info "Configuring SSH..."
if [[ -f /var/server-connector/configs/sshd_config ]]; then
    # Backup existing config
    if [[ -f /etc/ssh/sshd_config ]]; then
        cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup.$(date +%s)
    fi
    
    cp /var/server-connector/configs/sshd_config /etc/ssh/sshd_config
    chmod 644 /etc/ssh/sshd_config
    
    # Validate SSH config before restarting
    if sshd -t 2>/dev/null; then
        log_info "SSH configuration validated"
    else
        log_warn "SSH configuration validation failed, but proceeding..."
    fi
    
    log_info "SSH configuration updated"
else
    log_warn "sshd_config not found, skipping SSH configuration"
fi

# Restart services
log_info "Restarting services..."
restart_service ssh
restart_service sshd
restart_service vsftpd

# Cleanup config files (optional - can be kept for reference)
CLEANUP_CONFIGS="${CLEANUP_CONFIGS:-1}"
if [[ "$CLEANUP_CONFIGS" == "1" ]]; then
    log_info "Cleaning up temporary config files..."
    rm -f /var/server-connector/configs/vsftpd.conf
    rm -f /var/server-connector/configs/sshd_config
fi

log_info "System settings configuration completed successfully"
