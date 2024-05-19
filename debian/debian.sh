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

echo -e "${GREEN}updating os ...${NC}"
apt update -y


echo -e "${GREEN}install useful packages ....${NC}"
bash /var/server-connector/debian/packages.sh

echo -e "${GREEN}install docker ....${NC}"
if [ $os_version = "12" ]; then
    for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do apt-get remove $pkg; done
elif [ $os_version = "11" ]; then
    for pkg in docker.io docker-doc docker-compose containerd runc; do apt-get remove $pkg; done
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

bash /var/server-connector/debian/commands.sh

bash /var/server-connector/utilities/firewall.sh

bash /var/server-connector/utilities/finall.sh