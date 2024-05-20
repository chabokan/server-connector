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

echo -e "${GREEN}set Tehran Timezone ...${NC}"
TZ=Asia/Tehran
ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# Type of connection menu
function choose_from_menu() {
    local prompt="$1" outvar="$2"
    shift
    shift
    local options=("$@") cur=0 count=${#options[@]} index=0
    local esc=$(echo -en "\e") # cache ESC as test doesn't allow esc codes
    printf "$prompt\n"
    while true
    do
        # list all options (option list is zero-based)
        index=0
        for o in "${options[@]}"
        do
            if [ "$index" == "$cur" ]
            then echo -e " >\e[7m$o\e[0m" # mark & highlight the current option
            else echo "  $o"
            fi
            index=$(( $index + 1 ))
        done
        read -s -n3 key # wait for user to key in arrows or ENTER
        if [[ $key == $esc[A ]] # up arrow
        then cur=$(( $cur - 1 ))
            [ "$cur" -lt 0 ] && cur=0
        elif [[ $key == $esc[B ]] # down arrow
        then cur=$(( $cur + 1 ))
            [ "$cur" -ge $count ] && cur=$(( $count - 1 ))
        elif [[ $key == "" ]] # nothing, i.e the read delimiter - ENTER
        then break
        fi
        echo -en "\e[${count}A" # go up to the beginning to re-render
    done
    # export the selection to the requested output variable
    printf -v $outvar "${options[$cur]}"
}
selections=(
"Direct"
"FOD"
"Shecan-DNS"
"403-DNS"
)

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
    else
        echo "- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
Type of connections are used for connect your server to chabokan server
assistant.You can choose from various connection types. If you encounter
any issues, simply try running the command again with a different
type of connection. For more detailed instructions, please refer to
the Chabokan documentation:
https://docs.chabokan.net/server-assistant/setup/
- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -"      
        choose_from_menu "Please select Type of Connect:" TYPE_OF_CONNECT "${selections[@]}"
    fi

    echo -e "${GREEN}Type of Connect: ${TYPE_OF_CONNECT} ${NC}" 
    if [ $TYPE_OF_CONNECT = "FOD" ]; then
      echo -e "${GREEN}set type of connect fod ...${NC}"
      export http_proxy='http://fodev.org:8118'
      export https_proxy='http://fodev.org:8118'
    elif [ $TYPE_OF_CONNECT = "Shecan-DNS" ]; then
      echo -e "${GREEN}add shecan dns ...${NC}"
      rm /etc/resolv.conf
      cat >/etc/resolv.conf <<EOF
options timeout:1
nameserver 178.22.122.100
nameserver 185.51.200.2
EOF
    elif [ $TYPE_OF_CONNECT = "403-DNS" ]; then
      echo -e "${GREEN}add 403 dns ...${NC}"
      rm /etc/resolv.conf
      cat >/etc/resolv.conf <<EOF
options timeout:1
nameserver 10.202.10.202
nameserver 10.202.10.102
EOF
    fi
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
    echo "- Ubuntu 16.04+"
    echo "- Debian 11+"
    exit 1
fi
echo "The OS is: $release"

rm -fr /var/server-connector/
cd /var

if [ "$release" = "ubuntu" ]; then
    apt update -y
    apt install git
    git clone https://github.com/chabokan/server-connector.git
    bash /var/server-connector/debian/ubuntu.sh
elif [ "$release" = "debian" ]; then
    apt update -y
    apt install git
    git clone https://github.com/chabokan/server-connector.git
    bash /var/server-connector/debian/debian.sh
fi