# Ce qui a changé

Chaque version publiée a sa section ; `scripts/release.sh` la reprend pour la page de la version sur
GitHub, et l'app la montre dans Réglages › Mises à jour.

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
