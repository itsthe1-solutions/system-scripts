#!/bin/bash
# Script to auto-install Tailscale and join Headscale
# Usage: sudo ./headscale-join.sh

# === CONFIG ===
HEADSCALE_SERVER="https://hs.itsdemo1.xyz"   # Replace with your Headscale URL
AUTH_KEY="dd420b986128f3742384a0546d36d3ba9758b73ec3f37872"  # Replace with your pre-generated key
TS_PACKAGE_URL="https://pkgs.tailscale.com/stable/tailscale_1.78.1_amd64.tgz"

# === INSTALL TAILSCALE ===
echo "[*] Installing Tailscale..."
if ! command -v tailscale &> /dev/null; then
    curl -fsSL https://tailscale.com/install.sh | sh
fi

# === ENABLE & START TAILSCALED ===
echo "[*] Enabling service..."
systemctl enable --now tailscaled

# === CONNECT TO HEADSCALE ===
echo "[*] Connecting to Headscale server: $HEADSCALE_SERVER"
tailscale up \
  --login-server=$HEADSCALE_SERVER \
  --auth-key=$AUTH_KEY \
  --accept-dns=true \

# === SHOW STATUS ===
echo "[*] Connection status:"
tailscale status
