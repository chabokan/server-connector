#!/bin/bash

# Color
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# check root user
[[ $EUID -ne 0 ]] && echo -e "${RED}Fatal error: ${NC} Please run command with root privilege \n " && exit 1

set -e

unset http_proxy
unset https_proxy

echo -e "${GREEN}add base dns ...${NC}"
    rm /etc/resolv.conf
    cat >/etc/resolv.conf <<EOF
options timeout:1
nameserver 8.8.8.8
nameserver 1.1.1.1
EOF


if [[ "$1" != '' ]]; then
    TOKEN=$1
else
    read -p "Enter TOKEN: " TOKEN
fi
export TOKEN

if [[ "$2" != '' ]]; then
    HUB_URL=$1
else
    read -p "Enter HUB URL (ex:hub.chabokan.net): " HUB_URL
fi
export HUB_URL

echo -e "${GREEN}set Tehran Timezone ...${NC}"
TZ=Asia/Tehran
ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

SERVER_IP=$(hostname -I | awk '{print $1}')
IP_CHECK_URL="https://api.country.is/$SERVER_IP"
CHECK_IP=$(curl -s "$IP_CHECK_URL")
if echo "$CHECK_IP" | grep -q "\"error\""; then
  echo -e "${RED} Error! IP address not found ${NC}"
  exit 1
fi

COUNTRY=$(echo "$CHECK_IP" | grep -o -P '"country":"\K[^"]+' | tr -d \")
export COUNTRY

echo -e "${GREEN}Server IP: ${SERVER_IP} ${NC}"
echo -e "${GREEN}Server Country: ${COUNTRY} ${NC}"

if [ "$COUNTRY" = "IR" ]; then
    if [[ "$2" != '' ]]; then
        TYPE_OF_CONNECT=$2
    fi

    curl https://ddns.shecan.ir/update?password=1e24cbe0ff267c08
    echo -e "\nAdding Server IP to Our System, Please Wait ..."
    sleep 90
    rm /etc/resolv.conf
    cat >/etc/resolv.conf <<EOF
options timeout:1
nameserver 178.22.122.101
nameserver 185.51.200.1
EOF

fi


# Check OS and set release variable
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

os_version=""
export os_version=$(grep -i version_id /etc/os-release | cut -d \" -f2 | cut -d . -f1)

if [[ "${release}" == "ubuntu" ]]; then
    if [[ ${os_version} -lt 20 ]]; then
        echo -e "${RED} Please use Ubuntu 20 or higher ${NC}\n" && exit 1
    fi
elif [[ "${release}" == "debian" ]]; then
    if [[ ${os_version} -lt 11 ]]; then
        echo -e "${RED} Please use Debian 11 or higher ${NC}\n" && exit 1
    fi
else
    echo -e "${RED}Your operating system is not supported by this script.${NC}\n"
    echo "Please ensure you are using one of the following supported operating systems:"
    echo "- Ubuntu 20.04+"
    echo "- Debian 11+"
    exit 1
fi

rm -fr /var/server-connector/
cd /var

if [ "$release" = "ubuntu" ]; then
    apt update -y
    apt install git -y
    git clone https://github.com/chabokan/server-connector.git
    bash /var/server-connector/debian/ubuntu.sh
elif [ "$release" = "debian" ]; then
    apt update -y
    apt install git -y
    git clone https://github.com/chabokan/server-connector.git
    bash /var/server-connector/debian/debian.sh
fi
