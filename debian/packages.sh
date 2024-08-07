#!/bin/bash

# Color
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    release=$ID
elif [[ -f /usr/lib/os-release ]]; then
    source /usr/lib/os-release
    release=$ID
else
    echo "${RED}Failed to check the system OS, please contact the server author!${NC}" >&2
    exit 1
fi

if [ "$release" = "ubuntu" ]; then
    DEBIAN_FRONTEND=noninteractive apt install -y iptables-persistent sqlite3 pigz default-mysql-client nano jq vsftpd vim htop net-tools iputils-ping apache2-utils rkhunter supervisor net-tools htop fail2ban wget zip nmap git letsencrypt build-essential iftop dnsutils python3-venv python3-pip dsniff grepcidr iotop rsync atop software-properties-common
    git config --global credential.helper store
elif [ "$release" = "debian" ]; then
    apt --fix-broken install
    DEBIAN_FRONTEND=noninteractive apt install -y iptables-persistent sqlite3 pigz default-mysql-client nano jq vsftpd vim htop net-tools iputils-ping apache2-utils rkhunter supervisor net-tools htop fail2ban wget zip nmap git letsencrypt build-essential iftop dnsutils python3-venv python3-pip dsniff grepcidr iotop rsync atop software-properties-common
    git config --global credential.helper store
fi
