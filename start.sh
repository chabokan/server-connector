#!/bin/bash

# Color
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

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

UBUNTU_VERSION=$(lsb_release -c)
UBUNTU_VERSION=${UBUNTU_VERSION#*:}

echo -e "${GREEN}set Tehran Timezone ...${NC}"
TZ=Asia/Tehran
ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

echo -e "${GREEN}disable systemd resolved ...${NC}"
systemctl disable systemd-resolved.service
systemctl stop systemd-resolved

echo -e "${GREEN}updating os ...${NC}"
apt update -y && upgrade -y

echo -e "${GREEN}disable ipv6 ...${NC}"
sysctl -w net.ipv6.conf.all.disable_ipv6=1
sysctl -w net.ipv6.conf.default.disable_ipv6=1
sysctl -w net.ipv6.conf.lo.disable_ipv6=1
sysctl -p

echo -e "${GREEN}install useful packages ....${NC}"
DEBIAN_FRONTEND=noninteractive apt install -y iptables-persistent nano vim htop net-tools iputils-ping apache2-utils rkhunter supervisor net-tools htop fail2ban wget zip nmap git letsencrypt build-essential iftop dnsutils dsniff grepcidr iotop rsync atop software-properties-common
git config --global credential.helper store

debconf-set-selections <<EOF
iptables-persistent iptables-persistent/autosave_v4 boolean true
iptables-persistent iptables-persistent/autosave_v6 boolean true
EOF

echo -e "${GREEN}install Minio mc ....${NC}"
curl https://public-chabok.s3.ir-thr-at1.arvanstorage.com/minio-mc \
  --create-dirs \
  -o /usr/local/bin/mc

chmod +x /usr/local/bin/mc


echo -e "${GREEN}install docker ....${NC}"
for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do sudo apt-get remove $pkg; done
apt-get update
DEBIAN_FRONTEND=noninteractive apt install -y ca-certificates curl gnupg
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --yes --dearmor -o /etc/apt/keyrings/docker.gpg
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
git clone https://github.com/chabokan/node-manager /var/manager
cd /var/manager
docker compose up -d

# Define the URL
url="http://0.0.0.0:8123/api/v1/connect/"

# Define the JSON request body

# shellcheck disable=SC2016
data='{"token": "'$TOKEN'"}'

# Make the POST request with curl
response=$(curl -X POST -H "Content-Type: application/json" -d "$data" "$url")

# Print the response
echo "Response: $response"