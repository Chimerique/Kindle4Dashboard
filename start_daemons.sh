#!/bin/sh
# start_daemons.sh — Lance les daemons dashboard en production
# Tue les anciennes instances et démarre proprement

echo "=== Arrêt des instances existantes ==="
ps -ef | grep -e 'kindle_scheduler' -e 'toggle_dashboard' | grep -v grep | awk '{print $2}' | while read pid; do kill -9 "$pid" 2>/dev/null; done
sleep 1

echo "=== Lancement scheduler ==="
( sh /mnt/us/kindle_scheduler.sh >> /tmp/scheduler.log 2>&1 & )

echo "=== Lancement toggle ==="
( sh /mnt/us/toggle_dashboard.sh > /dev/null 2>&1 & )

sleep 2

echo "=== Processus actifs ==="
ps -ef | grep -e 'kindle_scheduler' -e 'toggle_dashboard' | grep -v grep
echo "=== OK ==="
