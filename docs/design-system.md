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
- **La barre latérale** est une `List` native (sa sélection et son verre sont ceux du système, jamais de verre
  ni de fond ajouté sur une rangée) : de grandes rangées (`sidebarRowSize` `.large`), le symbole de chaque
  section dans sa couleur (`listItemTint`), un nombre à droite quand il sert (mails non lus, rendez-vous qui
  restent aujourd'hui), un point rouge sur Réunions pendant un enregistrement. Réglages est en bas, dans une
  liste à lui, dessiné et sélectionné comme les autres rangées.

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

- Une seule palette (`Palette`) pour les comptes Google, les projets et les statuts.
- La couleur d'un **compte** marque ses rendez-vous (et « Rejoindre », sur la ligne du prochain rendez-vous de l'Accueil) ;
  celle d'un **statut** marque les colonnes du Kanban (un point, un fond très léger) ; celle d'un **projet**
  teinte sa carte (≈ 14 % en clair, 22 % en sombre, un trait plus franc à gauche), et marque son logo, sa
  pastille dans les mails, son point dans Contacts : une seule source, `ProjectViews.tint(_:)`.
- Chaque **section** a sa couleur, la même dans la barre latérale et dans Réglages : Accueil sarcelle, Projets
  bleu, Réunions violet, Calendrier orange, Mails rose, Contacts vert, Inspiration jaune, Réglages gris.
- La couleur d'accent du système reste celle de la sélection et de « Moi » dans les transcriptions.
- Rouge pour le retard, orange pour aujourd'hui et pour ce qui est à vérifier, jamais pour décorer.

## Les composants

| Composant | Usage |
|---|---|
| `Page { }` | Une page qui défile, à la bonne largeur et aux bonnes marges |
| `PageHeader("Titre", subtitle:)` | Le titre d'une page qui en a besoin (la page d'un projet) |
| `Card { }` | Une surface de contenu ; `.cardSurface()` pour une vue existante |
| `SectionTitle("Titre", systemImage:, count:) { trailing }` | Le titre d'une carte ou d'une partie |
| `Chip("Texte", systemImage:, tint:)` | Un statut, une date, une étiquette |
| `Avatar(initiales, size:)` | Une personne |
| `ColorDot(couleur)` | Un compte, un statut, un projet |
| `FloatingBar { }` | Des commandes flottantes en bas d'une page, en verre |
| `.windowTitle(_:subtitle:)` | Le titre de la fenêtre |
| `TextButton("Modifier") { }` | Un mot à cliquer dans une carte (« Modifier », « Changer », « Tout enregistrer… ») : sa capsule au survol, son texte aligné sur la carte |
| `RowButton { ligne }` | Une ligne cliquable d'une carte (Accueil, page d'un projet, Contacts) : toute la largeur répond, le fond déborde sans décaler le texte |
| `IconMenu("ellipsis", help: "Plus") { }` | Un menu derrière une icône ronde, dessiné comme `IconButton` |
| `NotificationBell(inbox:perform:)` (module `MeetingsUI`) | La cloche des notifications : le nombre de nouvelles en pastille rouge ; un clic ouvre le panneau (popover en verre) : cartes calmes à la couleur de leur section, par jour, les rafales en pile, un point bleu tant qu'elles sont nouvelles, × au survol ou glissé pour en effacer une, « Tout effacer » |
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

- L'action principale d'un écran ou d'une fiche : `.buttonStyle(.glassProminent)`, teintée si la couleur
  a un sens (« Rejoindre » prend la couleur du compte).
- Une action secondaire visible : `.buttonStyle(.glass)`.
- Dans une liste ou une carte : `.buttonStyle(.hover)` (ou `IconButton` pour une icône), qui reste discret au
  repos et répond au survol et à l'appui ; plus de `.borderless` ni de `.plain` sans retour.
- Une ligne qui est un bouton : `.buttonStyle(.row)` (ou `RowButton`) ; une ligne pleine largeur d'une liste à
  la Gmail (les brouillons) : `LineButtonStyle(ground:)`.
- Dans une capsule de verre (le lecteur, les gestes d'un fil ouvert), des `IconButton` : pas de verre sur le
  verre.

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

- **Deux colonnes** à partir de 760 points de contenu (`HomeLayout`) : à gauche la colonne de Colin (ce qui est fait,
  où on en est), à droite les listes (ce qui attend), larges de 360 points. En fenêtre étroite, les listes passent
  au-dessus, la colonne de Colin dessous. Pas de grand titre : la fenêtre s'appelle « Accueil ».
- **« Le point »** (`BriefingCard`) : quatre phrases au plus, en deux colonnes (de quoi la phrase parle en gris, ce
  qu'elle dit en 15 points), avec le jour et l'heure où il a été préparé (« mardi 9:04 »). Il se prépare à un retour
  de Paul (première présence du jour, ou trois heures après), jamais à chaque affichage.
- **« À valider »** (`ReviewCard`) : une phrase et un bouton par ligne. Le symbole de la sorte de ligne à gauche (celui
  d'un brouillon prêt dans la couleur d'accent), la phrase en `.rowTitle`, le projet et les jours dessous en `.meta`,
  puis le mot à cliquer (`TextButton` : « Relire », « Ouvrir », « Ranger ») et, pour une ligne qui peut s'écarter, un
  menu « … ». Un clic sur la ligne fait la même chose que son mot, sauf pour une réunion : il l'ouvre, et « Ranger »
  propose les projets. Cinq lignes, puis « Voir les N autres ». Une ligne part seule quand la chose est faite ;
  écartée ou rangée à la main, elle part tout de suite.
- **Une ligne par personne, une ligne par projet** (`ReviewRules`) : « attend ta réponse » se lit sur l'échange avec
  la personne dans tous les fils et toutes les boîtes (`Exchanges`), « ne répond plus » sur le projet entier. Lues
  fil par fil, ces deux lignes parlaient dix fois trop : on répond dans un nouveau mail aussi souvent que dans le fil.
  Écarter une ligne vaut donc pour la personne ou pour le projet.
- **« Aujourd'hui »** (`TodayCard`) : ce qui reste de la journée. Le prochain rendez-vous dit « dans 40 min » ou « en
  cours » et porte « Rejoindre » en `.glassProminent` à la couleur de son compte ; les autres gardent l'icône. S'il ne
  reste rien, le rendez-vous suivant avec son jour (« Demain 10:00 »).
- **Un brouillon ou un fil s'ouvre par-dessus l'Accueil** (`mailPanels`, les mêmes panneaux que dans Mails) : on
  relit, on envoie, on ferme, et la ligne suivante est là. « Précédent » referme.
- **La colonne de Colin** (`ColinHome`, 18/11) : en tête, « Colin » avec un point vert et « en marche », et
  « Mettre à l'arrêt » (`TextButton`) ; puis « Le point », puis le fil (`ColinThreadView`), par jour (« Aujourd'hui »,
  « Hier », « lundi 16 novembre », en `.meta` gras gris, centrés). Les questions de Paul à droite, sur `Surface.fill`
  en `.rowBody` ; les réponses de Colin à gauche, en clair, en `.rowTitle`. Un message à copier est une carte avec
  « Copier » ; une ligne à garder, en gris avec « Garder » ; un brouillon de la réponse, une ligne avec « Relire ».
  Ce que Colin fait pendant qu'il répond (« Colin lit tes mails… ») et la fin d'une réponse (« Arrêté : … ») en
  `.meta` gris. **Un lien écrit par Colin n'est jamais cliquable** (`ColinAnswer.inline`) : son adresse s'écrit en
  clair.
- **La barre de Colin** (`ColinComposer`) : un champ qui grandit (une à huit lignes) dans une `FloatingBar` de verre
  au rayon `Radius.hero`, ↑ pour envoyer (`IconButton`, ⌘↩ quand le champ a le focus), le carré d'arrêt pendant une
  réponse. En deux colonnes, chaque colonne défile seule et la barre reste sous celle de Colin ; en fenêtre étroite,
  elle flotte en bas de la page. À l'arrêt, « Allumer Colin » (`.glassProminent`) prend sa place ; pendant un call,
  le champ est grisé : « Colin attend la fin de ton call ». Le bandeau d'un envoi de mail reste au-dessus.
- **Rien n'est dit deux fois** : ce que disaient l'ancien titre daté, la carte du prochain rendez-vous, « Priorité 2 »,
  « Dernières réunions » et « À classer » est dans « Le point », « Aujourd'hui » et « À valider ».

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
- **Mesures** : 360 points de large, marges de 14, écarts de 10 ; tuiles de 161 × 80 (rayon 16), vedette de rayon 22 et
  de 90 à 130 points de haut, jamais écrasée sous son contenu (une exception : « Réunion détectée » avec un lien Meet, les cinq lignes de la maquette,
  environ 146 points pendant ses 10 secondes) ; hauteur selon le contenu, au plus 640 points (ou l'écran moins 40).
  Le panneau prend toujours sa hauteur entière (`fixedSize`) : souple, il laissait la fenêtre de la barre des menus
  garder une hauteur plus ancienne, et les boutons de la vedette débordaient sur les tuiles (16/11).
  Au-delà, seule la carte des mails cède, par lignes entières (jamais un mail coupé à travers son objet) : les mails
  qui tiennent, puis son seul en-tête avec « Voir les N nouveaux » ; si même cela ne tient plus, elle part et la tuile
  Mails garde le nombre.
- **La vedette** montre la première situation vraie, dans cet ordre : réunion détectée (le même décompte que le HUD),
  enregistrement (rouge, l'horloge), fin présumée (orange), rendez-vous dans 15 min ou Meet commencé sans
  enregistrement (couleur du compte), détection suspendue (gris), compte rendu en préparation ou prêt depuis moins de
  2 h (violet), sinon la journée (« Libre jusqu'à 16:30 », « Plus rien aujourd'hui »). Une carte calme teintée à 10 %
  (16 % en sombre), titre en 17 points, horloge en 22 points à chiffres fixes ; une action principale en
  `.glassProminent` (↩), au plus une secondaire en `.glass`, de taille normale. Elle change en fondu (`Motion.gentle`).
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
- **« À régler »** : une carte orange calme, une ligne par cause, trois au plus, la plus risquée pour les
  enregistrements d'abord (alertes, compte Google à reconnecter, mise à jour en échec ou en attente de Paul) ; le
  détail de chaque cause sur deux lignes au plus. Une erreur de réseau n'y va jamais. Une version qui attend la fin
  d'une réunion est une ligne grise du pied.
- **« Nouveaux mails »** : les non-lus de la Boîte de réception (jamais Notifications), ceux d'un projet d'abord (le
  point à sa couleur), puis les contacts connus, puis les autres ; trois au plus, puis « Voir les N autres », qui
  compte tous ceux qu'elle ne montre pas. Au survol, « Marquer comme lu » se pose sur l'heure, sur la ligne de
  l'expéditeur, sans rien décaler ni couvrir l'objet. Cachée pendant une réunion.
- **Les boutons ronds** : 44 points de verre, leur nom en 12 points dessous, pleins de leur couleur quand ils sont
  allumés (Reprendre orange, comme le Reprendre de la vedette). Enregistrer ne sert qu'au repos : une réunion détectée
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
  titre, « Dans 2 min · Google Meet » à la seconde, « Rejoindre » plein à la couleur du compte (le panneau ne prend
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
POLHUB_LIVE=1 POLHUB_SNAPSHOTS=/tmp/captures swift test --filter "WindowSnapshotTests|MailScreenTests/theMailScreens|PeopleScreenTests"
POLHUB_LIVE=1 POLHUB_SNAPSHOTS=/tmp/captures swift test --filter CoupDoeilScreenTests   # Coup d'œil et le logo
POLHUB_LIVE=1 POLHUB_SNAPSHOTS=/tmp/captures swift test --filter InspirationScreenTests  # Inspiration, données inventées
POLHUB_LIVE=1 POLHUB_SNAPSHOTS=/tmp/captures swift test --filter HomeScreenTests         # l'Accueil, données inventées
```

Les fenêtres de test ne deviennent jamais actives (aucune touche ne doit les atteindre) : les boutons
`.glassProminent` y restent gris au lieu de prendre leur couleur.

La fenêtre s'affiche un instant, puis le système la capture (il faut l'autorisation d'enregistrement de
l'écran pour le terminal).
