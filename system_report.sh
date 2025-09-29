#!/bin/bash

# System Details HTML Report Script with Charts
OUTPUT_FILE="system_report_$(date +%Y%m%d_%H%M%S).html"

echo "Generating system report..."

# Function to get memory info
get_memory_info() {
    if command -v free &> /dev/null; then
        MEM_TOTAL=$(free -m | awk 'NR==2{print $2}')
        MEM_USED=$(free -m | awk 'NR==2{print $3}')
        MEM_FREE=$(free -m | awk 'NR==2{print $4}')
        MEM_AVAILABLE=$(free -m | awk 'NR==2{print $7}')
    elif [ -f /proc/meminfo ]; then
        MEM_TOTAL=$(grep MemTotal /proc/meminfo | awk '{print int($2/1024)}')
        MEM_AVAILABLE=$(grep MemAvailable /proc/meminfo | awk '{print int($2/1024)}')
        MEM_USED=$((MEM_TOTAL - MEM_AVAILABLE))
        MEM_FREE=$MEM_AVAILABLE
    else
        MEM_TOTAL=0
        MEM_USED=0
        MEM_FREE=0
        MEM_AVAILABLE=0
    fi
}

# Function to get CPU usage
get_cpu_usage() {
    if [ -f /proc/stat ]; then
        CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')
    else
        CPU_USAGE=$(ps -A -o %cpu | awk '{s+=$1} END {print s}')
    fi
    echo ${CPU_USAGE:-0}
}

# Function to get disk info
get_disk_info() {
    df -h / | awk 'NR==2 {gsub("%",""); print $2","$3","$4","$5}'
}

# Get system info
HOSTNAME=$(hostname)
OS_INFO=$(cat /etc/os-release 2>/dev/null | grep "PRETTY_NAME" | cut -d'"' -f2 || uname -s)
KERNEL=$(uname -r)
UPTIME=$(uptime -p 2>/dev/null || uptime | awk -F'up ' '{print $2}' | awk -F',' '{print $1}')
CPU_MODEL=$(grep "model name" /proc/cpuinfo 2>/dev/null | head -1 | cut -d':' -f2 | xargs || sysctl -n machdep.cpu.brand_string 2>/dev/null || echo "N/A")
CPU_CORES=$(grep -c processor /proc/cpuinfo 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo "N/A")
CPU_USAGE=$(get_cpu_usage)
get_memory_info
DISK_INFO=$(get_disk_info)
DISK_TOTAL=$(echo $DISK_INFO | cut -d',' -f1)
DISK_USED=$(echo $DISK_INFO | cut -d',' -f2)
DISK_FREE=$(echo $DISK_INFO | cut -d',' -f3)
DISK_PERCENT=$(echo $DISK_INFO | cut -d',' -f4)

# Get top processes
TOP_CPU_PROCS=$(ps aux --sort=-%cpu 2>/dev/null | head -6 | tail -5 || ps aux 2>/dev/null | sort -rk 3 | head -6 | tail -5)
TOP_MEM_PROCS=$(ps aux --sort=-%mem 2>/dev/null | head -6 | tail -5 || ps aux 2>/dev/null | sort -rk 4 | head -6 | tail -5)

# Create HTML report
cat > "$OUTPUT_FILE" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>System Report</title>
    <script src="https://cdnjs.cloudflare.com/ajax/libs/Chart.js/3.9.1/chart.min.js"></script>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            padding: 20px;
            min-height: 100vh;
        }
        .container {
            max-width: 1400px;
            margin: 0 auto;
            background: white;
            border-radius: 20px;
            box-shadow: 0 20px 60px rgba(0,0,0,0.3);
            overflow: hidden;
        }
        .header {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 40px;
            text-align: center;
        }
        .header h1 { font-size: 2.5em; margin-bottom: 10px; }
        .header p { opacity: 0.9; font-size: 1.1em; }
        .content { padding: 40px; }
        .grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 25px;
            margin-bottom: 30px;
        }
        .card {
            background: #f8f9fa;
            border-radius: 15px;
            padding: 25px;
            box-shadow: 0 4px 6px rgba(0,0,0,0.07);
            transition: transform 0.3s, box-shadow 0.3s;
        }
        .card:hover {
            transform: translateY(-5px);
            box-shadow: 0 8px 12px rgba(0,0,0,0.15);
        }
        .card h2 {
            color: #667eea;
            font-size: 1.3em;
            margin-bottom: 15px;
            display: flex;
            align-items: center;
            gap: 10px;
        }
        .icon {
            width: 30px;
            height: 30px;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            border-radius: 8px;
            display: flex;
            align-items: center;
            justify-content: center;
            color: white;
            font-weight: bold;
        }
        .info-row {
            display: flex;
            justify-content: space-between;
            padding: 12px 0;
            border-bottom: 1px solid #e0e0e0;
        }
        .info-row:last-child { border-bottom: none; }
        .info-label { font-weight: 600; color: #555; }
        .info-value { color: #333; }
        .chart-container {
            position: relative;
            height: 250px;
            margin-top: 20px;
        }
        .progress-bar {
            width: 100%;
            height: 30px;
            background: #e0e0e0;
            border-radius: 15px;
            overflow: hidden;
            margin-top: 10px;
        }
        .progress-fill {
            height: 100%;
            background: linear-gradient(90deg, #667eea 0%, #764ba2 100%);
            display: flex;
            align-items: center;
            justify-content: center;
            color: white;
            font-weight: bold;
            transition: width 1s ease;
        }
        .table-container {
            overflow-x: auto;
            margin-top: 15px;
        }
        table {
            width: 100%;
            border-collapse: collapse;
            font-size: 0.9em;
        }
        th {
            background: #667eea;
            color: white;
            padding: 12px;
            text-align: left;
            font-weight: 600;
        }
        td {
            padding: 10px 12px;
            border-bottom: 1px solid #e0e0e0;
        }
        tr:hover { background: #f5f5f5; }
        .metric {
            text-align: center;
            padding: 20px;
            background: white;
            border-radius: 10px;
            margin-top: 15px;
        }
        .metric-value {
            font-size: 2.5em;
            font-weight: bold;
            color: #667eea;
        }
        .metric-label {
            color: #666;
            margin-top: 5px;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🖥️ System Information Report</h1>
            <p>Generated on DATE_PLACEHOLDER</p>
        </div>
        
        <div class="content">
            <div class="grid">
                <div class="card">
                    <h2><span class="icon">💻</span>System Overview</h2>
                    <div class="info-row">
                        <span class="info-label">Hostname:</span>
                        <span class="info-value">HOSTNAME_PLACEHOLDER</span>
                    </div>
                    <div class="info-row">
                        <span class="info-label">OS:</span>
                        <span class="info-value">OS_PLACEHOLDER</span>
                    </div>
                    <div class="info-row">
                        <span class="info-label">Kernel:</span>
                        <span class="info-value">KERNEL_PLACEHOLDER</span>
                    </div>
                    <div class="info-row">
                        <span class="info-label">Uptime:</span>
                        <span class="info-value">UPTIME_PLACEHOLDER</span>
                    </div>
                </div>

                <div class="card">
                    <h2><span class="icon">⚡</span>CPU Information</h2>
                    <div class="info-row">
                        <span class="info-label">Model:</span>
                        <span class="info-value">CPU_MODEL_PLACEHOLDER</span>
                    </div>
                    <div class="info-row">
                        <span class="info-label">Cores:</span>
                        <span class="info-value">CPU_CORES_PLACEHOLDER</span>
                    </div>
                    <div class="metric">
                        <div class="metric-value">CPU_USAGE_PLACEHOLDER%</div>
                        <div class="metric-label">CPU Usage</div>
                    </div>
                </div>

                <div class="card">
                    <h2><span class="icon">🧠</span>Memory Usage</h2>
                    <div class="chart-container">
                        <canvas id="memoryChart"></canvas>
                    </div>
                    <div class="info-row" style="margin-top: 15px;">
                        <span class="info-label">Total:</span>
                        <span class="info-value">MEM_TOTAL_PLACEHOLDER MB</span>
                    </div>
                    <div class="info-row">
                        <span class="info-label">Used:</span>
                        <span class="info-value">MEM_USED_PLACEHOLDER MB</span>
                    </div>
                    <div class="info-row">
                        <span class="info-label">Available:</span>
                        <span class="info-value">MEM_AVAILABLE_PLACEHOLDER MB</span>
                    </div>
                </div>

                <div class="card">
                    <h2><span class="icon">💾</span>Disk Usage</h2>
                    <div class="chart-container">
                        <canvas id="diskChart"></canvas>
                    </div>
                    <div class="info-row" style="margin-top: 15px;">
                        <span class="info-label">Total:</span>
                        <span class="info-value">DISK_TOTAL_PLACEHOLDER</span>
                    </div>
                    <div class="info-row">
                        <span class="info-label">Used:</span>
                        <span class="info-value">DISK_USED_PLACEHOLDER</span>
                    </div>
                    <div class="info-row">
                        <span class="info-label">Free:</span>
                        <span class="info-value">DISK_FREE_PLACEHOLDER</span>
                    </div>
                    <div class="progress-bar">
                        <div class="progress-fill" style="width: DISK_PERCENT_PLACEHOLDER%">DISK_PERCENT_PLACEHOLDER%</div>
                    </div>
                </div>
            </div>

            <div class="card">
                <h2><span class="icon">📊</span>Top Processes by CPU</h2>
                <div class="table-container">
                    <table>
                        <thead>
                            <tr>
                                <th>User</th>
                                <th>PID</th>
                                <th>CPU%</th>
                                <th>MEM%</th>
                                <th>Command</th>
                            </tr>
                        </thead>
                        <tbody>
                            TOP_CPU_TABLE_PLACEHOLDER
                        </tbody>
                    </table>
                </div>
            </div>

            <div class="card" style="margin-top: 25px;">
                <h2><span class="icon">📈</span>Top Processes by Memory</h2>
                <div class="table-container">
                    <table>
                        <thead>
                            <tr>
                                <th>User</th>
                                <th>PID</th>
                                <th>CPU%</th>
                                <th>MEM%</th>
                                <th>Command</th>
                            </tr>
                        </thead>
                        <tbody>
                            TOP_MEM_TABLE_PLACEHOLDER
                        </tbody>
                    </table>
                </div>
            </div>
        </div>
    </div>

    <script>
        // Memory Chart
        const memCtx = document.getElementById('memoryChart').getContext('2d');
        new Chart(memCtx, {
            type: 'doughnut',
            data: {
                labels: ['Used', 'Available'],
                datasets: [{
                    data: [MEM_USED_PLACEHOLDER, MEM_AVAILABLE_PLACEHOLDER],
                    backgroundColor: ['#667eea', '#e0e0e0'],
                    borderWidth: 0
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                plugins: {
                    legend: { position: 'bottom' }
                }
            }
        });

        // Disk Chart
        const diskCtx = document.getElementById('diskChart').getContext('2d');
        new Chart(diskCtx, {
            type: 'doughnut',
            data: {
                labels: ['Used', 'Free'],
                datasets: [{
                    data: [DISK_PERCENT_PLACEHOLDER, 100 - DISK_PERCENT_PLACEHOLDER],
                    backgroundColor: ['#764ba2', '#e0e0e0'],
                    borderWidth: 0
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                plugins: {
                    legend: { position: 'bottom' }
                }
            }
        });
    </script>
</body>
</html>
EOF

# Replace placeholders
sed -i "s|DATE_PLACEHOLDER|$(date)|g" "$OUTPUT_FILE"
sed -i "s|HOSTNAME_PLACEHOLDER|$HOSTNAME|g" "$OUTPUT_FILE"
sed -i "s|OS_PLACEHOLDER|$OS_INFO|g" "$OUTPUT_FILE"
sed -i "s|KERNEL_PLACEHOLDER|$KERNEL|g" "$OUTPUT_FILE"
sed -i "s|UPTIME_PLACEHOLDER|$UPTIME|g" "$OUTPUT_FILE"
sed -i "s|CPU_MODEL_PLACEHOLDER|$CPU_MODEL|g" "$OUTPUT_FILE"
sed -i "s|CPU_CORES_PLACEHOLDER|$CPU_CORES|g" "$OUTPUT_FILE"
sed -i "s|CPU_USAGE_PLACEHOLDER|$(printf "%.1f" $CPU_USAGE)|g" "$OUTPUT_FILE"
sed -i "s|MEM_TOTAL_PLACEHOLDER|$MEM_TOTAL|g" "$OUTPUT_FILE"
sed -i "s|MEM_USED_PLACEHOLDER|$MEM_USED|g" "$OUTPUT_FILE"
sed -i "s|MEM_AVAILABLE_PLACEHOLDER|$MEM_AVAILABLE|g" "$OUTPUT_FILE"
sed -i "s|DISK_TOTAL_PLACEHOLDER|$DISK_TOTAL|g" "$OUTPUT_FILE"
sed -i "s|DISK_USED_PLACEHOLDER|$DISK_USED|g" "$OUTPUT_FILE"
sed -i "s|DISK_FREE_PLACEHOLDER|$DISK_FREE|g" "$OUTPUT_FILE"
sed -i "s|DISK_PERCENT_PLACEHOLDER|$DISK_PERCENT|g" "$OUTPUT_FILE"

# Generate CPU process table rows
CPU_TABLE=""
echo "$TOP_CPU_PROCS" | while read -r line; do
    if [ ! -z "$line" ]; then
        USER=$(echo "$line" | awk '{print $1}')
        PID=$(echo "$line" | awk '{print $2}')
        CPU=$(echo "$line" | awk '{print $3}')
        MEM=$(echo "$line" | awk '{print $4}')
        CMD=$(echo "$line" | awk '{for(i=11;i<=NF;i++) printf $i" "; print ""}' | cut -c1-50)
        CPU_TABLE="${CPU_TABLE}<tr><td>$USER</td><td>$PID</td><td>$CPU%</td><td>$MEM%</td><td>$CMD</td></tr>"
    fi
done
sed -i "s|TOP_CPU_TABLE_PLACEHOLDER|$CPU_TABLE|g" "$OUTPUT_FILE"

# Generate Memory process table rows
MEM_TABLE=""
echo "$TOP_MEM_PROCS" | while read -r line; do
    if [ ! -z "$line" ]; then
        USER=$(echo "$line" | awk '{print $1}')
        PID=$(echo "$line" | awk '{print $2}')
        CPU=$(echo "$line" | awk '{print $3}')
        MEM=$(echo "$line" | awk '{print $4}')
        CMD=$(echo "$line" | awk '{for(i=11;i<=NF;i++) printf $i" "; print ""}' | cut -c1-50)
        MEM_TABLE="${MEM_TABLE}<tr><td>$USER</td><td>$PID</td><td>$CPU%</td><td>$MEM%</td><td>$CMD</td></tr>"
    fi
done
sed -i "s|TOP_MEM_TABLE_PLACEHOLDER|$MEM_TABLE|g" "$OUTPUT_FILE"

echo "================================"
echo "✅ Report generated successfully!"
echo "📄 File: $OUTPUT_FILE"
echo "📍 Location: $(pwd)/$OUTPUT_FILE"
echo "================================"
echo "Open it in your browser to view the charts!"
