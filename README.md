# Polhub

Une application macOS qui enregistre seule les réunions Google Meet ouvertes dans le navigateur
[Dia](https://www.diabrowser.com/), les transcrit sur le Mac et les range dans des projets. **Rien ne
quitte la machine** : ni l'audio, ni le texte.

C'est le logiciel personnel d'un designer indépendant, publié tel quel. Il vise un seul Mac et un seul
usage : il n'est ni configurable pour d'autres navigateurs, ni traduit.

## Ce qu'il fait

- **Détecte un Meet** dans Dia. Un pop-up apparaît en haut de l'écran, avec un compte à rebours de
  10 secondes, puis l'enregistrement démarre seul. Il s'arrête seul quand la réunion se termine.
- **Enregistre deux pistes** : « Moi », le micro que Dia utilise, et « Les autres », le son de Dia
  seul. L'enregistrement tient bon quand on change de casque, de haut-parleurs ou d'AirPods, après une
  mise en veille et même après un plantage de l'app, qui est relancée seule.
- **Transcrit après la réunion**, hors ligne, avec [WhisperKit](https://github.com/argmaxinc/WhisperKit)
  (large-v3-turbo) et le détecteur de voix Silero de
  [FluidAudio](https://github.com/FluidInference/FluidAudio). Les phrases que Whisper invente dans le
  silence sont retirées ; une transcription douteuse est marquée « à vérifier ».
- **Montre le dialogue** « Moi / Les autres », relié au lecteur. On peut chercher dans toutes les
  réunions et relancer une transcription dans une autre langue.
- **Range les projets** : un kanban, des vues « À rendre » et « À surveiller », une page par projet.
- **Ouvre les réunions à Claude Code**, en lecture seule, par la commande `polhub` et son
  serveur MCP.
- **Se met à jour seul** à partir des versions publiées ici, et jamais pendant une réunion.

## Configuration requise

- Un Mac à puce Apple, sous macOS 27 ;
- le navigateur Dia ;
- environ 1,6 Go pour les modèles de transcription, rangés dans
  `~/Library/Application Support/Polhub/Models/`.

## Construire

```bash
brew install xcodegen
make check   # les tests, sans micro, sans navigateur, sans modèle
make app     # build/Polhub.app, signée (certificat Developer ID requis)
```

La signature utilise une identité « Developer ID Application ». Une version publiable (app signée,
notarisée et archivée pour les mises à jour) se prépare avec `scripts/release.sh <version>`.

## Organisation du code

| Dossier | Contenu |
|---|---|
| `App/Polhub` | L'application : barre des menus, fenêtre, lancement, relance |
| `Packages/Kernel` | Types du domaine, base SQLite (GRDB), journaux |
| `Packages/MeetingsMac` | Détection, capture audio, transcription, file de calcul, interface, projets, ligne de commande |

Le calcul tourne dans un processus séparé, `polhub-calcul`, que l'app lance hors réunion :
l'app ne charge jamais de modèle.

## Licence

MIT, voir [LICENSE](LICENSE).

La liste des pixels espions bloqués dans les mails vient de
[simplify-trackers](https://github.com/leggett/simplify-trackers) (© 2021 Michael Leggett, simpl.fyi) ; sa
notice est reprise dans `Packages/MeetingsMac/Sources/Mail/MailTrackers.swift`.
