# Ce qui a changé

Chaque version publiée a sa section ; `scripts/release.sh` la reprend pour la page de la version sur
GitHub, et l'app la montre dans Réglages › Mises à jour.

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
