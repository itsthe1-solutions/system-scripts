#!/bin/bash
# ============================================================
# netadmin-menu.sh
# Ubuntu network admin helper menu
#   1) Netplan: set interface to DHCP or Static
#   2) Enable IP forwarding + NAT (share internet WAN -> LAN)
#   3) Open SSH for password login, no key required (ITS The1 Solutions banner)
#   4) LAN DHCP server (isc-dhcp-server)
#   5) UFW firewall + fail2ban
#   6) Port-forward / DNAT helper
#   7) Tailscale install + connect (own auth key)
#   8) ZeroTier install + join network
#   9) Install all dependencies now (bootstrap)
#   10) Show current status
# Run as root: sudo bash netadmin-menu.sh
# ============================================================

set -uo pipefail

# ---------- helpers ----------

require_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "This script must be run as root. Try: sudo bash $0"
        exit 1
    fi
}

pause() {
    read -rp "Press Enter to continue..." _
}

list_interfaces() {
    ip -o link show | awk -F': ' '{print $2}' | grep -v '^lo$'
}

pick_interface() {
    local prompt="$1"
    echo "Available interfaces:"
    local ifaces
    mapfile -t ifaces < <(list_interfaces)
    local i=1
    for ifc in "${ifaces[@]}"; do
        echo "  $i) $ifc"
        ((i++))
    done
    read -rp "$prompt (name or number): " choice
    if [[ "$choice" =~ ^[0-9]+$ ]]; then
        echo "${ifaces[$((choice-1))]}"
    else
        echo "$choice"
    fi
}

backup_file() {
    local f="$1"
    if [[ -f "$f" && ! -f "${f}.bak.orig" ]]; then
        cp -a "$f" "${f}.bak.orig"
    fi
}

# ---------- 1. Netplan: DHCP or Static ----------

configure_netplan() {
    echo "=== Configure Netplan interface (DHCP or Static) ==="
    if ! command -v netplan >/dev/null 2>&1; then
        echo "netplan not found, installing it first..."
        DEBIAN_FRONTEND=noninteractive apt-get update -y
        DEBIAN_FRONTEND=noninteractive apt-get install -y netplan.io
    fi

    local ifc
    ifc=$(pick_interface "Interface to configure")
    if [[ -z "$ifc" ]]; then
        echo "No interface selected."
        pause
        return
    fi

    read -rp "Mode - (d)hcp or (s)tatic [d]: " mode
    mode=${mode:-d}

    local ncdir="/etc/netplan"
    mkdir -p "$ncdir"
    # remove any earlier config this script wrote for this interface (dhcp or static)
    rm -f "${ncdir}/99-${ifc}-dhcp.yaml" "${ncdir}/99-${ifc}-static.yaml"

    if [[ "$mode" =~ ^[Ss] ]]; then
        read -rp "Static address with CIDR (e.g. 192.168.1.50/24): " addr
        read -rp "Gateway (e.g. 192.168.1.1): " gw
        read -rp "DNS servers, comma-separated [1.1.1.1,8.8.8.8]: " dnsline
        dnsline=${dnsline:-1.1.1.1,8.8.8.8}

        if [[ -z "$addr" || -z "$gw" ]]; then
            echo "Address and gateway are required for static mode."
            pause
            return
        fi

        # turn "1.1.1.1,8.8.8.8" into a yaml list "[1.1.1.1, 8.8.8.8]"
        local dns_yaml
        dns_yaml="[$(echo "$dnsline" | sed 's/,/, /g')]"

        local outfile="${ncdir}/99-${ifc}-static.yaml"
        cat > "$outfile" <<EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    ${ifc}:
      dhcp4: false
      addresses: [${addr}]
      routes:
        - to: default
          via: ${gw}
      nameservers:
        addresses: ${dns_yaml}
EOF
        chmod 600 "$outfile"
        echo "Wrote $outfile:"
        cat "$outfile"
    else
        local outfile="${ncdir}/99-${ifc}-dhcp.yaml"
        cat > "$outfile" <<EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    ${ifc}:
      dhcp4: true
      dhcp6: false
EOF
        chmod 600 "$outfile"
        echo "Wrote $outfile:"
        cat "$outfile"
    fi

    echo
    read -rp "Apply this netplan config now? (y/N): " ans
    if [[ "$ans" =~ ^[Yy]$ ]]; then
        netplan generate && netplan apply
        echo "Applied. Current addressing for $ifc:"
        ip addr show "$ifc"
    else
        echo "Not applied. Run 'sudo netplan apply' manually when ready."
    fi
    pause
}

# ---------- 2. IP forwarding + NAT ----------

configure_forwarding() {
    echo "=== Enable IP forwarding + NAT (Internet -> LAN) ==="
    local wan lan
    wan=$(pick_interface "WAN interface (has internet)")
    lan=$(pick_interface "LAN interface (serves local clients)")

    if [[ -z "$wan" || -z "$lan" ]]; then
        echo "Both interfaces are required."
        pause
        return
    fi

    # Persist sysctl ip_forward
    local sysctl_file="/etc/sysctl.d/99-ipforward.conf"
    cat > "$sysctl_file" <<EOF
net.ipv4.ip_forward=1
net.ipv6.conf.all.forwarding=1
EOF
    sysctl -p "$sysctl_file"

    # Install iptables-persistent (or nftables) if missing, non-interactively
    if ! command -v iptables >/dev/null 2>&1; then
        DEBIAN_FRONTEND=noninteractive apt-get update -y
        DEBIAN_FRONTEND=noninteractive apt-get install -y iptables
    fi
    if ! dpkg -s iptables-persistent >/dev/null 2>&1; then
        echo "iptables-persistent netfilter-persistent iptables-persistent/autosave_v4 boolean true" | debconf-set-selections
        echo "iptables-persistent netfilter-persistent iptables-persistent/autosave_v6 boolean true" | debconf-set-selections
        DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent
    fi

    # NAT + forwarding rules
    iptables -t nat -C POSTROUTING -o "$wan" -j MASQUERADE 2>/dev/null || \
        iptables -t nat -A POSTROUTING -o "$wan" -j MASQUERADE

    iptables -C FORWARD -i "$wan" -o "$lan" -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || \
        iptables -A FORWARD -i "$wan" -o "$lan" -m state --state RELATED,ESTABLISHED -j ACCEPT

    iptables -C FORWARD -i "$lan" -o "$wan" -j ACCEPT 2>/dev/null || \
        iptables -A FORWARD -i "$lan" -o "$wan" -j ACCEPT

    netfilter-persistent save >/dev/null 2>&1 || true

    echo "Done. WAN=$wan LAN=$lan"
    echo "  - ip_forward persisted in $sysctl_file"
    echo "  - NAT/forward rules added and saved (iptables-persistent)"
    echo
    echo "Note: give $lan a static address of its own (netplan option 1, static mode),"
    echo "then use option 4 (isc-dhcp-server) if LAN clients need addresses handed out."
    pause
}

# ---------- 3. SSH fully open (password auth, no key required) ----------

configure_ssh_open() {
    echo "=== Configure SSH for password login (no key required) ==="
    echo "WARNING: this makes SSH accept any valid system account password,"
    echo "including root if enabled. Fine for a lab/homelab, risky on the open"
    echo "internet -- make sure the box is firewalled or on a private network."
    read -rp "Continue? (y/N): " ans
    if [[ ! "$ans" =~ ^[Yy]$ ]]; then
        echo "Cancelled."
        pause
        return
    fi

    if ! command -v sshd >/dev/null 2>&1; then
        echo "openssh-server not found, installing it first..."
        DEBIAN_FRONTEND=noninteractive apt-get update -y
        DEBIAN_FRONTEND=noninteractive apt-get install -y openssh-server
        systemctl enable --now ssh
    fi

    local sshd_config="/etc/ssh/sshd_config"
    backup_file "$sshd_config"

    set_sshd_option() {
        local key="$1" val="$2"
        if grep -qE "^[#[:space:]]*${key}\b" "$sshd_config"; then
            sed -i -E "s|^[#[:space:]]*${key}\b.*|${key} ${val}|" "$sshd_config"
        else
            echo "${key} ${val}" >> "$sshd_config"
        fi
    }

    set_sshd_option "PasswordAuthentication" "yes"
    set_sshd_option "PubkeyAuthentication" "yes"
    set_sshd_option "PermitRootLogin" "yes"
    set_sshd_option "ChallengeResponseAuthentication" "no"
    set_sshd_option "UsePAM" "yes"

    # Pre-login banner
    local banner_file="/etc/issue.net"
    cat > "$banner_file" <<'EOF'
############################################################
   ITS The1 Solutions
   Authorized access only. All activity may be monitored
   and logged. Disconnect immediately if you are not an
   authorized user.
############################################################
EOF
    set_sshd_option "Banner" "$banner_file"

    # Drop any Include snippet that forces key-only auth (Ubuntu cloud images)
    if [[ -d /etc/ssh/sshd_config.d ]]; then
        for f in /etc/ssh/sshd_config.d/*.conf; do
            [[ -e "$f" ]] || continue
            sed -i -E 's|^[#[:space:]]*PasswordAuthentication.*|PasswordAuthentication yes|' "$f"
        done
    fi

    sshd -t && systemctl restart ssh
    echo "SSH now accepts password authentication (config test passed, service restarted)."
    echo "Banner set to $banner_file (ITS The1 Solutions)."
    echo "Backup of original sshd_config saved as ${sshd_config}.bak.orig"

    if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
        ufw allow OpenSSH >/dev/null 2>&1 || ufw allow 22/tcp >/dev/null 2>&1
        echo "ufw: allowed SSH (22/tcp)."
    fi
    pause
}

# ---------- 4. LAN DHCP server (isc-dhcp-server) ----------

configure_lan_dhcp() {
    echo "=== LAN DHCP server (isc-dhcp-server) ==="
    local ifc
    ifc=$(pick_interface "LAN interface to serve DHCP on")
    if [[ -z "$ifc" ]]; then
        echo "No interface selected."
        pause
        return
    fi

    local my_ip
    my_ip=$(ip -4 -o addr show "$ifc" | awk '{print $4}' | cut -d/ -f1 | head -n1)
    if [[ -z "$my_ip" ]]; then
        echo "Interface $ifc has no IPv4 address yet. Give it a static address first"
        echo "(netplan option 1, static mode) before running a DHCP server on it."
        pause
        return
    fi

    echo "$ifc currently has $my_ip. This will be offered as gateway/DNS unless you override it."
    read -rp "Network address (e.g. 192.168.50.0): " network
    read -rp "Netmask [255.255.255.0]: " netmask
    netmask=${netmask:-255.255.255.0}
    read -rp "DHCP range start (e.g. 192.168.50.100): " range_start
    read -rp "DHCP range end   (e.g. 192.168.50.200): " range_end
    read -rp "Gateway to hand out [$my_ip]: " gateway
    gateway=${gateway:-$my_ip}
    read -rp "DNS server(s) to hand out, comma-separated [$my_ip]: " dns
    dns=${dns:-$my_ip}
    read -rp "Default/max lease time in seconds [43200 = 12h]: " lease
    lease=${lease:-43200}

    if [[ -z "$network" || -z "$range_start" || -z "$range_end" ]]; then
        echo "Network address and range start/end are required."
        pause
        return
    fi

    if ! command -v dhcpd >/dev/null 2>&1; then
        DEBIAN_FRONTEND=noninteractive apt-get update -y
        DEBIAN_FRONTEND=noninteractive apt-get install -y isc-dhcp-server
    fi

    # dhcpd.conf has no wildcard include, so add an explicit include line
    # for this interface's subnet file if it isn't already referenced.
    local dhcpd_conf="/etc/dhcp/dhcpd.conf"
    backup_file "$dhcpd_conf"
    mkdir -p /etc/dhcp/dhcpd.conf.d
    if ! grep -qF "dhcpd.conf.d/${ifc}.conf" "$dhcpd_conf" 2>/dev/null; then
        echo "include \"/etc/dhcp/dhcpd.conf.d/${ifc}.conf\";" >> "$dhcpd_conf"
    fi

    local subnet_conf="/etc/dhcp/dhcpd.conf.d/${ifc}.conf"
    local dns_line
    dns_line=$(echo "$dns" | sed 's/,/, /g')

    cat > "$subnet_conf" <<EOF
default-lease-time ${lease};
max-lease-time ${lease};

subnet ${network} netmask ${netmask} {
    range ${range_start} ${range_end};
    option routers ${gateway};
    option domain-name-servers ${dns_line};
}
EOF

    # Tell isc-dhcp-server which interface to listen on
    local defaults_file="/etc/default/isc-dhcp-server"
    backup_file "$defaults_file"
    if grep -q '^INTERFACESv4=' "$defaults_file" 2>/dev/null; then
        local current
        current=$(grep '^INTERFACESv4=' "$defaults_file" | sed -E 's/INTERFACESv4="?([^"]*)"?/\1/')
        if [[ ",$current," != *",$ifc,"* ]]; then
            local merged
            merged=$(echo "$current $ifc" | xargs)
            sed -i -E "s|^INTERFACESv4=.*|INTERFACESv4=\"${merged}\"|" "$defaults_file"
        fi
    else
        echo "INTERFACESv4=\"${ifc}\"" >> "$defaults_file"
    fi

    dhcpd -t -cf "$dhcpd_conf" 2>&1 | tail -n 5
    systemctl enable isc-dhcp-server >/dev/null 2>&1
    systemctl restart isc-dhcp-server

    echo "Wrote $subnet_conf:"
    cat "$subnet_conf"
    echo
    systemctl is-active isc-dhcp-server && echo "isc-dhcp-server restarted and enabled on boot."
    pause
}

# ---------- 5. UFW firewall + fail2ban ----------

configure_ufw_fail2ban() {
    echo "=== UFW firewall + fail2ban ==="
    if ! command -v ufw >/dev/null 2>&1 || ! command -v fail2ban-client >/dev/null 2>&1; then
        DEBIAN_FRONTEND=noninteractive apt-get update -y
        DEBIAN_FRONTEND=noninteractive apt-get install -y ufw fail2ban
    fi

    # Keep forwarding working through ufw for the NAT setup in option 2
    sed -i -E 's|^DEFAULT_FORWARD_POLICY=.*|DEFAULT_FORWARD_POLICY="ACCEPT"|' /etc/default/ufw 2>/dev/null || true

    ufw default deny incoming
    ufw default allow outgoing
    ufw allow OpenSSH >/dev/null 2>&1 || ufw allow 22/tcp

    read -rp "Any extra ports to allow now? (comma-separated, e.g. 80,443,8080/tcp) [skip]: " extra
    if [[ -n "$extra" ]]; then
        IFS=',' read -ra ports <<< "$extra"
        for p in "${ports[@]}"; do
            p="${p// /}"
            [[ -n "$p" ]] && ufw allow "$p"
        done
    fi

    ufw --force enable

    # fail2ban: make sure the sshd jail is on
    mkdir -p /etc/fail2ban/jail.d
    cat > /etc/fail2ban/jail.d/sshd.local <<EOF
[sshd]
enabled = true
port    = ssh
backend = systemd
maxretry = 5
bantime  = 1h
findtime = 10m
EOF
    systemctl enable fail2ban >/dev/null 2>&1
    systemctl restart fail2ban

    echo
    echo "ufw status:"
    ufw status verbose
    echo
    echo "fail2ban sshd jail status:"
    fail2ban-client status sshd 2>/dev/null
    pause
}

# ---------- 6. Port-forward / DNAT helper ----------

configure_port_forward() {
    echo "=== Port-forward / DNAT (expose an internal host:port via WAN) ==="
    local wan
    wan=$(pick_interface "WAN interface (public-facing)")
    if [[ -z "$wan" ]]; then
        echo "No interface selected."
        pause
        return
    fi

    read -rp "Protocol (tcp/udp) [tcp]: " proto
    proto=${proto:-tcp}
    read -rp "External port on $wan: " ext_port
    read -rp "Internal LAN host IP: " int_ip
    read -rp "Internal port [same as external]: " int_port
    int_port=${int_port:-$ext_port}

    if [[ -z "$ext_port" || -z "$int_ip" ]]; then
        echo "External port and internal IP are required."
        pause
        return
    fi

    if ! command -v iptables >/dev/null 2>&1; then
        DEBIAN_FRONTEND=noninteractive apt-get update -y
        DEBIAN_FRONTEND=noninteractive apt-get install -y iptables
    fi

    iptables -t nat -C PREROUTING -i "$wan" -p "$proto" --dport "$ext_port" \
        -j DNAT --to-destination "${int_ip}:${int_port}" 2>/dev/null || \
    iptables -t nat -A PREROUTING -i "$wan" -p "$proto" --dport "$ext_port" \
        -j DNAT --to-destination "${int_ip}:${int_port}"

    iptables -C FORWARD -p "$proto" -d "$int_ip" --dport "$int_port" -j ACCEPT 2>/dev/null || \
        iptables -A FORWARD -p "$proto" -d "$int_ip" --dport "$int_port" -j ACCEPT

    if command -v netfilter-persistent >/dev/null 2>&1; then
        netfilter-persistent save >/dev/null 2>&1 || true
    fi

    echo "Forwarding ${wan}:${ext_port}/${proto} -> ${int_ip}:${int_port}"
    if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
        ufw allow "${ext_port}/${proto}" >/dev/null 2>&1
        echo "ufw: also allowed ${ext_port}/${proto}."
    fi
    pause
}

# ---------- 7. Tailscale (own auth key) ----------

configure_tailscale() {
    echo "=== Tailscale install + connect ==="
    if ! command -v tailscale >/dev/null 2>&1; then
        echo "Installing Tailscale..."
        curl -fsSL https://tailscale.com/install.sh | sh
    else
        echo "Tailscale already installed: $(tailscale version | head -n1)"
    fi

    systemctl enable --now tailscaled >/dev/null 2>&1

    read -rsp "Paste your Tailscale auth key (input hidden): " authkey
    echo
    if [[ -z "$authkey" ]]; then
        echo "No key entered, cancelling."
        pause
        return
    fi

    read -rp "Advertise this box as an exit node/subnet router? (y/N): " adv
    if [[ "$adv" =~ ^[Yy]$ ]]; then
        read -rp "Subnet(s) to advertise, comma-separated (blank for none): " routes
        if [[ -n "$routes" ]]; then
            tailscale up --authkey="$authkey" --advertise-routes="$routes" --accept-dns=false
        else
            tailscale up --authkey="$authkey" --advertise-exit-node --accept-dns=false
        fi
    else
        tailscale up --authkey="$authkey" --accept-dns=false
    fi

    unset authkey
    echo
    echo "Tailscale status:"
    tailscale status
    pause
}

# ---------- 8. ZeroTier (install + join network) ----------

configure_zerotier() {
    echo "=== ZeroTier install + join network ==="
    if ! command -v zerotier-cli >/dev/null 2>&1; then
        echo "Installing ZeroTier..."
        curl -s https://install.zerotier.com | bash
    else
        echo "ZeroTier already installed: $(zerotier-cli -v 2>/dev/null)"
    fi

    systemctl enable --now zerotier-one >/dev/null 2>&1

    read -rp "ZeroTier Network ID to join: " netid
    if [[ -z "$netid" ]]; then
        echo "No network ID entered, cancelling."
        pause
        return
    fi

    zerotier-cli join "$netid"

    echo
    echo "Joined. This device now needs to be authorized in the ZeroTier Central"
    echo "console (my.zerotier.com) for that network before traffic will flow."
    echo
    echo "ZeroTier status:"
    zerotier-cli info
    zerotier-cli listnetworks
    pause
}

# ---------- 10. Install all dependencies up front ----------

install_all_deps() {
    echo "=== Install all dependencies used by this menu ==="
    echo "This will apt-get install (if missing): netplan.io, openssh-server,"
    echo "iptables, iptables-persistent, isc-dhcp-server, ufw, fail2ban,"
    echo "and install Tailscale + ZeroTier via their official scripts."
    read -rp "Continue? (y/N): " ans
    if [[ ! "$ans" =~ ^[Yy]$ ]]; then
        echo "Cancelled."
        pause
        return
    fi

    echo "Updating package index..."
    DEBIAN_FRONTEND=noninteractive apt-get update -y

    local pkgs=(netplan.io openssh-server iptables isc-dhcp-server ufw fail2ban)
    for p in "${pkgs[@]}"; do
        if dpkg -s "$p" >/dev/null 2>&1; then
            echo "[skip] $p already installed"
        else
            echo "[install] $p"
            DEBIAN_FRONTEND=noninteractive apt-get install -y "$p"
        fi
    done

    if ! dpkg -s iptables-persistent >/dev/null 2>&1; then
        echo "[install] iptables-persistent"
        echo "iptables-persistent netfilter-persistent iptables-persistent/autosave_v4 boolean true" | debconf-set-selections
        echo "iptables-persistent netfilter-persistent iptables-persistent/autosave_v6 boolean true" | debconf-set-selections
        DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent
    else
        echo "[skip] iptables-persistent already installed"
    fi

    systemctl enable --now ssh >/dev/null 2>&1

    if command -v tailscale >/dev/null 2>&1; then
        echo "[skip] tailscale already installed"
    else
        echo "[install] tailscale"
        curl -fsSL https://tailscale.com/install.sh | sh
    fi
    systemctl enable --now tailscaled >/dev/null 2>&1

    if command -v zerotier-cli >/dev/null 2>&1; then
        echo "[skip] zerotier already installed"
    else
        echo "[install] zerotier"
        curl -s https://install.zerotier.com | bash
    fi
    systemctl enable --now zerotier-one >/dev/null 2>&1

    echo
    echo "All dependencies checked/installed. You can now use any menu option"
    echo "without waiting on a package install mid-task."
    pause
}

# ---------- 11. Status ----------

show_status() {
    echo "=== Current status ==="
    echo "--- Interfaces & addresses ---"
    ip -brief addr show
    echo
    echo "--- IP forwarding ---"
    echo "ipv4: $(cat /proc/sys/net/ipv4/ip_forward)"
    echo
    echo "--- NAT / forward rules ---"
    iptables -t nat -L POSTROUTING -n -v 2>/dev/null
    echo
    iptables -L FORWARD -n -v 2>/dev/null
    echo
    echo "--- SSH auth settings ---"
    grep -E "^(PasswordAuthentication|PermitRootLogin|PubkeyAuthentication)" /etc/ssh/sshd_config 2>/dev/null
    echo
    systemctl is-active ssh 2>/dev/null && echo "ssh service: active"
    echo
    echo "--- isc-dhcp-server ---"
    systemctl is-active isc-dhcp-server 2>/dev/null && ls /etc/dhcp/dhcpd.conf.d/*.conf 2>/dev/null
    echo
    echo "--- ufw ---"
    command -v ufw >/dev/null 2>&1 && ufw status
    echo
    echo "--- fail2ban ---"
    command -v fail2ban-client >/dev/null 2>&1 && fail2ban-client status sshd 2>/dev/null
    echo
    echo "--- tailscale ---"
    command -v tailscale >/dev/null 2>&1 && tailscale status 2>/dev/null
    echo
    echo "--- zerotier ---"
    command -v zerotier-cli >/dev/null 2>&1 && zerotier-cli listnetworks 2>/dev/null
    pause
}

# ---------- main menu ----------

main_menu() {
    require_root
    while true; do
        clear
        cat <<'MENU'
============================================
 Ubuntu Net Admin Menu
============================================
 1) Netplan: set interface to DHCP or Static
 2) Enable IP forwarding + NAT (share internet to LAN)
 3) Open SSH (password login, no key required, ITS The1 Solutions banner)
 4) LAN DHCP server (isc-dhcp-server)
 5) UFW firewall + fail2ban
 6) Port-forward / DNAT helper
 7) Tailscale install + connect (own auth key)
 8) ZeroTier install + join network
 9) Install all dependencies now (bootstrap)
 10) Show status
 11) Exit
============================================
MENU
        read -rp "Choose an option [1-11]: " opt
        case "$opt" in
            1) configure_netplan ;;
            2) configure_forwarding ;;
            3) configure_ssh_open ;;
            4) configure_lan_dhcp ;;
            5) configure_ufw_fail2ban ;;
            6) configure_port_forward ;;
            7) configure_tailscale ;;
            8) configure_zerotier ;;
            9) install_all_deps ;;
            10) show_status ;;
            11) exit 0 ;;
            *) echo "Invalid choice."; pause ;;
        esac
    done
}

main_menu
