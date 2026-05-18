#!/bin/sh
pkill -f kindle_scheduler 2>/dev/null
sleep 2
rm -f /tmp/wifi_busy
sh /mnt/us/kindle_scheduler.sh >> /tmp/scheduler.log 2>&1 &
sleep 6
tail -8 /tmp/scheduler.log
echo "=== usb0 ==="
ifconfig usb0
echo "=== WiFi ==="
lipc-get-prop -s com.lab126.wifid cmState
ifconfig wlan0 | grep inet
