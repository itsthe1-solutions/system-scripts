#!/bin/bash

# System Details Display Script
# Shows comprehensive system information in terminal

echo "================================"
echo "SYSTEM INFORMATION REPORT"
echo "Generated: $(date)"
echo "================================"
echo ""

# Hostname
echo "=== HOSTNAME ==="
hostname
echo ""

# OS Information
echo "=== OPERATING SYSTEM ==="
if [ -f /etc/os-release ]; then
    cat /etc/os-release
else
    uname -a
fi
echo ""

# Kernel Version
echo "=== KERNEL VERSION ==="
uname -r
echo ""

# Uptime
echo "=== SYSTEM UPTIME ==="
uptime
echo ""

# CPU Information
echo "=== CPU INFORMATION ==="
if [ -f /proc/cpuinfo ]; then
    grep "model name" /proc/cpuinfo | head -1
    echo "CPU Cores: $(grep -c processor /proc/cpuinfo)"
    lscpu 2>/dev/null || echo "lscpu not available"
else
    echo "CPU info not available"
fi
echo ""

# Memory Information
echo "=== MEMORY INFORMATION ==="
if command -v free &> /dev/null; then
    free -h
elif [ -f /proc/meminfo ]; then
    head -5 /proc/meminfo
else
    echo "Memory info not available"
fi
echo ""

# Disk Usage
echo "=== DISK USAGE ==="
df -h
echo ""

# Disk Information
echo "=== DISK INFORMATION ==="
if command -v lsblk &> /dev/null; then
    lsblk
else
    echo "Disk info not available"
fi
echo ""

# Network Interfaces
echo "=== NETWORK INTERFACES ==="
if command -v ip &> /dev/null; then
    ip addr show
else
    ifconfig 2>/dev/null || echo "Network info not available"
fi
echo ""

# Running Processes
echo "=== TOP PROCESSES (by CPU) ==="
ps aux --sort=-%cpu 2>/dev/null | head -11 || \
ps aux 2>/dev/null | sort -rk 3 | head -11 || \
echo "Process info not available"
echo ""

echo "=== TOP PROCESSES (by Memory) ==="
ps aux --sort=-%mem 2>/dev/null | head -11 || \
ps aux 2>/dev/null | sort -rk 4 | head -11 || \
echo "Process info not available"
echo ""

# Logged-in Users
echo "=== LOGGED IN USERS ==="
who
echo ""

# System Load
echo "=== SYSTEM LOAD ==="
cat /proc/loadavg 2>/dev/null || uptime
echo ""

# GPU Information (if available)
echo "=== GPU INFORMATION ==="
if command -v lspci &> /dev/null; then
    lspci | grep -i vga
    lspci | grep -i nvidia
else
    echo "GPU info not available"
fi
echo ""

echo "================================"
echo "Report display complete!"
echo "================================"
