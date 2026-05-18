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

## Retour d'expérience
- Les incidents de veille profonde, de USBNetwork et de reconnectivité WiFi sont documentés dans [docs/REX-2026-05-14.md](docs/REX-2026-05-14.md).
- Le scheduler utilise maintenant une stratégie de sommeil robuste pour éviter les blocages lors des longues attentes.
- Le dashboard garde l'écran actif en combinant la prévention de l'économiseur et de la suspension pendant l'affichage.

## Licence
Ce projet est sous licence MIT. Voir le fichier [LICENSE](LICENSE) pour plus d'informations.

## Décision : Désactivation de LinkSS pour le Dashboard

### Problème rencontré
LinkSS, utilisé pour gérer les économiseurs d'écran personnalisés, provoquait des conflits avec l'affichage dynamique du dashboard. Lorsque la Kindle entrait en veille, LinkSS reprenait la main et affichait une ancienne image mise en cache, écrasant l'image actuelle affichée par `eips`.

### Solution adoptée
- **Anti-doublons (CRITIQUE) :** `update_frame.sh` et `toggle_dashboard.sh` intègrent un mécanisme d'auto-nettoyage. Au lancement, chaque script identifie et tue les anciennes instances orphelines. C'est **indispensable** pour éviter les conflits d'affichage, les blocages réseau et les fuites de processus qui finissent par suspendre le scheduler.
- **Maintien de `preventScreenSaver=1` :** Cela empêche LinkSS de s'activer, tout en permettant à l'écran e-ink de conserver l'image affichée par `eips` sans consommation d'énergie supplémentaire.
- **Suppression de `framework restart` :** Cette commande redémarrait LinkSS et réinitialisait son cache, causant des comportements imprévisibles.

### Pourquoi ne pas utiliser LinkSS ?
L'écran e-ink est bistable, ce qui signifie qu'il peut conserver une image sans consommer d'énergie. En maintenant `preventScreenSaver=1`, nous évitons les interférences de LinkSS tout en profitant de cette propriété unique de l'écran.

### Conséquences
- **Dashboard activé :** L'image affichée par `eips` reste visible en permanence, même après plusieurs cycles de veille.
- **Dashboard désactivé :** `preventScreenSaver=0` est rétabli, et la Kindle retrouve son comportement normal avec LinkSS actif.

### Notes importantes
- Le fichier `/mnt/us/KEEP_WIFI` permet de forcer le maintien du WiFi entre les cycles (très utile pour la maintenance SSH).
- Le fichier `/mnt/us/DASHBOARD_DISABLED` dans `/mnt/us/` désactive le dashboard.
- Cette configuration est optimale pour un usage dédié au dashboard. Si LinkSS est nécessaire pour d'autres fonctionnalités (ex. affichage de couvertures de livres), des ajustements seront nécessaires.
- Le CPU entre toujours en veille légère (light sleep) entre les cycles, garantissant une consommation minimale de la batterie.