# Ce qui a changé

Chaque version publiée a sa section ; `scripts/release.sh` la reprend pour la page de la version sur
GitHub, et l'app la montre dans Réglages › Mises à jour.

## 0.30.1 — 17 novembre 2026

**Des corrections sur la barre fixe des brouillons.**

- Quand un fil a deux réponses en cours, la barre fixe en bas suit celle que tu écris. Avant, elle pouvait viser
  l'autre, et « Envoyer » serait parti sur le mauvais brouillon. Les réponses gardent aussi leur place pendant que
  tu tapes.
- Le bandeau « Mail envoyé » s'affiche au-dessus de la barre, sans en cacher les boutons.
- La page suit le curseur aussi quand tu gardes une flèche enfoncée ou que tu fais ⌘↓.

## 0.30.0 — 17 novembre 2026

**Écrire un long mail : la page défile, la barre reste en bas.**

- La molette fait de nouveau défiler la page quand le pointeur est sur le texte d'un mail : nouveau mail, brouillon,
  réponse.
- « Envoyer », « Joindre » et la mise en forme sont réunis dans une barre fixe en bas du panneau ou de la page du fil.
  Elle reste à portée de main même tout en bas d'un long mail.
- Quand tu tapes en bas d'un long mail, la page suit : la ligne en cours reste visible au-dessus de la barre.

## 0.29.0 — 17 novembre 2026

**Écrire un mail mis en forme, comme dans Gmail.**

- Le texte d'un brouillon s'écrit maintenant avec sa mise en forme : gras, italique, souligné, listes à puces et
  numérotées, liens. Une petite barre de boutons au-dessus du texte, et les raccourcis de Gmail : ⌘B, ⌘I, ⌘U, ⌘K
  pour un lien.
- Un brouillon préparé par un agent avec de la mise en forme s'ouvre tel qu'il partira, et tu le modifies sans la
  perdre. « Repasser en texte simple » disparaît : il n'y en a plus besoin.
- Un brouillon écrit dans Gmail avec de la mise en forme s'ouvre lui aussi dans l'éditeur, prêt à modifier ; seul
  un brouillon avec des images ou des tableaux garde son texte à part, tel quel, sous ce que tu ajoutes.
- Un texte collé depuis une page web ou un document garde son gras, ses listes et ses liens, sans ses couleurs ni ses
  polices.

## 0.28.0 — 16 novembre 2026

**Tes agents font presque tout par Polhub, et Polhub ne dépend plus d'Obsidian.**

Ce que tes agents Claude Code savent faire en plus, par le MCP de Polhub :

- **Joindre des fichiers à un brouillon**, seulement quand tu le leur demandes : 10 fichiers et 25 Mo au plus, jamais
  un fichier caché, un trousseau ni ta Bibliothèque (iCloud Drive et les Drive restent permis). Ils apparaissent
  dans le brouillon comme ceux que tu joins.
- **Écrire un brouillon mis en forme** : gras, italique, listes, liens. C'est Polhub qui fabrique le mail, jamais
  l'agent. Le brouillon l'indique, et « Repasser en texte simple » te le rend modifiable (« Remettre la mise en
  forme » revient en arrière).
- **Ranger un fil** dans un projet, Perso, Newsletters, Paiements ou Services, sans rien apprendre de l'expéditeur.
- **Lire ton agenda** (avec la date de la dernière lecture de tes calendriers) et **créer un rendez-vous**, avec un
  lieu et un Meet si besoin, marqué « préparé par un agent ». Jamais d'invité : un agent n'invite personne.
- **Retrouver un contact** : adresses, téléphone, entreprise, projets.
- **Créer un projet**, changer son client et ses notes (l'ancienne version des notes reste dans le journal du
  projet), lier ou retirer un contact.
- **Chercher dans Inspiration** (sites, branding, mock-ups) et voir une fiche avec son image.

Polhub sans Obsidian :

- Les imports du coffre (l'historique, les projets, Inspiration) et le choix du dossier du coffre disparaissent de
  Réglages : le coffre est supprimé. Rien de ce qui a été importé ne change.
- Une page de projet ouverte suit les changements faits par un agent pendant qu'elle est à l'écran.
- La page de confidentialité dit qu'un assistant peut créer un rendez-vous à ta demande.

Les sessions Claude Code déjà ouvertes gardent l'ancien MCP : relance-les (ou `/mcp`, « Reconnect »).

## 0.27.0 — 16 novembre 2026

**Tes agents lisent les pièces jointes de tes mails.**

- Un nouvel outil `piece_jointe` dans le MCP de Polhub : une capture d'écran ou une photo est montrée à l'agent, un
  PDF ou un fichier texte lui donne son contenu, un autre fichier (Word, Excel…) son emplacement sur le Mac.
- Les images collées dans le texte d'un mail, comme les captures d'écran, comptent aussi ; les logos et les
  signatures non.
- Une pièce pas encore sur le Mac est téléchargée par Polhub en quelques secondes : l'app doit être ouverte. Le
  programme des agents, lui, n'a toujours aucun accès au réseau.
- Les sessions Claude Code déjà ouvertes gardent l'ancien MCP : relance-les (ou `/mcp`, « Reconnect »).

## 0.26.0 — 16 novembre 2026

**Les brouillons écrits dans Gmail, corrigés.**

- Un brouillon écrit dans Gmail avec de la mise en forme (gras, listes, liens), comme ceux qu'écrivaient tes agents
  avec l'ancien MCP, montre maintenant tout son texte dans Polhub. Il n'est plus replié dans un « Message cité ».
- Un brouillon envoyé ou supprimé depuis Gmail, sur le web ou le téléphone, disparaît aussi de Polhub. S'il avait
  changé dans Polhub entre-temps, Polhub te demande quoi en faire.
- Supprimer un brouillon que Gmail n'a plus ne finit plus en « Google a répondu 500 ».

## 0.25.0 — 16 novembre 2026

**Tes agents Claude Code peuvent changer un projet quand tu le leur demandes.**

- Un nouvel outil `projet` dans le MCP de Polhub : le statut (priorité 2, priorité 1, en pause, terminé),
  l'échéance et la tâche du moment d'un projet. Seul ce que tu demandes change, et la réponse dit quoi.
- L'outil `action` corrige le texte d'une action ouverte, ou la retire quand elle n'a plus lieu d'être.
- Les sessions Claude Code déjà ouvertes gardent l'ancien MCP : relance-les (ou `/mcp`, « Reconnect ») pour avoir
  les nouveaux outils.

## 0.24.0 — 16 novembre 2026

**Précédent et Suivant, partout dans la fenêtre.**

- Les boutons latéraux de la souris reviennent en arrière et repartent en avant, comme dans un navigateur : d'une
  réunion à l'autre, d'un fil de mails à la liste, d'une fiche d'Inspiration à sa page, d'une section à l'autre.
- Les mêmes gestes au clavier (⌘[ et ⌘], ou ⌘← et ⌘→ quand tu n'écris pas) et au trackpad (balayer entre les pages).
- Rien de plus à l'écran : pas de bouton, seulement les gestes que tu utilises déjà.

## 0.23.0 — 16 novembre 2026

**Inspiration au propre.**

- **Une seule barre de recherche**, en haut à droite de chaque page. Tape « minimal », « tech » ou le nom d'une
  page LinkedIn suivi d'un espace : ça devient un filtre, posé dans la barre, que tu retires d'un clic. En cours de
  frappe, la barre propose les catégories qui commencent par ce que tu tapes, avec leur nombre de fiches. Les rangées
  de pastilles disparaissent.
- **Des titres propres** : « Adam Bricker - Home » s'affiche « Adam Bricker », « Home - ADA » s'affiche « ADA », et
  les posts perdent l'emoji de tête. Les titres d'origine restent dans la base.
- **Awwwards est de nouveau lu** : Polhub se présentait comme Chrome, et le filtre anti-robots d'Awwwards le
  refusait (erreur 403). Il se présente maintenant comme Safari.
- **Les catégories de l'IA d'Apple ne s'emballent plus** : une réponse a 45 secondes au plus (le modèle tournait
  parfois six minutes sur un seul post), dix fiches toutes les cinq minutes, jamais pendant une réunion.

## 0.22.0 — 16 novembre 2026

**Exporter une réunion en Markdown, pour l'envoyer.**

- Un bouton « Exporter » en haut de la page d'une réunion écrit un fichier .md, à l'endroit que tu choisis
  (Téléchargements par défaut), nommé « 2026-11-16 Titre de la réunion.md ».
- Une seule page, propre : le titre, la date et la durée, les participants, puis le compte rendu (résumé, points
  clés, décisions, actions avec leurs cases) et la transcription, par prise de parole, avec l'heure. « Moi » y
  devient ton prénom, puisque la page part chez d'autres.
- Inspiration : les vignettes en mémoire suivent une règle simple, les moins récemment vues partent d'abord, et tout
  se libère quand macOS manque de mémoire.

## 0.21.0 — 16 novembre 2026

**Une carte qui reste à l'écran avant une visio.**

- Deux minutes avant un rendez-vous avec Meet, une carte apparaît en haut à droite de l'écran, au-dessus de toutes
  les apps et sur tous les bureaux : le titre, « Dans 2 min », puis « Maintenant », et un bouton « Rejoindre » à la
  couleur du compte, qui ouvre le Meet dans Dia avec le bon compte.
- Contrairement aux notifications de macOS, elle ne part pas seule : elle reste jusqu'à ce que tu rejoignes ou la
  fermes avec la croix, dix minutes après le début au plus. Rien pour la réunion que Polhub enregistre déjà.
- Réglages › Notifications : activée, 1, 2 ou 5 minutes avant.

## 0.20.0 — 16 novembre 2026

**Inspiration : tes sites, ton branding et tes mock-ups quittent Obsidian.**

- Une nouvelle entrée « Inspiration » dans la barre latérale, avec trois pages : Websites, Branding, Mock-ups. Une
  grille de cartes, les plus récentes d'abord, une rangée de filtres par famille de catégories et la recherche.
- Un clic ouvre la fiche : les images, les liens (le site, le post LinkedIn, le dossier du mock-up), le texte, et les
  catégories, que tu corriges d'un clic. Une catégorie corrigée reste la tienne.
- **L'import du coffre**, dans Réglages › Inspiration : il lit les fiches, les images et les catégories sans rien
  changer au coffre, et peut lire aussi l'ancienne copie où n8n écrit encore. Relancé, il n'ajoute que ce qui
  manque. Les images sont allégées, et il s'arrête avant de dépasser 1 Go.
- **La collecte se fait dans Polhub**, sans compte ni cookie : le site du jour d'Awwwards toutes les 2 heures de 8 h
  à 22 h, les pages LinkedIn que tu suis à 9 h, 14 h et 20 h, et au réveil du Mac. Le « + » de chaque page ajoute un
  site, une page LinkedIn ou un mock-up.
- Les fiches sans catégories en reçoivent de l'IA d'Apple, sur le Mac, dans le vocabulaire du coffre.
- Pendant une réunion, rien de tout ça ne tourne : la collecte, les catégories et l'import attendent la fin.

## 0.19.1 — 16 novembre 2026

**Coup d'œil : le compte rendu se range.**

- Une petite croix en haut de la carte « Résumé prêt » (ou « Compte rendu en cours ») la retire du panneau pour de
  bon ; la journée revient à sa place.
- Elle part aussi d'elle-même dès que tu ouvres la réunion dans Polhub une fois transcrite : un compte rendu déjà lu
  ne reste pas en avant.

## 0.19.0 — 16 novembre 2026

**Coup d'œil allégé : rien n'y est dit deux fois.**

- Deux tuiles au lieu de quatre : Calendrier et Mails. La tuile Réunions redisait la carte du haut, la tuile Projets
  donnait un nombre qui ne servait à rien.
- Trois boutons ronds au lieu de quatre : Enregistrer, Nouveau mail, Suspendre. Le bouton Rendez-vous part.
- « Arrêter » n'est plus que dans la carte du haut, à côté de la réunion ; le bouton rond Enregistrer reste à sa
  place, grisé pendant une réunion.

## 0.18.1 — 16 novembre 2026

**Coup d'œil, deux corrections.**

- La carte du haut ne déborde plus sur les tuiles : pendant un enregistrement, « Voir la réunion » et « Arrêter »
  passaient sur le Calendrier et les Mails. Le panneau prend toujours sa hauteur entière.
- Un expéditeur écrit « Nom, Prénom » apparaît par son prénom dans la tuile Mails, sans virgule en trop.

## 0.18.0 — 16 novembre 2026

**Coup d'œil : le menu de la barre des menus devient un vrai panneau.**

- Un clic sur le logo ouvre un panneau en verre, construit comme le Centre de contrôle, qui dit d'un regard où
  tu en es :
  - **en haut, la situation du moment** : réunion détectée (avec le même décompte que la petite fenêtre),
    enregistrement en cours et son horloge, fin présumée, rendez-vous dans le quart d'heure avec « Rejoindre »,
    détection suspendue, compte rendu en préparation ou prêt, sinon ta journée (« Libre jusqu'à 16:30 ») ;
  - **quatre tuiles** : Calendrier, Mails, Réunions, Projets ; un clic ouvre la page dans Polhub ;
  - **les nouveaux mails** : les non-lus de la Boîte de réception, ceux de tes projets d'abord, trois au plus,
    à marquer comme lus au survol ; cachés pendant une réunion ;
  - **quatre boutons ronds** : Enregistrer ou Arrêter, Nouveau mail, Rendez-vous, Suspendre ou Reprendre ;
  - **« À régler »**, seulement quand quelque chose menace un enregistrement ou demande ton geste (onglets de Dia
    illisibles, disque presque plein, compte Google à reconnecter…) ;
  - en bas : Ouvrir Polhub, la cloche des notifications, Réglages et « ⋯ ».
- Au clavier : ↩ pour l'action principale, J pour rejoindre le Meet, ⌘N pour un nouveau mail, ⌘1 à ⌘6 pour les
  pages. Arrêter un enregistrement se fait toujours au clic.
- **Le logo est plein** : plein, Polhub guette tes réunions ; en contour, la détection est suspendue ; rouge, il
  enregistre.
  - « 8 min » s'affiche à côté du logo dans le quart d'heure avant un Meet (à couper dans Réglages › Général).
  - Une pastille sur le coin signale un enregistrement menacé, et part seule quand la cause disparaît.
- L'alerte de disque presque plein suit l'espace libre pendant une réunion, et revient si le disque se remplit
  de nouveau.

## 0.17.2 — 15 novembre 2026

**Le bas de la barre latérale, plus propre.**

- Réglages et la cloche des notifications sont sur une même ligne, bien alignés, la cloche avec la même icône
  que le reste de la barre ; son nombre reste dans la barre.
- Le trait qui les sépare du reste est remonté, avec de l'air au-dessus et en dessous ; les lignes de la liste
  ne passent plus dessous en transparence.

## 0.17.1 — 15 novembre 2026

**Tes retours sur la 0.17.0.**

- **Projets**
  - Priorité 2, la plus urgente, est à gauche du Kanban, puis Priorité 1, En pause et Terminé. La carte de
    l'Accueil montre désormais tes projets en Priorité 2.
  - Les quatre colonnes ont la même largeur et prennent toute la place de la fenêtre.
  - Les cartes sont plus grandes et plus lisibles : le nom sans le client, la prochaine chose à faire mise en
    avant, puis en toutes lettres le prochain rendez-vous (« RDV demain à 14:00 »), l'échéance (« Échéance dans
    3 j », « En retard de 2 j ») et la dernière réunion.
  - Les logos ont la même taille partout, Terminé compris, et l'icône d'un site remplit son carré.
  - Page d'un projet : la barre du haut ne prend plus la couleur du projet ; les Notes passent en premier et
    s'écrivent d'un clic, sans « Modifier » ; un menu « … » en haut à droite (statut, dossier de code, copier le
    nom, **Supprimer le projet**).
- **Mails**
  - Les fonds des mails lus, non lus et cochés reprennent les couleurs du reste de l'app.
  - Plus d'onglets : **Notifications** devient un dossier de la barre latérale, à côté d'Abonnements ;
    **Tous les messages** passe en dernier, après la Corbeille.
  - « Nouveau mail » quitte la barre latérale pour la barre du haut, dans tous les dossiers.
- **Contacts** : la page est refaite. La liste est rangée par dernier échange, avec les projets en couleur ; la
  page d'une personne montre ses projets, ses mails, ses rendez-vous, ses réunions, ses coordonnées et tes notes.
- **Calendrier** : chaque invité dit en toutes lettres où il en est (« Dans « P » », « Ajouter au projet »,
  « Ajouter aux contacts ») ; plus de « − » qui faisait croire qu'on retirait la personne du rendez-vous.
- **Notifications** : une cloche à côté de Réglages ouvre la liste des notifications que Polhub t'a envoyées
  (rappels, comptes rendus, mails…), comme le Centre de notifications d'Apple. Les répétitions se regroupent,
  la liste garde 30 jours.
- **Barre latérale** : de nouvelles icônes (Phosphor, libres de droits), et un trait sur toute la largeur
  au-dessus de Réglages.

## 0.17.0 — 15 novembre 2026

**Projets, mails, contacts, réunions : une grande passe d'interface.**

Après la mise à jour, redémarre tes sessions Claude Code ouvertes (ou tape `/mcp`) : l'outil polhub d'une
session déjà ouverte ne connaît pas encore les nouveaux statuts des projets.

- **Projets**
  - Quatre colonnes : Priorité 1, Priorité 2, En pause, Terminé. Tes projets ont été déplacés une fois :
    priorité 2 et idée vont en Priorité 1, priorité 3 en Priorité 2, en attente et le projet sans statut en
    En pause. Une copie de la base est faite juste avant, dans Sauvegardes.
  - Terminé s'affiche à droite, en petites cartes.
  - Les cartes sont dans la couleur du projet. Plus d'émojis : un logo automatique, l'icône du site du client
    (deviné d'après les adresses de ses contacts, ou le champ « Site »), ou une image que tu glisses sur le
    logo ; sinon ses initiales. Réglages › Projets : « Logos des sites des clients » et la taille des cartes
    (Normales ou Compactes).
  - Page d'un projet : actions, journal (en extraits), mails et réunions coupés à quelques lignes, avec
    « Voir les N autres » ; la première ligne du compte rendu de chaque réunion.
  - Accueil : la carte Priorité 1 montre six projets, puis « Voir les N autres ».
- **Mails**
  - Deux onglets : Personnes et Notifications (les newsletters y sont).
  - « Nouveau mail » en haut de Mails, dans la barre latérale ; ⌘N dans Mails.
  - Un clic sur une pièce jointe de la liste l'ouvre en aperçu.
  - Envoyés montre « À : » et les destinataires.
  - « Ranger dans » sur plusieurs mails cochés.
  - Une seule recherche : dès deux lettres, elle filtre toute la copie ; Entrée cherche aussi dans Gmail.
  - **Spam** et **Corbeille**, lus dans Gmail : seulement « Pas un spam » et « Restaurer ». Le texte d'un spam
    n'est jamais gardé sur le Mac et ses images ne s'affichent jamais.
  - **Programmer l'envoi**, à côté d'« Envoyer » : demain matin, demain après-midi, lundi matin ou une date.
    Un dossier « Programmés » apparaît tant qu'un mail attend. Si le mail change entre-temps (téléphone,
    Gmail), il ne part pas. Mac en veille à l'heure prévue : il part à ton retour jusqu'à 12 h de retard,
    au-delà il attend ton accord.
  - Correction : « Tous les messages » montre toute la copie, hors spam et corbeille (la 0.16.0 disait
    « six mois » : c'était faux).
- **Contacts, sans passer par la page Contacts**
  - Autocomplétion des destinataires classée (les personnes à qui tu écris le plus d'abord), avec ↑ ↓,
    Entrée ou Tab, Échap.
  - Dans un mail : les personnes du fil, qui est déjà un contact, et « Ajouter N au projet ».
  - Dans le calendrier et sur la page d'une réunion : les invités, qui est contact, et un petit menu pour les
    lier au projet.
- **Réunions**
  - La liste montre la première ligne du compte rendu ; clic droit ; la plus récente s'ouvre seule.
  - Le compte rendu a quatre parties : Résumé, Points clés, Décisions, Actions, avec « Copier le compte rendu »
    et « Refaire » ; « Partiel » quand une réunion très longue a dû être coupée.
  - Le lecteur avance ou recule de 15 s et change de vitesse.
  - Un passage refusé par le modèle d'Apple ne fait plus échouer tout le compte rendu.
- **Partout**
  - Un système de design commun : survol et appui sur tout ce qui se clique, animations douces, listes
    coupées avec « Voir les N autres ».
  - Barre latérale : icônes en couleur, plus grande et de largeur fixe, compteurs (mails non lus, rendez-vous
    du jour, point rouge pendant un enregistrement).
  - Accueil rééquilibré.

## 0.16.0 — 15 novembre 2026

**Les mails, comme dans Gmail.**

- **La liste** : une ligne par fil, comme Gmail. Les expéditeurs à gauche, séparés par des virgules ; l'objet,
  puis le début du mail en plus petit et en gris ; la date au bout. Un mail **non lu** est sur fond blanc et en
  gras, un mail **lu** sur fond bleu-gris. Les **pièces jointes** s'affichent en pastilles sous la ligne.
- **Le survol ne fait plus bouger la grille** : la ligne prend une ombre, et archiver, supprimer, lu/non lu
  et « Ranger dans » s'affichent par-dessus la date.
- **Les cases à cocher** sont toujours là, comme dans Gmail. Au-dessus de la liste, une barre porte la case
  « tout sélectionner » (avec Tous, Aucun, Lus, Non lus), « Relever », « Plus » et « Non lus » ; avec des fils
  cochés, elle porte archiver, supprimer, lu, non lu.
- **Les onglets** Personnes, Notifications et Newsletters quittent la barre du haut : ils sont sous la barre
  des gestes, comme ceux de Gmail, chacun sa couleur, avec le nombre de non-lus.
- **La barre latérale** : « Mails » s'ouvre sur Boîte de réception, Envoyés, Brouillons, Tous les messages et
  Abonnements, avec les non-lus et les brouillons comptés ; dessous, tes boîtes, à cocher pour les afficher
  ou les masquer. Elle a une largeur fixe : elle ne change plus de taille d'une section à l'autre.
- **Tous les messages** : nouveau dossier, avec les fils archivés de la copie (six mois), comme dans Gmail.
  Un fil archivé s'y remet en boîte de réception d'un clic.
- **Réglages › Mails**, plus complet :
  - la densité d'affichage de Gmail (Par défaut, Confortable, Compacte) ;
  - les jours séparés (Aujourd'hui, Hier…), désormais coupés par défaut, comme Gmail ;
  - ce qui s'affiche après un archivage ou une suppression : le fil suivant, le précédent ou la liste ;
  - le délai d'annulation de l'envoi : 5, 10, 20 ou 30 secondes ;
  - le tri des onglets expliqué règle par règle, et ce que Polhub a retenu de chaque expéditeur, à oublier
    d'un clic.

## 0.15.3 — 15 novembre 2026

**Une interface plus grande et plus aérée.** Comprend aussi les corrections de la 0.15.2, qui n'a pas été
publiée.

- **La liste des mails** passe sur deux lignes : l'expéditeur, sa case et la date ; puis l'objet et le début
  du texte. Le texte est plus grand (15 et 14 points au lieu de 12), les lignes plus hautes, les jours mieux
  séparés. Au survol, archiver, supprimer et lu/non lu s'affichent à la place de la date.
- **Un fil** : titre plus grand ; l'adresse, la date et les destinataires de chaque message ne sont plus en
  10 points ; le texte d'un mail écrit sans mise en forme passe de 13 à 15 pixels.
- **Écrire** : champs, objet et texte plus grands, boutons plus hauts.
- **Brouillons et Abonnements** suivent la même mise en page que la liste.
- **Partout** : plus aucun texte à lire en 10 points (étiquettes, sous-titres de l'accueil, page d'un
  projet, contacts, réunions, recherche, détail d'un rendez-vous) : 12 points au moins. La grille du
  calendrier garde sa taille.

## 0.15.2 — 14 novembre 2026

**Mails : corrections de la relecture de Ranger et des agents.**

- **Tes agents** :
  - le texte caché d'un mail ne leur parvient plus, même imbriqué, caché par une feuille de style, par
    l'attribut `hidden`, par une hauteur nulle ou une police minuscule ; l'extrait de la liste vient du texte
    visible, plus de l'aperçu de Gmail (qui contient l'en-tête caché des newsletters) ;
  - l'objet et les noms leur arrivent sur une ligne, sans caractère invisible ;
  - les caractères invisibles sont retirés du texte d'un brouillon d'agent : rien ne part sous tes yeux sans
    que tu le voies ;
  - « Ce que lisent tes agents » vaut tout de suite, même pour une session Claude Code déjà ouverte ;
  - ouvrir un fil ne met plus dans Gmail le brouillon d'un agent : il n'y va qu'une fois que tu l'as retouché ;
  - une réponse d’agent préparée hors ligne est reprise quand tu reviens sur Polhub ou que tu relèves tes mails.
- **Ranger** :
  - un collègue de ton domaine, relié par l'agenda à un projet, n'y range plus tous ses mails internes ;
  - un contact que tu as retiré d'un projet n'y revient plus par son domaine ;
  - plus de boîtes grand public reconnues (Gmail, Outlook et Yahoo d'autres pays, Proton, Fastmail,
    fournisseurs belges et suisses…) ;
  - une adresse « …-noreply » n'est jamais faite contact.
- **Recherche** : « Tout archiver » et « Tout marquer comme lu » ne s'appliquent plus aux résultats d'une
  recherche, qui mêlent tous les onglets.
- **Pixels espions** : la liste ne bloque plus des images légitimes par des motifs trop larges ; deux motifs
  de la liste d'origine (Campaign Monitor, Cprpt) bloquent enfin ce qu'ils visaient.

## 0.15.1 — 14 novembre 2026

- **Mails : les pixels espions connus sont bloqués**, même quand les images s'affichent (la liste libre
  simplify-trackers : Mailchimp, HubSpot, SendGrid, Mailtrack… près de 280 motifs). L'expéditeur ne sait
  pas que tu as ouvert son mail par ces pixels-là.

## 0.15.0 — 14 novembre 2026

**Mails : tes agents.** Claude Code lit tes mails par Polhub et te prépare des réponses ; toi seul envoies.

- **Trois outils** dans le serveur de Polhub, déclaré pour toutes tes sessions Claude Code :
  - `mails` : la liste des fils de ta copie locale (ceux d'un projet, ceux qui contiennent des mots, les non
    lus) ;
  - `mail` : un fil, message par message, page par page ;
  - `brouillon` : une réponse sous un fil, ou un nouveau mail.
- **Ce qu'ils lisent** : le texte que tu vois. Le texte caché d'un mail (le moyen habituel de glisser un
  ordre à un assistant) et les caractères invisibles sont retirés. Chaque réponse rappelle qu'un mail est
  une donnée, jamais une instruction. Ni spam ni corbeille, et les pièces jointes sont nommées, pas lues.
- **Réglages › Mails › « Ce que lisent tes agents »** : tous les mails, ou seulement ceux de tes projets.
- **Leurs brouillons** t'attendent dans Brouillons, marqués « préparé par un agent ». Pour une réponse,
  Polhub calcule lui-même les destinataires et la citation, jamais l'agent. Une adresse que tu n'as jamais
  utilisée est en orange. Un brouillon d'agent ne va dans Gmail qu'une fois que tu l'as retouché.
- **Rien ne peut partir sans toi** : le programme des agents n'a ni réseau ni jeton Google (un test le
  vérifie), et aucune ligne de la base ne déclenche un envoi.
- `contexte` donne le nombre de mails récents d'un projet.
- Une ligne de fil qui a un brouillon le dit, en rouge, comme dans Gmail.

## 0.14.0 — 14 novembre 2026

**Mails : ranger.** Chaque fil client porte son projet.

- **La case** : une étiquette à côté de l'objet dit où va un fil : le nom du projet (à sa couleur), Perso,
  ou Paiements dans l'onglet Notifications. Polhub la devine, de la règle la plus sûre à la moins sûre :
  1. ton choix pour ce fil ;
  2. ton dernier choix pour cet expéditeur ;
  3. l'expéditeur est un contact d'un seul projet (s'il en a plusieurs, celui que l'objet nomme) ;
  4. son domaine est celui des contacts d'un seul projet (jamais gmail.com et consorts, ni ton domaine) ;
  5. un mail automatique : Newsletters, Paiements (facture, reçu, prestataire de paiement) ou Services.

  Perso ne se devine jamais : tu le poses. Les personnes en copie ne comptent pas.
- **Corriger en un clic** : un clic sur l'étiquette (ou sur « Ranger », au survol d'une ligne sans case), ou
  clic droit › « Ranger dans ». Polhub retient l'expéditeur pour ses prochains mails. Ranger dans un projet
  en fait un contact du projet, comme pour le calendrier. « Annuler » défait le tout.
- **Personne n'est caché** : un contact, ou quelqu'un à qui tu as écrit, reste dans Personnes même quand
  Gmail le classe en Promotions ou en Notifications.
- **La carte « Mails »** sur la page d'un projet : ses derniers fils ; un clic ouvre le fil.
- **« … » › Tout archiver** dans les onglets Notifications et Newsletters, avec « Annuler ».
- **Notifications** : Réglages › Notifications › « Seulement les mails de tes projets ».

## 0.13.0 — 14 novembre 2026

**Mails : écrire, et faire le ménage.** Tu réponds, écris et envoies sans ouvrir Gmail.

- **Trois onglets** à la place de Principale et Automatiques : « Personnes », « Notifications » (reçus,
  confirmations, alertes) et « Newsletters » (lettres, promotions, réseaux sociaux). Clic droit › « Déplacer
  vers » range un expéditeur dans un autre onglet, et Polhub le retient.
- **Répondre** : ⌘R (ou ⇧⌘R pour répondre à tous) ouvre la réponse au bas du fil. « … » › Transférer. La ligne
  « De » montre toujours la boîte qui envoie ; ta signature Gmail et le message cité sont posés dessous, comme
  dans Gmail, pour que le fil reste propre chez ton correspondant.
- **Nouveau mail** : ⌘N ou le crayon. À, Cc et Cci se complètent avec tes contacts et les personnes qui
  t'écrivent. Pièces jointes par le trombone ou en glissant un fichier, 25 Mo au plus.
- **Brouillons partagés avec Gmail** : un brouillon est enregistré sur le Mac, puis dans Gmail 3 secondes après
  ta dernière frappe. Tu le retrouves sur ton téléphone ; un brouillon commencé ailleurs se reprend dans Polhub.
- **Envoyer** : tu as 10 secondes pour annuler. Si l'app quitte pendant ces 10 secondes, rien ne part et le
  brouillon reste. Un envoi raté laisse le brouillon et te prévient. La mise à jour de l'app attend la fin
  d'un envoi.
- **Le menu de la boîte** (en haut à gauche) : Boîte de réception, Brouillons, Envoyés, Abonnements.
- **Abonnements** : les expéditeurs de lettres des 90 derniers jours, des plus bavards aux plus discrets. « Se
  désabonner » montre d'abord le domaine concerné, puis agit en un clic quand l'expéditeur le permet et que Gmail
  a vérifié le mail ; sinon il prépare le mail de désinscription, que tu envoies toi-même, ou ouvre sa page.
  « Tout archiver » vide la boîte de réception de ses mails.
- **Ménage** :
  - le filtre « Non lus » dans la barre ;
  - « … » › Tout marquer comme lu ;
  - clic droit › Tous les mails de cet expéditeur, Signaler comme spam ;
  - sur un fil, « … » › Se désabonner, Signaler comme spam ;
  - sur un message, « … » › Afficher l'original (le mail tel qu'il a voyagé, avec ses en-têtes).
- **Notifications** : seulement pour l'onglet Personnes.
- **Garde-fous** (relecture de l'étape) :
  - un brouillon envoyé, supprimé ou modifié ailleurs (ton téléphone) n'est jamais recréé ni écrasé en
    silence : un bandeau te demande quelle version garder, et rien ne part avant ;
  - un brouillon n'est jamais enregistré deux fois dans Gmail, même si tu tapes pendant qu'il s'enregistre ;
  - un nouveau mail ne va dans les brouillons de Gmail qu'une fois la boîte choisie ; changer de boîte le
    retire de la première ;
  - une adresse que tu n'as jamais utilisée s'affiche en entier, en orange, même derrière un nom connu ;
  - une adresse tapée mais pas encore validée part avec le mail, ou l'arrête si elle est incomplète ;
  - ⌘↩ n'envoie que le brouillon où tu écris ;
  - le HTML d'un mail cité ou transféré est nettoyé : ni style, ni script, ni formulaire, et rien ne sort de
    la citation ;
  - « Annuler » disparaît dès que le mail est en route ;
  - un dossier ne se joint pas (compresse-le), et les pièces de même nom gardent chacune la leur.
- La version de développement n'écrit jamais dans tes vraies boîtes : ni brouillon, ni envoi.

## 0.12.1 — 14 novembre 2026

**Mails : tes retours sur la lecture.**

- **Accents** : Gmail donne le texte en UTF-8 même quand un mail annonce un autre jeu de caractères ; Polhub
  croyait l'annonce et affichait « accÃ¨s » pour « accès » (75 mails sur 900). C'est corrigé, et les mails déjà
  copiés sont réparés au lancement, sans rien retélécharger.
- **Mode sombre** : plus de boîte blanche. Le mail prend le fond de l'app ; ses fonds clairs s'assombrissent et
  ses textes foncés s'éclaircissent, comme dans Apple Mail. Un mail qui gère lui-même le sombre le garde, les
  couleurs vives (un bouton de marque) restent telles quelles, et un mail fait d'images reste sur fond clair.
  « … » › « Afficher sur fond clair » montre un message tel que l'expéditeur l'a prévu.
- **La liste** :
  - non lu : un point de couleur, l'expéditeur et l'objet en gras ; lu : en gris ;
  - la couleur de la boîte devient un trait à gauche de chaque ligne ;
  - des repères de date : Aujourd'hui, Hier, Cette semaine, Ce mois-ci, puis les mois ;
  - un expéditeur seul garde son nom entier (« La Lettre du design », plus « La »).
- **Sélection de plusieurs mails** : la case au survol, ⌘-clic, ⇧-clic, ⌘A, ou le bouton « Sélectionner ». La
  barre propose alors Archiver, Supprimer, Lu, Non lu, Tout sélectionner, avec un seul « Annuler » pour tout le
  lot. Clavier : flèches, Entrée pour ouvrir, Espace pour cocher, Suppr, Échap.
- **Barre d'outils** : « Relever » (demander à Gmail maintenant) et « Sélectionner ». Les onglets disent ce
  qu'ils contiennent : survole-les, et l'onglet Automatiques s'explique en haut de la liste.
- **Fenêtre flottante** : un mail et un projet s'ouvrent par-dessus leur liste, qui reste visible derrière ;
  Échap ou un clic à côté la referme. Réglages › Général › « Ouvrir un mail ou un projet » : en fenêtre flottante
  ou en pleine page, pour comparer.
- **La page d'un mail** : l'objet, la boîte et le nombre de messages en tête ; « 3 sur 42 » et les flèches pour
  passer au fil précédent ou suivant ; après Archiver ou Supprimer, le fil suivant s'ouvre. Chaque message a sa
  date complète, « à moi ▾ » qui déplie De, À, Cc et l'authenticité vérifiée par Gmail, et un menu (Ouvrir dans
  Gmail, Copier l'adresse). Un long fil replie ses messages du milieu (« 4 messages plus anciens »). Les pièces
  jointes sont des vignettes avec leur icône et leur taille, et « Tout enregistrer… ».
- **Notifications** : un nouveau mail de l'onglet Principale te prévient ; un clic ouvre le fil. Jamais pour les
  mails automatiques, ni pendant la première lecture d'une boîte. Réglages › Notifications › Mails.

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
