#!/bin/bash

# Color
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

set -e
# Eror handeling
trap "echo -e '${RED}ERROR: Run the command again and select a different type of connection!${NC}'" ERR

if [[ "$1" != '' ]]; then
    TOKEN=$1
else
    read -p "Enter TOKEN: " TOKEN
fi

os_version=""
os_version=$(grep -i version_id /etc/os-release | cut -d \" -f2 | cut -d . -f1)

if [ $os_version -lt 11 ]; then
    echo -e "${RED} Please use Debian 11 or higher ${NC}\n" && exit 1
fi

echo -e "${GREEN}set Tehran Timezone ...${NC}"
TZ=Asia/Tehran
ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone


echo -e "${GREEN}updating os ...${NC}"
apt update -y

echo -e "${GREEN}disable ipv6 ...${NC}"
sysctl -w net.ipv6.conf.all.disable_ipv6=1
sysctl -w net.ipv6.conf.default.disable_ipv6=1
sysctl -w net.ipv6.conf.lo.disable_ipv6=1
sysctl -p

echo -e "${GREEN}install useful packages ....${NC}"
apt --fix-broken install
DEBIAN_FRONTEND=noninteractive apt install -y iptables-persistent sqlite3 pigz default-mysql-client nano jq vsftpd vim htop net-tools iputils-ping apache2-utils rkhunter supervisor net-tools htop fail2ban wget zip nmap git letsencrypt build-essential iftop dnsutils python3-pip dsniff grepcidr iotop rsync atop software-properties-common
git config --global credential.helper store

debconf-set-selections <<EOF
iptables-persistent iptables-persistent/autosave_v4 boolean true
iptables-persistent iptables-persistent/autosave_v6 boolean true
EOF

echo -e "${GREEN}install docker ....${NC}"
if [ $os_version = "12" ]; then
    for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do apt-get remove $pkg; done
elif [ $os_version = "11" ]; then
    for pkg in docker.io docker-doc docker-compose docker-compose-v2 containerd runc; do apt-get remove $pkg; done
fi
apt-get update -y
DEBIAN_FRONTEND=noninteractive apt install -y ca-certificates curl gnupg
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
    tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update
if [ $os_version = "12" ]; then
    VERSION_STRING=5:25.0.3-1~debian.12~bookworm
    DEBIAN_FRONTEND=noninteractive apt install -y docker-ce=$VERSION_STRING docker-ce-cli=$VERSION_STRING containerd.io docker-buildx-plugin docker-compose-plugin
elif [ $os_version = "11" ]; then
    VERSION_STRING=5:25.0.3-1~debian.11~bullseye
    DEBIAN_FRONTEND=noninteractive apt install -y docker-ce=$VERSION_STRING docker-ce-cli=$VERSION_STRING containerd.io docker-buildx-plugin docker-compose-plugin 
else
    echo -e "${RED} not proper version, please check your debian version first.${NC}"
    exit 1
fi
apt-mark hold docker-ce docker-ce-cli
apt purge postfix -y

mkdir -p /builds
mkdir -p /storage
mkdir -p /backups

echo "0 3 * * * root bash /var/ch-manager/update_core.sh >> /dev/null 2>&1" > /etc/cron.d/update-core
echo "0 6 * * * root git pull /var/server-connector >> /dev/null 2>&1" > /etc/cron.d/update-packages
echo "0 7 * * * root bash /var/server-connector/debian/packages.sh >> /dev/null 2>&1" > /etc/cron.d/update-packages
service cron restart

echo -e "${GREEN}installing node manager ....${NC}"
rm -rf /var/ch-manager
git clone https://github.com/chabokan/node-manager /var/ch-manager
cd /var/ch-manager/

pip3 install --break-system-packages -r requirements.txt
sleep 2
pip3 install --break-system-packages -r requirements.txt


if [ $COUNTRY = "IR" ]; then
  unset http_proxy
  unset https_proxy
fi

if ! [ -f "/var/ch-manager/sql_app.db" ]
then
   alembic upgrade head
fi
docker compose down
docker compose up -d

declare -p | grep -Ev 'BASHOPTS|BASH_VERSINFO|EUID|PPID|SHELLOPTS|UID' > /.env

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

bash /var/server-connector/configs/firewall.sh

if [ $COUNTRY = "IR" ]; then
echo -e "${GREEN}add shecan dns ...${NC}"
    rm /etc/resolv.conf
    cat >/etc/resolv.conf <<EOF
options timeout:1
nameserver 178.22.122.100
nameserver 185.51.200.2
EOF
fi

sleep 15

# Define the URL
url="http://0.0.0.0:8123/api/v1/connect/?token=${TOKEN}"

# Make the POST request with curl
response=$(curl -X POST -H "Content-Type: application/json" -d "" "$url")

# Print the response
success_response=$(echo $response | jq -r '.success')

message_response=$(echo $response | jq -r '.response.message')

if [ "$success_response" == "true" ]; then
  echo -e "${GREEN}------------ Node connected to chabokan successfully ------------${NC}"

elif [ "$success_response" == "false" ]; then

  if [ "$message_response"  == "null" ]; then
     message=$(echo $response | jq -r '.message')
     echo -e "${YELLOW}Error:$message${NC}"
  else
     message=$(echo $response | jq -r '.response.message[]')
     echo -e "${RED}Error: $message${NC}"
  fi

else
  echo -e "${RED}$response${NC}"
fi
