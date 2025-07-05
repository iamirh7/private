#!/bin/bash
set -e

BIN_SRC="/root/pingtunnel"
BIN_DST="/etc/pi/pingtunnel"
DIR_DST="/etc/pi"

# Select action
echo "Select action:"
echo "  1) Install"
echo "  2) Uninstall"
read -rp "> " ACTION_INPUT
ACTION_INPUT="${ACTION_INPUT:-1}"

if [[ "$ACTION_INPUT" == "1" ]]; then
    ACTION="install"
elif [[ "$ACTION_INPUT" == "2" ]]; then
    ACTION="uninstall"
else
    echo "❌ Invalid selection. Choose 1 or 2."
    exit 1
fi

# Select location
echo "Select server location:"
echo "  1) Iran (Client)"
echo "  2) Outside (Server)"
read -rp "> " LOC_INPUT
LOC_INPUT="${LOC_INPUT:-1}"

if [[ "$LOC_INPUT" == "1" ]]; then
    LOCATION="iran"
elif [[ "$LOC_INPUT" == "2" ]]; then
    LOCATION="outside"
else
    echo "❌ Invalid location. Choose 1 or 2."
    exit 1
fi

SERVICE_NAME=$([[ "$LOCATION" == "iran" ]] && echo "pingtunnel-client" || echo "pingtunnel-server")

if [[ "$ACTION" == "uninstall" ]]; then
    echo "🧹 Uninstalling $SERVICE_NAME..."
    systemctl stop ${SERVICE_NAME} || true
    systemctl disable ${SERVICE_NAME} || true
    rm -f /etc/systemd/system/${SERVICE_NAME}.service
    systemctl daemon-reload
    rm -f "$BIN_DST"
    rm -rf "$DIR_DST"
    echo "✅ $SERVICE_NAME and related files removed."
    exit 0
fi

# Install section
echo "🔧 Installing PingTunnel..."

if [ ! -f "$BIN_SRC" ]; then
    echo "❌ Binary not found at $BIN_SRC"
    exit 1
fi

mkdir -p "$DIR_DST"
mv "$BIN_SRC" "$BIN_DST"
chmod +x "$BIN_DST"

if [[ "$LOCATION" == "iran" ]]; then
    echo "Enter IP of outside server:"
    read -r OUTSIDE_IP
    if [[ ! "$OUTSIDE_IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        echo "❌ Invalid IP format."
        exit 1
    fi

    echo "Enter port of outside server:"
    read -r OUTSIDE_PORT
    if ! [[ "$OUTSIDE_PORT" =~ ^[0-9]{1,5}$ ]] || [ "$OUTSIDE_PORT" -lt 1 ] || [ "$OUTSIDE_PORT" -gt 65535 ]; then
        echo "❌ Invalid port number."
        exit 1
    fi

    cat > /etc/systemd/system/${SERVICE_NAME}.service <<EOF
[Unit]
Description=PingTunnel Client (Iran)
After=network.target

[Service]
ExecStart=$BIN_DST -type client -l :$OUTSIDE_PORT -s $OUTSIDE_IP -t $OUTSIDE_IP:$OUTSIDE_PORT -tcp 1 > /dev/null 2>&1
Restart=always
RestartSec=3
User=root

[Install]
WantedBy=multi-user.target
EOF

else
    cat > /etc/systemd/system/${SERVICE_NAME}.service <<EOF
[Unit]
Description=PingTunnel Server (Outside)
After=network.target

[Service]
ExecStart=$BIN_DST -type server > /dev/null 2>&1
Restart=always
RestartSec=3
User=root

[Install]
WantedBy=multi-user.target
EOF
fi

systemctl daemon-reload
systemctl enable ${SERVICE_NAME}
systemctl restart ${SERVICE_NAME}
echo "✅ $SERVICE_NAME is now running and enabled."
