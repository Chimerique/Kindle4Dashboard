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
# MAINTENIR L'ÉCRAN E-INK PENDANT L'INTERVALLE
# preventScreenSaver=1 → LinkSS ne prend jamais la main (image e-ink préservée).
# preventSuspend=0     → le CPU PEUT entrer en light sleep entre cycles.
# L'écran e-ink est bistable : il conserve l'image MÊME en light sleep.
# Ne jamais mettre preventSuspend=1 entre les cycles → tue la batterie et
# ralentit la tablette (CPU reste à fréquence pleine).
# ================================================================
keep_eink_display() {
    if [ "$NO_SUSPEND" = "1" ]; then
        log "INFO" "NO_SUSPEND=1 → mode test, skip"
        return 0
    fi
    lipc-set-prop com.lab126.powerd preventScreenSaver 1 2>/dev/null || true
    lipc-set-prop com.lab126.powerd preventSuspend 0 2>/dev/null || true
    log "INFO" "preventScreenSaver → 1 | preventSuspend → 0 (e-ink préservé, CPU peut dormir)"
}

# ================================================================
# RTC WAKEUP ALARM — best effort, non bloquant si non disponible
# Programme un réveil matériel pour sortir d'un éventuel RTSuspend.
# ================================================================
set_rtc_alarm() {
    WAKE_SEC="$1"
    RTC_ALARM="/sys/class/rtc/rtc0/wakealarm"
    if [ -w "$RTC_ALARM" ]; then
        WAKE_AT=$(( $(date +%s) + WAKE_SEC ))
        echo 0 > "$RTC_ALARM" 2>/dev/null
        echo "$WAKE_AT" > "$RTC_ALARM" 2>/dev/null \
            && log "INFO" "RTC alarm +${WAKE_SEC}s (epoch=$WAKE_AT)" \
            || log "WARN" "RTC alarm write failed"
    else
        log "INFO" "RTC wakealarm non disponible — skip"
    fi
}

# ================================================================
# SLEEP ROBUSTE — survit aux suspend/resume
# Découpe l'attente en tranches de 60s et vérifie l'horloge mur.
# Si le device entre en RTSuspend malgré preventSuspend, le scheduler
# reprend immédiatement dès le prochain réveil (RTC, bouton, charge…).
# ================================================================
smart_sleep() {
    SLEEP_SECS="$1"
    TARGET_EPOCH=$(( $(date +%s) + SLEEP_SECS ))
    set_rtc_alarm "$SLEEP_SECS"
    while true; do
        NOW_EP=$(date +%s)
        REMAINING=$(( TARGET_EPOCH - NOW_EP ))
        [ "$REMAINING" -le 0 ] && break
        CHUNK=60
        [ "$REMAINING" -lt "$CHUNK" ] && CHUNK="$REMAINING"
        sleep "$CHUNK"
    done
    log "INFO" "smart_sleep terminé (intervalle=${SLEEP_SECS}s)"
}

# ================================================================
# WIFI WATCHDOG — détecte la boucle WPS de wifid et force la connexion PSK
# Polling toutes les 60s (pas 5s) : 5s = 12 révéils CPU/min en permanence
# sur un K4 à contrainte batterie, c'est inacceptable.
# Le watchdog n'intervient que si wifid est actif ET que le délai depuis
# le dernier inject est suffisant (évite de casser une connexion en cours).
# ================================================================
wifi_watchdog() {
    WIFI_SSID="NoTrespassing"
    WIFI_PSK="9dc6b9e281f746e118d0def9c328456ae4da79a94e97875b9703ee38a6540809"
    LAST_INJECT=0
    while true; do
        sleep 60
        # Ne pas intervenir si update_frame.sh gère déjà le WiFi
        [ -f /tmp/wifi_busy ] && continue
        # Uniquement si wifid est actif
        WIFID_EN=$(lipc-get-prop -i com.lab126.wifid enable 2>/dev/null || echo "0")
        [ "$WIFID_EN" != "1" ] && continue
        # wifid actif → vérifier état wpa_supplicant
        WS=$(wpa_cli -i wlan0 status 2>/dev/null | grep wpa_state= | cut -d= -f2)
        # Connecté → vérifier que l'IP est bien assignée (wifid ne lance pas DHCP pour
        # les réseaux injectés dynamiquement, seulement pour ceux dans wifid.conf)
        if [ "$WS" = "COMPLETED" ]; then
            IP=$(ifconfig wlan0 2>/dev/null | grep 'inet addr' | cut -d: -f2 | cut -d' ' -f1)
            if [ -z "$IP" ] || [ "$IP" = "127.0.0.1" ]; then
                log "INFO" "[watchdog] COMPLETED sans IP → lancement DHCP"
                udhcpc -i wlan0 -n -q -t 5 2>/dev/null || true
            fi
            continue
        fi
        # Délai de 60s après chaque inject : laisser le temps à la connexion PSK
        # (SCAN → ASSOC → AUTH → 4WAY → DHCP peut prendre jusqu'à 30s)
        NOW=$(date +%s 2>/dev/null || echo "0")
        ELAPSED=$((NOW - LAST_INJECT))
        [ "$ELAPSED" -lt 60 ] && continue
        # wifid actif, pas COMPLETED, délai écoulé → inject PSK
        log "INFO" "[watchdog] wifid actif (wpa=$WS) → inject PSK"
        LAST_INJECT=$NOW
        touch /tmp/wifi_busy
        # Annuler WPS si en cours
        wpa_cli -i wlan0 wps_cancel 2>/dev/null || true
        # Nettoyer les anciens réseaux injectés (garder seulement le réseau 0)
        NL=$(wpa_cli -i wlan0 list_networks 2>/dev/null | tail -n +2 | cut -f1)
        for OLD_NID in $NL; do
            [ "$OLD_NID" = "0" ] || wpa_cli -i wlan0 remove_network "$OLD_NID" 2>/dev/null || true
        done
        # Injecter le réseau PSK
        NID=$(wpa_cli -i wlan0 add_network 2>/dev/null)
        if [ -n "$NID" ] && [ "$NID" != "FAIL" ]; then
            wpa_cli -i wlan0 set_network "$NID" ssid "\"$WIFI_SSID\""
            wpa_cli -i wlan0 set_network "$NID" psk $WIFI_PSK
            wpa_cli -i wlan0 set_network "$NID" key_mgmt WPA-PSK
            wpa_cli -i wlan0 set_network "$NID" priority 100
            wpa_cli -i wlan0 enable_network "$NID"
            wpa_cli -i wlan0 select_network "$NID"
        fi
        rm -f /tmp/wifi_busy
    done
}

# ================================================================
# AUTO-START USBNETWORK — SSH permanent sans intervention manuelle
# Appelé une fois au démarrage du scheduler.
# Avec K3_WIFI_SSHD_ONLY=false : crée l'interface USB ethernet (RNDIS)
# + démarre le daemon SSH. Compatible K4 via volumd.
# ================================================================
start_usbnetwork() {
    USBNET_SCRIPT="/mnt/us/usbnet/bin/usbnetwork"
    USBNET_SSHD_PID="/mnt/us/usbnet/run/sshd.pid"
    USBNET_DROPBEAR_PID="/mnt/us/usbnet/run/dropbear.pid"
    KINDLE_USB_IP="192.168.15.244"

    # Toujours vérifier que usb0 a bien une IP, qu'importe l'état de sshd
    USB_IP=$(ifconfig usb0 2>/dev/null | grep 'inet addr' | cut -d: -f2 | cut -d' ' -f1)
    if [ -z "$USB_IP" ] || [ "$USB_IP" = "127.0.0.1" ]; then
        log "WARN" "usb0 sans IP — config manuelle $KINDLE_USB_IP"
        ifconfig usb0 "$KINDLE_USB_IP" netmask 255.255.255.0 up 2>/dev/null || true
    fi

    # Vérifier si sshd/dropbear est actif et vivant
    for PF in "$USBNET_SSHD_PID" "$USBNET_DROPBEAR_PID"; do
        if [ -f "$PF" ]; then
            PID=$(cat "$PF" 2>/dev/null)
            if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
                log "INFO" "USBNetwork déjà actif (pid=$PID)"
                return 0
            else
                log "WARN" "USBNetwork PID $PID mort — relance"
                rm -f "$PF"
            fi
        fi
    done
    if [ -x "$USBNET_SCRIPT" ]; then
        log "INFO" "Démarrage USBNetwork (SSH USB automatique)"
        sh "$USBNET_SCRIPT" >> "$LOG_FILE" 2>&1 &
        sleep 5
        USB_IP2=$(ifconfig usb0 2>/dev/null | grep 'inet addr' | cut -d: -f2 | cut -d' ' -f1)
        if [ -z "$USB_IP2" ] || [ "$USB_IP2" = "127.0.0.1" ]; then
            log "WARN" "usb0 sans IP après usbnetwork — config manuelle $KINDLE_USB_IP"
            ifconfig usb0 "$KINDLE_USB_IP" netmask 255.255.255.0 up 2>/dev/null || true
        fi
    else
        log "WARN" "USBNetwork non trouvé ($USBNET_SCRIPT) — skip"
    fi
}

# ================================================================
# PROGRAMME PRINCIPAL — boucle de cycles
# ================================================================
log "INFO" "============================================"
log "INFO" "Scheduler démarré | pid=$$"

# Optimisations CPU dès le départ
set_powersave

# SSH USB auto-start (permet accès SSH même sans WiFi)
start_usbnetwork

# Watchdog WiFi — connexion PSK automatique si wifid coincé en boucle WPS
wifi_watchdog &
WATCHDOG_PID=$!
log "INFO" "WiFi watchdog démarré (pid=$WATCHDOG_PID)"

CYCLE_COUNT=0

while true; do
    INTERVAL=$(get_interval)
    BATT=$(get_battery)
    HOUR=$(date +%H | awk '{print int($1)}')

    # --- Si dashboard désactivé : ne rien faire du tout ---
    # La liseuse doit rester utilisable normalement par le lecteur.
    # On lève preventSuspend pour permettre la veille profonde normale.
    if [ -f "$FLAG_FILE" ]; then
        log "INFO" "Dashboard OFF | batt=${BATT}% → attente ${POLL_SEC}s"
        lipc-set-prop com.lab126.powerd preventScreenSaver 0 2>/dev/null || true
        lipc-set-prop com.lab126.powerd preventSuspend 0 2>/dev/null || true
        sleep "$POLL_SEC"
        continue
    fi

    # --- Dashboard actif : mise à jour ---
    log "INFO" "--- Cycle heure=${HOUR}h | intervalle=${INTERVAL}s (~$((INTERVAL/60))min) | batt=${BATT}% ---"

    if [ -x "$UPDATE_SCRIPT" ]; then
        UPDATE_ARGS=""
        [ "$NO_WIFI" = "1" ] && UPDATE_ARGS="--no-wifi"
        log "INFO" "Lancement update_frame.sh $UPDATE_ARGS"
        # Timeout de 3 minutes pour éviter un blocage réseau infini.
        # sleep 15 dans la boucle de monitoring (pas 5) : inutile de poll plus vite,
        # update_frame.sh a son propre rythme de retry sur IP.
        sh "$UPDATE_SCRIPT" $UPDATE_ARGS &
        UPDATE_PID=$!
        TIMEOUT=180
        ELAPSED=0
        while kill -0 "$UPDATE_PID" 2>/dev/null && [ $ELAPSED -lt $TIMEOUT ]; do
            sleep 15
            ELAPSED=$((ELAPSED + 15))
        done
        if kill -0 "$UPDATE_PID" 2>/dev/null; then
            log "WARN" "update_frame.sh bloqué après ${TIMEOUT}s → kill forcé"
            kill -9 "$UPDATE_PID" 2>/dev/null
            # kill -9 bypasse le trap cleanup → wifi_busy pourrait rester bloqué indéfiniment
            rm -f /tmp/wifi_busy 2>/dev/null || true
            UPDATE_EXIT=124
        else
            wait "$UPDATE_PID" 2>/dev/null
            UPDATE_EXIT=$?
        fi
        if [ "$UPDATE_EXIT" -ne 0 ]; then
            log "WARN" "update_frame.sh exit=$UPDATE_EXIT"
        else
            log "INFO" "Update OK"
        fi
    else
        log "ERROR" "Script update introuvable : $UPDATE_SCRIPT"
    fi

    # Maintenir l'affichage e-ink pendant le sleep (LinkSS ignoré, image conservée)
    keep_eink_display

    # Vérifier USB tous les 10 cycles seulement — pas besoin de poll à chaque cycle
    CYCLE_COUNT=$((CYCLE_COUNT + 1))
    if [ $((CYCLE_COUNT % 10)) -eq 0 ]; then
        start_usbnetwork
    fi

    log "INFO" "Pause ${INTERVAL}s..."
    smart_sleep "$INTERVAL"
done
