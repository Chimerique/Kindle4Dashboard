# Kindle Dashboard HA

## Description
Kindle Dashboard HA transforme une Kindle 4 en un écran d'affichage dynamique pour Home Assistant. Il utilise l'économiseur d'écran pour afficher une image générée par Home Assistant, tout en optimisant la consommation d'énergie grâce à des cycles de mise à jour planifiés et une gestion intelligente du WiFi.

## Fonctionnalités
- **Affichage dynamique** : Affiche une image générée par Home Assistant en tant qu'économiseur d'écran.
- **Scheduler dynamique** : Planifie les mises à jour selon des intervalles spécifiques à l'heure de la journée.
- **Économie d'énergie** : Désactive le WiFi entre les cycles et active la veille naturelle après chaque mise à jour.
- **Toggle bouton Home** : Active/désactive le dashboard avec 3-4 clics rapides.
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

## Installation
1. **Cloner le dépôt** :
   ```sh
   git clone https://github.com/Chimerique/Kindle4Dashboard.git
   ```
2. **Configurer les scripts** :
   - Modifier les variables dans `.env` si nécessaire.
3. **Déployer sur Kindle** :
   - Copier les scripts via `scp`.
   - Exécuter `kindle_dashboard_boot.sh` pour installer l'auto-start.

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

## Licence
Ce projet est sous licence MIT. Voir le fichier [LICENSE](LICENSE) pour plus d'informations.