#!/bin/sh
# kindle_scheduler.sh
# Orchestrateur du cycle complet de mise à jour du dashboard.
# Architecture : update → optimisations batterie → RTC alarm → suspend propre
#
# Ce script s'exécute UNE SEULE FOIS par cycle. Il n'y a PAS de boucle infinie.
# Le réveil suivant est programmé dans le matériel (RTC) avant de dormir.
# Au redémarrage/réveil, le système le relance via init.d.
#
# Usage : sh /mnt/us/kindle_scheduler.sh

FLAG_FILE="/mnt/us/DASHBOARD_DISABLED"
LOG_FILE="/tmp/scheduler.log"
RTC_ALARM="/sys/devices/platform/pmic_rtc.1/rtc/rtc1/wakealarm"
UPDATE_SCRIPT="/mnt/us/update_frame.sh"
MAX_LOG_LINES=200

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
    # Essais en cascade selon les chemins disponibles sur Kindle 4
    cat /sys/class/power_supply/battery/capacity 2>/dev/null       && return
    cat /sys/class/power_supply/*/capacity 2>/dev/null | head -1   && return
    lipc-get-prop -i com.lab126.powerd battLevel 2>/dev/null       && return
    echo "?"
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
# PROGRAMME L'ALARME RTC
# Le matériel PMIC (rtc1) réveillera le processeur après $INTERVAL secondes,
# indépendamment de l'OS.
# Essai relatif (+N) en premier, fallback absolu si le noyau ne supporte pas.
# ================================================================
set_rtc_wakeup() {
    INTERVAL="$1"

    if [ ! -f "$RTC_ALARM" ]; then
        log "WARN" "wakealarm introuvable : $RTC_ALARM - réveil matériel impossible"
        return 1
    fi

    # Réinitialisation obligatoire avant de programmer une nouvelle alarme
    echo 0 > "$RTC_ALARM" 2>/dev/null

    # Tentative relative (supportée par certaines versions du noyau Kindle)
    echo "+${INTERVAL}" > "$RTC_ALARM" 2>/dev/null
    ALARM_VAL=$(cat "$RTC_ALARM" 2>/dev/null)

    if [ -z "$ALARM_VAL" ] || [ "$ALARM_VAL" = "0" ]; then
        # Fallback : timestamp UNIX absolu
        NOW=$(date +%s)
        WAKE_AT=$((NOW + INTERVAL))
        echo "$WAKE_AT" > "$RTC_ALARM" 2>/dev/null
        log "INFO" "RTC alarme (absolu) programmée à $WAKE_AT (+${INTERVAL}s)"
    else
        log "INFO" "RTC alarme (relatif) +${INTERVAL}s OK (val retournée=$ALARM_VAL)"
    fi
}

# ================================================================
# MISE EN VEILLE PROPRE
# Ordre de tentatives : powerd (Amazon) → kernel mem → abandon
# L'abandon est non-fatal : la tablette restera éveillée mais au moins
# le prochain cycle sera correct après réveil RTC.
# ================================================================
do_suspend() {
    log "INFO" "Début procédure de mise en veille..."

    # Autoriser le screensaver/suspend (si on bloquait à 1, le système refusait de dormir)
    lipc-set-prop com.lab126.powerd preventScreenSaver 0 2>/dev/null || true

    # Couper le WiFi / mode avion avant de dormir
    lipc-set-prop com.lab126.cmd wirelessEnable 0 2>/dev/null || true
    sleep 2
    log "INFO" "WiFi coupé"

    # --- Tentative 1 : demande propre via powerd (daemon Amazon) ---
    # deferSuspend=1 signale à powerd qu'il peut entrer en veille dès qu'il est prêt
    lipc-set-prop com.lab126.powerd deferSuspend 1 2>/dev/null || true
    sleep 5

    # --- Tentative 2 : suspend kernel direct ---
    # ATTENTION : sur certains firmware, echo mem freeze le système si des pilotes
    # sont mal initialisés. On ne tente que si /sys/power/state existe.
    if [ -f "/sys/power/state" ]; then
        STATES=$(cat /sys/power/state 2>/dev/null)
        if echo "$STATES" | grep -q "mem"; then
            log "INFO" "Tentative suspend kernel (echo mem)"
            echo mem > /sys/power/state 2>/dev/null
            sleep 2
            # Si on arrive ici après le sleep, on vient de se réveiller
            log "INFO" "Réveil confirm : retour de mem suspend"
        else
            log "WARN" "/sys/power/state ne propose pas 'mem' (valeurs: $STATES)"
        fi
    else
        log "WARN" "/sys/power/state absent - pas de suspend kernel"
    fi

    # Si on est encore là, le suspend a échoué ou on vient de se réveiller
    log "INFO" "Procédure de veille terminée"
}

# ================================================================
# PROGRAMME PRINCIPAL
# ================================================================
INTERVAL=$(get_interval)
BATT=$(get_battery)

log "INFO" "============================================"
log "INFO" "Cycle démarré | heure=$(date '+%H:%M') | intervalle=${INTERVAL}s (~$((INTERVAL/60))min) | batt=${BATT}%"

# Optimisations CPU dès le départ
set_powersave

# --- Si dashboard désactivé ---
if [ -f "$FLAG_FILE" ]; then
    log "INFO" "Dashboard OFF → pas d'update, prochain réveil dans ${INTERVAL}s"
    set_rtc_wakeup "$INTERVAL"
    do_suspend
    log "INFO" "Cycle terminé (dashboard OFF)"
    exit 0
fi

# --- Dashboard actif : mise à jour de l'image ---
if [ -x "$UPDATE_SCRIPT" ]; then
    log "INFO" "Lancement update_frame.sh..."
    sh "$UPDATE_SCRIPT"
    UPDATE_EXIT=$?
    if [ "$UPDATE_EXIT" -ne 0 ]; then
        log "WARN" "update_frame.sh a retourné le code $UPDATE_EXIT"
    else
        log "INFO" "Update terminé avec succès"
    fi
else
    log "ERROR" "Script update introuvable ou non exécutable : $UPDATE_SCRIPT"
fi

# --- Programme le prochain réveil ---
set_rtc_wakeup "$INTERVAL"

# --- Mise en veille ---
do_suspend

log "INFO" "Cycle terminé (post-suspend ou échec suspend)"
exit 0
