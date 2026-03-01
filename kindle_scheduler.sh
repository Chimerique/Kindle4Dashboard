#!/bin/sh
# kindle_scheduler.sh
# Orchestrateur du cycle de mise à jour du dashboard Kindle.
#
# Fonctionnement : boucle infinie avec sleep dynamique selon l'heure.
# Entre chaque cycle : WiFi off (via update_frame.sh) + preventScreenSaver 0
# → la liseuse entre en veille naturelle (light sleep), économisant la batterie.
# preventScreenSaver 1 uniquement pendant la mise à jour de l'image.
#
# Pas de boucle infinie si dashboard OFF → on vérifie toutes les POLL_SEC.
#
# Variables d'environnement :
#   NO_WIFI=1      → passe --no-wifi à update_frame.sh (tests SSH)
#   NO_SUSPEND=1   → ne pas mettre preventScreenSaver à 0 (tests SSH)
#
# Usage : sh /mnt/us/kindle_scheduler.sh

FLAG_FILE="/mnt/us/DASHBOARD_DISABLED"
LOG_FILE="/tmp/scheduler.log"
UPDATE_SCRIPT="/mnt/us/update_frame.sh"
MAX_LOG_LINES=200
NO_WIFI="${NO_WIFI:-0}"
NO_SUSPEND="${NO_SUSPEND:-0}"
# Intervalle de scrutation quand dashboard OFF (en secondes)
POLL_SEC=60

# ================================================================
# LOGGING
# ================================================================
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$1] $2" >> "$LOG_FILE"
}

# Rotation légère du fichier de log
if [ -f "$LOG_FILE" ]; then
    LINES=$(wc -l < "$LOG_FILE" 2>/dev/null || echo 0)
    if [ "$LINES" -gt "$MAX_LOG_LINES" ]; then
        tail -50 "$LOG_FILE" > "${LOG_FILE}.tmp" && mv "${LOG_FILE}.tmp" "$LOG_FILE"
    fi
fi

# ================================================================
# INTERVALLE selon heure de la journée
# Retourne le nombre de secondes à dormir entre deux updates.
# ================================================================
get_interval() {
    # BusyBox `date` : `%H` retourne "07" → on retire le zéro de tête pour l'arithmétique
    HOUR=$(date +%H | awk '{print int($1)}')

    if   [ "$HOUR" -ge  0 ] && [ "$HOUR" -lt  6 ]; then echo 1800  # 00h-06h : 30min
    elif [ "$HOUR" -ge  6 ] && [ "$HOUR" -lt  8 ]; then echo 300   # 06h-08h : 5min
    elif [ "$HOUR" -ge  8 ] && [ "$HOUR" -lt 17 ]; then echo 900   # 08h-17h : 15min
    elif [ "$HOUR" -ge 17 ] && [ "$HOUR" -lt 20 ]; then echo 300   # 17h-20h : 5min
    else                                                  echo 900  # 20h-00h : 15min
    fi
}

# ================================================================
# LECTURE BATTERIE
# ================================================================
get_battery() {
    lipc-get-prop -i com.lab126.powerd battLevel 2>/dev/null || echo "?"
}

# ================================================================
# CPU POWERSAVE
# Réduction de la fréquence processeur pour économiser la batterie
# pendant les courtes tâches réseau.
# ================================================================
set_powersave() {
    GOV_PATH="/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor"
    if [ -f "$GOV_PATH" ]; then
        echo powersave > "$GOV_PATH" 2>/dev/null && log "INFO" "CPU governor → powersave"
    else
        log "INFO" "cpufreq non disponible (skip)"
    fi
}

# ================================================================
# AUTORISER LA VEILLE NATURELLE
# Après affichage, on relâche le verrou screensaver pour que le Kindle
# puisse entrer en veille légère (light sleep) entre deux cycles.
# preventScreenSaver 1 sera remis par update_frame.sh au prochain cycle.
# ================================================================
allow_sleep() {
    if [ "$NO_SUSPEND" = "1" ]; then
        log "INFO" "NO_SUSPEND=1 → veille naturelle ignorée (mode test)"
        return 0
    fi
    lipc-set-prop com.lab126.powerd preventScreenSaver 0 2>/dev/null || true
    log "INFO" "preventScreenSaver → 0 (veille naturelle autorisée)"
}

# ================================================================
# PROGRAMME PRINCIPAL — boucle de cycles
# ================================================================
log "INFO" "============================================"
log "INFO" "Scheduler démarré | pid=$$"

# Optimisations CPU dès le départ
set_powersave

while true; do
    INTERVAL=$(get_interval)
    BATT=$(get_battery)
    HOUR=$(date +%H | awk '{print int($1)}')

    # --- Si dashboard désactivé : ne rien faire du tout ---
    # La liseuse doit rester utilisable normalement par le lecteur.
    if [ -f "$FLAG_FILE" ]; then
        log "INFO" "Dashboard OFF | batt=${BATT}% → attente ${POLL_SEC}s"
        sleep "$POLL_SEC"
        continue
    fi

    # --- Dashboard actif : mise à jour ---
    log "INFO" "--- Cycle heure=${HOUR}h | intervalle=${INTERVAL}s (~$((INTERVAL/60))min) | batt=${BATT}% ---"

    if [ -x "$UPDATE_SCRIPT" ]; then
        UPDATE_ARGS=""
        [ "$NO_WIFI" = "1" ] && UPDATE_ARGS="--no-wifi"
        log "INFO" "Lancement update_frame.sh $UPDATE_ARGS"
        sh "$UPDATE_SCRIPT" $UPDATE_ARGS
        UPDATE_EXIT=$?
        if [ "$UPDATE_EXIT" -ne 0 ]; then
            log "WARN" "update_frame.sh exit=$UPDATE_EXIT"
        else
            log "INFO" "Update OK"
        fi
    else
        log "ERROR" "Script update introuvable : $UPDATE_SCRIPT"
    fi

    # Autoriser la veille naturelle pendant le sleep (screen off = batterie économisée)
    allow_sleep

    log "INFO" "Pause ${INTERVAL}s..."
    sleep "$INTERVAL"
done
