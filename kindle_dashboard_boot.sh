#!/bin/sh
# kindle_dashboard_boot.sh — Script d'installation de l'auto-start au boot
# À exécuter UNE FOIS en SSH sur le Kindle avec : sh /tmp/kindle_dashboard_boot.sh
#
# Ce script :
#   1. Monte le système de fichiers root en lecture-écriture (mntroot rw)
#   2. Crée /etc/init.d/dashboard avec le lancement des daemons
#   3. Crée le symlink S99dashboard dans /etc/rcS.d/
#   4. Remet le root en lecture seule (mntroot ro)
#   5. Vérifie l'installation

set -e

echo "=== Installation auto-start dashboard au boot ==="

# 1. Root en lecture-écriture
echo "--- mntroot rw ---"
mntroot rw
sleep 1

# 2. Créer le script init.d
echo "--- Création /etc/init.d/dashboard ---"
cat > /etc/init.d/dashboard << 'INITEOF'
#!/bin/sh
# /etc/init.d/dashboard — Lancement des daemons Kindle Dashboard HA
# Kindle 4 / BusyBox

case "$1" in
    start)
        echo "Starting Kindle Dashboard daemons..."
        # Tuer les instances orphelines si elles existent
        ps -ef | grep -e 'kindle_scheduler' -e 'toggle_dashboard' | grep -v grep \
            | awk '{print $2}' | while read pid; do kill -9 "$pid" 2>/dev/null; done
        sleep 1
        # Lancer le scheduler en arrière-plan
        ( sh /mnt/us/kindle_scheduler.sh >> /tmp/scheduler.log 2>&1 & )
        # Lancer le toggle du bouton Home
        ( sh /mnt/us/toggle_dashboard.sh > /dev/null 2>&1 & )
        echo "Dashboard daemons started."
        ;;
    stop)
        echo "Stopping Kindle Dashboard daemons..."
        ps -ef | grep -e 'kindle_scheduler' -e 'toggle_dashboard' | grep -v grep \
            | awk '{print $2}' | while read pid; do kill -9 "$pid" 2>/dev/null; done
        echo "Dashboard daemons stopped."
        ;;
    restart)
        $0 stop
        sleep 2
        $0 start
        ;;
    *)
        echo "Usage: $0 {start|stop|restart}"
        exit 1
        ;;
esac

exit 0
INITEOF

chmod +x /etc/init.d/dashboard

# 3. Créer le symlink S99dashboard dans rcS.d
echo "--- Symlink S99dashboard ---"
ln -sf /etc/init.d/dashboard /etc/rcS.d/S99dashboard
echo "Symlink créé : /etc/rcS.d/S99dashboard -> /etc/init.d/dashboard"

# 4. Root en lecture seule
echo "--- mntroot ro ---"
mntroot ro

# 5. Vérification
echo "=== Vérification ==="
ls -la /etc/init.d/dashboard
ls -la /etc/rcS.d/S99dashboard
echo ""
echo "=== Installation terminée ! ==="
echo "Au prochain reboot, les daemons démarreront automatiquement."
echo "Test manuel : sh /etc/init.d/dashboard start"
