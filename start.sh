#!/bin/bash

# Color
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color
set -e

if [ -n "$1" ]; then
    TOKEN=$1
else
    read -p "Enter TOKEN: " TOKEN
fi


if [[ $(uname -a) == *Ubuntu* ]]; then
        echo -e "${GREEN}YES! This is Ubuntu.${NC}"
else
    echo -e "${RED}Sorry! This operating system does not supported.${NC}"
    exit 1
fi


SERVER_IP=$(hostname -I | awk '{print $1}')
IP_CHECK_URL="https://api.country.is/$SERVER_IP"
CHECK_IP=$(curl -s "$IP_CHECK_URL")
if echo "$CHECK_IP" | grep -q "\"error\""; then
  echo -e "${RED} Error! IP address not found ${NC}"
  exit 1
fi

COUNTRY=$(echo "$CHECK_IP" | grep -o -P '"country":"\K[^"]+' | tr -d \")

echo -e "${GREEN}Server IP: ${SERVER_IP} ${NC}"
echo -e "${GREEN}Server Country: ${COUNTRY} ${NC}"

UBUNTU_VERSION=$(lsb_release -c)
UBUNTU_VERSION=${UBUNTU_VERSION#*:}

echo -e "${GREEN}set Tehran Timezone ...${NC}"
TZ=Asia/Tehran
ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

echo -e "${GREEN}disable systemd resolved ...${NC}"
systemctl disable systemd-resolved.service
systemctl stop systemd-resolved

echo -e "${GREEN}add base dns ...${NC}"
    rm /etc/resolv.conf
    cat >/etc/resolv.conf <<EOF
options timeout:1
nameserver 8.8.8.8
nameserver 1.1.1.1
EOF


if [ $COUNTRY = "IR" ]; then
echo -e "${GREEN}add base dns ...${NC}"
    rm /etc/resolv.conf
    cat >/etc/resolv.conf <<EOF
options timeout:1
nameserver 178.22.122.100
nameserver 185.51.200.2
EOF
    echo -e "${GREEN}change server repo ...${NC}"
    sed -i 's/http:\/\/archive.ubuntu.com/http:\/\/ir.archive.ubuntu.com/g' /etc/apt/sources.list
    sed -i 's/http:\/\/security.ubuntu.com/http:\/\/ir.archive.ubuntu.com/g' /etc/apt/sources.list
    sed -i 's/http:\/\/[a-z]*.archive.ubuntu.com/http:\/\/ir.archive.ubuntu.com/g' /etc/apt/sources.list
    sed -i 's/http:\/\/[a-z]*.[a-z]*.archive.ubuntu.com/http:\/\/ir.archive.ubuntu.com/g' /etc/apt/sources.list
    sed -i 's/http:\/\/[a-z]*.[a-z]*.[a-z]*.archive.ubuntu.com/http:\/\/ir.archive.ubuntu.com/g' /etc/apt/sources.list
    sed -i 's/http:\/\/[a-z]*.[a-z]*.[a-z]*.[a-z]*.archive.ubuntu.com/http:\/\/ir.archive.ubuntu.com/g' /etc/apt/sources.list
    sed -i 's/http:\/\/[a-z]*.security.ubuntu.com/http:\/\/ir.archive.ubuntu.com/g' /etc/apt/sources.list
fi

echo -e "${GREEN}updating os ...${NC}"
apt update -y

echo -e "${GREEN}disable ipv6 ...${NC}"
sysctl -w net.ipv6.conf.all.disable_ipv6=1
sysctl -w net.ipv6.conf.default.disable_ipv6=1
sysctl -w net.ipv6.conf.lo.disable_ipv6=1
sysctl -p

echo -e "${GREEN}install useful packages ....${NC}"
DEBIAN_FRONTEND=noninteractive apt install -y iptables-persistent sqlite3 pigz nano vsftpd vim htop net-tools iputils-ping apache2-utils rkhunter supervisor net-tools htop fail2ban wget zip nmap git letsencrypt build-essential iftop dnsutils python3-pip dsniff grepcidr iotop rsync atop software-properties-common
git config --global credential.helper store

debconf-set-selections <<EOF
iptables-persistent iptables-persistent/autosave_v4 boolean true
iptables-persistent iptables-persistent/autosave_v6 boolean true
EOF

echo -e "${GREEN}install Minio mc ....${NC}"
curl https://public-chabok.s3.ir-thr-at1.arvanstorage.com/minio-mc-new \
  --create-dirs \
  -o /usr/local/bin/mc

chmod +x /usr/local/bin/mc
if [ $COUNTRY = "IR" ]; then
  export http_proxy='http://fodev.org:8118'    
  export https_proxy='http://fodev.org:8118'
fi
echo -e "${GREEN}install docker ....${NC}"
for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do sudo apt-get remove $pkg; done
apt-get update
DEBIAN_FRONTEND=noninteractive apt install -y ca-certificates curl gnupg
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --batch --yes --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update

if [ $UBUNTU_VERSION = "focal" ]; then
    VERSION_STRING=5:25.0.3-1~ubuntu.20.04~focal
    DEBIAN_FRONTEND=noninteractive apt install -y docker-ce=$VERSION_STRING docker-ce-cli=$VERSION_STRING containerd.io docker-buildx-plugin docker-compose-plugin
elif [ $UBUNTU_VERSION = "jammy" ]; then
    VERSION_STRING=5:25.0.3-1~ubuntu.22.04~jammy
    DEBIAN_FRONTEND=noninteractive apt install -y docker-ce=$VERSION_STRING docker-ce-cli=$VERSION_STRING containerd.io docker-buildx-plugin docker-compose-plugin
else
    echo -e "${RED} not proper version, please check your ubuntu version first.${NC}"
    exit 1
fi
apt-mark hold docker-ce docker-ce-cli

apt purge postfix -y

mkdir -p /builds
mkdir -p /storage
mkdir -p /backups

echo -e "${GREEN}installing node manager ....${NC}"
rm -rf /var/ch-manager
git clone https://github.com/chabokan/node-manager /var/ch-manager
cd /var/ch-manager/

pip3 install -r requirements.txt
sleep 2
pip3 install -r requirements.txt

alembic upgrade head

docker compose up -d
if [ $COUNTRY = "IR" ]; then
  unset http_proxy
  unset https_proxy
fi

declare -p | grep -Ev 'BASHOPTS|BASH_VERSINFO|EUID|PPID|SHELLOPTS|UID' > /.env

echo -e "SHELL=/bin/bash
BASH_ENV=/.env
*/1 * * * * root cd /var/ch-manager/ && python3 server-queue.py > /dev/null 2>&1
" > /etc/cron.d/server-queue
service cron restart

cd /tmp
wget https://raw.githubusercontent.com/chabokan/server-connector/main/vsftpd.conf -O vsftpd.conf
wget https://raw.githubusercontent.com/chabokan/server-connector/main/sshd_config -O sshd_config

cp ./vsftpd.conf /etc/vsftpd.conf
sed -i 's,\r,,;s, *$,,' /etc/vsftpd.conf
cp ./sshd_config /etc/ssh/sshd_config

service ssh restart
service sshd restart
service vsftpd restart

rm -rf ./vsftpd.conf
rm -rf ./sshd_config

curl -s https://raw.githubusercontent.com/chabokan/server-connector/main/firewall.sh | bash

sleep 15

# Define the URL
url="http://0.0.0.0:8123/api/v1/connect/?token=${TOKEN}"

# Make the POST request with curl
response=$(curl -X POST -H "Content-Type: application/json" -d "" "$url")

# Print the response
echo "Response: $response"
