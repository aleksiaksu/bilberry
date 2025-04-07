#!/bin/ash
# A simple neofetch-like script for ash

# Function to print an ASCII logo
print_logo() {
    cat << 'EOF'
       .--.
      |o_o |
      |:_/ |
     //   \ \
    (|     | )
   /'\_   _/`\
   \___)=(___/
EOF
}

# Function to print basic system information
print_info() {
    # OS and kernel info
    echo "OS: $(uname -s)"
    echo "Kernel: $(uname -r)"
    echo "Hostname: $(hostname)"

    # Uptime (if available)
    uptime_info=$(uptime -p 2>/dev/null)
    if [ -n "$uptime_info" ]; then
        echo "Uptime: $uptime_info"
    else
        echo "Uptime: N/A"
    fi

    # CPU information
    cpu_model=$(grep -m 1 "model name" /proc/cpuinfo 2>/dev/null | cut -d: -f2 | sed 's/^ *//')
    if [ -z "$cpu_model" ]; then
        cpu_model="Unknown CPU"
    fi
    echo "CPU: $cpu_model"

    # Memory information from /proc/meminfo
    mem_total=$(grep -m 1 "MemTotal" /proc/meminfo | awk '{print $2, $3}')
    mem_available=$(grep -m 1 "MemAvailable" /proc/meminfo | awk '{print $2, $3}')
    if [ -n "$mem_total" ] && [ -n "$mem_available" ]; then
        echo "Memory: $mem_available available / $mem_total total"
    else
        echo "Memory: N/A"
    fi
}

# Clear the screen, print the logo, and then system info
cls
print_logo
echo
print_info