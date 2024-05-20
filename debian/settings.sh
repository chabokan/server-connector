#!/bin/bash

# Color
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}disable ipv6 ...${NC}"
sysctl -w net.ipv6.conf.all.disable_ipv6=1
sysctl -w net.ipv6.conf.default.disable_ipv6=1
sysctl -w net.ipv6.conf.lo.disable_ipv6=1
sysctl -p

debconf-set-selections <<EOF
iptables-persistent iptables-persistent/autosave_v4 boolean true
iptables-persistent iptables-persistent/autosave_v6 boolean true
EOF

mkdir -p /builds
mkdir -p /storage
mkdir -p /backups

echo "0 3 * * * root bash /var/ch-manager/update_core.sh >> /dev/null 2>&1
" > /etc/cron.d/update-core
echo "0 6 * * * root git --git-dir=/var/server-connector/.git pull >> /dev/null 2>&1
0 7 * * * root bash /var/server-connector/debian/packages.sh >> /dev/null 2>&1
" > /etc/cron.d/update-packages
service cron restart

echo -e "SHELL=/bin/bash
BASH_ENV=/.env
*/1 * * * * root cd /var/ch-manager/ && python3 server-queue.py > /dev/null 2>&1
" > /etc/cron.d/server-queue
service cron restart

cp /var/server-connector/configs/vsftpd.conf /etc/vsftpd.conf
sed -i 's,\r,,;s, *$,,' /etc/vsftpd.conf
cp /var/server-connector/configs/sshd_config /etc/ssh/sshd_config

service ssh restart
service sshd restart
service vsftpd restart

rm -rf /var/server-connector/configs/vsftpd.conf
rm -rf /var/server-connector/configs/sshd_config
