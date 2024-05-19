#!/bin/bash

iptables -t filter -F DOCKER-USER
iptables -t filter -F INPUT

host_ip=$(hostname -I | awk '{print $1}')
ip_addresses="https://chabokan.net/ips.txt"
select_ip=$(curl -s "$ip_addresses")

echo "your host ip is: $host_ip"
echo "adding iptables rules ..."

while IFS= read -r ip; do
  iptables -A INPUT -s $ip -p tcp -m tcp -j ACCEPT
  iptables -A DOCKER-USER -s $ip -p tcp -m tcp -j ACCEPT
done <<< "$select_ip"

iptables -A INPUT -s "$host_ip"/32 -p tcp -m tcp -j ACCEPT
iptables -A INPUT -s 127.0.0.0/8 -p tcp -m tcp -j ACCEPT
iptables -A INPUT -s 10.0.0.0/8 -p tcp -m tcp -j ACCEPT
iptables -A INPUT -s 172.16.0.0/12 -p tcp -m tcp -j ACCEPT
iptables -A INPUT -s 192.168.0.0/16 -p tcp -m tcp -j ACCEPT
iptables -A INPUT -p tcp -m tcp --dport 9990 -j DROP
iptables -A INPUT -p tcp -m tcp --dport 3000 -j DROP
iptables -A INPUT -p tcp -m tcp --dport 9000 -j DROP
iptables -A INPUT -p tcp -m tcp --dport 8000 -j DROP
iptables -A INPUT -p tcp -m tcp --dport 8081 -j DROP
iptables -A INPUT -p tcp -m tcp --dport 8080 -j DROP
iptables -A INPUT -p tcp -m tcp --dport 9093 -j DROP
iptables -A INPUT -p tcp -m tcp --dport 9090 -j DROP
iptables -A INPUT -p tcp -m tcp --dport 9100 -j DROP

iptables -A DOCKER-USER -s "$host_ip"/32 -p tcp -m tcp -j ACCEPT
iptables -A DOCKER-USER -s 127.0.0.0/8 -p tcp -m tcp -j ACCEPT
iptables -A DOCKER-USER -s 10.0.0.0/8 -p tcp -m tcp -j ACCEPT
iptables -A DOCKER-USER -s 172.16.0.0/12 -p tcp -m tcp -j ACCEPT
iptables -A DOCKER-USER -s 192.168.0.0/16 -p tcp -m tcp -j ACCEPT
iptables -A DOCKER-USER -p tcp -m tcp --dport 9990 -j DROP
iptables -A DOCKER-USER -p tcp -m tcp --dport 3000 -j DROP
iptables -A DOCKER-USER -p tcp -m tcp --dport 9000 -j DROP
iptables -A DOCKER-USER -p tcp -m tcp --dport 8000 -j DROP
iptables -A DOCKER-USER -p tcp -m tcp --dport 8081 -j DROP
iptables -A DOCKER-USER -p tcp -m tcp --dport 8080 -j DROP
iptables -A DOCKER-USER -p tcp -m tcp --dport 9093 -j DROP
iptables -A DOCKER-USER -p tcp -m tcp --dport 9090 -j DROP
iptables -A DOCKER-USER -p tcp -m tcp --dport 80 -j DROP
iptables -A DOCKER-USER -j RETURN

echo "all rules added to iptables"
echo "saving rules to iptables persistent ..."
iptables-save > /etc/iptables/rules.v4
echo "all rules saved to /etc/iptables/rules.v4"