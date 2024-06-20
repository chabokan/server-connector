#!/bin/bash

# Color
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

set -e
# Eror handeling
trap "echo -e '${RED}ERROR: Run the command again and select a different type of connection!${NC}'" ERR

echo -e "${GREEN}disable systemd resolved ...${NC}"
systemctl disable systemd-resolved.service
systemctl stop systemd-resolved


echo -e "${GREEN}updating os ...${NC}"
apt update -y

echo -e "${GREEN}install useful packages ....${NC}"
bash /var/server-connector/debian/packages.sh


os_version=""
export os_version=$(grep -i version_id /etc/os-release | cut -d \" -f2 | cut -d . -f1)

echo -e "${GREEN}install docker ....${NC}"
if [ $os_version = "22" ]; then
    for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do apt-get remove $pkg; done
elif [ $os_version = "20" ]; then
    for pkg in docker.io docker-doc docker-compose docker-compose-v2 containerd runc; do apt-get remove $pkg; done
fi
apt-get update -y
DEBIAN_FRONTEND=noninteractive apt install -y ca-certificates curl gnupg
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --batch --yes --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
echo \
    "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
    "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | \
    tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update
if [ $os_version = "22" ]; then
    VERSION_STRING=5:25.0.3-1~ubuntu.22.04~jammy
    DEBIAN_FRONTEND=noninteractive apt install -y docker-ce=$VERSION_STRING docker-ce-cli=$VERSION_STRING containerd.io docker-buildx-plugin docker-compose-plugin
elif [ $os_version = "20" ]; then
    VERSION_STRING=5:25.0.3-1~ubuntu.20.04~focal
    DEBIAN_FRONTEND=noninteractive apt install -y docker-ce=$VERSION_STRING docker-ce-cli=$VERSION_STRING containerd.io docker-buildx-plugin docker-compose-plugin
else
    echo -e "${RED} not proper version, please check your ubuntu version first.${NC}"
    exit 1
fi
apt-mark hold docker-ce docker-ce-cli
apt purge postfix -y


echo -e "${GREEN}installing node manager ....${NC}"

rm -rf /var/ch-manager
git clone https://github.com/chabokan/node-manager /var/ch-manager
cd /var/ch-manager/
pip3 install -r requirements.txt
sleep 2
pip3 install -r requirements.txt
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

bash /var/server-connector/debian/settings.sh

bash /var/server-connector/utilities/firewall.sh

bash /var/server-connector/utilities/finall.sh
