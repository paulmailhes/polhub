# Ce qui a changé

Chaque version publiée a sa section ; `scripts/release.sh` la reprend pour la page de la version sur
GitHub, et l'app la montre dans Réglages › Mises à jour.

## 0.12.0 — 14 novembre 2026

**Mails : lire.** Tes trois boîtes Gmail dans Polhub.

- **La section « Mails »**, entre Calendrier et Contacts : une seule liste pour tes boîtes, chaque ligne avec la
  pastille de couleur de sa boîte. Les pastilles en haut à droite affichent ou masquent une boîte. Le nombre à
  côté de « Mails » compte les fils non lus de l'onglet Principale.
- **Deux onglets** : « Principale » (les personnes) et « Automatiques » (ce que Gmail classe en notifications,
  promotions et réseaux sociaux). Clic droit › « Déplacer vers Principale » : Polhub le retient pour cet
  expéditeur.
- **Un clic ouvre le fil à la place de la liste.** Le mail s'affiche en HTML comme son expéditeur l'a écrit, à sa
  largeur, sur fond blanc ; les messages lus sont repliés, le texte cité est derrière « ••• ».
- **Archiver, supprimer, lu et non lu** : l'écran change tout de suite, Gmail suit en quelques secondes.
  « Annuler » reste quelques secondes (ou ⌘Z). Supprimer met à la corbeille de Gmail. Un geste ne touche que les
  messages que tu voyais : une réponse arrivée entre-temps reste en boîte de réception.
- **Recherche** : ton texte part à Gmail tel quel, avec ses opérateurs (`from:`, `has:attachment`…).
- **Pièces jointes** : aperçu pour les images, PDF et documents ; le reste s'enregistre seulement. macOS les
  marque comme venant d'un mail.
- **Images distantes** : affichées seules pour les expéditeurs que tu connais (tes contacts, les personnes à qui
  tu as écrit) quand Gmail confirme que le mail vient bien d'eux ; pour les autres, « Afficher les images » et
  « Toujours pour cet expéditeur ». Réglage dans Réglages › Mails.
- **Sécurité de l'affichage** : les scripts du mail sont coupés, rien d'autre que les images permises ne se
  charge (vérifié sur un mail piégé), aucun cookie n'est gardé, le mode Isolement de macOS est actif sur
  l'affichage, et l'info-bulle d'un lien montre sa vraie adresse, avec un avertissement si le texte en affiche
  une autre.
- **Copie locale** : tous tes mails sont copiés sur le Mac, du plus récent au plus ancien, en arrière-plan ; une
  ligne sous la liste dit où en est la lecture. Ensuite Polhub demande à Gmail « quoi de neuf » toutes les
  30 secondes quand il est devant, chaque minute sinon. « Déconnecter » un compte efface sa copie.
- **Répondre** : pas encore. « Répondre dans Gmail » et « Ouvrir dans Gmail » ouvrent le fil sous le bon compte ;
  l'écriture est la prochaine étape.
- La section « Mesures avant les mails » a quitté Réglages › Comptes Google.

## 0.11.1 — 14 novembre 2026

Première marche des **mails** dans Polhub : autoriser et mesurer. Rien ne s'affiche encore de tes mails.

- **Réglages › Comptes Google** : tes comptes ont maintenant leur propre famille (ils quittent Réglages ›
  Calendrier), avec leur couleur, l'état de leur agenda et celui de leurs mails.
- **« Autoriser les mails »**, compte par compte : le bouton ouvre la page de Google. L'agenda du compte reste
  connecté quoi que tu répondes : une réponse sans l'agenda est jetée, l'ancienne connexion est gardée. Si
  l'administrateur d'un compte bloque Polhub, le message dit ce qu'il doit approuver.
- **Mesures avant les mails**, dans la même page : combien de messages sur six mois, combien de fils en boîte
  de réception, le débit de lecture sans dépasser le quota de Google, les formats et les en-têtes d'un
  échantillon. Le rapport ne garde que des nombres : aucun objet, aucun texte, aucune adresse de
  correspondant. Deux essais courts : ouvrir un fil dans Gmail, et mettre à la corbeille puis rétablir un mail
  d'essai que tu t'es envoyé (objet « Polhub essai »).
- `scripts/configurer-google.command` : quand la clé est déjà en place, il ouvre les deux pages de la console
  qui ouvrent Gmail à Polhub.
- Sous le capot : le code Google commun au calendrier et aux mails a son module, et ce que chaque compte a
  autorisé est gardé d'un lancement à l'autre. La version de développement n'écrit jamais dans une vraie
  boîte.

## 0.11.0 — 14 novembre 2026

- **Notifications**, réglables dans Réglages › Notifications :
  - **Rappels avant un rendez-vous** : 10 min et 1 min avant par défaut (30, 15, 10, 5 ou 1 min au choix),
    éventuellement seulement pour ceux avec une visio. Ils sont confiés à macOS une semaine à l'avance : ils
    arrivent même si Polhub est fermé. Un clic, ou « Rejoindre », ouvre le Meet avec le bon compte dans Dia,
    où la réunion s'enregistre. Un changement (lien Meet ajouté, titre, son) suit dans les rappels prévus.
  - **Nouveau rendez-vous** dans tes agendas : pas ceux que tu crées depuis Polhub, pas à la connexion
    d'un compte, pas les occurrences d'une série qui entrent dans les 60 jours lus. Un clic ouvre sa fiche ;
    « Rejoindre » rejoint.
  - **Réunion commencée sans enregistrement** : cinq minutes après le début d'un rendez-vous avec Meet, si
    rien n'enregistre, une alerte pour le rejoindre ; jamais pour une réunion déjà enregistrée, refusée au
    pop-up ou marquée « jamais », ni pendant une pause de la détection.
  - **Compte rendu prêt** ; un clic ouvre la réunion.
  - Le son, et un bouton pour envoyer un essai.
- **Réglages › Général** : « Ouvrir Polhub à l'ouverture de session » (c'était déjà le cas ; c'est
  maintenant visible et réglable, jamais pendant une réunion).
- Un seul déclencheur d'enregistrement, la détection des onglets de Dia : les notifications ne font
  qu'ouvrir le Meet, rien ne peut lancer deux enregistrements.
- **Calendrier** : la légende des comptes disparaît du haut de la grille (ils se règlent dans Réglages ›
  Calendrier) ; la grille s'ouvre bien à l'heure choisie dans les réglages.

## 0.10.2 — 14 novembre 2026

- **L'icône, en noir** : les trois colonnes noires en verre, sans plaque blanche, faites avec le format
  d'Icon Composer, l'outil d'Apple pour les icônes Liquid Glass.
- **Le Dock affiche enfin l'icône.** macOS range l'image de l'icône selon la date du dossier de l'app, que les
  mises à jour laissaient au 13 novembre (avant l'icône) : la version publiée porte maintenant sa date, la
  mise à jour la rafraîchit, et l'app la répare d'elle-même au lancement.
- **La barre des menus** montre, au repos, les trois colonnes en simple tracé ; enregistrement, pause et
  alerte gardent leurs symboles.

## 0.10.1 — 14 novembre 2026

- **Nouvelle icône : les Colonnes, en Liquid Glass**. Des plaques de verre posées sur trois colonnes sombres,
  sur fond beige ; macOS en fait une version sombre, teintée et transparente selon tes réglages.
- **L'icône s'affiche enfin dans le Dock**, et nette partout. macOS avait gardé en mémoire l'app d'avant,
  sans icône : Polhub se réenregistre maintenant à chaque lancement et à chaque mise à jour.

## 0.10.0 — 14 novembre 2026

- **Une icône** : des ondes sur fond beige, dans le style de tes icônes Polflix et Nextcloud, faite en
  calques pour Liquid Glass (sombre en mode sombre, teintée ou transparente selon tes réglages macOS).
- **Réglages refaits** comme ceux d'Apple : la liste des familles, puis une page par famille.
  - **Calendrier** : tes comptes Google et leur couleur, ajouter ou déconnecter un compte ; l'agenda, la
    durée et la visio par défaut des nouveaux rendez-vous ; afficher ou non le week-end, l'heure à laquelle
    la grille s'ouvre.
  - **Projets** : la taille des cartes du Kanban (petites, moyennes, grandes). Elles sont moyennes par
    défaut, plus compactes qu'avant.
  - **Réunions** : comptes rendus automatiques oui ou non, langue des transcriptions.
  - Mises à jour, Diagnostic et Journal, comme avant.
- **Réglages passe en bas de la barre latérale**, à part du travail.
- Le Calendrier garde la légende des couleurs ; son bouton ouvre Réglages › Calendrier. « Autoriser la
  modification » disparaît : tes comptes sont autorisés.

## 0.9.1 — 14 novembre 2026

Corrections de deux relectures complètes, pour que rien ne se perde :

- **Comptes rendus** : une réunion qui avait déjà un compte rendu (celui d'Obsidian, repris à l'import de
  l'historique) le garde ; « Refaire le compte rendu » reste possible. Un compte rendu refait garde les
  actions cochées ou ajoutées au projet, sans doublon. Une réunion ou une transcription qui commence
  l'interrompt sans jamais compter un échec ; les longues réunions ont aussi le leur ; plus d'échéances
  vides (« à venir », « vide »).
- **Calendrier** : une modification n'envoie à Google que ce que tu as changé (la description et les
  invités ne sont plus réécrits, les invités facultatifs le restent) et attend d'avoir lu le rendez-vous ;
  une synchronisation en cours ne défait plus ce que tu viens d'écrire ; passer de « toute la journée » à
  une heure propose 9 h–10 h ; un rendez-vous de plusieurs jours n'ouvre qu'une fiche ; une série est
  signalée (seul le rendez-vous choisi change).
- Toutes les copies d'un rendez-vous prennent le projet de sa réunion, et une copie ne prend plus la
  réunion suivante.
- Accueil › Priorité 1 ouvre le projet cliqué ; la page d'un projet garde ses deux colonnes ; l'échéance
  affichée à la création d'un projet est bien enregistrée.
- Une mise à jour attend aussi la fin d'un compte rendu.
- Pages publiques et écran de connexion à jour : Polhub écrit dans tes agendas, à ta demande.

## 0.9.0 — 14 novembre 2026

- **Calendrier en écriture** : « + » dans la barre du haut, ou un double-clic dans la grille, crée un
  rendez-vous (titre, agenda, horaires, visio Google Meet, lieu, invités pris dans tes contacts, notes) ;
  « Modifier » dans sa fiche le change ou le supprime. Google envoie les invitations.
- Seuls les rendez-vous que tu organises se modifient ; une invitation reste à son organisateur.
- Un compte connecté avant cette version reste en lecture : « Autoriser la modification », dans sa fiche
  (clic sur le compte, en haut du Calendrier), le reconnecte.

## 0.8.0 — 14 novembre 2026

- **Un système de design commun, dans l'esprit Liquid Glass** : barre du haut en verre sur chaque écran,
  toujours présente (les boutons de la fenêtre ne bougent plus, l'Accueil n'est plus collé en haut), le
  titre de la fenêtre suit l'écran, les mêmes cartes, pastilles et couleurs partout.
- **Projets** : le Kanban, en grand (cartes plus lisibles, prochaine étape, échéance, dernière réunion),
  et la **Liste** de tous les projets, triable par colonne et filtrable par statut. La recherche, en
  haut, vaut pour les deux. « Tous », « À rendre » et « À surveiller » disparaissent.
- **Nouveau projet** : « + » en haut ou en tête d'une colonne ouvre une fenêtre avec tous ses champs.
- **La page d'un projet** est refaite : la prochaine étape en tête, actions, journal et notes ; sur le
  côté ses infos, ses contacts, ses réunions et ses prochains rendez-vous.
- Plus aucun import depuis Obsidian : le bouton, le menu et l'onglet Réglages › Projets disparaissent.

## 0.7.0 — 14 novembre 2026

- **Comptes rendus** : après la transcription, chaque réunion reçoit son résumé, ses décisions et ses
  actions, écrits sur le Mac par le modèle d'Apple intégré à macOS (rien à télécharger, rien ne sort du
  Mac). Jamais pendant une réunion ; les réunions déjà enregistrées suivent, des plus récentes aux
  plus anciennes. Il faut Apple Intelligence activée.
- Les actions se cochent sur la page de la réunion ; « Ajouter au projet » en fait une action du projet.
- **Page d'une réunion** revue : en-tête avec projet et participants, compte rendu, dialogue en
  paragraphes, lecteur flottant en bas ; les gestes rares (refaire le compte rendu, copier la
  transcription, retranscrire, Finder, supprimer) dans le menu « … ».
- Claude Code (outil `reunion`) lit le compte rendu et ses actions avant le dialogue.

## 0.6.0 — 14 novembre 2026

- **Chaque agenda a sa couleur** : le perso en orange, les comptes pro en violet, vert, bleu… dans
  l'ordre où tu les as connectés. Un clic sur un compte, en haut du Calendrier, change sa couleur.
- **Un clic sur un rendez-vous** ouvre sa fiche : **Rejoindre** ouvre le Meet dans Dia avec le bon
  compte Google (celui du rendez-vous), son projet, sa réunion enregistrée, ses invités.
- Un rendez-vous présent dans deux de tes agendas ne s'affiche plus qu'une fois, sous le compte avec
  lequel le rejoindre ; le ranger dans un projet range toutes ses copies.
- **Accueil** : le prochain rendez-vous en tête, avec « Rejoindre ».
- **Une réunion qui démarre prend le nom de son rendez-vous** dès le pop-up ; son projet, son titre et
  ses participants arrivent dès qu'elle se termine.
- Interface plus légère, dans l'esprit Liquid Glass : les commandes de chaque écran passent dans la
  barre du haut, le calendrier est redessiné (jour courant, ligne de l'heure, week-end).

## 0.5.1 — 13 novembre 2026

Corrections de la relecture de la 0.5.0, pour que rien de ce que tu fais ne se perde :

- Un nouvel import des projets garde les liens entre contacts et projets (ceux que tu as retirés
  aussi) et les rendez-vous que tu as rangés.
- Tu peux sortir un rendez-vous d'un projet (« Aucun ») : il y reste.
- La boucle automatique ne revient jamais sur un choix que tu viens de faire.
- Un nouvel import de l'historique ajoute seulement ce qui manque : tes modifications, tes réunions
  mises à la corbeille et tes actions cochées restent telles quelles ; une adresse déjà utilisée ne
  l'arrête plus.
- Une ancienne réunion importée n'est jamais envoyée en transcription.
- La page d'un projet n'enregistre que le champ que tu modifies : une note écrite pendant ce temps par
  Claude Code reste.

## 0.5.0 — 13 novembre 2026

- **Calendrier** : la semaine de tes agendas Google (connexion directe, en lecture seule, qui tient
  dans le temps), le détail d'un rendez-vous, son projet modifiable, sa réunion enregistrée.
- **Contacts** : les invités de tes agendas deviennent des contacts tout seuls, rangés dans les projets
  de leurs rendez-vous ; une fiche par contact, ses projets (un lien retiré ne revient plus), ses
  réunions, ses rendez-vous.
- **La boucle** : un rendez-vous trouve son projet (ton choix, la réunion enregistrée, la série, les
  invités, le titre) et sa réunion enregistrée, qui prend son titre et ses participants.
- **Historique** : les fiches contact et les anciennes réunions du coffre s'importent (Réglages ›
  Projets), sans rien remplacer ; une réunion déjà enregistrée par Polhub est complétée, pas doublée.
- **Accueil** : les rendez-vous du jour, les projets en priorité 1, les dernières réunions, ce qui
  est à classer.
- Le `contexte` du MCP montre les contacts et les prochains rendez-vous du projet.

## 0.4.0 — 13 novembre 2026

- **Suivi de projet par Claude Code** : le serveur MCP `polhub` reprend les outils du serveur Obsidian,
  avec les mêmes noms — `projets`, `contexte`, `actions`, et pour écrire `action`, `note`, `journal`,
  `fait`. Le projet se déduit du dossier de la session. `reunions` prend un projet, `chercher`
  cherche aussi dans les projets.
- Ce que Claude Code écrit apparaît tout de suite dans l'app.
- La commande `polhub` lit la base même quand l'app est fermée (pendant une mise à jour, par exemple).
- L'import du coffre prévient qu'il remplace aussi ce que Claude Code a écrit dans l'app.

## 0.3.2 — 13 novembre 2026

- La barre latérale ne garde que **Projets**, **Réunions** et **Réglages**. Diagnostic et Journal
  passent dans Réglages, en onglets, à côté de Mises à jour et du dossier du coffre (Projets).
- Réglages apparaît toujours : il manquait quand le Diagnostic s'ouvrait au lancement.
- « Diagnostic… » dans le menu ouvre Réglages › Diagnostic.

## 0.3.1 — 13 novembre 2026

- Le serveur MCP `polhub` annonce la version de l'app au lieu d'un numéro figé.
- Première mise à jour installée automatiquement : elle sert d'essai au système de mise à jour.

## 0.3.0 — 13 novembre 2026

Première version publiée.

- **Enregistrement automatique des Meet de Dia** : pop-up avec compte à rebours de 10 s, deux pistes
  (« Moi », « Les autres »), fin détectée seule, relance après un plantage. L'enregistrement tient
  bon à travers les changements de casque et la mise en veille.
- **Transcription sur le Mac**, hors ligne (WhisperKit, détecteur de voix Silero), avec dialogue relié
  au lecteur, recherche, « Retranscrire » et « Réessayer ».
- **Projets** : kanban, vues Tous, Tableau, À rendre, À surveiller, page de projet, import depuis
  Obsidian, rangement d'une réunion dans un projet.
- **Claude Code** : la commande `polhub` et son serveur MCP, en lecture seule.
- **Mises à jour automatiques** depuis les versions publiées sur GitHub, jamais pendant une réunion.
