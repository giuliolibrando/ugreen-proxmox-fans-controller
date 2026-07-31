#!/usr/bin/env bash

echo "System Thermal & Fan Control Report - $(date '+%Y-%m-%d %H:%M:%S')"
echo "================================================================================"

# --- 1. SETUP AND SENSOR SEARCH ---
# Dynamically find system paths for CPU and Fans
IT_DIR=$(grep -l "it8603" /sys/class/hwmon/hwmon*/name 2>/dev/null | head -n1 | sed 's/\/name//')
CPU_DIR=$(grep -l "coretemp" /sys/class/hwmon/hwmon*/name 2>/dev/null | head -n1 | sed 's/\/name//')

if [ -z "$IT_DIR" ]; then
    echo "ERROR: Fan chip (it8603) not found! it87 module not loaded."
    exit 1
fi

# --- 2. CPU TEMPERATURE ---
cpu_temp_raw=$(cat "$CPU_DIR/temp1_input" 2>/dev/null)
cpu_temp=$((cpu_temp_raw / 1000))

# --- 3. HDD TEMPERATURES ---
printf "%-4s %-6s %-18s %-14s %-6s %-6s\n" "BAY" "DEV" "MODEL" "SERIAL" "TEMP" "STATE"
echo "--------------------------------------------------------------------------------"

temps=()
output=()
max_hdd_temp=0

for disk in sda sdb sdc sdd; do
    if [ -b "/dev/$disk" ]; then
        model=$(lsblk -dn -o MODEL /dev/$disk | xargs)
        serial=$(lsblk -dn -o SERIAL /dev/$disk | xargs)
        bay=$(ls -l /dev/disk/by-path/ 2>/dev/null | grep "$disk" | sed -n 's/.*ata-\([0-9]\+\).*/\1/p' | head -n1)
        [ -z "$bay" ] && bay="?"

        temp=$(smartctl -A /dev/$disk | awk '/Temperature_Celsius/ {print $10}')
        [ -z "$temp" ] && temp=$(smartctl -A /dev/$disk | awk '/Temperature:/ {print $2}')

        if [ -z "$temp" ]; then
            state="N/A"
            temp_val=0
        else
            temp_val=$temp
            [ "$temp_val" -gt "$max_hdd_temp" ] && max_hdd_temp=$temp_val
            
            if [ "$temp" -ge 55 ]; then
                state="HOT"
            elif [ "$temp" -ge 50 ]; then
                state="WARM"
            else
                state="OK"
            fi
        fi

        temps+=("$temp_val")
        output+=("$temp_val|$bay|/dev/$disk|$model|$serial|$temp|$state")
    fi
done

IFS=$'\n' sorted=($(sort -t'|' -k1 -nr <<<"${output[*]}"))
unset IFS

for line in "${sorted[@]}"; do
    IFS='|' read -r t bay dev model serial temp state <<< "$line"
    if [ "$t" -ge 55 ]; then color="\033[31m"
    elif [ "$t" -ge 50 ]; then color="\033[33m"
    else color="\033[32m"
    fi
    printf "${color}%-4s %-6s %-18s %-14s %-6s %-6s\033[0m\n" "$bay" "$dev" "$model" "$serial" "${temp}°C" "$state"
done

echo "--------------------------------------------------------------------------------"

# --- 4. SEPARATE FAN CONTROL LOGIC (CPU vs HDD) ---

# 4A. CPU Fan Curve (Higher thresholds for processors)
if [ "$cpu_temp" -ge 85 ]; then cpu_pwm=255       # 100% - Emergency
elif [ "$cpu_temp" -ge 70 ]; then cpu_pwm=180     # ~70% - Warm
elif [ "$cpu_temp" -ge 55 ]; then cpu_pwm=100     # ~40% - Normal
else cpu_pwm=60                                   # ~25% - Quiet
fi

# 4B. HDD Fan Curve (Stricter thresholds to protect mechanical drives)
if [ "$max_hdd_temp" -ge 55 ]; then hdd_pwm=255   # 100% - Emergency
elif [ "$max_hdd_temp" -ge 50 ]; then hdd_pwm=180 # ~70% - Warm
elif [ "$max_hdd_temp" -ge 45 ]; then hdd_pwm=100 # ~40% - Normal
else hdd_pwm=60                                   # ~25% - Quiet
fi

# 4C. Choose the highest demand between CPU and HDDs
if [ "$hdd_pwm" -gt "$cpu_pwm" ]; then
    pwm_val=$hdd_pwm
    trigger_temp=$max_hdd_temp
    trigger_name="HDD"
else
    pwm_val=$cpu_pwm
    trigger_temp=$cpu_temp
    trigger_name="CPU"
fi

# Set fan state label for reporting
if [ "$pwm_val" -eq 255 ]; then fan_state="100% (CRITICAL)"
elif [ "$pwm_val" -eq 180 ]; then fan_state="70% (WARM)"
elif [ "$pwm_val" -eq 100 ]; then fan_state="40% (NORMAL)"
else fan_state="25% (QUIET)"
fi

# Apply PWM to fans (Forcing manual mode)
for i in 1 2 3; do
    echo 1 > "$IT_DIR/pwm${i}_enable" 2>/dev/null
    echo $pwm_val > "$IT_DIR/pwm${i}" 2>/dev/null
done

# --- 5. FINAL SUMMARY ---
echo "Summary & Fan Action:"
echo "  CPU Temp      : ${cpu_temp}°C"
echo "  Max HDD Temp  : ${max_hdd_temp}°C"
echo "  Driving Temp  : ${trigger_temp}°C ($trigger_name)"
echo "  Fans Target   : $fan_state (PWM: $pwm_val)"
echo "================================================================================"
