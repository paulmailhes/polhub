# Système de design de Polhub

Polhub suit Liquid Glass, le langage visuel de macOS 26 et suivants. Toute nouvelle page reprend ces règles
et les composants du module `PolhubDesign` (`Packages/MeetingsMac/Sources/PolhubDesign`).

Référence : [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass)
(Apple).

## Le principe

Le design system v2 (plan d'affinage du 19/11) tient en cinq règles :

- **Le contenu est calme, les commandes flottent.** Le verre est pour la navigation et les commandes qui flottent
  au-dessus du contenu : la barre d'outils, la barre latérale, les popovers, les feuilles, les barres flottantes
  (le lecteur d'une réunion, la barre de saisie de Colin), les panneaux en verre (Coup d'œil, le HUD, la carte avant
  une visio). **Jamais un bouton en verre dans le contenu** : dans une fenêtre qui n'est pas au premier plan, il
  paraît désactivé (mesuré le 19/11). Jamais de verre sur du texte à lire, jamais de verre sur du verre.
- **Une couleur a un seul sens** (`Tint`, ci-dessous). L'accent est celui de Polhub, l'encre, quel que soit l'accent
  du Mac : aucune vue n'écrit `Color.accentColor`.
- **La hiérarchie vient de la taille et de l'air**, pas de la couleur.
- **Tout ce qui se clique répond, et rien ne bouge au survol.**
- **Peu de mots, toujours les mêmes.**

Des composants standard d'abord (`NavigationSplitView`, `toolbar`, `Table`, `Form` groupé, `sheet`, `popover`) :
ils prennent Liquid Glass tout seuls. Aucun fond personnalisé sur une barre.

## La fenêtre

- Chaque section a **une barre d'outils**, toujours présente : le bouton de barre latérale y est en
  permanence, si bien que les boutons de la fenêtre ne bougent jamais d'une section à l'autre.
- Le titre de la fenêtre est celui de la page (`.windowTitle("Calendrier", subtitle: "Novembre 2026")`).
- Les commandes d'une page vont dans sa barre d'outils, groupées par sens : navigation à gauche
  (`.navigation`), choix de vue au centre (`.principal`, contrôle segmenté), actions à droite
  (`.primaryAction`), recherche par `.searchable(placement: .toolbar)`.
- Les icônes de la barre d'outils ont toujours un libellé (`Label`) pour l'accessibilité.
- Les gestes rares vont dans un menu « … » (`ellipsis`), pas en boutons dans la page.
- **Rien ne défile sous la barre d'outils quand la zone est plus étroite que la page** (19/11) : une zone qui défile
  et touche le haut de la fenêtre reçoit un fond flou à sa propre largeur, qui dessinait une boîte au-dessus des
  cartes de l'Accueil et de la liste de Réunions. `.belowToolbar()` la fait commencer sous la barre. Une page entière
  (`Page`) peut passer dessous : son fond couvre toute la largeur.
- **Une barre de boutons ne s'écrase jamais** : elle garde sa taille (`fixedSize`) et passe au-dessus du titre quand
  la place manque (`ViewThatFits`), comme celle d'un mail ouvert.
- **Un trait de grille fait un pixel**, posé sur un pixel (`PixelGrid`) et de la couleur de séparation du système :
  un demi-point s'effaçait sur un écran qui n'est pas Retina, d'autant plus que la fenêtre s'élargissait.
- **La barre latérale** est une `List` native (sa sélection et son verre sont ceux du système, jamais de verre
  ni de fond ajouté sur une rangée) : de grandes rangées (`sidebarRowSize` `.large`), le symbole de chaque
  section dans sa couleur (`listItemTint`), un nombre à droite quand il sert (mails non lus, rendez-vous qui
  restent aujourd'hui), un point rouge sur Réunions pendant un enregistrement. Réglages est en bas, dans une
  liste à lui, dessiné et sélectionné comme les autres rangées.

## Les mesures

| | Valeur |
|---|---|
| Espacements (`Space`) | 4, 8, 12, 16, 24, 32 |
| Rayons (`Radius`), toujours `style: .continuous` | 8 (`control` : ce qui se clique, une ligne, un champ, une puce), 12 (`inner` : dans une carte), 16 (`card` : une carte, un panneau), et la capsule |
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
- **les pièces jointes** en pastilles sous la ligne, en densité « Par défaut » ; un clic sur une pastille
  ouvre le fichier dans Coup d'œil (Quick Look) sans ouvrir le fil ; un type que Polhub n'ouvre jamais
  s'enregistre ;
- **le survol ne déplace rien** : une ombre sous la ligne, et les gestes par-dessus la date, sur le fond de la
  ligne ; aucun élément n'apparaît ni ne disparaît dans la mise en page ;
- **deux onglets**, Personnes et Notifications (les lettres d'information y sont), sous la barre des gestes,
  chacun sa couleur, souligné quand il est ouvert ; **les dossiers et les boîtes** dans la barre latérale, sous
  « Mails », avec **« Nouveau mail »** en tête, comme le bouton de Gmail (⌘N dans Mails) ;
- la barre latérale a **une largeur fixe** (252 points, la plus petite qui montre « Boîte de réception » avec un
  nombre à deux chiffres, et « Tous les messages », en grandes rangées) : elle ne change plus d'une section à
  l'autre.

**Un fil ouvert** montre, pour chaque message, ce qui a été écrit (Paul, 19/11 : « incompréhensible, il y en a dans
tous les sens ») :

- **l'historique cité** se replie derrière une pastille « Historique ▾ », de l'endroit où il commence jusqu'à la
  fin : la classe de Gmail ou d'Apple Mail, le bloc « De / Envoyé (ou Date) / À / Objet » d'Outlook sous son filet
  gris, une ligne « Le … à 17:28, … a écrit : » ou « On … wrote: », ou un historique recopié à plat au milieu d'un
  paragraphe. Le premier message du fil garde le sien ;
- **la signature** se replie derrière « Signature ▾ » dans chaque message : celle que le mail marque, sinon ce qui
  suit « -- », sinon le bloc après la formule et le prénom quand il porte un téléphone, une adresse, un site ou des
  mentions légales. La formule et le prénom restent ;
- **les en-têtes** d'un message cité ou transféré sont petits et pâles ; un transfert reste lisible ;
- **rien ne se replie** quand il ne resterait rien d'écrit (un transfert sans mot, une citation seule) ;
- un mail en texte brut est découpé de même (`MailPlainText`), le script de la page (`MailHTML.readerScript`)
  fait le reste ; le HTML du mail n'est jamais réécrit, et les agents le lisent en entier.

**Le texte d'un brouillon** s'écrit mis en forme, comme dans Gmail (Paul, 17/11) : `RichTextEditor`, une vue web à
sa page, qui ne charge rien ni ne suit aucun lien. Il grandit avec son texte (180 points au moins) et ne défile
jamais lui-même : la molette fait défiler la page autour, qui garde la ligne tapée en vue. Il prend la police et les
couleurs du système, et ce qu'il donne ne garde que la mise en forme simple (`MailRichText.clean`) : un brouillon
d'agent mis en forme s'y ouvre tel qu'il partira.

**La barre d'un brouillon** (`ComposeBar`, dans un `FloatingBar`) reste en bas du panneau « Nouveau mail » ou de la
page du fil, quelle que soit la longueur du mail (Paul, 17/11) : « Envoyer » et sa flèche de programmation,
« Joindre », la mise en forme (gras ⌘B, italique ⌘I, souligné ⌘U, listes à puces et numérotée, lien ⌘K, effacer la
mise en forme), où en est le brouillon, la corbeille. Le texte et sa barre partagent une `ComposeSession`. Dans un
fil à plusieurs réponses, la barre fixe est celle de la réponse qui a eu le clavier en dernier (`ComposePinning`) ;
les autres gardent la leur sous leur carte. Le bandeau du bas (`MailUndoBar`) monte au-dessus de la barre.

## Les couleurs

**Une couleur, un sens** (`Tint`, module `PolhubDesign`, fichier `Tint.swift`). Chaque valeur est celle d'un texte :
lisible à 4,5:1 au moins sur une fenêtre et sur une carte, en clair et en sombre (`TintTests`). Une couleur de sens
ne va jamais seule : toujours un mot ou un symbole avec elle.

| Jeton | Sens | Clair | Sombre |
|---|---|---|---|
| `Tint.accent` | l'encre de Polhub : le bouton principal, la sélection, un lien | `#1D1D1F` | `#F5F5F7` |
| `Tint.late` | en retard, une échéance passée | `#B42318` | `#FF6961` |
| `Tint.attention` | maintenant, bientôt, à vérifier, un problème | `#944A00` | `#FFB340` |
| `Tint.recording` | une réunion qui s'enregistre, « Arrêter » | `#C00013` | `#FF7A70` |
| `Tint.done` | fait, livré, accepté, en marche | `#17712F` | `#4CD964` |
| `Tint.agent` | préparé par un agent ou par Colin | `#6340C8` | `#B79CFF` |

- **La teinte des commandes du système** est posée à la racine de chaque fenêtre et de chaque panneau
  (`.tint(Tint.control.color)`) : l'encre en clair, le graphite en sombre. Mesuré le 19/11 : avec l'encre presque blanche
  en sombre, le système écrivait en noir sur son verre, et la piste d'un interrupteur rejoignait son bouton.
- **Un lien dans un texte** se reconnaît à son soulignement, pas à sa couleur.
- **Une erreur** se dit par l'icône d'attention dans sa couleur et une phrase dans la couleur du texte
  (`ErrorLine`) ; jamais une phrase colorée.
- **Les couleurs d'identité** (un compte Google, un projet, une section) ne colorent que des points, des traits, des
  monogrammes, les blocs du calendrier et les cartes du Kanban ; jamais un bouton ni un texte. Une seule palette
  (`Palette`) ; une seule source pour un projet, `ProjectViews.tint(_:)`.
- Chaque **section** garde sa couleur dans la barre latérale et dans Réglages : Accueil sarcelle, Projets bleu,
  Réunions violet, Calendrier orange, Mails rose, Contacts vert, Inspiration jaune, Réglages gris.
- Les surfaces : `Surface.fill` (une carte), `.raised` (au survol, un cran plus haut), `.selected` (ce qui est
  choisi : l'encre à 12 %), `.stroke` (le seul trait).

## Les composants

| Composant | Usage |
|---|---|
| `Page { }` | Une page qui défile, à la bonne largeur et aux bonnes marges |
| `PageHeader("Titre", subtitle:)` | Le titre d'une page qui en a besoin (la page d'un projet) |
| `Card { }` | Une surface de contenu ; `.cardSurface()` pour une vue existante |
| `Banner(.attention, "Titre", detail:) { boutons }` | Un bandeau d'information : seule l'icône porte la couleur (`.information`, `.attention`, `.late`, `.done`, `.agent`) |
| `ErrorLine("Phrase")` | Un problème en une ligne : l'icône d'attention dans sa couleur, la phrase dans celle du texte |
| `SectionTitle("Titre", systemImage:, count:) { trailing }` | Le titre d'une carte ou d'une partie |
| `Chip("Texte", systemImage:, tint:)` | Un statut, une date, une étiquette |
| `Avatar(initiales, size:)` | Une personne |
| `ColorDot(couleur)` | Un compte, un statut, un projet |
| `FloatingBar { }` | Des commandes flottantes en bas d'une page, en verre |
| `.windowTitle(_:subtitle:)` | Le titre de la fenêtre |
| `TextButton("Modifier") { }` | Un mot à cliquer dans une carte (« Modifier », « Changer », « Tout enregistrer… ») : sa capsule au survol, son texte aligné sur la carte |
| `RowButton { ligne }` | Une ligne cliquable d'une carte (Accueil, page d'un projet, Contacts) : toute la largeur répond, le fond déborde sans décaler le texte |
| `IconMenu("ellipsis", help: "Plus") { }` | Un menu derrière une icône ronde, dessiné comme `IconButton` |
| `NotificationBell(inbox:perform:)` (module `MeetingsUI`) | La cloche des notifications : le nombre de nouvelles en pastille à l'encre ; un clic ouvre le panneau (popover en verre) : cartes calmes à la couleur de leur section, par jour, les rafales en pile, un point bleu tant qu'elles sont nouvelles, × au survol ou glissé pour en effacer une, « Tout effacer » |
| `ProjectLogo(projet, size:)` (module `ProjectsUI`) | Le logo d'un projet : l'icône du site du client sur une plaque blanche, sinon ses initiales sur sa couleur (le monogramme, aussi dans les tests et les captures) |

Les personnes (module `MeetingsUI`, `PeopleViews.swift`), partout où Paul croise quelqu'un, jamais en passant par
la page Contacts :

| Composant | Usage |
|---|---|
| `PersonAvatar(initials:, tint:, badge:)` | Les initiales d'une personne et ce qu'elle est pour le projet : dans le projet (une coche à sa couleur), un contact (une coche grise), à ajouter (« + ») |
| `PersonChip(person:, badge:, help:) { menu }` | Une personne sur une pastille (avatar, prénom, coche ou « + ») ; un clic ouvre son petit menu |
| `PersonMenuItems` | Le petit menu d'une personne : « Ajouter à « P » » ou « Retirer de « P » » (« Ajouter aux contacts » sans projet), « Écrire », « Copier l'adresse » ; le même dans un fil, un rendez-vous et une réunion |
| `PersonSuggestionList` | Les suggestions sous un champ À ou Invités : ↑ ↓, ↩ ou ⇥ pour prendre, Échap pour fermer ; le survol allume la ligne comme les flèches |

## Les boutons

Quatre rôles, et rien d'autre ne dessine un bouton dans le contenu :

| Rôle | Style | Usage |
|---|---|---|
| Principal | `.buttonStyle(.primary)` | L'action principale d'un écran, **une par écran** : plein et mat, à l'encre, son libellé à l'opposé (blanc en clair, encre en sombre) |
| Secondaire | `.buttonStyle(.secondary)` | Une autre action visible : un contour fin, la couleur du texte, un fond au survol |
| Discret | `IconButton`, `TextButton(_:quiet:)` | Un geste qui est là sans appeler : gris (`quiet`), ou à l'encre ; un fond au survol |
| Ligne | `RowButton`, `.buttonStyle(.row)`, `LineButtonStyle(ground:)` | Une ligne entière qui est un bouton |

- **Dans la barre d'outils**, les styles du système (« Nouveau mail » en `.glassProminent`, à la teinte des
  commandes). **Partout ailleurs**, panneaux en verre et popovers compris, les rôles de Polhub : un bouton en verre
  teinté ressemble au principal, et un bouton en verre paraît éteint dans une fenêtre qui n'est pas devant (mesuré le
  19/11).
- **Un rond en verre qui flotte** au-dessus d'une page (✕ d'un panneau, « … » d'un projet) reste neutre :
  `.tint(nil)` (mesuré : il redevient du verre neutre sous une racine teintée).
- **« Arrêter »** un enregistrement : `.primary(.recording)`, un rouge plein (`Tint.recordingFill`) au libellé blanc.
- **Un choix parmi quelques-uns** (les minutes d'un rappel) : `.buttonStyle(.choice(choisi))`, le choisi cerné
  d'encre ; un choix est un état, jamais un bouton principal.
- `.primary`, `.secondary` et `.choice` suivent `.controlSize`, aux hauteurs du système (mesurées le 19/11) : 20, 24
  et 28 points en petit, normal et grand ; une page garde sa mise en page quand ses boutons changent de rôle.
- Une teinte de compte ou de projet ne va jamais sur un bouton : « Rejoindre » est à l'encre, la couleur du compte
  reste dans son rond.
- Dans une capsule de verre (le lecteur, les gestes d'un fil ouvert), des `IconButton` : pas de verre sur le verre.

## L'interaction

Tout ce qui se clique répond : un fond au survol, un léger enfoncement à l'appui. Et **le survol ne déplace
rien** : il change un fond, une ombre, une échelle, jamais une marge ni la place d'un élément. Sur macOS,
`.hoverEffect` n'existe pas : le survol vient de `onHover`, dans les outils de `Interaction.swift` (module
`PolhubDesign`).

| Outil | Usage |
|---|---|
| `Motion.quick` (0,15 s) | Un survol, un appui, une sélection |
| `Motion.standard` (0,25 s) | Ce qui s'ouvre, se ferme, se déplie ou bouge |
| `Motion.gentle` (0,35 s) | Un plus grand changement de contenu |
| `.hoverRow(selected:, radius:, inset:)` | Une ligne cliquable : un fond arrondi au survol (`Surface.fill`), la couleur de la sélection quand elle est choisie (`Surface.selected`) ; `inset` laisse le fond déborder à gauche et à droite sans décaler le texte |
| `.buttonStyle(.row(selected:, radius:, inset:))` | La même ligne quand c'est un bouton : un cran plus sombre à l'appui (`Surface.raised`) |
| `LineButtonStyle(ground:)` | Une ligne pleine largeur sur son fond (les brouillons, comme les mails) : une ombre au survol, un voile à l'appui |
| `.cardHover(radius:)` | Une carte cliquable qui se soulève : ombre, un peu plus grande, bord plus net ; elle dessine le bord de la carte |
| `.buttonStyle(.hover)`, `.hover(.circle)`, `.hover(.capsule)` | Un bouton : un fond au survol, plus petit et plus clair à l'appui ; le libellé garde ses marges (`HoverButtonStyle(fill:)` pour une autre couleur) |
| `IconButton("archivebox", help: "Archiver") { }` | Un bouton rond à icône de 32 points, gris, son cercle au survol |
| `ShowMoreList(éléments, limit: 5) { ligne }` | Les premières lignes, puis « Voir les N autres » (« Voir l'autre » pour une seule), « Voir moins » une fois dépliée |
| `EmptyLine("Aucun mail")` | Une partie vide : une ligne grise en `.rowBody` |

- Une liste dans une carte ne montre que **quelques lignes** (5 en général), puis « Voir les N autres » :
  jamais de liste coupée en silence.
- Les listes natives (`List` : Réunions, Contacts) gardent la sélection du système, et leurs lignes prennent
  aussi `.hoverRow(inset:)` au survol. Seule la barre latérale reste entièrement celle du système. Dans un
  tableau (`Table`, la liste des projets), le nom du projet est un bouton `.hover` qui l'ouvre d'un clic.
- Un bloc du calendrier est un bouton `HoverButtonStyle(fill:)` à la couleur de son compte : un cran plus
  soutenu au survol, un peu plus petit à l'appui.
- Le mouvement respecte « Réduire les animations » : sans échelle, les fondus restent.

## Le logo de la barre des menus

Une image monochrome de 18 × 16 (22 de large avec la pastille) que la barre colore seule (`MenuBarGlyph`,
`MenuBarLabel`, module `MeetingsUI`).
Une seule règle : **plein**, Polhub guette les réunions ; **en contour**, il ne les guette pas ; **rouge**, il
enregistre des voix. Rien n'y bouge : l'image change seulement avec l'état.

| État, du plus au moins prioritaire | Logo |
|---|---|
| Enregistrement | rond rouge plein et l'horloge « 12:47 » |
| Réunion détectée (les 10 s) | rond en contour et « 7 s », le même décompte que le HUD (`AppModel.promptDeadline`) |
| Fin présumée | rond en contour et « fin ? » |
| Détection suspendue, version de développement | les trois colonnes en contour |
| Repos | les trois colonnes pleines ; « 8 min » à côté dans le quart d'heure avant un Meet (Réglages › Général) |

Une pastille découpée sur le coin en haut à droite s'ajoute aux colonnes quand un enregistrement est menacé (onglets
de Dia illisibles, autotest raté, disque presque plein, piste en échec) ; elle déborde du coin, et la troisième
colonne garde toute sa hauteur, mordue en haut : posée sur la colonne, elle se lisait comme le point d'un « i ». Elle
disparaît seule quand la cause n'existe plus. Les mails, les notifications, les comptes et les mises à jour ne
touchent jamais le logo.

## L'Accueil

L'Accueil dit d'un regard ce qui attend le clic de Paul et où il en est (`HomeView`, dossier `MeetingsUI/Home`). Ce
qu'il montre est calculé hors de l'affichage par `ColinLibrary`, par règles seules : aucun modèle, rien ne sort du Mac.
Passe UX/UI du 18/11 : une conversation à la Claude à gauche, « ta journée » à droite, une seule couleur pour ce qui
compte.

- **Deux zones** à partir de 760 points de contenu (`HomeLayout`) : à gauche la conversation avec Colin
  (`ColinConversation`), à droite « ta journée », 420 points fixes : le point sur la page, puis des cartes calmes
  (`HomeCard`, 0.37.0 : « Aujourd'hui » mise en avant, « À valider », « À faire », « Comptes Claude »). Chaque zone défile seule. En fenêtre étroite : une bande du jour
  fixe en haut (la date et « Voir » ; le prochain rendez-vous, « À valider N · À faire M » qui déplie les deux listes
  par-dessus le fil), puis la conversation. Pas
  de grand titre : la fenêtre s'appelle « Accueil ». Deux colonnes à partir de 800 points de contenu.
- **Les cartes de ta journée** (`HomeCard`, 0.37.0 ; Paul : « tout est trop tassé, on peut rien lire ») : la carte du
  système (`Surface.fill`, un trait, rayon 16, « Aujourd'hui » compris), 20 points de marge
  intérieure, 16 entre deux cartes ; jamais de verre sous le texte. Le titre en 17 points semi-gras
  (`HomeSectionHeader`), son nombre dans une pastille (`Surface.raised`). Un groupe en petites capitales grises de 11
  points (`HomeGroupLabel`, « EN RETARD »). Un trait fin entre deux lignes (`homeRow`), six points d'air de part et
  d'autre.
- **L'encre (l'accent) pour ce qui compte, seulement** : envoyer (le rond plein de la barre), « Rejoindre » dix
  minutes avant, « dans N min » à un quart d'heure, le retard d'une ligne à valider (plus de deux fois son seuil), le
  retard d'une échéance (« depuis 6 j ») et un compte Claude plein ou qui le sera avant sa remise à zéro.
  « Voir » et ■ sont neutres. Les actions des lignes sont neutres (`.subtle` : petit, bordé d'un trait, la couleur du texte) ; les
  gestes rares sont des mots gris (`TextButton(quiet:)`) ou dans un menu « … ».
- **Le verre pour la barre seulement** (et le bouton ↓) : ni les cartes, ni les bulles, ni les lignes.

### La conversation

- **L'en-tête** reste en haut, hors du défilement : « Colin », un point vert et « en marche » (gris et « à l'arrêt »),
  un menu « … » avec « Mettre à l'arrêt » et « Réglages… ».
- **Le fil** (`ColinThreadView`) est une colonne de lecture de 680 points au plus. Les jours entre deux traits fins
  (`DaySeparator`). Les questions de Paul en bulles à droite (`PaulBubble` : 15 points, rayon 18, `Surface.bubble`,
  jamais plus que la colonne moins 140 points), l'heure au survol. Les réponses de Colin en clair, 15 points sur 22.
  24 points entre deux tours, 10 dans un tour.
- **Les actions de Colin dans son texte** (`StepRow`), là où il les a faites : une icône grise (une enveloppe, un
  dossier, un agenda…) qui bat pendant l'action, et une phrase en `.meta` gris, au présent pendant (« Lit le fil
  « Devis · Claire Morel »… »), au passé ensuite (« A lu 2 fils › »). Des lectures qui se suivent se replient en une
  ligne qui se déplie au clic. Une panne : l'icône rouge et « (raté) ». Avant le premier mot : « Réfléchit… ». Jamais
  un nom d'outil, jamais ce que l'outil a rendu.
- **Le texte s'écrit mot à mot** : les mots reçus sortent à un rythme régulier (`StreamPacer`), les nouveaux
  apparaissent en fondu d'un cinquième de seconde (`FreshRenderer`), sans saut à la fin (la réponse en cours est la
  ligne même du message). Le fil ne suit la fin que si Paul y est ; s'il remonte lire, un rond de verre ↓ le ramène.
  « Réduire les animations » coupe le fondu.
- **Les cartes de ce que Colin a fait** (`ThreadCard` : `Surface.fill`, un trait, rayon 12) : un message à copier
  (« Copier », puis « Copié »), un brouillon (« Brouillon prêt pour Claire », « Relire »), un changement de projet
  (`ChangeCard` : le projet, pourquoi ou qui, une ligne par champ « avant → après », « Annuler » ; annulé, la carte
  pâlit). Un projet créé par Colin (19/11) est mis en avant : « Nouveau projet », son nom en grand, « Ouvrir le
  projet » et « Annuler » (qui le met à la corbeille). Les changements faits dans une réponse vont avec elle ; ceux des règles et des agents sont des cartes à leur
  heure. Une chose à retenir : une ligne grise avec un signet et « Garder ».
- **Le pied d'une réponse** : « a travaillé 9 s », « Copier » ; sous une réponse arrêtée ou ratée, « Arrêté : … » et
  « Réessayer ». Les mots restent sur la dernière réponse, au survol sur les autres. **Un lien écrit par Colin n'est
  jamais cliquable** (`ColinAnswer.inline`) : son adresse s'écrit en clair.
- **La barre** (`ColinComposer`) flotte sur le fil, qui passe sous son verre (`safeAreaBar`) : une capsule de 44 points
  (rayon 16 quand elle grandit, jusqu'à huit lignes), le texte en 15 points centré sur une ligne, à son pied un rond
  de 28 points pour envoyer (pas de bouton pour dicter : la dictée de Polhub viendra, sur Whisper), plein d'encre quand il y a du texte, ■ gris pendant une
  réponse. Entrée envoie, Maj+Entrée va à la ligne, Échap arrête ; un mot en cours de dictée n'est jamais envoyé. Ce
  qui la retient (« Colin attend la fin de ton call. », un réveil du Mac, une panne) se dit au-dessus du champ, dans le
  verre. Au-dessus de la barre, tant que Paul n'a rien demandé aujourd'hui, trois suggestions tirées de sa journée ; un
  clic remplit la barre, rien ne part. Colin à l'arrêt : une carte calme, « Colin est à l'arrêt », « Allumer Colin »
  (`.glassProminent`).

### Ta journée

- **« Le point »** (`BriefingCard`, sans carte) : la date en `.title2` semi-gras (« Mercredi 18 novembre »), « Le point
  · mardi 9:04 » en gris, puis « Depuis hier 19:40 : 1 mail de client, 2 projets ont bougé. » et « Voir ». Plus de
  chiffres en tuiles (0.36.0) : un chiffre seul ne disait rien à Paul ; les listes en dessous disent quoi, où et quand. Il se prépare à un retour de Paul (première présence du jour, ou trois heures
  après), jamais à chaque affichage.
- **« Voir »** ouvre une feuille (`ChangesSheet`) titrée de la phrase du point : les fils des clients (« Ouvrir »), puis
  ce qui a bougé sans Paul, en cartes signées (« Un agent, aujourd'hui 16:27 ») avec « Annuler », et « Fermer ».
- **« Aujourd'hui »** (`TodayCard`) avant « À valider » : le prochain rendez-vous en grand (`.title3` semi-gras ; « dans
  40 min · 14:00 · Studio Nord » dessous, l'attente à la couleur d'attention à un quart d'heure), « Rejoindre » en `.subtle` puis en
  `.primary` (petit) dix minutes avant ; les autres sur une ligne (l'heure dans une colonne de 44 points, le titre, le
  projet, l'icône pour rejoindre). S'il ne reste rien, le rendez-vous suivant avec son jour (« Demain 10:00 »).
  **Le soir** (0.36.0), à partir de l'heure réglée (Réglages › Calendrier, 19 h) et une fois fini le dernier rendez-vous
  du jour, le titre devient « Demain · jeudi 19 novembre » et la liste celle du lendemain ; « Rejoindre » n'y apparaît
  que dix minutes avant. Le titre change toujours avec le contenu.
- **« À valider »** (`ReviewCard`) : une ligne par chose. Le visage de la personne (`PersonAvatar`, aux couleurs du
  projet) ou, pour une réunion à ranger, son symbole ; la phrase avec le nom en semi-gras ; le projet et l'âge dessous,
  l'âge en rouge (`Tint.late`) en retard ; l'action en `.subtle` toujours au même bord (« Relire », « Ouvrir », « Ranger ») ; le
  menu « … » au survol. Un clic sur la ligne fait la même chose que son action, sauf pour une réunion : il l'ouvre, et
  « Ranger » propose les projets. Cinq lignes, puis « Voir les N autres ». Vide : « Rien à valider. ».
- **« À faire »** (`TodoCard`, règles `TodoRules`, 0.36.0) : les projets en priorité 2 et ceux dont l'échéance est
  passée ou à sept jours, groupés « En retard », « Aujourd'hui », « Demain », « Cette semaine », « Ensuite » (le titre
  d'un groupe en `.meta` gris, aucun s'il n'y en a qu'un). Une ligne : le projet en `.rowTitle` et « · client » en gris,
  le quand à droite (« depuis 6 j » en rouge de retard semi-gras, « vendredi », « lundi 30 », « call demain 9:30 »), la tâche du
  moment dessous (sinon la première action). Un chevron devant le projet : un clic déplie la ligne sur place (une à la
  fois) — « Tâche · … », les actions ouvertes du projet en puces (huit, puis « + N autres »), « Ouvrir le projet » en mot
  gris, « Reporter » et « Livré ». L'échéance est la prochaine étape datée : un rendez-vous du projet ce
  jour-là en fait un call, sauf si Paul a posé la date lui-même ; le call passé, l'étape est faite. « Reporter » (un
  menu : demain, lundi, dans une semaine, une date) et « Livré » en `.subtle` : toujours sous une ligne en retard ou
  dépliée, au survol à la place du quand ailleurs ; ce sont des gestes de Paul. Quand le projet a un prochain call,
  « Livré » est un menu (0.37.0) : « Livré, prochaine échéance : call jeudi 9:30 » (l'échéance devient ce jour-là, et
  reste un call) ou « Livré, sans échéance ». Après l'un d'eux, « Cabinet Martin livré ·
  Annuler » en tête de liste pendant huit secondes. Six lignes, celles d'aujourd'hui et de demain toujours, puis « Voir
  les N autres ». Vide : « Rien à faire. ».
- **« Comptes Claude »** (`ClaudeAccountsCard`, 0.36.0) : seulement si Vigie est là et répond au jeton de lecture
  qu'il réserve à Polhub ; sinon rien, ni titre ni erreur. Une ligne par compte connecté : le nom (80 points), une
  barre de six points (`Surface.fill`, le plein en gris) du quota le plus serré (la semaine, ou celle d'un modèle si
  elle est plus haute), le pourcentage ; dessous « tient · lun. 20 h », ou « plein jeu. 14 h » à la couleur d'attention, et la
  session de cinq heures au-delà de 75 %. Sans relevé récent : la barre vide, « pas de relevé récent ».
- **Une ligne par personne, une ligne par projet** (`ReviewRules`) : « attend ta réponse » se lit sur l'échange avec
  la personne dans tous les fils et toutes les boîtes (`Exchanges`), « ne répond plus » sur le projet entier. Lues
  fil par fil, ces deux lignes parlaient dix fois trop : on répond dans un nouveau mail aussi souvent que dans le fil.
  Écarter une ligne vaut donc pour la personne ou pour le projet.
- **Un brouillon ou un fil s'ouvre par-dessus l'Accueil** (`mailPanels`, les mêmes panneaux que dans Mails) : on
  relit, on envoie, on ferme, et la ligne suivante est là. « Précédent » referme.
- **Rien n'est dit deux fois** : ce que disaient l'ancien titre daté, la carte du prochain rendez-vous, « Priorité 2 »,
  « Dernières réunions », « À classer » et les tuiles de chiffres est dans « Le point », « Aujourd'hui », « À valider »
  et « À faire ».

## Coup d'œil

Le panneau qui s'ouvre d'un clic sur le logo (`MenuBarPanel`, dossier `MeetingsUI/MenuBarPanel`), construit comme le
Centre de contrôle. La logique vit à part, testée sans écran (`PanelModel`).

- **De haut en bas** : « À régler » (seulement s'il y a une cause), la vedette, deux tuiles fixes (Calendrier, Mails),
  « Nouveaux mails », trois boutons ronds (Enregistrer, Nouveau mail, Suspendre), le pied (Ouvrir Polhub, la cloche,
  Réglages, « ⋯ »). Les tuiles et les boutons ne bougent jamais ; le bandeau, le contenu de la vedette et les mails
  partent quand ils n'ont rien à dire.
- **Rien n'est dit deux fois** (« Tuiles allégées », Paul, 16/11) : une tuile Réunions redisait la vedette, une tuile
  Projets donnait un nombre sur lequel on n'agit pas, « Arrêter » était à la fois dans la vedette et en bouton rond.
  Avant d'ajouter une chose au panneau, vérifier qu'aucune autre ne la dit déjà.
- **Mesures** : 360 points de large, marges de 14, écarts de 10 ; tuiles de 161 × 80 (rayon 16), vedette de rayon 16 et
  de 90 à 130 points de haut, jamais écrasée sous son contenu (une exception : « Réunion détectée » avec un lien Meet, les cinq lignes de la maquette,
  environ 146 points pendant ses 10 secondes) ; hauteur selon le contenu, au plus 640 points (ou l'écran moins 40).
  Le panneau prend toujours sa hauteur entière (`fixedSize`) : souple, il laissait la fenêtre de la barre des menus
  garder une hauteur plus ancienne, et les boutons de la vedette débordaient sur les tuiles (16/11).
  Au-delà, seule la carte des mails cède, par lignes entières (jamais un mail coupé à travers son objet) : les mails
  qui tiennent, puis son seul en-tête avec « Voir les N nouveaux » ; si même cela ne tient plus, elle part et la tuile
  Mails garde le nombre.
- **La vedette** montre la première situation vraie, dans cet ordre : réunion détectée (le même décompte que le HUD),
  enregistrement (rouge d'enregistrement, l'horloge), fin présumée (attention), rendez-vous dans 15 min (neutre, « dans
  8 min » à la couleur d'attention) ou Meet commencé sans enregistrement (attention), détection suspendue (neutre),
  compte rendu en préparation ou prêt depuis moins de 2 h (neutre), sinon la journée (« Libre jusqu'à 16:30 », « Plus rien aujourd'hui »). Une carte calme teintée à 10 %
  (16 % en sombre), titre en 17 points, horloge en 22 points à chiffres fixes ; une action principale en
  `.primary` (↩), au plus une secondaire en `.secondary`, de taille normale ; « Arrêter » en `.primary(.recording)`. Elle change en fondu (`Motion.gentle`).
  « Réunion détectée » suit la maquette : le décompte, le titre, « S'enregistre seule dans 7 s », les deux réponses,
  puis « Jamais pour ce lien » dessous, seulement pour un lien Meet. Un Meet enregistré puis fini dans son créneau n'est
  jamais « pas enregistrée » : son compte rendu en préparation prend la place.
  Le compte rendu (en cours ou prêt) a une croix en haut à droite qui le range pour de bon ; il se range aussi seul dès
  que la réunion est ouverte dans Polhub une fois transcrite (Paul, 16/11 : « je l'ai déjà traité, j'ai plus besoin
  qu'il s'affiche »). Les comptes rendus rangés sont gardés d'un lancement à l'autre (`AppModel.reportsPutAway`).
- **Les tuiles** : l'icône de la section dans sa couleur et son nom (13 points), la valeur (15 points), une ligne de
  détail (13 points), un nombre en haut à droite pour Calendrier. Un plateau clair sur le verre du panneau
  (`PanelSurface`), `.cardHover` au survol ; un clic ouvre la page puis la fenêtre (⌘1 à ⌘6 dans l'ordre de la barre
  latérale).
- **« À régler »** : une carte calme à la couleur d'attention, une ligne par cause, trois au plus, la plus risquée pour les
  enregistrements d'abord (alertes, compte Google à reconnecter, mise à jour en échec ou en attente de Paul) ; le
  détail de chaque cause sur deux lignes au plus. Une erreur de réseau n'y va jamais. Une version qui attend la fin
  d'une réunion est une ligne grise du pied.
- **« Nouveaux mails »** : les non-lus de la Boîte de réception (jamais Notifications), ceux d'un projet d'abord (le
  point à sa couleur), puis les contacts connus, puis les autres ; trois au plus, puis « Voir les N autres », qui
  compte tous ceux qu'elle ne montre pas. Au survol, « Marquer comme lu » se pose sur l'heure, sur la ligne de
  l'expéditeur, sans rien décaler ni couvrir l'objet. Cachée pendant une réunion.
- **Les boutons ronds** : 44 points de verre, leur nom en 12 points dessous, pleins de leur couleur quand ils sont
  allumés (Reprendre à l'encre, comme le Reprendre de la vedette). Enregistrer ne sert qu'au repos : une réunion détectée
  ou enregistrée se règle dans la vedette, et Arrêter n'est que là, au clic, jamais au clavier.
- **Le verre** ne sert qu'aux boutons ; tuiles, vedette et cartes sont calmes, jamais de verre sous du texte.
- **Le temps** : le panneau ne lit jamais `AppModel.now` ; il suit une horloge de 30 s calée sur les demi-minutes
  (`PanelModel.clock`), si bien que « dans 8 min » tourne en même temps que le « 8 min » de la barre ; le décompte comme
  l'horloge d'un enregistrement ont leur propre `TimelineView` à la seconde. Il ne lit que ce qui est déjà en mémoire :
  ni base, ni réseau, ni essai matériel.
- **Avec « Réduire les animations »**, il ne reste que des fondus.

## La carte avant une visio

- **En haut à droite de l'écran de la barre des menus**, sous la barre ou l'encoche, comme les notifications de
  macOS, au-dessus de toutes les apps et sur tous les bureaux (`MeetingCardPresenter`, le panneau du HUD).
- **Une carte en verre par rendez-vous** (trois au plus, le plus proche d'abord) : un rond à la couleur du compte, le
  titre, « Dans 2 min · Google Meet » à la seconde, « Rejoindre » plein à l'encre (la couleur du compte reste dans son rond) (le panneau ne prend
  jamais la main : un bouton proéminent y deviendrait gris), la croix.
- **Elle reste** jusqu'à « Rejoindre » ou la croix, dix minutes après le début au plus ; jamais pour la réunion que
  Polhub enregistre déjà. Réglages › Notifications : activée, 2 min avant (1, 2 ou 5).

## Inspiration

Les trois bases d'idées de Paul (dossier `MeetingsUI/Inspiration`, 16/11), reprises de son ancien coffre Obsidian,
puis nourries par la collecte et ses ajouts. La logique vit à part, testée sans écran (`InspirationBrowse`,
`InspirationLibrary`).

- **Dans la barre latérale** : « Inspiration » (ampoule, jaune), après Contacts, repliable comme Mails, avec ses trois
  pages dessous : « Websites » (globe), « Branding » (palette), « Mock-ups » (cadre). Aucun raccourci ⌘ : ⌘1 à ⌘6 restent
  ceux d'avant.
- **Une page** : la barre d'outils (titre, nombre de fiches, ou « 4 sites sur 212 » quand un filtre agit ; « + » ;
  recherche), puis une ligne de pastilles par famille de catégories, le nom de la famille à gauche, « Tout » en
  premier : une seule valeur à la fois par famille, comme la barre de tags d'Obsidian. Une pastille ne propose que les
  valeurs qui mènent à des fiches, compte tenu de la recherche et des autres familles ; les plus fréquentes d'abord.
  Choisie, elle prend l'accent à 16 % (calme : chaque ligne en a une) ; une ligne trop longue défile et s'efface au
  bord. Branding filtre aussi par page LinkedIn (« Source »), chacune avec son point de couleur.
- **La grille** : des cartes de 240 points au moins, l'image de couverture en 4:3, recadrée, le titre (`.rowTitle`) et
  une ligne de détail (`.meta`) : date et adresse du site ; date et studio, avec le point de la page ; types du mock-up.
  `cardHover` au survol, un léger enfoncement à l'appui, un clic droit pour « Ouvrir », le lien, « Supprimer ».
- **Les images** ne sont jamais décodées entières pour une carte : une vignette ImageIO aux pixels de la carte, faite
  hors du fil principal et gardée en mémoire (256 Mo au plus, `InspirationThumbnails`) ; l'image se pose en
  surimpression, si bien qu'elle ne change jamais la taille de sa carte.
- **Une fiche ouverte** prend la place de la grille, avec un chevron de retour (comme un projet) : grande image (les
  images d'un post côte à côte, à leurs proportions), les liens en boutons `.glass` (« Ouvrir le site », « Voir sur
  LinkedIn », « Ouvrir le dossier » : le Finder si le dossier est sur le Mac, sinon son lien Nextcloud), les autres
  liens du post, le texte (860 points au plus), polices et client, puis les catégories : un clic sur une famille ouvre
  le vocabulaire, chaque valeur cochée ou non. Corrigées par Paul, elles sont à lui : ni la collecte ni l'IA n'y
  touchent plus. « Supprimer » est dans « … », avec « Annuler » en bas de la page (⌘Z), comme dans Mails.
- **Une page vide** : une ligne et le bouton de son « + » (« Ajouter un site », « Ajouter une page LinkedIn »,
  « Ajouter un mock-up »).
- **Réglages › Inspiration** : les pages LinkedIn (nom, lien, couleur ; ajouter, modifier, ne plus suivre) avec leur
  dernière lecture en clair ; « Collecte automatique » et l'état de chaque lieu lu ; « Catégories par l'IA d'Apple ».
  L'import du coffre est parti avec le coffre (16/11).

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
POLHUB_LIVE=1 POLHUB_SNAPSHOTS=/tmp/captures swift test --filter DesignCatalogueScreenTests # les couleurs et les boutons, avant / après
POLHUB_LIVE=1 POLHUB_SNAPSHOTS=/tmp/captures swift test --filter "WindowSnapshotTests|MailScreenTests/theMailScreens|PeopleScreenTests"
POLHUB_LIVE=1 POLHUB_SNAPSHOTS=/tmp/captures swift test --filter CoupDoeilScreenTests   # Coup d'œil et le logo
POLHUB_LIVE=1 POLHUB_SNAPSHOTS=/tmp/captures swift test --filter InspirationScreenTests  # Inspiration, données inventées
POLHUB_LIVE=1 POLHUB_SNAPSHOTS=/tmp/captures swift test --filter HomeScreenTests         # l'Accueil, données inventées
```

Une suite à la fois : lancées ensemble, les captures ont laissé des corps de mails vides (19/11).

Les fenêtres de test ne deviennent jamais actives (aucune touche ne doit les atteindre) : un bouton en verre y
paraît gris, ce qui est la raison de la règle « jamais de verre dans le contenu ». Un bouton `.primary` garde son
encre.

La fenêtre se pose sous toutes les autres, juste au-dessus du fond d'écran, sans jamais passer devant le travail en
cours (19/11), puis le système prend son image seule (il faut l'autorisation d'enregistrement de l'écran pour le
terminal). Hors de tout écran, rien ne se dessine : elle reste donc sur un écran, en dessous.

**Le garde-fou** (`DesignGuardTests`) compte dans le code de l'interface ce qui doit disparaître : `Color.accentColor`,
les rayons écrits à la main, les boutons en verre hors des barres et des panneaux. Le nombre ne peut que baisser :
un lot qui en retire abaisse le plafond.
