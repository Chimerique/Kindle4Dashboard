#!/bin/sh
FLAG_FILE="/mnt/us/DASHBOARD_DISABLED"
LOG_FILE="/mnt/us/toggle_dashboard.log"
PID_FILE="/tmp/toggle_dashboard.pid"

# ------ ANTI-DOUBLONS : tuer TOUTES les instances pr??c??dentes ------
# ps -ef fonctionne sur BusyBox ; on filtre notre propre PID avec grep -v
MYPID=$$
PIDS_TO_KILL=$(ps -ef | grep '[t]oggle_dashboard.sh' | awk -v me="$MYPID" '$2 != me {print $2}')
if [ -n "$PIDS_TO_KILL" ]; then
	kill -9 $PIDS_TO_KILL 2>/dev/null
	sleep 1
fi
echo $MYPID > "$PID_FILE"

cleanup() { rm -f "$PID_FILE"; }
trap cleanup EXIT INT TERM

# ------ CONFIGURATION ------
# Nombre d'??v??nements requis dans la fen??tre pour d??clencher
# 1 clic physique = ~2 ??v??nements (appui + rel??chement)
# 3 clics = ~6 ??v??nements, 4 clics = ~8 ??v??nements ??? seuil ?? 7
EVENTS_REQUIRED=7
# Dur??e max (ms) pendant laquelle les ??v??nements doivent s'accumuler (fen??tre glissante)
WINDOW_MS=3000
# Cooldown (s) apr??s un basculement pour ignorer les rebonds
COOLDOWN_SEC=3

get_ms() { awk '{print int($1 * 1000)}' /proc/uptime; }

show_status() {
	/usr/sbin/eips 2 2 "                "
	/usr/sbin/eips 2 3 "                "
	/usr/sbin/eips 2 2 "DASHBOARD"
	/usr/sbin/eips 2 3 "$1"
}

# D??marrer en mode OFF par d??faut
if [ ! -f "$FLAG_FILE" ]; then
	touch "$FLAG_FILE"
fi

# Ignorer les ??v??nements mis en queue avant le d??marrage (cooldown initial)
LAST_TOGGLE=$(date +%s)
WINDOW_START_MS=0
EVENT_COUNT=0
LAST_EVENT_MS=0

echo "$(date) - START pid=$$ (required=${EVENTS_REQUIRED} events in ${WINDOW_MS}ms, cooldown=${COOLDOWN_SEC}s)" >> "$LOG_FILE"

while true; do
	waitforkey 102
	NOW=$(date +%s)
	NOW_MS=$(get_ms)

	# --- Ignorer pendant le cooldown post-basculement ---
	if [ $((NOW - LAST_TOGGLE)) -lt $COOLDOWN_SEC ]; then
		continue
	fi

	# --- Fen??tre glissante ---
	# Si trop de temps s'est ??coul?? depuis le dernier ??v??nement ??? on repart de 0
	if [ $LAST_EVENT_MS -eq 0 ] || [ $((NOW_MS - LAST_EVENT_MS)) -gt $WINDOW_MS ]; then
		WINDOW_START_MS=$NOW_MS
		EVENT_COUNT=1
	else
		EVENT_COUNT=$((EVENT_COUNT + 1))
	fi
	LAST_EVENT_MS=$NOW_MS

	echo "$(date) - EVENT #${EVENT_COUNT} gap=$((NOW_MS - WINDOW_START_MS))ms" >> "$LOG_FILE"

	# --- D??clenchement si seuil atteint dans la fen??tre ---
	if [ $EVENT_COUNT -ge $EVENTS_REQUIRED ]; then
		ELAPSED=$((NOW_MS - WINDOW_START_MS))
		echo "$(date) - TOGGLE TRIGGERED (${EVENT_COUNT} events in ${ELAPSED}ms)" >> "$LOG_FILE"

		LAST_TOGGLE=$(date +%s)
		WINDOW_START_MS=0
		EVENT_COUNT=0
		LAST_EVENT_MS=0

		if [ -f "$FLAG_FILE" ]; then
			rm "$FLAG_FILE"
			show_status "ON"
			lipc-set-prop com.lab126.powerd preventScreenSaver 1
			sleep 1
			sh /mnt/us/update_frame.sh &
		else
			touch "$FLAG_FILE"
			show_status "OFF"
			lipc-set-prop com.lab126.powerd preventScreenSaver 0
			sleep 1
			/usr/sbin/eips -c
		fi
	fi
done
