#!/bin/bash
# Auto-install Tailscale and join Headscale
# Can be run as normal user; escalates with sudo where needed

set -e

# === CONFIG ===
HEADSCALE_SERVER="https://hs.itsdemo1.xyz"   # Headscale URL
AUTH_KEY="9fc35bff0ffed458b43eb2fc22850b98a7850a2fc634ef0f"  # Pre-auth key

# Function to run commands with sudo if not root
run_sudo() {
    if [ "$EUID" -ne 0 ]; then
        sudo "$@"
    else
        "$@"
    fi
}

echo "[*] Installing Tailscale..."
curl -fsSL https://tailscale.com/install.sh | run_sudo sh

echo "[*] Enabling and starting tailscaled..."
run_sudo systemctl enable --now tailscaled

echo "[*] Waiting a few seconds for tailscaled to start..."
sleep 3

echo "[*] Connecting to Headscale server..."
run_sudo tailscale up \
    --login-server=$HEADSCALE_SERVER \
    --auth-key=$AUTH_KEY \
    --accept-dns=true \

echo "[✔] Tailscale installed and connected!"
tailscale status
