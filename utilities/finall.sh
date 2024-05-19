#!/bin/bash

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