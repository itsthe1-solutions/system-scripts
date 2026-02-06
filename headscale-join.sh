#!/bin/bash
# Auto-install Tailscale and join Headscale
# Can be run as normal user; escalates with sudo where needed

set -e

# === CONFIG ===
HEADSCALE_SERVER="https://hs.itsdemo1.xyz"   # Headscale URL
AUTH_KEY="cb9d5c1f492499ddf882f7c441063a6f49122ccb21d61390"  # Pre-auth key

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
