# UGREEN DXP4800 Plus - Proxmox Auto Fan Control

A lightweight bash script and systemd daemon to automatically control fan speeds on the **UGREEN DXP4800 Plus** NAS running Proxmox VE (or Debian).

When replacing the stock Ugreen OS with Proxmox, the Linux kernel lacks native management for the ITE IT8613E Super IO fan controller. This causes the fans to spin at a fixed low speed, risking severe CPU and HDD overheating under heavy load. Standard tools like `fancontrol` or `pwmconfig` fail due to hardware limits.

This script elegantly bypasses the issue by continuously reading CPU and HDD temperatures, calculating the optimal cooling target, and writing PWM values directly to the `sysfs` registers.

## Features

- **Dynamic Dual Monitoring:** Checks both CPU (`coretemp`) and HDD (SMART) temperatures dynamically.
- **Smart Logic:** Prioritizes cooling based on the hottest component in the system.
- **Visual Dashboard:** Run the script manually anytime to get a beautifully colored CLI summary of your drives' bays, temps, and current fan state.
- **Set and Forget:** Runs silently in the background as a `systemd` daemon (updates every 30 seconds).

## Prerequisites

Before installing this tool, you must force the Linux kernel to load the compatible `it87` driver and install the tools required to read HDD thermals.

**1. Install SMART tools:**
```bash
apt update && apt install smartmontools
```

**2. Force the ITE fan controller driver:**
Run these commands as root to load the driver persistently:
```bash
echo "options it87 force_id=0x8623" > /etc/modprobe.d/it87.conf
echo "it87" >> /etc/modules
update-initramfs -u -k all
modprobe it87 force_id=0x8623
```
*(Run `sensors` to verify. You should now see an `it8603-isa-0a30` section with `fan2`, `fan3`, and `pwm` readouts).*

## Installation

**1. Prepare the directory:**
Clone the repository or copy the files manually into `/opt/ugreen-fan/`.
```bash
mkdir -p /opt/ugreen-fan
cd /opt/ugreen-fan
git clone https://github.com/giuliolibrando/ugreen-proxmox-fans-controller.git .
```

**2. Make scripts executable:**
```bash
chmod +x /opt/ugreen-fan/temps.sh
chmod +x /opt/ugreen-fan/fan-daemon.sh
```

**3. Install and enable the Daemon:**
```bash
cp /opt/ugreen-fan/ugreen-fan.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now ugreen-fan.service
```

**4. Verify it's running:**
```bash
systemctl status ugreen-fan.service
```

## Customizing the Fan Curve

You can easily tweak the temperature thresholds and fan speeds. Note that PWM values range from `0` (off) to `255` (100% speed).

Open the main script:
```bash
nano /opt/ugreen-fan/temps.sh
```
Scroll down to the **FAN CONTROL LOGIC** section and adjust the values to fit your noise/cooling preference:

```bash
if [ "$trigger_temp" -ge 65 ]; then
    pwm_val=255 # 100% Speed - CRITICAL
elif [ "$trigger_temp" -ge 55 ]; then
    pwm_val=180 # ~70% Speed - WARM
elif [ "$trigger_temp" -ge 45 ]; then
    pwm_val=100 # ~40% Speed - NORMAL
else
    pwm_val=60  # ~25% Speed - QUIET
fi
```
Save the file and restart the service to apply changes: 
```bash
systemctl restart ugreen-fan.service
```

## Manual Thermal Dashboard

You can manually trigger the script at any time to see a live report of your system thermals without interrupting the daemon.

```bash
/opt/ugreen-fan/temps.sh
```

**Example Output:**
```text
System Thermal & Fan Control Report - 2026-07-31 10:29:17
================================================================================
BAY  DEV    MODEL              SERIAL         TEMP  STATE 
--------------------------------------------------------------------------------
1    /dev/sda WDC WD4000FYYZ-01 WD-WMC130E8J 45°C  OK    
2    /dev/sdb WDC WD4000FYYZ-01 WD-WCC131HLS 48°C  OK    
--------------------------------------------------------------------------------
Summary & Fan Action:
  CPU Temp      : 61°C
  Max HDD Temp  : 48°C
  Driving Temp  : 61°C (CPU)
  Fans Target   : 70% (WARM) (PWM: 180)
================================================================================
```
