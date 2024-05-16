#!/bin/bash

# Color
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# check root user
[[ $EUID -ne 0 ]] && echo -e "${RED}Fatal error: ${NC} Please run command with root privilege \n " && exit 1

set -e
# Eror handeling
trap "echo -e '${RED}ERROR: Run the command again and select a different type of connection!${NC}'" ERR

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

cd /var/server-connector
git clone 

if [ "$release" = "ubuntu" ]; then
    cd /tmp
    wget https://raw.githubusercontent.com/chabokan/server-connector/main/ubuntu.sh -O ubuntu.sh
    bash ubuntu.sh $1
elif [ "$release" = "debian" ]; then
    cd /tmp
    wget https://raw.githubusercontent.com/chabokan/server-connector/main/debian.sh -O debian.sh
    bash debian.sh $1
fi