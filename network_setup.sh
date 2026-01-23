#!/bin/bash
set -euo pipefail

NETPLAN_FILE="/etc/netplan/01-routeros.yaml"
STATE_DIR="/var/lib/routeros-menu"
mkdir -p "$STATE_DIR"

log(){ echo -e "[$(date +'%F %T')] $*"; }
need_root(){
  if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    echo "❌ Run as root (use sudo)."
    exit 1
  fi
}
pause(){ read -r -p "Press Enter to continue... " _; }

list_ifaces(){
  ip -o link show | awk -F': ' '{print $2}' | grep -Ev 'lo|docker|veth|br-|tun|tap' || true
}

backup_netplan(){
  local bdir="/root/netplan-backup-$(date +%F-%H%M%S)"
  mkdir -p "$bdir"
  cp -a /etc/netplan/*.yaml "$bdir" 2>/dev/null || true
  echo "$bdir" > "$STATE_DIR/last_netplan_backup"
  log "🗂 Netplan backup saved to: $bdir"
}

apply_netplan_safe(){
  log "⚙ netplan generate..."
  netplan generate
  log "⚙ netplan apply..."
  netplan apply
  log "✅ Netplan applied."
}

ask_yesno(){
  local prompt="$1"
  local ans
  while true; do
    read -r -p "$prompt (yes/no): " ans
    case "${ans,,}" in
      yes|y) echo "yes"; return ;;
      no|n)  echo "no";  return ;;
      *) echo "Please type yes or no." ;;
    esac
  done
}

# -------------------- 1) NETPLAN --------------------
netplan_menu(){
  echo "===================================="
  echo " Netplan: Multi-Interface Config"
  echo "===================================="
  echo "📡 Detected interfaces:"
  list_ifaces | sed 's/^/ - /'
  echo

  backup_netplan

  cat > "$NETPLAN_FILE" <<EOF
network:
  version: 2
  renderer: networkd
  ethernets:
EOF

  local WAN_DEFINED="no"

  while true; do
    local add
    add="$(ask_yesno "➕ Add an interface")"
    [[ "$add" == "no" ]] && break

    local iface role dhcp
    read -r -p "Interface name (e.g. eth0): " iface
    read -r -p "Role (wan/lan/dmz): " role
    dhcp="$(ask_yesno "Use DHCP on $iface")"

    echo "    Configuring $iface ($role)"

    if [[ "$dhcp" == "yes" ]]; then
      cat >> "$NETPLAN_FILE" <<EOF
    $iface:
      dhcp4: true
EOF
      # For WAN via DHCP, we can still set route metric using dhcp4-overrides.
      if [[ "${role,,}" == "wan" ]]; then
        if [[ "$WAN_DEFINED" == "yes" ]]; then
          echo "❌ Only ONE WAN default route allowed in this script."
          exit 1
        fi
        WAN_DEFINED="yes"
        local metric
        read -r -p "Route metric for WAN (lower=priority, e.g. 100): " metric
        cat >> "$NETPLAN_FILE" <<EOF
      dhcp4-overrides:
        route-metric: $metric
EOF
        echo "$iface" > "$STATE_DIR/wan_iface"
      fi
      continue
    fi

    # Static config
    local ip dns
    read -r -p "Static IP (CIDR, e.g. 192.168.10.1/24): " ip
    read -r -p "DNS servers (comma separated, e.g. 8.8.8.8,1.1.1.1): " dns

    cat >> "$NETPLAN_FILE" <<EOF
    $iface:
      addresses:
        - $ip
      nameservers:
        addresses: [${dns//,/\, }]
EOF

    if [[ "${role,,}" == "wan" ]]; then
      if [[ "$WAN_DEFINED" == "yes" ]]; then
        echo "❌ Only ONE WAN default route allowed in this script."
        exit 1
      fi
      WAN_DEFINED="yes"

      local gw metric
      read -r -p "Gateway IP (WAN): " gw
      read -r -p "Route metric (lower=priority, e.g. 100): " metric

      cat >> "$NETPLAN_FILE" <<EOF
      routes:
        - to: default
          via: $gw
          metric: $metric
EOF
      echo "$iface" > "$STATE_DIR/wan_iface"
    else
      # For LAN/DMZ, no default gateway (best practice).
      :
    fi
  done

  echo
  echo "================ GENERATED NETPLAN ================"
  cat "$NETPLAN_FILE"
  echo "==================================================="
  echo

  local apply
  apply="$(ask_yesno "⚠ Apply netplan now")"
  if [[ "$apply" == "yes" ]]; then
    apply_netplan_safe
  else
    log "ℹ Not applied. File saved at: $NETPLAN_FILE"
  fi
  pause
}

# -------------------- 2) DHCP SERVER --------------------
dhcp_setup(){
  echo "===================================="
  echo " DHCP Server Setup (isc-dhcp-server)"
  echo "===================================="

  apt-get update -y
  apt-get install -y isc-dhcp-server

  echo "📡 Interfaces:"
  list_ifaces | sed 's/^/ - /'
  echo

  local iface net mask gw dns rstart rend lease maxlease
  read -r -p "🔌 LAN interface for DHCP (e.g. eth0): " iface
  read -r -p "🌐 Network address (e.g. 192.168.10.0): " net
  read -r -p "📏 Netmask (e.g. 255.255.255.0): " mask
  read -r -p "🚪 Gateway/router IP for clients (e.g. 192.168.10.1): " gw
  read -r -p "🧠 DNS for clients (e.g. 8.8.8.8,1.1.1.1): " dns
  read -r -p "🔢 Range start (e.g. 192.168.10.100): " rstart
  read -r -p "🔢 Range end (e.g. 192.168.10.200): " rend
  read -r -p "⏱ Default lease time seconds (e.g. 600): " lease
  read -r -p "⏱ Max lease time seconds (e.g. 7200): " maxlease

  cp /etc/dhcp/dhcpd.conf /etc/dhcp/dhcpd.conf.bak 2>/dev/null || true

  cat > /etc/dhcp/dhcpd.conf <<EOF
default-lease-time $lease;
max-lease-time $maxlease;
authoritative;

subnet $net netmask $mask {
  range $rstart $rend;
  option routers $gw;
  option subnet-mask $mask;
  option domain-name-servers ${dns//,/ , };
}
EOF

  # Set interface
  if grep -q '^INTERFACESv4=' /etc/default/isc-dhcp-server 2>/dev/null; then
    sed -i "s/^INTERFACESv4=.*/INTERFACESv4=\"$iface\"/" /etc/default/isc-dhcp-server
  else
    echo "INTERFACESv4=\"$iface\"" >> /etc/default/isc-dhcp-server
  fi

  systemctl enable isc-dhcp-server
  systemctl restart isc-dhcp-server

  echo "$iface" > "$STATE_DIR/lan_iface"
  log "✅ DHCP configured on $iface"
  systemctl --no-pager --full status isc-dhcp-server || true
  pause
}

# -------------------- 3) NAT + FORWARD --------------------
nat_setup(){
  echo "===================================="
  echo " NAT + Forwarding (iptables MASQUERADE)"
  echo "===================================="

  apt-get update -y
  apt-get install -y iptables iptables-persistent

  echo "📡 Interfaces:"
  list_ifaces | sed 's/^/ - /'
  echo

  local wan lan
  read -r -p "🌐 WAN interface (internet/upstream, e.g. eth1): " wan
  read -r -p "🏠 LAN interface (clients side, e.g. eth0): " lan

  # Enable forwarding runtime
  sysctl -w net.ipv4.ip_forward=1 >/dev/null

  # Persist forwarding
  if grep -q '^#\?net.ipv4.ip_forward=' /etc/sysctl.conf; then
    sed -i 's/^#\?net.ipv4.ip_forward=.*/net.ipv4.ip_forward=1/' /etc/sysctl.conf
  else
    echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
  fi

  # Baseline rules (keeps it simple)
  iptables -F
  iptables -t nat -F

  iptables -t nat -A POSTROUTING -o "$wan" -j MASQUERADE
  iptables -A FORWARD -i "$lan" -o "$wan" -j ACCEPT
  iptables -A FORWARD -i "$wan" -o "$lan" -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

  iptables-save > /etc/iptables/rules.v4

  echo "$wan" > "$STATE_DIR/wan_iface"
  echo "$lan" > "$STATE_DIR/lan_iface"

  log "✅ NAT configured: LAN=$lan -> WAN=$wan"
  echo
  echo "NAT table:"
  iptables -t nat -L -v
  echo
  echo "FORWARD chain:"
  iptables -L FORWARD -v
  pause
}

# -------------------- 4) SSH HARDENING --------------------
ssh_hardening(){
  echo "===================================="
  echo " SSH Hardening"
  echo "===================================="

  apt-get update -y
  apt-get install -y openssh-server

  local change_port dis_root dis_pass ssh_port
  change_port="$(ask_yesno "Change SSH port")"
  if [[ "$change_port" == "yes" ]]; then
    read -r -p "New SSH port (e.g. 2222): " ssh_port
  else
    ssh_port="22"
  fi

  dis_root="$(ask_yesno "Disable root login")"
  dis_pass="$(ask_yesno "Disable password login (keys only)")"

  local conf="/etc/ssh/sshd_config"
  cp "$conf" "${conf}.bak.$(date +%F-%H%M%S)" 2>/dev/null || true

  # Set/replace directives (append if missing)
  set_sshd(){
    local key="$1" val="$2"
    if grep -qiE "^[#\s]*${key}\b" "$conf"; then
      sed -i -E "s/^[#\s]*${key}\b.*/${key} ${val}/I" "$conf"
    else
      echo "${key} ${val}" >> "$conf"
    fi
  }

  set_sshd "Port" "$ssh_port"
  [[ "$dis_root" == "yes" ]] && set_sshd "PermitRootLogin" "no"
  if [[ "$dis_pass" == "yes" ]]; then
    set_sshd "PasswordAuthentication" "no"
    set_sshd "KbdInteractiveAuthentication" "no"
    set_sshd "ChallengeResponseAuthentication" "no"
    set_sshd "PubkeyAuthentication" "yes"
  fi

  # Validate before restart
  if sshd -t; then
    systemctl restart ssh
    echo "$ssh_port" > "$STATE_DIR/ssh_port"
    log "✅ SSH hardened. Port: $ssh_port"
  else
    echo "❌ sshd_config test failed. Restoring last backup is recommended."
  fi

  echo "⚠ Make sure you have key access before closing your current session."
  pause
}

# -------------------- 5) UFW FIREWALL --------------------
ufw_setup(){
  echo "===================================="
  echo " UFW Firewall (Gateway Baseline)"
  echo "===================================="
  apt-get update -y
  apt-get install -y ufw

  local ssh_port="22"
  [[ -f "$STATE_DIR/ssh_port" ]] && ssh_port="$(cat "$STATE_DIR/ssh_port")" || true

  local wan="" lan=""
  [[ -f "$STATE_DIR/wan_iface" ]] && wan="$(cat "$STATE_DIR/wan_iface")" || true
  [[ -f "$STATE_DIR/lan_iface" ]] && lan="$(cat "$STATE_DIR/lan_iface")" || true

  echo "Detected: SSH port=$ssh_port  WAN=${wan:-unknown}  LAN=${lan:-unknown}"
  echo

  # Reset & set defaults
  ufw --force reset
  ufw default deny incoming
  ufw default allow outgoing

  # Allow SSH
  ufw allow "$ssh_port"/tcp

  # Allow DHCP server replies on LAN (server side)
  # If you're running DHCP on this box, clients need UDP 67/68 on LAN.
  if [[ -n "$lan" ]]; then
    ufw allow in on "$lan" to any port 67 proto udp
    ufw allow in on "$lan" to any port 68 proto udp
  fi

  # Enable forwarding policy (needed for router)
  # NOTE: UFW needs DEFAULT_FORWARD_POLICY="ACCEPT"
  if grep -q '^DEFAULT_FORWARD_POLICY=' /etc/default/ufw; then
    sed -i 's/^DEFAULT_FORWARD_POLICY=.*/DEFAULT_FORWARD_POLICY="ACCEPT"/' /etc/default/ufw
  else
    echo 'DEFAULT_FORWARD_POLICY="ACCEPT"' >> /etc/default/ufw
  fi

  # Allow forwarding LAN->WAN (basic)
  if [[ -n "$lan" && -n "$wan" ]]; then
    local before="/etc/ufw/before.rules"
    cp "$before" "${before}.bak.$(date +%F-%H%M%S)" 2>/dev/null || true

    # Add NAT to before.rules if not present (UFW NAT)
    if ! grep -q "ROUTEROS_NAT_BEGIN" "$before"; then
      cat >> "$before" <<EOF

# ROUTEROS_NAT_BEGIN
*nat
:POSTROUTING ACCEPT [0:0]
-A POSTROUTING -o $wan -j MASQUERADE
COMMIT
# ROUTEROS_NAT_END
EOF
    fi
  fi

  ufw --force enable
  ufw status verbose
  log "✅ UFW configured."
  pause
}

# -------------------- 6) STATUS --------------------
show_status(){
  echo "===================================="
  echo " STATUS"
  echo "===================================="
  echo "Interfaces:"
  ip -br a || true
  echo
  echo "Routes:"
  ip route || true
  echo
  echo "IP Forwarding:"
  sysctl net.ipv4.ip_forward || true
  echo
  echo "DHCP Service:"
  systemctl --no-pager --full status isc-dhcp-server || true
  echo
  echo "SSH Service:"
  systemctl --no-pager --full status ssh || true
  echo
  echo "iptables NAT:"
  iptables -t nat -L -v || true
  echo
  echo "UFW:"
  ufw status verbose || true
  echo
  echo "Netplan file:"
  [[ -f "$NETPLAN_FILE" ]] && cat "$NETPLAN_FILE" || echo "(not found: $NETPLAN_FILE)"
  pause
}

# -------------------- 7) NETPLAN ROLLBACK --------------------
netplan_rollback(){
  echo "===================================="
  echo " Netplan Rollback"
  echo "===================================="
  if [[ ! -f "$STATE_DIR/last_netplan_backup" ]]; then
    echo "❌ No backup recorded."
    pause
    return
  fi
  local bdir
  bdir="$(cat "$STATE_DIR/last_netplan_backup")"
  if [[ ! -d "$bdir" ]]; then
    echo "❌ Backup folder missing: $bdir"
    pause
    return
  fi

  local ok
  ok="$(ask_yesno "Restore netplan YAMLs from $bdir and apply")"
  if [[ "$ok" == "yes" ]]; then
    rm -f /etc/netplan/*.yaml 2>/dev/null || true
    cp -a "$bdir"/*.yaml /etc/netplan/ 2>/dev/null || true
    apply_netplan_safe
    log "✅ Netplan rolled back."
  else
    echo "Canceled."
  fi
  pause
}

# -------------------- MAIN MENU --------------------
main_menu(){
  need_root
  while true; do
    clear
    echo "=============================="
    echo "   Ubuntu Router OS (Menu)    "
    echo "=============================="
    echo "1) Configure Netplan (multi-iface, WAN metric)"
    echo "2) Setup DHCP Server"
    echo "3) Setup NAT + Forwarding"
    echo "4) SSH Hardening"
    echo "5) Setup UFW Firewall (gateway baseline)"
    echo "6) Show Status"
    echo "7) Rollback Netplan"
    echo "0) Exit"
    echo "------------------------------"
    read -r -p "Choose: " choice
    case "$choice" in
      1) netplan_menu ;;
      2) dhcp_setup ;;
      3) nat_setup ;;
      4) ssh_hardening ;;
      5) ufw_setup ;;
      6) show_status ;;
      7) netplan_rollback ;;
      0) exit 0 ;;
      *) echo "Invalid choice"; pause ;;
    esac
  done
}

main_menu
