# Système de design de Polhub

Polhub suit Liquid Glass, le langage visuel de macOS 26 et suivants. Toute nouvelle page reprend ces règles
et les composants du module `PolhubDesign` (`Packages/MeetingsMac/Sources/PolhubDesign`).

Référence : [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass)
(Apple).

## Le principe

- **Le verre est pour la navigation et les commandes**, qui flottent au-dessus du contenu : la barre
  d'outils, la barre latérale, les popovers, les feuilles, les commandes flottantes (le lecteur d'une
  réunion), les boutons `.glass` et `.glassProminent`.
- **Le contenu reste calme** : texte sur le fond de la fenêtre, cartes arrondies (`Card`), jamais de verre
  sur du texte à lire, jamais de verre sur du verre.
- **Des composants standard d'abord** (`NavigationSplitView`, `toolbar`, `Table`, `Form` groupé, `sheet`,
  `popover`) : ils prennent Liquid Glass tout seuls. Aucun fond personnalisé sur une barre.

## La fenêtre

- Chaque section a **une barre d'outils**, toujours présente : le bouton de barre latérale y est en
  permanence, si bien que les boutons de la fenêtre ne bougent jamais d'une section à l'autre.
- Le titre de la fenêtre est celui de la page (`.windowTitle("Calendrier", subtitle: "Novembre 2026")`).
- Les commandes d'une page vont dans sa barre d'outils, groupées par sens : navigation à gauche
  (`.navigation`), choix de vue au centre (`.principal`, contrôle segmenté), actions à droite
  (`.primaryAction`), recherche par `.searchable(placement: .toolbar)`.
- Les icônes de la barre d'outils ont toujours un libellé (`Label`) pour l'accessibilité.
- Les gestes rares vont dans un menu « … » (`ellipsis`), pas en boutons dans la page.

## Les mesures

| | Valeur |
|---|---|
| Espacements (`Space`) | 4, 8, 12, 16, 24, 32 |
| Rayons (`Radius`), toujours `style: .continuous` | 6 (petit), 10 (commande), 16 (carte), 22 (carte mise en avant) |
| Page (`PageMetrics`) | largeur 1 080 (lecture : 860), marges 28, haut 16, bas 40 |

## La typographie

| Rôle | Style |
|---|---|
| Titre de page | `.largeTitle`, gras (`PageHeader`) |
| Titre d'un fil ou d'une fiche ouverte | `.title`, gras |
| Titre de carte ou de partie | `.headline` (`SectionTitle`) |
| Texte | `.body` |
| Ligne d'une liste : première ligne (qui, quoi) | `.rowTitle` (15 pt) |
| Ligne d'une liste : deuxième ligne (objet, extrait) | `.rowBody` (14 pt) |
| Détail, méta (dates, adresses, nombres) | `.meta` (13 pt) ou `.callout`, `.secondary` |
| Étiquette (`Chip`), plus petit texte de l'app | `.tag` (12 pt) |
| Corps d'un mail | 15 px (`TextSize.reading`) |
| Heures, durées | `.monospacedDigit()` |

Rien à lire sous 12 points : `.caption` et `.caption2` (10 points) ne servent qu'aux icônes et à la grille
du calendrier (Paul, 15/11 : « tout est un peu petit… trop serré et illisible »).

## La liste des mails

Elle copie Gmail, l'outil que Paul connaît le mieux (Paul, 15/11 : « calque-toi le plus possible sur Gmail ») :

- **une ligne par fil** : la case à cocher, les expéditeurs (`.rowTitle`, colonne de 210 points), puis la
  case du fil, l'objet (`.rowTitle`) et, plus petit et en gris, le début du mail (`.rowBody`) ; la date au bout ;
- **non lu** : fond le plus clair (`MailSurface.unread`, blanc en clair) et gras ; **lu** : fond bleu-gris
  (`MailSurface.read`) ; **coché** : bleu clair (`MailSurface.ticked`) ; le bleu des cases et de l'onglet
  Personnes est celui de Gmail (`MailSurface.blue`), quelle que soit la couleur d'accent du Mac ;
- **les pièces jointes** en pastilles sous la ligne, en densité « Par défaut » ;
- **le survol ne déplace rien** : une ombre sous la ligne, et les gestes par-dessus la date, sur le fond de la
  ligne ; aucun élément n'apparaît ni ne disparaît dans la mise en page ;
- **les onglets** (Personnes, Notifications, Newsletters) sous la barre des gestes, chacun sa couleur, souligné
  quand il est ouvert ; **les dossiers et les boîtes** dans la barre latérale, sous « Mails » ;
- la barre latérale a **une largeur fixe** (230 points) : elle ne change plus d'une section à l'autre.

## Les couleurs

- Une seule palette (`Palette`) pour les comptes Google, les projets et les statuts.
- La couleur d'un **compte** marque ses rendez-vous ; celle d'un **statut** marque les colonnes du Kanban ;
  celle d'un **projet** marque sa carte (un trait à gauche).
- La couleur d'accent du système reste celle de la sélection et de « Moi » dans les transcriptions.
- Rouge pour le retard, orange pour aujourd'hui et pour ce qui est à vérifier, jamais pour décorer.

## Les composants

| Composant | Usage |
|---|---|
| `Page { }` | Une page qui défile, à la bonne largeur et aux bonnes marges |
| `PageHeader("Titre", subtitle:)` | Le titre d'une page qui en a besoin (Accueil, page d'un projet) |
| `Card { }` | Une surface de contenu ; `.cardSurface()` pour une vue existante |
| `SectionTitle("Titre", systemImage:, count:) { trailing }` | Le titre d'une carte ou d'une partie |
| `Chip("Texte", systemImage:, tint:)` | Un statut, une date, une étiquette |
| `Avatar(initiales, size:)` | Une personne |
| `ColorDot(couleur)` | Un compte, un statut, un projet |
| `FloatingBar { }` | Des commandes flottantes en bas d'une page, en verre |
| `.windowTitle(_:subtitle:)` | Le titre de la fenêtre |

## Les boutons

- L'action principale d'un écran ou d'une fiche : `.buttonStyle(.glassProminent)`, teintée si la couleur
  a un sens (« Rejoindre » prend la couleur du compte).
- Une action secondaire visible : `.buttonStyle(.glass)`.
- Dans une liste ou une carte : `.borderless` ou `.plain`, pour ne pas charger le contenu.

## Les réglages

- Chaque fonction range ses réglages dans **Réglages**, dans sa famille (Calendrier, Projets, Réunions…),
  comme les réglages d'Apple : la liste des familles, puis une page par famille, avec un retour.
- Une page n'a pas de bouton de réglage à elle ; au plus un raccourci vers sa famille dans Réglages.
- Chaque réglage a sa clé et sa valeur par défaut dans `Preferences` (module `PolhubDesign`) ; les vues le lisent
  par `@AppStorage(Preferences.Key…)`.
- Réglages est en bas de la barre latérale, à part du travail.

## Vérifier une page

Les captures hors écran ne dessinent ni le verre ni la barre d'outils. Pour voir le vrai rendu :

```sh
POLHUB_LIVE=1 POLHUB_SNAPSHOTS=/tmp/captures swift test --filter WindowSnapshotTests
```

La fenêtre s'affiche un instant, puis le système la capture (il faut l'autorisation d'enregistrement de
l'écran pour le terminal).
