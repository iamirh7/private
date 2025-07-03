#!/bin/bash
set -e

echo "[+] ورود اطلاعات اولیه..."

read -p "Enter your domain (e.g., vpn.example.com): " DOMAIN
read -p "Enter your email (for Let's Encrypt): " EMAIL
read -p "Enter RADIUS server IP: " RADIP
read -p "Enter RADIUS secret: " RADSECRET

echo "Please select the IP range for VPN clients:"
echo "1) 192.168.0.0/20 (4096 clients)"
echo "2) 10.8.0.0/21 (2048 clients)"
echo "3) 10.9.0.0/21 (2048 clients)"
echo "4) 192.168.100.0/21 (2048 clients)"
echo "5) 172.16.0.0/21 (2048 clients)"
echo "6) Enter a custom IP range (must be a /21 or /20 subnet)"
read -p "Choice [1-6]: " choice

case $choice in
  1) iprange="192.168.0.0/20";;
  2) iprange="10.8.0.0/21";;
  3) iprange="10.9.0.0/21";;
  4) iprange="192.168.100.0/21";;
  5) iprange="172.16.0.0/21";;
  6) read -p "Enter custom IP range: " iprange;;
  *) echo "Invalid choice"; exit 1;;
esac

echo -e "\e[92m[*] نصب OpenConnect VPN با radcli + RADIUS و دریافت SSL ...\e[0m"

apt update
apt install -y git build-essential libtool autoconf automake pkg-config libssl-dev \
                freeradius-utils libpam-radius-auth libnss3-tools software-properties-common \
                iptables-persistent netfilter-persistent ocserv certbot

add-apt-repository universe -y
apt update

certbot certonly --standalone --preferred-challenges http --agree-tos -m "$EMAIL" -d "$DOMAIN" --non-interactive

cd /usr/local/src
rm -rf radcli
git clone https://github.com/radcli/radcli.git
cd radcli
./autogen.sh
./configure --prefix=/usr
make && make install

mkdir -p /etc/radcli
echo "$RADIP $RADSECRET" > /etc/radcli/servers
chmod 600 /etc/radcli/servers

cat > /etc/radcli/radiusclient.conf <<EOF
authserver     $RADIP
acctserver     $RADIP
servers        /etc/radcli/servers
dictionary     /etc/radcli/dictionary
radius_timeout 10
radius_retries 3
bindaddr       *
nas-identifier ocserv
EOF

mkdir -p /var/lib/ocserv
chown nobody:nogroup /var/lib/ocserv

cat > /etc/ocserv/ocserv.conf <<EOF
auth = "radius[config=/etc/radcli/radiusclient.conf,groupconfig=true]"
acct = "radius[config=/etc/radcli/radiusclient.conf]"

tcp-port = 443
udp-port = 0
run-as-user = nobody
run-as-group = nogroup
socket-file = ocserv.sock
chroot-dir = /var/lib/ocserv

max-clients = 0
max-same-clients = 0
rate-limit-ms = 100

keepalive = 32400
dpd = 90
mobile-dpd = 1800
switch-to-tcp-timeout = 25
try-mtu-discovery = false
mtu = 1280

server-cert = /etc/letsencrypt/live/$DOMAIN/fullchain.pem
server-key  = /etc/letsencrypt/live/$DOMAIN/privkey.pem

stats-report-time = 60

tls-priorities = "NORMAL:%COMPAT"
auth-timeout = 240
cookie-timeout = 86400
deny-roaming = false

rekey-time = 172800
rekey-method = ssl

use-occtl = true
pid-file = /run/ocserv.pid

device = vpns
predictable-ips = true

ipv4-network = ${iprange%/*}
ipv4-netmask = 255.255.248.0

dns = 8.8.8.8
dns = 1.1.1.1
tunnel-all-dns = true
ping-leases = false

route = default
cisco-client-compat = true
dtls-legacy = true

default-group-config = "default"
EOF

# ظپط¹ط§ظ„â€Œط³ط§ط²غŒ IP forwarding
echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
sysctl -p

# فعالسازي NAT و فوروارد
echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
sysctl -p
echo 'net.ipv6.conf.all.forwarding=1' >> /etc/sysctl.conf
sysctl -p
IFACE=$(ip route get 8.8.8.8 | awk '{print $5; exit}')
iptables -t nat -A POSTROUTING -s $iprange -o $IFACE -j MASQUERADE
apt install iptables-persistent -y
netfilter-persistent save

echo "0 3 * * * root certbot renew --quiet && systemctl restart ocserv" > /etc/cron.d/ocserv-ssl-renew
chmod 644 /etc/cron.d/ocserv-ssl-renew

systemctl enable ocserv
systemctl restart ocserv

echo -e "\n\e[92m✅ نصب ocserv با تنظیمات دلخواه شما با موفقیت انجام شد.\e[0m"
