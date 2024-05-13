#!/bin/bash

# Color
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

set -e
# Eror handeling
trap "echo -e '${RED}ERROR: Run the command again and select a different type of connection!${NC}'" ERR

unset http_proxy
unset https_proxy

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
"Proxy1"
"Proxy2"
"Proxy3"
"FOD"
"Shecan-DNS"
"403-DNS"
)


if [[ "$1" != '' ]]; then
    TOKEN=$1
else
    read -p "Enter TOKEN: " TOKEN
fi

# check root user
[[ $EUID -ne 0 ]] && echo -e "${RED}Fatal error: ${NC} Please run command with root privilege \n " && exit 1


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
echo "The OS is: $release"

# check cpu arch
#arch() {
#    case "$(uname -m)" in
#    x86_64 | x64 | amd64) echo 'amd64' ;;
#    i*86 | x86) echo '386' ;;
#    armv8* | armv8 | arm64 | aarch64) echo 'arm64' ;;
#    armv7* | armv7 | arm) echo 'armv7' ;;
#    armv6* | armv6) echo 'armv6' ;;
#    armv5* | armv5) echo 'armv5' ;;
#    s390x) echo 's390x' ;;
#    *) echo -e "${RED}Unsupported CPU architecture! ${NC}" && rm -f install.sh && exit 1 ;;
#    esac
#}
#echo "${GREEN}CPU arch: $(arch)${NC}"

os_version=""
os_version=$(grep -i version_id /etc/os-release | cut -d \" -f2 | cut -d . -f1)

if [[ "${release}" == "ubuntu" ]]; then
    if [[ ${os_version} -lt 16 ]]; then
        echo -e "${RED} Please use Ubuntu 16 or higher ${NC}\n" && exit 1
    fi
#elif [[ "${release}" == "centos" ]]; then
#    if [[ ${os_version} -lt  7 ]]; then
#        echo -e "${RED} Please use Centos 7 or higher version!${NC}\n" && exit 1
#    fi
elif [[ "${release}" == "debian" ]]; then
    if [[ ${os_version} -lt 11 ]]; then
        echo -e "${RED} Please use Debian 11 or higher ${NC}\n" && exit 1
    fi
#elif [[ "${release}" == "rocky" ]]; then
#    if [[ ${os_version} -lt 8 ]]; then
#        echo -e "${RED} Please use Rocky Linux 8 or higher ${NC}\n" && exit 1
#    fi
else
    echo -e "${RED}Your operating system is not supported by this script.${NC}\n"
    echo "Please ensure you are using one of the following supported operating systems:"
    echo "- Ubuntu 16.04+"
    echo "- Debian 11+"
#    echo "- CentOS 7+"
#    echo "- Rocky 8+"
    exit 1
fi

echo -e "${GREEN}add base dns ...${NC}"
    rm /etc/resolv.conf
    cat >/etc/resolv.conf <<EOF
options timeout:1
nameserver 8.8.8.8
nameserver 1.1.1.1
EOF

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

echo -e "${GREEN}set Tehran Timezone ...${NC}"
TZ=Asia/Tehran
ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

if [ "$release" = "ubuntu" ]; then
echo -e "${GREEN}disable systemd resolved ...${NC}"
systemctl disable systemd-resolved.service
systemctl stop systemd-resolved
fi
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
    
    if [ $TYPE_OF_CONNECT = "Proxy1" ]; then
      echo -e "${GREEN}set type of connect proxy1 ...${NC}"
      export http_proxy='http://wraygnbd:eqj5y20wjznk@proxy.chabokan-two.ir:6322'
      export https_proxy='http://wraygnbd:eqj5y20wjznk@proxy.chabokan-two.ir:6322'
    elif [ $TYPE_OF_CONNECT = "Proxy2" ]; then
      echo -e "${GREEN}set type of connect proxy2 ...${NC}"
      export http_proxy='http://wraygnbd:eqj5y20wjznk@proxy2.chabokan-two.ir:6405'
      export https_proxy='http://wraygnbd:eqj5y20wjznk@proxy2.chabokan-two.ir:6405'
    elif [ $TYPE_OF_CONNECT = "Proxy3" ]; then
      echo -e "${GREEN}set type of connect proxy3 ...${NC}"
      export http_proxy='http://wraygnbd:eqj5y20wjznk@proxy3.chabokan-two.ir:6247'
      export https_proxy='http://wraygnbd:eqj5y20wjznk@proxy3.chabokan-two.ir:6247'
    elif [ $TYPE_OF_CONNECT = "FOD" ]; then
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
    cp /usr/share/doc/apt/examples/sources.list /etc/apt/sources.list
    echo -e "${GREEN}change server repo ...${NC}"
    sed -i 's/http:\/\/archive.ubuntu.com/http:\/\/ir.archive.ubuntu.com/g' /etc/apt/sources.list
    sed -i 's/http:\/\/[a-z]*.archive.ubuntu.com/http:\/\/ir.archive.ubuntu.com/g' /etc/apt/sources.list
    sed -i 's/http:\/\/[a-z]*.[a-z]*.archive.ubuntu.com/http:\/\/ir.archive.ubuntu.com/g' /etc/apt/sources.list
    sed -i 's/http:\/\/[a-z]*.[a-z]*.[a-z]*.archive.ubuntu.com/http:\/\/ir.archive.ubuntu.com/g' /etc/apt/sources.list
    sed -i 's/http:\/\/[a-z]*.[a-z]*.[a-z]*.[a-z]*.archive.ubuntu.com/http:\/\/ir.archive.ubuntu.com/g' /etc/apt/sources.list
fi

echo -e "${GREEN}updating os ...${NC}"

install_base() {

    case "${release}" in
    centos | rocky)
        yum -y update
        ;;
    ubuntu | debian)
        apt update -y
        ;;
    *)
        echo "Wrong OS ..."
        exit 1
        ;;

    esac
}

echo -e "${GREEN}disable ipv6 ...${NC}"
sysctl -w net.ipv6.conf.all.disable_ipv6=1
sysctl -w net.ipv6.conf.default.disable_ipv6=1
sysctl -w net.ipv6.conf.lo.disable_ipv6=1
sysctl -p

echo -e "${GREEN}install useful packages ....${NC}"
apt --fix-broken install
DEBIAN_FRONTEND=noninteractive apt install -y iptables-persistent sqlite3 pigz nano jq vsftpd vim htop net-tools iputils-ping apache2-utils rkhunter supervisor net-tools htop fail2ban wget zip nmap git letsencrypt build-essential iftop dnsutils python3-pip dsniff grepcidr iotop rsync atop software-properties-common
git config --global credential.helper store

debconf-set-selections <<EOF
iptables-persistent iptables-persistent/autosave_v4 boolean true
iptables-persistent iptables-persistent/autosave_v6 boolean true
EOF

echo -e "${GREEN}install docker ....${NC}"
if [[ "${release}" == "ubuntu" ]]; then
    for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do sudo apt-get remove $pkg; done
    apt update -y
    DEBIAN_FRONTEND=noninteractive apt install -y ca-certificates curl gnupg
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --batch --yes --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    echo \
      "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | \
      sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    apt-get update

    if [ $os_version = "20" ]; then
        VERSION_STRING=5:25.0.3-1~ubuntu.20.04~focal
        DEBIAN_FRONTEND=noninteractive apt install -y docker-ce=$VERSION_STRING docker-ce-cli=$VERSION_STRING containerd.io docker-buildx-plugin docker-compose-plugin
    elif [ $os_version = "22" ]; then
        VERSION_STRING=5:25.0.3-1~ubuntu.22.04~jammy
        DEBIAN_FRONTEND=noninteractive apt install -y docker-ce=$VERSION_STRING docker-ce-cli=$VERSION_STRING containerd.io docker-buildx-plugin docker-compose-plugin
    else
        echo -e "${RED} not proper version, please check your ubuntu version first.${NC}"
        exit 1
    fi
    apt-mark hold docker-ce docker-ce-cli

    apt purge postfix -y
elif [[ "${release}" == "debian" ]]; then
    for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do apt-get remove $pkg; done
    apt update -y
    DEBIAN_FRONTEND=noninteractive apt install -y ca-certificates curl gnupg
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc

    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      tee /etc/apt/sources.list.d/docker.list > /dev/null
    apt update
    if [ $os_version = "12" ]; then
        VERSION_STRING=5:25.0.3-1~debian.12~bookworm
        DEBIAN_FRONTEND=noninteractive apt install -y docker-ce=$VERSION_STRING docker-ce-cli=$VERSION_STRING containerd.io docker-buildx-plugin docker-compose-plugin
    elif [ $os_version = "11" ]; then
       VERSION_STRING=5:25.0.3-1~debian.11~bullseye
       DEBIAN_FRONTEND=noninteractive apt install -y docker-ce=$VERSION_STRING docker-ce-cli=$VERSION_STRING containerd.io docker-buildx-plugin doc>
    else
        echo -e "${RED} not proper version, please check your debian version first.${NC}"
        exit 1
    fi
    apt-mark hold docker-ce docker-ce-cli

    apt purge postfix -y
fi
mkdir -p /builds
mkdir -p /storage
mkdir -p /backups

echo "0 3 * * * root bash /var/ch-manager/update_core.sh >> /dev/null 2>&1" > /etc/cron.d/update-core
service cron restart

echo -e "${GREEN}installing node manager ....${NC}"
rm -rf /var/ch-manager
git clone https://github.com/chabokan/node-manager /var/ch-manager
cd /var/ch-manager/

if [ "$release" = "ubuntu" ]; then
pip3 install -r requirements.txt
sleep 2
pip3 install -r requirements.txt
elif [ "$release" = "debian" ]; then
pip3 install --break-system-packages -r requirements.txt
sleep 2
pip3 install --break-system-packages -r requirements.txt
fi

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