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
  restent aujourd'hui), un point rouge sur Réunions pendant un enregistrement. Elle ne liste que des lieux
  (« Mails court », lot 4, 19/11) : Accueil, Projets, Réunions, Calendrier, Mails (Boîte de réception, Brouillons,
  Envoyés, puis « Plus »), Inspiration ; Contacts et Réglages en bas, à part, dessinés et sélectionnés comme les autres
  rangées. Treize rangées au plus, « Plus » replié ; 224 points de large. La cloche des notifications est en haut, dans
  la barre d'outils, près du bouton de la barre latérale.

## La navigation

Le lot 4 (19/11) a posé ces règles ; le code navigue par les méthodes du routeur (`WindowRouter`).

- **Fermer, c'est revenir** (`WindowRouter.close()`) : ✕, Échap, le clic à côté d'un panneau flottant et le ‹ d'une page
  ramènent d'où l'objet a été ouvert, une autre section comprise (un projet ouvert depuis l'Accueil revient à l'Accueil,
  « Réglages des mails… » à Mails), sans ajouter de pas à l'historique : dix fils lus ne font plus vingt pas, et
  « Suivant » rouvre l'objet. Ouvert d'emblée (la fenêtre s'est ouverte dessus), il se ferme sur place. L'aide du ‹ dit
  où il mène : « Revenir à l'Accueil (Échap) ».
- **✕ en haut à droite**, partout où un panneau ou un objet ouvert en a un (fil, nouveau mail, projet).
- **Le titre de la fenêtre** est le mot de la barre latérale ; le sous-titre dit où l'on est dedans (dossier, semaine,
  famille, « Websites · 12 sites »), jamais le nom d'un objet déjà écrit en grand dans la page.
- **Les touches de la fenêtre**, les mêmes que dans Coup d'œil : ⌘1 à ⌘7 suivent la barre latérale de haut en bas
  (calculés depuis sa liste, `SidebarItem.numbered`), ⌘, ouvre Réglages, ⌘N fait le « + » de la page (un nouveau mail là
  où la page n'en a pas), ⌘F pose le curseur dans sa recherche. ⌘[ ⌘], les boutons de la souris et le balayage
  parcourent l'historique ; ⌘← ⌘→ aussi, sauf dans un texte qu'on écrit, l'éditeur d'un mail compris. Polhub n'a pas de
  barre des menus à lui : son moniteur de touches les lit (`NavigationInput`, `WindowKeys`).
- **Un nom mène à son objet** : le projet d'un fil, d'une réunion ou d'un rendez-vous (« Ouvrir le projet » en tête de
  son menu), la date d'une réunion vers son rendez-vous, les prochains rendez-vous d'un projet.

## Les mesures

| | Valeur |
|---|---|
| Espacements (`Space`) | 4, 8, 12, 16, 24, 32 |
| Rayons (`Radius`), toujours `style: .continuous` | 8 (`control` : ce qui se clique, une ligne, un champ, une puce), 12 (`inner` : dans une carte), 16 (`card` : une carte, un panneau), et la capsule |
| Page (`PageMetrics`) | largeur 1 080 (lecture : 860), marges 28, haut 16, bas 40 |
| Carte (`PageMetrics.cardPadding`, `.cardGap`) | 20 points de marge dans toute carte, 16 entre deux cartes, 24 entre l'en-tête d'une page et ses cartes (lot 8, 19/11) |

## La typographie

| Rôle | Style |
|---|---|
| Titre de page | `.largeTitle`, gras (`PageHeader`) |
| Titre d'un objet ouvert : un projet, une réunion, un contact, une fiche d'Inspiration | `.largeTitle`, gras, 26 points (lot 8, 19/11) ; une page sans objet ouvert n'a que son titre de fenêtre |
| Titre d'un fil | `.title`, gras (lot 6) |
| Titre de carte ou de partie | `.headline` (`SectionTitle`) |
| Texte | `.body` |
| Ligne d'une liste : première ligne (qui, quoi) | `.rowTitle` (15 pt) |
| Ligne d'une liste : deuxième ligne (objet, extrait) | `.rowBody` (14 pt) |
| Détail, méta (dates, adresses, nombres) | `.meta` (13 pt) ou `.callout`, `.secondary` |
| Étiquette (`Chip`), plus petit texte de l'app | `.tag` (12 pt) |
| Sur-titre, titre d'un groupe (« En retard », « Dans 8 min », « Aujourd'hui ») | `.tag`, semi-gras, gris, en casse normale : jamais de capitales |
| Corps d'un mail | 15 px (`TextSize.reading`) |
| Heures, durées | `.monospacedDigit()` |

Rien à lire sous 12 points : `.caption` et `.caption2` (10 points) ne servent qu'aux icônes et à la grille
du calendrier (Paul, 15/11 : « tout est un peu petit… trop serré et illisible »).

## La liste des mails

Elle copie Gmail, l'outil que Paul connaît le mieux (Paul, 15/11 : « calque-toi le plus possible sur Gmail »), sur
**une seule grille pour tous les dossiers** (lot 6, 19/11) :

- **la barre des gestes est toujours là**, à la même hauteur (48 points) dans chaque dossier : la première ligne ne
  saute plus d'un dossier à l'autre. À gauche, la case « tout » et son menu (grisés là où rien ne se coche :
  Brouillons, Programmés, Abonnements), ↻ et « … » ; des fils cochés, leurs gestes et « 2 sélectionnés ». À droite,
  « Boîtes » (s'il y en a plusieurs) et « Non lus », seulement là où il filtre : Boîte de réception, Notifications,
  Envoyés, Tous les messages, jamais pendant une recherche ;
- **la grille** (`MailGrid`, `MailGridLine`) : le filet de la boîte, la case (44 points), les expéditeurs (210), l'objet
  et, plus petit et en gris, le début du mail, puis **une colonne de fin fixe** (134 points) : la date au repos, les
  gestes au survol à sa place (archiver, supprimer, lu, ranger), sans dégradé ; rien ne couvre l'objet, rien ne bouge.
  Les brouillons, les programmés et les abonnements ont les mêmes colonnes : à la place de la case, rien, l'horloge,
  l'initiale de l'expéditeur. La ligne d'avis (une recherche, la corbeille, le spam, Programmés, Abonnements) a son
  icône dans la colonne des cases et son texte sur celle des expéditeurs, comme les titres de jours ;
- **le filet de la boîte**, à gauche, seulement quand la liste montre deux boîtes ou plus ; sa place reste gardée :
  masquer une boîte ne déplace aucune ligne ;
- **non lu** : le fond de la fenêtre (`MailSurface.unread`), le gras, la date en semi-gras ; **lu** : un cran plus bas,
  doux (`MailSurface.read`, 97 % de blanc en clair, 14,5 % en sombre) ; **coché** : l'encre mêlée au fond
  (`MailSurface.ticked`), la case à l'encre. Le survol garde l'ombre de Gmail (choix de Paul du 15/11) ;
- après les noms, « Brouillon » et « Programmé » en gris (le rouge ne dit plus que le retard), « En retard » au rouge du
  retard ;
- **les pièces jointes** en pastilles sous la ligne, alignées sur l'objet, en densité « Par défaut » ; un clic sur une
  pastille ouvre le fichier dans Coup d'œil (Quick Look) sans ouvrir le fil ; un type que Polhub n'ouvre jamais
  s'enregistre ;
- **une liste vide dit quoi faire** (`MailEmptyState`), jamais « Rien ici » : ce qui arrive dans le dossier et « ⌘N pour
  écrire » ; « Tout est lu » et « Afficher tous les mails » quand « Non lus » a tout caché ; « 1 boîte est masquée » et
  « Afficher toutes les boîtes » quand une boîte masquée l'a vidée ;
- **les dossiers** dans la barre latérale, sous « Mails » : Boîte de réception, Brouillons, Envoyés, puis « Plus »,
  qui déplie Notifications, Abonnements, Programmés (seulement quand un mail y attend), Spam, Corbeille et Tous les
  messages à la même profondeur, comme Gmail ; « Plus » reste déplié sur un de ses dossiers ouvert. **« Nouveau
  mail »** est dans la barre d'outils (⌘N), plein tant que la liste est seule à l'écran ;
- **les boîtes** sont un filtre de la liste : le menu « Boîtes » de sa barre, à côté de « Non lus », coche celles que
  la liste montre ; son titre dit « Boîtes : 2 sur 3 » tant qu'une est masquée (lot 4, 19/11) ;
- la barre latérale a **une largeur fixe** (224 points) : elle ne change plus d'une section à l'autre. Le nom d'un
  dossier tient entier, à peine resserré s'il le faut (« Boîte de réception » et son nombre).

**Un fil ouvert** tient sur **une seule colonne de lecture** (lot 6, 19/11 : `readingColumn()`, 860 points au plus,
marges de 28) : l'objet, la méta, les personnes, la capsule des gestes et ✕, les messages, les boutons de réponse et la
réponse ont le même bord. Un nouveau mail aussi : son titre au bord de sa carte.

- **Un seul bouton principal** : « Répondre », plein, avec « Répondre à tous » et « Transférer » en secondaires, en grand
  comme « Envoyer » ; dès qu'une réponse est ouverte sous le fil, « Répondre » passe en secondaire et son « Envoyer » est
  le principal. Tant qu'un fil ou un brouillon est ouvert par-dessus la liste, « Nouveau mail » quitte le plein.
- **La date d'un message est courte** (`MailText.shortDate`) : « Aujourd'hui 17:55 », « Hier 9:12 », « 14 nov. »,
  « 3 déc. 2025 » ; la date entière et « il y a… » sont dans son aide.
- **Les bandeaux sont tous des `Banner`**, seule l'icône porte la couleur : préparé par un agent (l'étincelle violette ;
  la règle des adresses dit leur marque, jamais une couleur), conflit avec Gmail (attention, deux secondaires), images
  masquées (« Afficher » secondaire, « Toujours pour cet expéditeur » en mot gris), corbeille ou spam (« Restaurer » ou
  « Pas un spam », le principal de l'écran), envoi programmé (l'horloge grise, ou le rouge du retard et « Envoyer
  maintenant »).

Pour chaque message, le fil montre ce qui a été écrit (Paul, 19/11 : « incompréhensible, il y en a dans tous les sens ») :

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

- **« Envoyé · Annuler »** (lot 6, 19/11) : une réponse qui part le dit dans sa propre barre, à la place de
  « Enregistré sur le Mac », tant qu'elle peut être rappelée (⌘Z) ; le bandeau du bas ne le redit pas par-dessus.
  Rappelée d'ici, elle redevient un brouillon sous le fil, sans un mot en bas de page. Un nouveau mail se ferme en
  partant : c'est le bandeau du bas qui dit « … part dans 8 s · Annuler ».
- **Les destinataires** : « Cc » et « Cci » en mots gris ; une adresse à vérifier porte son symbole en plus de la couleur
  d'attention : « ? » pour une adresse à qui Paul n'a jamais écrit, le triangle pour une adresse invalide
  (`RecipientMark`). La réponse est la carte de l'app (fond et trait, rayon 16).

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
  (`Palette`) ; une seule source pour un projet, `ProjectViews.tint(_:)`. Une pastille qui nomme un projet ou un
  statut est neutre, sa couleur dans son point (`Chip(_:dot:)`, lot 8, 19/11).
- **Un statut de projet** : une pastille neutre et son point (Priorité 2, Priorité 1, En pause) ; seul « Terminé » prend
  une couleur de sens, celle de ce qui est fait, avec sa coche (`StatusChip`, `ProjectViews.statusRole`). « Priorité 2 »
  en orange se lisait « à vérifier ».
- Chaque **section** garde sa couleur dans la barre latérale et dans Réglages : Accueil sarcelle, Projets bleu,
  Réunions violet, Calendrier orange, Mails rose, Contacts vert, Inspiration jaune, Réglages gris.
- Les surfaces : `Surface.fill` (une carte), `.raised` (au survol, un cran plus haut), `.selected` (ce qui est
  choisi : l'encre à 12 %), `.stroke` (le seul trait).

## Les composants

| Composant | Usage |
|---|---|
| `Page { }` | Une page qui défile, à la bonne largeur et aux bonnes marges |
| `PageHeader("Titre", subtitle:)` | Le titre d'une page qui en a besoin (la page d'un projet) |
| `Card { }` | Une surface de contenu, 20 points de marge (`PageMetrics.cardPadding`) ; `.cardSurface()` pour une vue existante |
| `Banner(.attention, "Titre", detail:, systemImage:) { boutons }` | Un bandeau d'information : seule l'icône porte la couleur (`.information`, `.attention`, `.late`, `.done`, `.agent`) ; `systemImage` dit de quoi il parle (la corbeille, un spam, une image) à la couleur du ton ; ses boutons passent sous le texte quand la place manque, jamais écrasés |
| `ErrorLine("Phrase")` | Un problème en une ligne : l'icône d'attention dans sa couleur, la phrase dans celle du texte |
| `SectionTitle("Titre", systemImage:, count:) { trailing }` | Le titre d'une carte ou d'une partie |
| `Chip("Texte", systemImage:, tint:, dot:)` | Un statut, une date, une étiquette ; `dot:` met une couleur d'identité dans un point, le texte reste neutre |
| `AudioProblemLine(problem:)` (module `MeetingsUI`) | L'audio d'une réunion qui ne se lit pas : la phrase de Polhub par `ErrorLine`, le texte du système sous « Détails » (`AudioProblem`, lot 8) |
| `Avatar(initiales, size:)` | Une personne |
| `ColorDot(couleur)` | Un compte, un statut, un projet |
| `FloatingBar { }` | Des commandes flottantes en bas d'une page, en verre |
| `.windowTitle(_:subtitle:)` | Le titre de la fenêtre |
| `TextButton("Modifier") { }` | Un mot à cliquer dans une carte (« Modifier », « Changer », « Tout enregistrer… ») : sa capsule au survol, son texte aligné sur la carte |
| `RowButton { ligne }` | Une ligne cliquable d'une carte (Accueil, page d'un projet, Contacts) : toute la largeur répond, le fond déborde sans décaler le texte |
| `IconMenu("ellipsis", help: "Plus") { }` | Un menu derrière une icône ronde, dessiné comme `IconButton` |
| `SettingRow("Titre", help:, detail:, problem:) { contrôle }` | Un réglage dans sa carte : le titre, l'aide d'une ligne dessous, « ⓘ » pour le détail, le contrôle à droite ; `.settingsForm()` pour la page |
| `SettingHelp("Phrase", detail:)`, `InfoBubble("Détail")` | L'aide d'une ligne seule (sous une liste, un éditeur), et « ⓘ » avec sa bulle |
| `NotificationBell(inbox:perform:)` (module `MeetingsUI`) | La cloche des notifications, dans la barre d'outils près du bouton de la barre latérale, et au pied de Coup d'œil : le nombre de nouvelles en pastille à l'encre ; un clic ouvre le panneau (popover en verre, « Notifications » en 17 semi-gras, 16 de marge) : les cartes de Coup d'œil (le fond et le trait de l'app, sans ombre, rayon 16), l'icône de leur section dans sa couleur (Phosphor, sans carré), par jour (étiquette de 12 points), les rafales en pile (les cartes du dessous ne se voient que sous celle du dessus), un point à l'encre tant qu'elles sont nouvelles, × au survol ou glissé pour en effacer une, « Tout effacer » en mot gris |
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
- **Un choix parmi quelques-uns** : `.buttonStyle(.choice(choisi))`, le choisi cerné d'encre ; un choix est un état,
  jamais un bouton principal. Dans un formulaire, un menu ou un segmenté ; plusieurs choix à la fois (les minutes
  d'un rappel), un menu à coches (lot 7, 19/11 : les cinq pastilles des rappels sont parties).
- `.primary`, `.secondary` et `.choice` suivent `.controlSize`, aux hauteurs du système (mesurées le 19/11) : 20, 24
  et 28 points en petit, normal et grand ; une page garde sa mise en page quand ses boutons changent de rôle. Les
  boutons de réponse d'un fil sont grands, comme « Envoyer » dans la barre du brouillon (lot 6, 19/11).
- **Un principal qui cède** : quand un autre principal s'ouvre sur le même écran, le premier passe en secondaire
  (« Répondre » devant l'« Envoyer » d'une réponse ouverte, « Nouveau mail » devant un fil ouvert), lot 6, 19/11.
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
Lot 5 du plan d'affinage (19/11), « Colin à droite » : ta journée est la page, Colin un panneau à droite.

- **La composition** (`HomeLayout`) : à gauche, la journée, une colonne de 640 points au plus au milieu de ce que le
  panneau laisse ; à droite, le panneau de Colin, 420 points, sur toute la hauteur, sur son propre fond
  (`Surface.fill`), un filet entre les deux, sans ombre. Deux colonnes dès que la journée garde 420 points à côté du
  panneau (897 points de page). Chaque zone défile seule. Sans Colin (version sans les mails, captures sans moteur) :
  la journée seule.
- **La fenêtre étroite** : la journée prend toute la page ; la barre de Colin flotte en bas, avec à sa tête son état ou
  le début de sa dernière réponse (`ColinBarLine`, « Colin · Marc t'a écrit lundi ⌃ »). Un clic sur cette ligne, ou une
  question envoyée, ouvre le fil dans un panneau opaque par-dessus la journée (`FloatingPanel`), ✕ en haut à droite,
  Échap ou un clic à côté le referme. Colin à l'arrêt, la phrase de sa carte ouvre le fil.
- **Les cartes de ta journée** (`HomeCard`, 0.37.0 ; Paul : « tout est trop tassé, on peut rien lire ») : la carte du
  système (`Surface.fill`, un trait, rayon 16), 20 points de marge intérieure, 16 entre deux cartes ; jamais de verre
  sous le texte. Le titre en 17 points semi-gras (`HomeSectionHeader`), son nombre dans une pastille. Un groupe en
  étiquette grise de 12 points, en casse normale (`HomeGroupLabel`, « En retard »). Un trait fin entre deux lignes
  (`homeRow`).
- **Les lignes sont calmes** : au repos, aucune bordure. L'action d'une ligne apparaît au survol, sur une place gardée
  pour elle au bout de la ligne (rien ne bouge), et existe au clic droit. Les boutons d'une ligne sont des secondaires
  petits (`.secondary` en `.controlSize(.small)`) : un seul contour pour tout l'Accueil.
- **Les couleurs** : l'encre pour le seul bouton plein (« Rejoindre » dix minutes avant) et pour envoyer (le rond de la
  barre) ; l'attention pour « dans N min » à un quart d'heure, Colin en panne et un compte Claude plein ; le rouge du
  retard pour l'âge d'une ligne à valider (plus de deux fois son seuil) et « depuis 6 j ». Nulle part ailleurs.
- **Le verre pour la barre seulement** (et le rond ↓) : ni les cartes, ni les bulles, ni les lignes.

### Le panneau de Colin

- **L'en-tête** reste en haut, hors du défilement : « Colin » en 17 points, puis son état réel avec son point
  (`ColinState`) : « prêt » (vert), « répond… » (le point bat), « attend ton call », « se réveille », « en panne » (à la
  couleur d'attention), « à l'arrêt » ; jamais « en marche » pendant un call ou une panne. Un menu « … » avec « Mettre à
  l'arrêt » et « Réglages… ». Un filet dessous ; le fil passe sous lui en fondu de 16 points.
- **Le fil** (`ColinThreadView`) est une colonne de lecture de 680 points au plus. Les jours entre deux traits fins
  (`DaySeparator`). Les questions de Paul en bulles à droite (`PaulBubble` : 15 points, rayon 16, `Surface.bubble`,
  jamais plus que la colonne moins 64 points), l'heure au survol. Les réponses de Colin en clair, 15 points sur 22.
  24 points entre deux tours, 10 dans un tour.
- **Les actions de Colin dans son texte** (`StepRow`), là où il les a faites : une icône grise (une enveloppe, un
  dossier, un agenda…) qui bat pendant l'action, et une phrase en `.meta` gris, au présent pendant (« Lit le fil
  « Devis · Claire Morel »… »), au passé ensuite (« A lu 2 fils › »). Des lectures qui se suivent se replient en une
  ligne qui se déplie au clic. Une panne : l'icône d'attention et « (raté) ». Avant le premier mot : « Réfléchit… ».
  Jamais un nom d'outil, jamais ce que l'outil a rendu.
- **Le texte s'écrit mot à mot** : les mots reçus sortent à un rythme régulier (`StreamPacer`), les nouveaux
  apparaissent en fondu d'un cinquième de seconde (`FreshRenderer`), sans saut à la fin (la réponse en cours est la
  ligne même du message). Le fil ne suit la fin que si Paul y est ; s'il remonte lire, un rond de verre ↓ le ramène.
  « Réduire les animations » coupe le fondu.
- **Les cartes de ce que Colin a fait** (`ThreadCard`) : sur le fond de la fenêtre, un trait, rayon 12, pour se
  détacher du gris du panneau. Une même grammaire : une étiquette grise de 12 points en tête (`ResultCard` : « Message à
  copier », « Brouillon », « Projet modifié », « Nouveau projet »), son action en face (« Copier », « Relire », « Ouvrir
  le projet », secondaires petits), puis l'objet en 15 points semi-gras (le projet, « Pour Claire » et l'objet du
  brouillon, le texte du message), pourquoi ou qui en gris, une ligne par champ « avant → après », et « Annuler », un
  mot gris, en bas (annulé : ce qu'il a fait, et la carte pâlit). « Annuler » un projet créé le met à la corbeille. Les
  changements faits dans une réponse vont avec elle ; ceux des règles et des agents sont des cartes à leur heure. Une
  chose à retenir : une ligne grise avec un signet et « Garder ».
- **Le pied d'une réponse** : sous une réponse arrêtée ou ratée, « Arrêté : … » ; « Copier », sauf quand sa carte copie
  déjà (« Copier » une seule fois), et « Réessayer » après un arrêt. Ils restent sur la dernière réponse, au survol sur
  les autres, à une place gardée. Un pied vide ne prend aucune place. Le temps de travail (« a travaillé 9 s ») est dans
  l'aide au survol de la réponse. **Un lien écrit par Colin n'est jamais cliquable** (`ColinAnswer.inline`) : son
  adresse s'écrit en clair.
- **La barre** (`ColinComposer`) flotte au pied du panneau, à 12 points de ses bords, et le fil passe sous son verre
  (`safeAreaBar`) : 44 points sur une ligne, rayon 16, jusqu'à huit lignes, le texte en 15 points, à son pied un rond
  de 28 points pour envoyer (pas de bouton pour dicter : la dictée de Polhub viendra, sur Whisper), plein d'encre quand
  il y a du texte, ■ gris pendant une réponse. Entrée envoie, Maj+Entrée va à la ligne, Échap arrête ; un mot en cours
  de dictée n'est jamais envoyé. Ce qui la retient (« Colin attend la fin de ton call. », un réveil du Mac, une panne) se
  dit au-dessus du champ, dans le verre. Au-dessus de la barre, tant que Paul n'a rien demandé aujourd'hui, trois
  suggestions tirées de sa journée ; un clic remplit la barre, rien ne part. Colin à l'arrêt : la barre devient « Colin
  est à l'arrêt » et « Allumer Colin » (secondaire, petit), dans le même verre (opaque, elle faisait dessiner un trait en
  travers du panneau).

### Ta journée

- **La date en titre de page** (`DayHeader`, `PageHeader` : 26 points gras, « Jeudi 19 novembre »), puis une ligne
  grise de ce qui est venu depuis le dernier passage de Paul, « Voir › » juste après : « Depuis hier 19:40 · 1 mail de
  client, 2 projets ont bougé  Voir › ». Quand « Le point » a été préparé est dit au survol (« Le point · aujourd'hui
  18:55 »). Il se prépare à un retour de Paul (première présence du jour, ou trois heures après), jamais à chaque
  affichage ; la date, elle, est toujours là. Plus de chiffres en tuiles (0.36.0) : les listes en dessous disent quoi,
  où et quand.
- **« Voir »** ouvre une feuille (`ChangesSheet`) titrée de la phrase du point : les fils des clients (« Ouvrir »), puis
  ce qui a bougé sans Paul, en cartes signées (« Un agent, aujourd'hui 16:27 ») avec « Annuler », et « Fermer ».
- **« Aujourd'hui »** (`TodayCard`) en premier : le prochain rendez-vous en grand (« dans 40 min · 14:00 · Studio
  Nord » dessous, l'attente à la couleur d'attention à un quart d'heure), « Rejoindre » à contour, puis plein d'encre
  dix minutes avant, en petit : le seul bouton plein de l'écran (`TodayText.join`). Les autres sur une ligne (l'heure
  dans une colonne de 44 points, le titre, le projet, l'icône pour rejoindre). S'il ne reste rien, le rendez-vous
  suivant avec son jour (« Demain 10:00 »). **Le soir** (0.36.0), à partir de l'heure réglée (Réglages › Calendrier,
  19 h) et une fois fini le dernier rendez-vous du jour, le titre devient « Demain · vendredi 20 novembre » et la liste
  celle du lendemain ; « Rejoindre » n'y apparaît que dix minutes avant.
- **« À valider »** (`ReviewCard`) : une ligne par chose. Le visage de la personne (`PersonAvatar`, aux couleurs du
  projet) ou, pour une réunion à ranger, son symbole ; la phrase avec le nom en semi-gras ; le projet et l'âge dessous,
  l'âge en rouge (`Tint.late`) en retard. Au survol, au bout de la ligne : son action (« Relire », « Ouvrir »,
  « Ranger ») et, à sa gauche, le « … » pour l'écarter ; au clic droit, les mêmes (`ReviewText.gestures`). Un clic sur
  la ligne fait la même chose que son action, sauf pour une réunion : il l'ouvre, et « Ranger » propose les projets.
  Cinq lignes, puis « Voir les N autres ». Vide : « Rien à valider. ».
- **« À faire »** (`TodoCard`, règles `TodoRules`, 0.36.0) : les projets en priorité 2 et ceux dont l'échéance est
  passée ou à sept jours, groupés « En retard », « Aujourd'hui », « Demain », « Cette semaine », « Ensuite » (aucun
  groupe s'il n'y en a qu'un). Une ligne : le projet en `.rowTitle` et « · client » en gris, le quand à droite
  (« depuis 6 j » en rouge de retard semi-gras, « vendredi », « lundi 30 », « call demain 9:30 »), la tâche du moment
  dessous, entière (sinon la première action). « Reporter » (un menu : demain, lundi, dans une semaine, une date) et
  « Livré » apparaissent au survol à la place du quand, gardée pour eux, sur toute ligne datée, en retard comprise ; au
  clic droit, avec « Ouvrir le projet » (`TodoText`). Un chevron devant le projet : un clic déplie la ligne sur place
  (une à la fois) — « Tâche · … », les actions ouvertes du projet en puces (huit, puis « + N autres »), « Ouvrir le
  projet » en mot gris, « Reporter » et « Livré ». L'échéance est la prochaine étape datée : un rendez-vous du projet ce
  jour-là en fait un call, sauf si Paul a posé la date lui-même ; le call passé, l'étape est faite. Quand le projet a un
  prochain call, « Livré » est un menu (0.37.0) : « Livré, prochaine échéance : call jeudi 9:30 » ou « Livré, sans
  échéance ». Après l'un d'eux, « Cabinet Martin livré · Annuler » en tête de liste pendant huit secondes. Six lignes,
  celles d'aujourd'hui et de demain toujours, puis « Voir les N autres ». Vide : « Rien à faire. ».
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
  « Dernières réunions », « À classer » et les tuiles de chiffres est dans le titre, « Aujourd'hui », « À valider » et
  « À faire ».

## Coup d'œil

Le panneau qui s'ouvre d'un clic sur le logo (`MenuBarPanel`, dossier `MeetingsUI/MenuBarPanel`), construit comme le
Centre de contrôle. La logique vit à part, testée sans écran (`PanelModel`).

- **De haut en bas** : « À régler » (seulement s'il y a une cause), la vedette, deux tuiles fixes (Calendrier, Mails),
  les nouveaux mails, trois boutons ronds (Enregistrer, Nouveau mail, Suspendre), le pied (Ouvrir Polhub, la cloche,
  Réglages, « ⋯ »). Les tuiles et les boutons ne bougent jamais ; le bandeau, le contenu de la vedette et les mails
  partent quand ils n'ont rien à dire.
- **Rien n'est dit deux fois** (« Tuiles allégées », Paul, 16/11) : une tuile Réunions redisait la vedette, une tuile
  Projets donnait un nombre sur lequel on n'agit pas, « Arrêter » était à la fois dans la vedette et en bouton rond.
  Le lot 9 (20/11) a retiré les derniers doublons : « Mails » et le nombre n'ont qu'une place (la tuile ; la carte des
  mails n'a plus d'en-tête et la tuile ne nomme plus les expéditeurs qu'elle liste), l'heure n'en a qu'une (sous « Libre
  jusqu'à 16:30 », la tuile Calendrier ne redit pas 16:30), une boîte à reconnecter n'est dite que dans « À régler », et
  l'Accueil ne s'ouvre que par « Ouvrir Polhub » (la carte de la journée se lit, elle ne se clique plus). Avant
  d'ajouter une chose au panneau, vérifier qu'aucune autre ne la dit déjà.
- **Mesures** (lot 9, 20/11 : sur l'échelle de l'app) : 360 points de large, marges de 16, écarts de 8 ; tuiles de
  160 × 80 (rayon 16, 12 à l'intérieur) ; vedette de rayon 16, 16 à l'intérieur de chaque côté, ses boutons 8 sous le
  texte, de 90 à 145 points de haut, jamais écrasée sous son contenu (une exception : « Réunion détectée » avec un lien
  Meet, les cinq lignes de la maquette, environ 160 points pendant ses 10 secondes) ; carte des mails et « À régler » à
  12 sur les côtés ; hauteur selon le contenu, au plus 640 points (ou l'écran moins 40).
  Le panneau prend toujours sa hauteur entière (`fixedSize`) : souple, il laissait la fenêtre de la barre des menus
  garder une hauteur plus ancienne, et les boutons de la vedette débordaient sur les tuiles (16/11).
  Au-delà, seule la carte des mails cède, par lignes entières (jamais un mail coupé à travers son objet) : les mails
  qui tiennent ; si aucun ne tient, elle part et la tuile Mails nomme les expéditeurs.
- **Les cartes** sont celles de l'app : `Surface.fill` et son trait (`Surface.stroke`), sans ombre (`PanelSurface`),
  la vedette, les tuiles, « À régler », les mails et les notifications de la cloche.
- **La vedette** montre la première situation vraie, dans cet ordre : réunion détectée (le même décompte que le HUD),
  enregistrement (rouge d'enregistrement, l'horloge), fin présumée (attention), rendez-vous dans 15 min (neutre, « Dans
  8 min » à la couleur d'attention) ou Meet commencé sans enregistrement (attention), détection suspendue (neutre),
  compte rendu en préparation ou prêt depuis moins de 2 h (neutre), sinon la journée (« Libre jusqu'à 16:30 », « Plus
  rien aujourd'hui »), une carte à lire. Une carte calme teintée à 10 % (16 % en sombre), titre en 17 points, horloge
  en 22 points à chiffres fixes ; une action principale en `.primary` (↩), au plus une secondaire en `.secondary`, de
  taille normale, ensemble à droite, la principale en dernier, chacune à sa largeur (jamais un libellé sur deux lignes ;
  à court de place, le bouton d'un compte rendu en préparation passe sous son état) ; « Arrêter » en
  `.primary(.recording)`. Elle change en fondu (`Motion.gentle`).
  « Réunion détectée » suit la maquette : le décompte, le titre, « S'enregistre seule dans 7 s », les deux réponses,
  puis « Jamais pour ce lien » dessous, seulement pour un lien Meet. Un Meet enregistré puis fini dans son créneau n'est
  jamais « pas enregistrée » : son compte rendu en préparation prend la place.
  Le compte rendu (en cours ou prêt) a une croix en haut à droite qui le range pour de bon ; il se range aussi seul dès
  que la réunion est ouverte dans Polhub une fois transcrite (Paul, 16/11 : « je l'ai déjà traité, j'ai plus besoin
  qu'il s'affiche »). Les comptes rendus rangés sont gardés d'un lancement à l'autre (`AppModel.reportsPutAway`).
- **Le sur-titre de la vedette** (`PanelModel.eyebrow`) est une étiquette grise de 12 points semi-gras, en casse
  normale (« Dans 8 min », « Enregistrement », « Vendredi 20 novembre » ; lot 9, 20/11 : en capitales de 13 avant). Une
  seule chose y prend la couleur, jamais toute la ligne : le symbole d'un état (le point de l'enregistrement, l'icône
  d'une fin présumée ou d'un problème) ou les mots d'un délai (« Dans 8 min », comme sur l'Accueil).
- **Les tuiles** : l'icône de la section dans sa couleur et son nom (13 points), la valeur (15 points), une ligne de
  détail (13 points), un nombre en haut à droite pour Calendrier (les rendez-vous qui restent aujourd'hui). La carte de
  l'app, `.cardHover` au survol ; un clic ouvre la page puis la fenêtre (⌘1 à ⌘7 dans l'ordre de la barre latérale, les
  mêmes que dans la fenêtre). Les deux valeurs partent du même haut ; sans ligne de détail dessous, une valeur prend deux
  lignes. **Calendrier** : le prochain rendez-vous, son titre puis son heure (« 16:30 – 17:00 ») ; « Ensuite à 17:30 »
  sous celui que montre la vedette ; son titre seul, entier, sous « Libre jusqu'à 16:30 ». **Mails** : « 5 nouveaux » et
  les prénoms des derniers expéditeurs, le nombre seul quand la carte des mails les liste.
- **« À régler »** : dessinée comme les bandeaux de l'app (`Banner`) : la carte calme du panneau, seule l'icône porte la
  couleur d'attention, le titre en 13 points semi-gras, le détail en gris ; une ligne par cause, trois au plus, la plus
  risquée pour les enregistrements d'abord (alertes, compte Google à reconnecter, mise à jour en échec ou en attente de
  Paul) ; le détail de chaque cause sur deux lignes au plus. Une erreur de réseau n'y va jamais. Une version qui attend
  la fin d'une réunion est une ligne grise du pied.
- **Les nouveaux mails** : une carte sans en-tête, sous la tuile Mails qui les compte ; les non-lus de la Boîte de
  réception (jamais Notifications), ceux d'un projet d'abord (le point à sa couleur), puis les contacts connus, puis les
  autres ; trois au plus, puis « Voir les N autres », qui compte tous ceux qu'elle ne montre pas. Au survol, « Marquer
  comme lu » se pose sur l'heure, sur la ligne de l'expéditeur, sans rien décaler ni couvrir l'objet. Cachée pendant
  une réunion.
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
  titre, « Dans 2 min · Google Meet » à la seconde, « Rejoindre » plein à l'encre (la couleur du compte reste dans son
  rond), la croix. Elle se lit comme Coup d'œil (lot 9, 20/11 ; `FloatingMetrics`) : le titre en 15 points semi-gras,
  sa ligne en 13, à 16 du bord ; « Rejoindre » est le bouton principal de l'app (`.primary`, dessiné à la main : le
  panneau ne prend jamais la main, un bouton proéminent du système y deviendrait gris), la croix un `IconButton`.
- **Elle reste** jusqu'à « Rejoindre » ou la croix, dix minutes après le début au plus ; jamais pour la réunion que
  Polhub enregistre déjà. Réglages › Notifications : activée, 2 min avant (1, 2 ou 5).
- **Le HUD** (la réunion détectée, un message, une alerte) flotte dans le même panneau et parle de même : son titre en
  15 points semi-gras (deux lignes au plus), sa ligne en 13 (deux lignes au plus), à 16 du bord ; 480 points de large
  (440 avant) et la hauteur de ses mots, de 76 à 120 (lot 9, 20/11 : « Google Meet · Rev… » et « Polhub ne lit plus
  les ongl… » étaient coupés).

## Inspiration

Les trois bases d'idées de Paul (dossier `MeetingsUI/Inspiration`, 16/11), reprises de son ancien coffre Obsidian,
puis nourries par la collecte et ses ajouts. La logique vit à part, testée sans écran (`InspirationBrowse`,
`InspirationLibrary`).

- **Dans la barre latérale** : « Inspiration » (ampoule, jaune), une seule rangée, après Mails (⌘6). Ses trois pages,
  « Websites », « Branding », « Mock-ups », sont un contrôle segmenté au centre de sa barre d'outils, comme « Kanban |
  Liste » dans Projets (lot 4, 19/11).
- **Une page** : la barre d'outils (« Inspiration », puis la page et son nombre de fiches, « Websites · 12 sites », ou
  « 4 sites sur 212 » quand un filtre agit ; les trois pages ; « + » ; recherche), puis une ligne de pastilles par
  famille de catégories, le nom de la famille à gauche, « Tout » en
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
- **Une fiche ouverte** prend la place de la grille, avec un chevron de retour (comme un projet) : son titre en 26 points
  (lot 8), grande image (les
  images d'un post côte à côte, à leurs proportions), les liens en boutons secondaires (« Ouvrir le site », « Voir sur
  LinkedIn », « Ouvrir le dossier » : le Finder si le dossier est sur le Mac, sinon son lien Nextcloud), les autres
  liens du post, le texte (860 points au plus), polices et client, puis les catégories : un clic sur une famille ouvre
  le vocabulaire, chaque valeur cochée ou non. Corrigées par Paul, elles sont à lui : ni la collecte ni l'IA n'y
  touchent plus. « Supprimer » est dans « … », avec « Annuler » en bas de la page (⌘Z), comme dans Mails.
- **Une page vide** : une ligne et le bouton de son « + » (« Ajouter un site », « Ajouter une page LinkedIn »,
  « Ajouter un mock-up »).
- **Réglages › Inspiration** : les pages LinkedIn (nom, lien, couleur ; ajouter, modifier, ne plus suivre) avec leur
  dernière lecture en clair ; « Collecte automatique » et l'état de chaque lieu lu ; « Catégories par l'IA d'Apple ».
  L'import du coffre est parti avec le coffre (16/11).

## Les pages : Projets, Réunions, Calendrier, Contacts

Lot 8 du plan d'affinage (19/11). Une page sans objet ouvert n'a que son titre de fenêtre (le mot de la barre
latérale) ; un objet ouvert (un projet, une réunion, un contact, une fiche) a son titre en 26 points gras, ses cartes à
20 points de marge et 16 entre elles.

- **Le Kanban, « teinte allégée »** (choix de Paul du 19/11) : une carte garde la couleur de son projet, à moitié
  (6,5 % en clair, 11 % en sombre, `ProjectViews.cardTint`), avec sa bande à gauche et son logo ; son contour est celui
  de toute carte. **Tous ses textes sont à la couleur du texte** : le nom, la tâche du moment, le prochain rendez-vous en
  semi-gras, l'échéance lointaine et la dernière réunion en gris ; « En retard de 2 j » et « Échéance aujourd'hui » en
  semi-gras, leur couleur (retard, attention) sur leur drapeau seulement (`ProjectViews.cardFacts`). **Les colonnes
  n'ont plus de fond** : leur statut est dans le point de leur titre ; sous une carte qu'on glisse, le fond de ce qui
  est choisi (`ProjectViews.columnFill`).
- **Les statuts** (Liste, page d'un projet) : une pastille neutre et son point ; « Terminé » à la couleur de ce qui est
  fait, avec sa coche (`StatusChip`).
- **Une réunion** se lit dans la colonne de lecture d'un fil, au milieu (`readingColumn()`), à 16 points sous la barre ;
  le lecteur flotte sur les bords de cette colonne ; les tours de parole sont au bord de la page, sous
  « Transcription ». **L'audio qui ne se lit pas le dit en français**, en une ligne (`AudioProblemLine`) :
  « L'audio de cette réunion est introuvable : son dossier est incomplet. », « … ne se lit pas : un de ses fichiers est
  abîmé. », « … ne se lit pas. » ; le texte du système (anglais, nom de fichier) attend sous « Détails ».
- **Le Calendrier** s'ouvre sur l'heure de Réglages › Calendrier avec de l'air au-dessus de son étiquette, qui monte de
  6 points sur sa ligne : « 08 h » se lit entier (`CalendarView.openingOffset`).
- **Contacts** : sans contact choisi, « Choisis un contact dans la liste. » ; les projets d'une personne en pastilles
  neutres avec leur point, comme « Dans « P » » dans la bulle d'un rendez-vous.

## Les réglages

- Chaque fonction range ses réglages dans **Réglages**, dans sa famille (Calendrier, Projets, Réunions…),
  comme les réglages d'Apple : la liste des familles, puis une page par famille, avec un retour (Paul, 14/11 ; pas deux
  colonnes, confirmé le 19/11).
- **Les familles suivent la barre latérale** (lot 7, 19/11), calculées depuis sa liste (`SettingsPane.families`) :
  Colin (la famille de l'Accueil, où il vit), Projets, Réunions, Calendrier, Mails, Inspiration ; puis ce qui vaut
  pour toute l'app : Comptes Google, Notifications, Mises à jour, Général. Diagnostic et Journal ne sont pas des
  familles : deux lignes en bas de Général (`SettingsPane.lines`). Leur ‹ revient d'un pas, là d'où ils ont été
  ouverts : Général, ou la page qui a demandé le Diagnostic ; ouverts d'emblée (premier lancement), Général
  (`WindowRouter.closeSettings()`).
- **Une page** : le formulaire groupé du système, à une seule largeur, 640 points (`settingsForm()`,
  `SettingsMetrics.width`), liste des familles comprise ; elle commence sous la barre d'outils (`belowToolbar()`).
- **Un réglage** (`SettingRow`) : son titre, sa phrase d'aide juste dessous, dans sa carte (`SettingHelp`, `.meta`
  gris), son contrôle à droite (un interrupteur reste un interrupteur). Une ligne, deux au plus
  (`SettingHelp.longest`, 110 caractères) ; aucune quand le titre dit tout ; jamais un paragraphe sous une carte. Le
  détail long (ce qui quitte le Mac, les règles exactes) est derrière « ⓘ », une bulle (`InfoBubble`). Ce qui empêche
  le réglage de marcher prend la place de l'aide (`ErrorLine`).
- **Plusieurs choix à la fois** : un menu à coches, dit comme les autres listes de la page (« Rappels   10 et 1 min
  avant »).
- **Un geste rare qui ne se rattrape pas** (« Déconnecter… » un compte Google) : dans le menu « … » de sa ligne, avec
  sa question.
- **Un réglage, une seule garde** : l'ouverture à la session et la relance passent partout par `StartupControl`
  (`StartupSwitch`, dans Général et dans le Diagnostic) : elles attendent la fin d'une réunion et demandent avant de
  fermer Polhub.
- **Ce qui quitte le Mac se dit là où on le choisit** : ce que Colin lit pour répondre part chez Anthropic
  (Réglages › Colin) ; « Les mails de tes projets », pour les agents, est une préférence, pas une barrière : une
  session qui a un terminal peut la changer (Réglages › Mails ; audit de sécurité du 19/11, M6 et M8).
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
POLHUB_LIVE=1 POLHUB_SNAPSHOTS=/tmp/captures swift test --filter NotificationCenterScreenTests  # la cloche
POLHUB_LIVE=1 POLHUB_SNAPSHOTS=/tmp/captures swift test --filter MeetingCardScreenTests  # la carte avant une visio, le HUD
POLHUB_LIVE=1 POLHUB_SNAPSHOTS=/tmp/captures swift test --filter InspirationScreenTests  # Inspiration, données inventées
POLHUB_LIVE=1 POLHUB_SNAPSHOTS=/tmp/captures swift test --filter HomeScreenTests         # l'Accueil, données inventées
POLHUB_LIVE=1 POLHUB_SNAPSHOTS=/tmp/captures swift test --filter SettingsScreenTests     # Réglages, chaque page, clair et sombre
POLHUB_LIVE=1 POLHUB_SNAPSHOTS=/tmp/captures swift test --filter PagesScreenTests        # Projets, Réunions, Calendrier, Contacts, Inspiration
```

Une suite à la fois : lancées ensemble, les captures ont laissé des corps de mails vides (19/11).

Les fenêtres de test ne deviennent jamais actives (aucune touche ne doit les atteindre) : un bouton en verre y
paraît gris, ce qui est la raison de la règle « jamais de verre dans le contenu ». Un bouton `.primary` garde son
encre.

La fenêtre se pose sous toutes les autres, juste au-dessus du fond d'écran, sans jamais passer devant le travail en
cours (19/11), puis le système prend son image seule (il faut l'autorisation d'enregistrement de l'écran pour le
terminal). Hors de tout écran, rien ne se dessine : elle reste donc sur un écran, en dessous.

**Le garde-fou** (`DesignGuardTests`) compte dans le code de l'interface ce qui doit disparaître : `Color.accentColor`,
les rayons écrits à la main, les boutons en verre hors des barres et des panneaux, les tailles de texte écrites à la
main, les textes mis en capitales. Le nombre ne peut que baisser : un lot qui en retire abaisse le plafond.
