#!/bin/bash
# Minimal script to install Tailscale and auto-join Headscale

set -e

# === CONFIG ===
HEADSCALE_SERVER="https://hs.itsdemo1.xyz"   # Your Headscale URL
AUTH_KEY="dd420b986128f3742384a0546d36d3ba9758b73ec3f37872"  # Pre-auth key

echo "[*] Installing Tailscale..."
curl -fsSL https://tailscale.com/install.sh | sh

echo "[*] Enabling and starting tailscaled..."
systemctl enable --now tailscaled

echo "[*] Connecting to Headscale server..."
tailscale up \
  --login-server=$HEADSCALE_SERVER \
  --authkey=$AUTH_KEY \
  --accept-dns=true \

echo "[✔] Tailscale installed and connected!"
tailscale status
