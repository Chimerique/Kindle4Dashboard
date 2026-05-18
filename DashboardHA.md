# Documentation Kindle Dashboard HA

## Fonctionnalités principales
- **Affichage dynamique** : Le dashboard affiche une image générée par Home Assistant en tant qu'économiseur d'écran.
- **Scheduler dynamique** : Les mises à jour sont planifiées selon des intervalles spécifiques à l'heure de la journée.
- **Économie d'énergie** : Le WiFi est désactivé entre les cycles, et la veille naturelle est activée après chaque mise à jour.
- **Toggle bouton Home** : Permet d'activer/désactiver le dashboard avec 3-4 clics rapides.
- **Auto-start au boot** : Les daemons démarrent automatiquement après un redémarrage.

## Architecture
1. **kindle_scheduler.sh** :
   - Orchestrateur principal qui gère les cycles de mise à jour.
   - Appelle `update_frame.sh` pour télécharger et afficher l'image.
   - Gère les intervalles dynamiques selon l'heure.

2. **update_frame.sh** :
   - Télécharge l'image depuis Home Assistant.
   - Copie l'image dans `/mnt/us/linkss/screensavers/`.
   - Active le screensaver pour afficher l'image immédiatement.

3. **toggle_dashboard.sh** :
   - Écoute les événements du bouton Home.
   - Active/désactive le dashboard en créant/supprimant un flag.

4. **kindle_dashboard_boot.sh** :
   - Installe un script dans `/etc/init.d/` pour démarrer les daemons au boot.

## Intervalles de mise à jour
| Heure       | Intervalle |
|-------------|------------|
| 00h-06h     | 30 min     |
| 06h-08h     | 5 min      |
| 08h-17h     | 15 min     |
| 17h-20h     | 5 min      |
| 20h-00h     | 15 min     |

## Commandes utiles
- **Activer manuellement les daemons** :
  ```sh
  sh /etc/init.d/dashboard start
  ```
- **Désactiver les daemons** :
  ```sh
  sh /etc/init.d/dashboard stop
  ```
- **Redémarrer les daemons** :
  ```sh
  sh /etc/init.d/dashboard restart
  ```

## Dépendances
- Kindle 4 avec BusyBox Linux.
- Hack LinkSS pour gérer les screensavers personnalisés.
- Home Assistant pour générer l'image du dashboard.

## Notes
- Le fichier `DASHBOARD_DISABLED` dans `/mnt/us/` désactive le dashboard.
- Le scheduler vérifie la batterie et ajuste les cycles en conséquence.
- Le WiFi est activé uniquement pendant les mises à jour.

## Retour d'expérience opérationnel
- Pour éviter les suspensions longues qui figent le scheduler, le script principal utilise un sommeil par paliers avec vérification du temps écoulé.
- L'affichage du dashboard doit maintenir `preventScreenSaver=1` et `preventSuspend=1` pendant les cycles actifs.
- USBNetwork peut être relancé automatiquement au boot pour conserver un accès SSH de secours sur `192.168.15.244`.
- En cas de blocage WiFi, vérifier la présence d'un réseau valide dans `/etc/wpa_supplicant.conf` et le réglage `ap_scan=1`.