#!/bin/bash
# System Details Report Script
# Collects comprehensive system information
OUTPUT_FILE="system_report_$(date +%Y%m%d_%H%M%S).txt"
echo "Generating system report..."
echo "================================" > "$OUTPUT_FILE"
echo "SYSTEM INFORMATION REPORT" >> "$OUTPUT_FILE"
echo "Generated: $(date)" >> "$OUTPUT_FILE"
echo "================================" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

# Hostname
echo "=== HOSTNAME ===" >> "$OUTPUT_FILE"
hostname >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

# OS Information
echo "=== OPERATING SYSTEM ===" >> "$OUTPUT_FILE"
if [ -f /etc/os-release ]; then
    cat /etc/os-release >> "$OUTPUT_FILE"
else
    uname -a >> "$OUTPUT_FILE"
fi
echo "" >> "$OUTPUT_FILE"

# Kernel Version
echo "=== KERNEL VERSION ===" >> "$OUTPUT_FILE"
uname -r >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

# Uptime
echo "=== SYSTEM UPTIME ===" >> "$OUTPUT_FILE"
uptime >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

# CPU Information
echo "=== CPU INFORMATION ===" >> "$OUTPUT_FILE"
if [ -f /proc/cpuinfo ]; then
    grep "model name" /proc/cpuinfo | head -1 >> "$OUTPUT_FILE"
    echo "CPU Cores: $(grep -c processor /proc/cpuinfo)" >> "$OUTPUT_FILE"
    lscpu 2>/dev/null >> "$OUTPUT_FILE" || echo "lscpu not available" >> "$OUTPUT_FILE"
else
    sysctl -n machdep.cpu.brand_string 2>/dev/null >> "$OUTPUT_FILE" || echo "CPU info not available" >> "$OUTPUT_FILE"
fi
echo "" >> "$OUTPUT_FILE"

# Memory Information
echo "=== MEMORY INFORMATION ===" >> "$OUTPUT_FILE"
if command -v free &> /dev/null; then
    free -h >> "$OUTPUT_FILE"
elif [ -f /proc/meminfo ]; then
    head -5 /proc/meminfo >> "$OUTPUT_FILE"
else
    vm_stat 2>/dev/null >> "$OUTPUT_FILE" || echo "Memory info not available" >> "$OUTPUT_FILE"
fi
echo "" >> "$OUTPUT_FILE"

# Disk Usage
echo "=== DISK USAGE ===" >> "$OUTPUT_FILE"
df -h >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

# Disk Information
echo "=== DISK INFORMATION ===" >> "$OUTPUT_FILE"
if command -v lsblk &> /dev/null; then
    lsblk >> "$OUTPUT_FILE"
elif command -v diskutil &> /dev/null; then
    diskutil list >> "$OUTPUT_FILE"
else
    fdisk -l 2>/dev/null >> "$OUTPUT_FILE" || echo "Disk info not available" >> "$OUTPUT_FILE"
fi
echo "" >> "$OUTPUT_FILE"

# Network Interfaces
echo "=== NETWORK INTERFACES ===" >> "$OUTPUT_FILE"
if command -v ip &> /dev/null; then
    ip addr show >> "$OUTPUT_FILE"
else
    ifconfig 2>/dev/null >> "$OUTPUT_FILE" || echo "Network info not available" >> "$OUTPUT_FILE"
fi
echo "" >> "$OUTPUT_FILE"

# Running Processes
echo "=== TOP PROCESSES (by CPU) ===" >> "$OUTPUT_FILE"
ps aux --sort=-%cpu 2>/dev/null | head -11 >> "$OUTPUT_FILE" || \
ps aux 2>/dev/null | sort -rk 3 | head -11 >> "$OUTPUT_FILE" || \
echo "Process info not available" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "=== TOP PROCESSES (by Memory) ===" >> "$OUTPUT_FILE"
ps aux --sort=-%mem 2>/dev/null | head -11 >> "$OUTPUT_FILE" || \
ps aux 2>/dev/null | sort -rk 4 | head -11 >> "$OUTPUT_FILE" || \
echo "Process info not available" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

# Logged-in Users
echo "=== LOGGED IN USERS ===" >> "$OUTPUT_FILE"
who >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

# System Load
echo "=== SYSTEM LOAD ===" >> "$OUTPUT_FILE"
cat /proc/loadavg 2>/dev/null >> "$OUTPUT_FILE" || uptime >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

# GPU Information (if available)
echo "=== GPU INFORMATION ===" >> "$OUTPUT_FILE"
if command -v lspci &> /dev/null; then
    lspci | grep -i vga >> "$OUTPUT_FILE"
    lspci | grep -i nvidia >> "$OUTPUT_FILE"
else
    echo "GPU info not available" >> "$OUTPUT_FILE"
fi
echo "" >> "$OUTPUT_FILE"

echo "================================" >> "$OUTPUT_FILE"
echo "Report saved to: $OUTPUT_FILE"
echo "Report generation complete!"

# Display file location
echo "Full path: $(pwd)/$OUTPUT_FILE"
