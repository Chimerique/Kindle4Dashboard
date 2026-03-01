🖼️ Prompt pour Claude : Création du Cadre Photo Autonome
Contexte de sécurité critique :
L'utilisateur est connecté en SSH via Wi-Fi sur une Kindle 4. Son ip est 192.168.0.197 et on a un id_rsa qui a été généré disponible sur cette machine ou tu tournes (windows 11)
ATTENTION : Toute commande désactivant le Wi-Fi (wirelessEnable 0) coupera immédiatement la session SSH en cours. Le script doit donc être conçu, testé et planifié de manière à ce qu'il puisse gérer le cycle Wi-Fi de façon 100% autonome.

Objectifs :

Créer un script shell /mnt/us/update_frame.sh sur la partition utilisateur.

Le script doit suivre cet algorithme :

Allumer le Wi-Fi : lipc-set-prop com.lab126.cmd wirelessEnable 1.

Attendre la connexion (prévoir une boucle de test ping ou un sleep généreux de 30s).

Télécharger l'image : wget http://192.168.0.2:5000/ -O /tmp/frame.png.

Afficher l'image : eips -g /tmp/frame.png.

Éteindre le Wi-Fi : lipc-set-prop com.lab126.cmd wirelessEnable 0.

Planning Horaire (Cron) :

00h-06h : 1/30 min | 06h-08h : 1/5 min | 08h-17h : 1/15 min | 17h-20h : 1/5 min | 20h-00h : 1/15 min.

Méthode de travail imposée :

Étape 1 : Propose d'abord une version du script qui NE COUPE PAS le Wi-Fi à la fin. Cela permettra à l'utilisateur de vérifier que le téléchargement et l'affichage fonctionnent sans perdre sa main en SSH.

Étape 2 : Une fois le test réussi, propose d'ajouter la commande d'extinction du Wi-Fi.

Étape 3 : Mise en place du Cron. Attention : sur Kindle 4, le système de fichiers est en Lecture Seule par défaut. Rappeler d'utiliser mntroot rw.

Point de contrôle : À chaque étape, demande : "L'image s'est-elle affichée et as-tu gardé ta connexion SSH ? [Oui / Non]". => Sur ce point, il s'agit d'un formulaire interactif que tu dois me faire, il faut que je clic sur un bouton pour te dire ce qu'il en est et pas que je taper au clavier oui ou non et qu'il s'agisse d'un nouveau prompt
-----
Jamais faire de /etc/init.d/framework stop, il faut toujours que je puisse reprendre la main sur l'interface
----
Apres analyse l'usage le plus interessant qu'on puisse faire avec la tablette est d'utiliser le mode screen saver comme sytem de rendu. Avec un forcage du refresh des images comme je l'ai précisé plus haut. Idéalement ce forcage doit s'arréter si on utilise la liseuse normalement (framework kindle).
Si le screen saver se remet en route, il faut reprendre le processus de dashboard maj automatiquement. Et tout ca s'arrete au moment ou on sort de ce mode screensaver
----
Complément d'information sur l'infra : 
- Kindle 192.168.0.197
- Container hass-lovelace-kindle-screensaver qui expose une image qu'il faut affiche : 192.168.0.2:5000
- HomeAssistant sur une VM avec autre IP (mais on s'en moque, toi tu dois récupérer l'image de hass-lovelace-kindle-screensaver)
- Ton poste sur lequel tu execute tes commandes : machine developpeur autre, pas d'interaction dans notre archi cible
----
Tu ne dois absoluement pas faire de proxy avec cette machine, ce n'est pas l'infra que je veux, tu dois absolument faire fonctionner avec le service cible ,
--
Egalement j'ai régulierement la bar kindle du haut en superposition, comment ca se fait ? 