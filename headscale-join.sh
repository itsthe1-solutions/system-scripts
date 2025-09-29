#!/bin/bash
# Auto install and join Headscale with pre-auth key
# Usage: curl -fsSL https://yourdomain.com/headscale-auto-install.sh | sudo bash

set -e

# === CONFIG ===
HEADSCALE_SERVER="https://hs.itsdemo1.xyz"   # Your Headscale server
AUTH_KEY="dd420b986128f3742384a0546d36d3ba9758b73ec3f37872"  # Pre-auth key
TAILSCALE_VERSION="1.78.1"   # Lock version (optional)

echo "[*] Updating system packages..."
apt-get update -y

echo "[*] Installing required dependencies..."
apt-get install -y curl gnupg lsb-release

# === INSTALL TAILSCALE ===
if ! command -v tailscale &>/dev/null; then
    echo "[*] Installing Tailscale v${TAILSCALE_VERSION}..."
    curl -fsSL https://pkgs.tailscale.com/stable/tailscale_${TAILSCALE_VERSION}_amd64.deb -o /tmp/tailscale.deb
    apt-get install -y /tmp/tailscale.deb
else
    echo "[*] Tailscale already installed, skipping."
fi

echo "[*] Enabling and starting tailscaled..."
systemctl enable --now tailscaled

# === CONNECT TO HEADSCALE ===
echo "[*] Connecting to Headscale server: $HEADSCALE_SERVER"
tailscale up \
  --login-server=${HEADSCALE_SERVER} \
  --authkey=${AUTH_KEY} \
  --accept-dns=true \
  --accept-routes=true

# === VERIFY ===
echo "[*] Tailscale status:"
tailscale status || true

echo "[✔] Node successfully connected to Headscale!"
