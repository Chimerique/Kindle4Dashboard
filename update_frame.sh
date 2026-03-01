#!/bin/sh
# Script de mise à jour du cadre photo Kindle 4
# Version améliorée : options, logging, functions, trap

# Defaults (modifiable via options ou variables d'environnement)
UPDATE_URL="${UPDATE_URL:-http://192.168.0.2:8080/cover.png}"
WIFI_IF="${WIFI_IF:-wlan0}"
LOG_FILE="${LOG_FILE:-/mnt/us/frame_update.log}"
FLAG_DISABLED="${FLAG_DISABLED:-/mnt/us/DASHBOARD_DISABLED}"
TMP_IMAGE="${TMP_IMAGE:-/tmp/frame.png}"
SAVE_PATH="${SAVE_PATH:-/mnt/us/linkss/screensavers/ha_dashboard.png}"
RETRIES="${RETRIES:-12}"
SLEEP_SEC="${SLEEP_SEC:-5}"
GATEWAY_FALLBACK="${GATEWAY_FALLBACK:-192.168.0.1}"
NO_WIFI=0

WIFI_ENABLED_BY_SCRIPT=0

log() {
    level="$1"; shift
    echo "$(date +"%Y-%m-%d %H:%M:%S") - $level - $*" >> "$LOG_FILE"
}

usage() {
    cat <<EOF
Usage: $0 [--url URL] [--interface IF] [--log FILE] [--retries N] [--sleep S] [--no-wifi]
  --url       URL to download the image (default: $UPDATE_URL)
  --interface Wi-Fi interface (default: $WIFI_IF)
  --log       Log file (default: $LOG_FILE)
  --retries   Number of IP retries (default: $RETRIES)
  --sleep     Seconds between retries (default: $SLEEP_SEC)
  --no-wifi   Do not enable/disable Wi-Fi (assume network already up)
  -h, --help  Show this help
EOF
}

# Load .env if present (variables exported, CLI args will override)
if [ -f .env ]; then
    set -o allexport
    . .env
    set +o allexport
fi

# Simple long-options parsing
while [ $# -gt 0 ]; do
    case "$1" in
        --url)
            UPDATE_URL="$2"; shift 2;;
        --interface)
            WIFI_IF="$2"; shift 2;;
        --log)
            LOG_FILE="$2"; shift 2;;
        --retries)
            RETRIES="$2"; shift 2;;
        --sleep)
            SLEEP_SEC="$2"; shift 2;;
        --no-wifi)
            NO_WIFI=1; shift;;
        -h|--help)
            usage; exit 0;;
        *)
            echo "Unknown option: $1"; usage; exit 2;;
    esac
done

log "INFO" "=== Début de mise à jour ==="

cleanup() {
    lipc-set-prop com.lab126.powerd preventScreenSaver 0 2>/dev/null || true
    if [ "$WIFI_ENABLED_BY_SCRIPT" -eq 1 ] && [ "$NO_WIFI" -eq 0 ]; then
        lipc-set-prop com.lab126.wifid enable 0 2>/dev/null || true
        lipc-set-prop com.lab126.cmd wirelessEnable 0 2>/dev/null || true
        log "INFO" "Wi‑Fi éteint par cleanup"
    fi
    log "INFO" "=== Fin de mise à jour ==="
}

trap 'cleanup' EXIT INT TERM

if [ -f "$FLAG_DISABLED" ]; then
    log "INFO" "Dashboard désactivé (skip)"
    lipc-set-prop com.lab126.powerd preventScreenSaver 0 || true
    exit 0
fi

lipc-set-prop com.lab126.powerd preventScreenSaver 1 || true

enable_wifi() {
    if [ "$NO_WIFI" -eq 1 ]; then
        log "INFO" "--no-wifi set, skip enabling Wi‑Fi"
        return 0
    fi
    log "INFO" "Activation du Wi‑Fi"
    lipc-set-prop com.lab126.cmd wirelessEnable 1 || true
    lipc-set-prop com.lab126.wifid enable 1 || true
    lipc-set-prop com.lab126.framework dismissDialog 1 || true
    WIFI_ENABLED_BY_SCRIPT=1
}

wait_for_ip() {
    log "INFO" "Attente d'une adresse IP valide... (interface $WIFI_IF)"
    i=0
    while [ $i -lt "$RETRIES" ]; do
        IP=$(ifconfig "$WIFI_IF" 2>/dev/null | grep 'inet addr' | cut -d: -f2 | cut -d' ' -f1)
        if [ -n "$IP" ] && [ "$IP" != "127.0.0.1" ]; then
            log "INFO" "Connecté ! IP: $IP (après $(( (i+1) * SLEEP_SEC ))s)"
            return 0
        fi
        i=$((i+1))
        log "INFO" "Pas encore d'IP (tentative $i/$RETRIES)"
        sleep "$SLEEP_SEC"
    done
    return 1
}

ensure_gateway() {
    GATEWAY=$(ip route 2>/dev/null | grep default | awk '{print $3}')
    if [ -z "$GATEWAY" ]; then
        if [ -n "$GATEWAY_FALLBACK" ]; then
            log "WARN" "Aucune gateway, ajout de fallback $GATEWAY_FALLBACK"
            route add default gw "$GATEWAY_FALLBACK" 2>/dev/null || true
        else
            log "WARN" "Aucune gateway détectée et aucun fallback configuré"
        fi
    fi
}

download_image() {
    log "INFO" "Téléchargement de l'image depuis $UPDATE_URL"
    rm -f "$TMP_IMAGE" 2>/dev/null || true
    wget -q -O "$TMP_IMAGE" "$UPDATE_URL" >>"$LOG_FILE" 2>&1
    if [ -s "$TMP_IMAGE" ]; then
        log "INFO" "Image téléchargée: $TMP_IMAGE"
        return 0
    fi
    log "ERROR" "Image vide ou échec du téléchargement"
    return 1
}

show_image() {
    log "INFO" "Affichage de l'image"
    /usr/sbin/eips -c || true
    sleep 1
    /usr/sbin/eips -g "$TMP_IMAGE" || true
    cp "$TMP_IMAGE" "$SAVE_PATH" 2>/dev/null || log "WARN" "Impossible de sauvegarder $SAVE_PATH"
    log "INFO" "Affichage initial terminé"
}

enable_wifi

if wait_for_ip; then
    sleep 10
    ensure_gateway
    if download_image; then
        show_image
    fi
else
    log "ERROR" "Pas d'IP après $RETRIES tentatives"
fi

# If we reach here, cleanup trap will run
