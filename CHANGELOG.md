# Ce qui a changé

Chaque version publiée a sa section ; `scripts/release.sh` la reprend pour la page de la version sur
GitHub, et l'app la montre dans Réglages › Mises à jour.

## 0.64.0 — 21 novembre 2026

**Dictée : elle répond dès l'appui, tu vois tes mots, et elle va deux à trois fois plus vite.**

- **Dès l'appui.** La touche répond dès la première seconde après un lancement, au lieu de vingt secondes sans rien.
  Ce que tu dictes pendant que Whisper se charge est écrit dès qu'il est là.
- **Tes mots en direct.** Les premiers arrivent après une seconde environ, puis ils se mettent à jour toutes les
  0,8 s (avant : plus de 2 s).
- **Le texte final.** Il s'écrit dès que tu te tais : il arrive souvent en moins d'une seconde après ton appui
  (avant : 1,5 à 3,5 s).
- **Une fenêtre qui dit ce qui se passe** : « Le micro s'ouvre… », « Je t'écoute », tes mots, « Je relis avec ta
  mémoire… » et sa barre, « Collé dans Mail », « Je n'ai rien entendu ». Un appui pendant que la Dictée démarre dit
  pourquoi, au lieu de ne rien montrer.
- **Les mots courts** : « Oui », « Merci », « OK » dictés seuls s'écrivent enfin.
- **Rien dit, rien écrit** : plus de « Merci. » inventé dans un silence.
- **Arrêt seul** : la fenêtre compte les trois dernières secondes avant de finir.
- **Micro Bluetooth** : Réglages › Dictée › Micros prévient qu'il met jusqu'à une seconde à s'ouvrir, et dit quoi
  faire.
- Réparé : une dictée annulée très vite pouvait laisser le son du Mac coupé ; un appui raté avalait l'appui suivant.

## 0.63.2 — 20 novembre 2026

**La Dictée remarche avec des écouteurs Bluetooth.**

- Avec des écouteurs comme micro, l'écoute de la Dictée s'arrêtait net : elle croyait le micro à 48 kHz alors qu'il
  tourne à 24 kHz. Elle lit maintenant le micro comme l'enregistreur des réunions, à son vrai format, quel qu'il soit.
- Changer de micro dans Réglages › Dictée marche dès la dictée suivante.

## 0.63.1 — 20 novembre 2026

**La Dictée remarche.**

- En 0.63.0, le micro ne s'ouvrait plus : hub le réglait avant chaque dictée, même quand c'était celui du système, et
  macOS refusait. Le micro du système est de nouveau laissé tel quel, comme en 0.62.0.
- Un micro qui ne s'ouvre pas ne bloque plus la Dictée jusqu'au relancement : la fenêtre le dit, le son du Mac et la
  musique reviennent, et la dictée suivante marche.

## 0.63.0 — 20 novembre 2026

**Dictée : une page en cartes, et tous les réglages que tu as choisis.**

- **La page Dictée**, deux onglets en cartes :
  - **Historique** : tes dictées rangées par jour, à copier, à réécouter ou à retranscrire avec ta mémoire du moment ;
    une recherche (⌘F) dans toutes tes dictées ;
  - **Mémoire** : tes mots en pastilles, tes corrections, et les noms que hub connaît déjà.
- **Transcrire un fichier** : glisse un son ou une vidéo sur l'historique, ou « Transcrire un fichier… » en haut.
  Un vocal, un mémo, un MP4 ou un MOV : son texte rejoint l'historique.
- **Le texte**, réglable dans Réglages › Dictée :
  - **ponctuation dite** : « à la ligne », « nouveau paragraphe », « virgule », « point d'interrogation »…
    deviennent des signes ;
  - **nombres en chiffres** : « dix heures trente » donne « 10 h 30 », « vingt-cinq euros » donne « 25 € » ;
  - **paragraphes** : une longue pause, quand tu changes de sujet, commence un paragraphe ;
  - **sans point final** sur une phrase seule, comme dans un message ;
  - **les « euh »**, retirés ou non ;
  - **une espace après** le texte collé.
- **La touche** : la dictée finit seule après un long silence, si tu oublies d'appuyer (10 s, réglable).
- **Le son** :
  - **les micros**, dans l'ordre que tu veux : le premier branché sert ;
  - **des petits sons** au début et à la fin ;
  - **le son du Mac coupé** pendant que tu dictes ;
  - **la musique ou la vidéo en pause**, puis relancée.

  Jamais de sourdine ni de pause pendant une réunion que hub enregistre.
- **L'historique** :
  - **le son** de chaque dictée est gardé sur ce Mac ;
  - **l'historique s'efface seul** après 7, 30 ou 90 jours, si tu veux.
- **La fenêtre** : en bas ou en haut de l'écran, au choix.

## 0.62.0 — 20 novembre 2026

**Dictée : un appui pour commencer, un appui pour finir.**

- Plus besoin de tenir la touche : appuie sur ⌥ droite, parle, appuie de nouveau. Le texte arrive là où tu écrivais.
  Échap annule. Tu préfères tenir ? Réglages › Dictée › « Façon » : « Appuyer, parler, appuyer », « Tenir pour
  parler » ou « Les deux ».
- Une fenêtre plus grande et plus lisible : tes mots en grand sur trois lignes, la courbe de ta voix, le temps écoulé
  et ce qu'il faut presser. Après le dernier appui, un sablier « J'écris… » jusqu'au collage.
- Ta dernière dictée dans le Coup d'œil, avec son heure et « Copier ».
- Réglages › Dictée : « Mots en direct » (les voir s'écrire pendant que tu parles) et « Presse-papiers » (remettre ce
  qu'il contenait après le collage), à couper si tu préfères.

## 0.61.0 — 20 novembre 2026

**Dictée : tu parles, tes mots s'écrivent là où est ton curseur.**

- Un nouvel add-on, à installer dans Réglages › Add-ons. Tiens ⌥ droite et parle : une pastille montre ta voix et tes
  mots, et le texte arrive là où tu écris, dans n'importe quelle app, quand tu relâches. Deux appuis : tu parles mains
  libres, un appui arrête. Échap annule.
- Elle utilise le même Whisper que tes réunions : rien à télécharger chez toi.
- Une section « Dictée » : l'historique de ce que tu as dit, et ta mémoire (tes mots, et des corrections comme
  « mythe » qui donne « Meet »). Whisper connaît d'avance tes projets, leurs clients et tes contacts.
- « Copier la dernière dictée » dans le Coup d'œil, et Réglages › Dictée pour la touche, la langue et l'autorisation
  Accessibilité.

## 0.60.0 — 20 novembre 2026

**Les notifications de l'iPhone passent chiffrées.**

- Le Mac chiffre chaque notification avec une clé que ton iPhone a faite et lui a donnée. Apple ne transporte plus que
  « Nouveau mail » et un texte illisible. Ton iPhone (1.7.0) le déchiffre et te montre l'expéditeur, l'objet et les
  premiers mots, comme avant.
- Tant que l'iPhone n'a pas donné sa clé, ses notifications disent seulement « Nouveau mail ». Il la donne dès que tu
  ouvres hub sur l'iPhone.

## 0.59.0 — 20 novembre 2026

**Réglages › Add-ons : ce que hub sait faire, à installer ou à retirer.**

- Une nouvelle page, en tête de Réglages : Projets, Réunions, Calendrier, Mails, Inspiration, Colin et iPhone, chacun
  avec « Installer » ou « Installé ». Ce qui n'est pas installé n'apparaît nulle part et ne tourne pas : ni dans la
  barre latérale, ni dans Réglages, ni dans les outils de tes agents, ni sur l'iPhone.
- Chez toi, tout est installé : rien ne change.
- Installer ou retirer relance hub, jamais pendant une réunion, et dit ce qui vient avec (Colin a besoin de Mails et de
  Calendrier). Les données restent : réinstaller remet tout comme avant.
- Sur un Mac neuf, hub s'ouvre sur cette page, et installer Réunions télécharge son modèle (1,6 Go), vérifié fichier
  par fichier.

## 0.58.0 — 20 novembre 2026

**Polhub s'appelle maintenant hub.**

- L'app s'appelle « hub » : dans le Dock, la barre des menus, les notifications et sur l'iPhone. Son nom complet,
  « hub-board », est sur GitHub et dans Réglages › Mises à jour.
- Rien ne se perd : tes autorisations, tes comptes Google, tes réglages, la copie iCloud et l'iPhone restent tels
  quels.
- Tes agents Claude Code trouvent ses outils sous le nom « hub ».

## 0.57.1 — 20 novembre 2026

**Préparation du nouveau nom : rien ne change à l'écran.**

- Polhub va changer de nom. Cette version apprend à la mise à jour à installer une app qui porte un autre nom et vient
  d'une autre adresse sur GitHub, en gardant l'ancienne de côté si la nouvelle ne démarre pas.

## 0.57.0 — 20 novembre 2026

**Un nombre sur l'icône de Polhub, et des mails plus propres sur l'iPhone.**

- L'icône de Polhub porte un nombre, dans le Dock et sur l'iPhone : les mails non lus de la boîte de réception, plus
  ce que Polhub t'a signalé et que tu n'as pas encore vu (comptes rendus, brouillons, rappels). Sur l'iPhone, il suit
  chaque notification, et change seul quand tu lis tes mails sur le Mac.
- Sur l'iPhone, un mail replie sa signature et l'historique cité, comme sur le Mac : un bouton les affiche.
- Sur l'iPhone, glisser un mail vers la gauche le supprime (jusqu'au bout) ou l'archive ; vers la droite, il passe en
  lu ou non lu. Une corbeille dans le fil le supprime aussi.
- Sur l'iPhone, plus de chevron au bout des mails ; un message replié montre ses premiers mots ; la liste se met à jour
  au retour d'un fil.
- Les notifications de l'iPhone ne dépendent plus de l'interrupteur « Accès depuis l'iPhone ».

## 0.56.0 — 20 novembre 2026

**Chaque nouveau mail sonne sur l'iPhone, comme dans Gmail.**

- Tous les nouveaux mails de tes boîtes arrivent en notification sur l'iPhone, et plus seulement ceux de l'onglet
  « Personnes » : l'expéditeur, l'objet et le début du texte, regroupés par fil. Au-delà de dix d'un coup, une ligne
  dit le reste.
- Le Mac garde ses propres réglages de notifications de mails ; l'iPhone ne reçoit plus deux fois le même mail.
- L'iPhone donne au Mac son adresse de notifications par iCloud, même quand Tailscale ne joint pas le Mac. Il l'avait
  donnée seulement par Tailscale, au premier lancement : elle n'était jamais arrivée. Réglages › iPhone le montre
  (« Notifications par iCloud »).
- Un iPhone relié et connu par iCloud ne reçoit qu'une notification.

## 0.55.0 — 20 novembre 2026

**Une copie dans ton iCloud, pour l'iPhone quand le Mac est éteint.**

- Polhub copie dans ton iCloud ce que l'iPhone montre : les projets, les réunions (compte rendu et transcription),
  l'agenda des semaines à venir et le fil de Colin. Les mails n'y vont pas : ils restent chez Google.
- Seul ce qui a changé est copié, toutes les deux minutes et juste avant que le Mac se mette en veille.
- Le contenu est chiffré de bout en bout : Apple ne peut pas le lire. Les très longues transcriptions le sont avec la
  protection avancée des données d'iCloud.
- Réglages › iPhone : « Copie dans iCloud », avec l'heure de la dernière copie, ou ce qui l'empêche.
- L'app est désormais construite par une archive exportée signée Developer ID, avec le profil qu'iCloud demande. Même
  signature qu'avant : les autorisations de macOS restent.

## 0.54.0 — 20 novembre 2026

**Colin lit tes conversations Claude Code.**

- Deux nouveaux outils pour Colin, en lecture seule : `conversations` (la liste, la plus récente d'abord, celles d'un
  projet ou qui contiennent des mots) et `conversation` (une conversation page par page, la plus récente d'abord).
- Il n'en voit que tes messages et les réponses de Claude : ni les outils, ni les pensées, ni les sous-agents, ni les
  textes du système. Les clés et jetons qui ont une forme connue sont masqués.
- Une conversation compte comme une lecture d'un tiers pour son verrou : ses brouillons restent dans le projet du
  dossier de la conversation.
- Même une conversation de 800 Mo se lit en quelques secondes.

## 0.53.1 — 20 novembre 2026

- Une mise à jour ne laisse plus jamais le Mac sans Polhub. Elle prenait pour une autre copie de Polhub tout programme du
  même nom, comme l'app iPhone ouverte dans le simulateur : elle abandonnait alors sans relancer Polhub, et l'iPhone ne
  joignait plus le Mac. Seule une copie de l'app installée compte désormais, et si l'échange ne se fait pas, Polhub
  repart quand même.

## 0.53.0 — 20 novembre 2026

**Les notifications de Polhub arrivent sur l'iPhone.**

- Ce que le Mac notifie (nouveaux mails, nouveaux rendez-vous, comptes rendus prêts, mail non envoyé, brouillons de Colin)
  part aussi sur l'iPhone, par le service de notifications d'Apple, quand le Mac est allumé. Les nouveaux mails arrivent
  sur l'iPhone même quand le Mac les tait.
- Les rappels avant un rendez-vous partent à leur heure.
- Réglages › iPhone : « Notifications sur l'iPhone », et une ligne si la clé d'Apple manque.
- Sur l'iPhone, toucher la notification d'un mail ouvre son fil.

## 0.52.1 — 20 novembre 2026

- Réglages › iPhone trouve seul l'adresse du Mac sur Tailscale : celle que `tailscale serve` publie. Lancée depuis Polhub,
  la commande de Tailscale essayait d'ouvrir son app au lieu de répondre, et l'adresse restait vide.
- Sous le QR code, « Copier le lien » : collé sur l'iPhone par « Coller le lien du code », il relie l'iPhone sans
  l'appareil photo.

## 0.52.0 — 20 novembre 2026

**Depuis l'iPhone, on écrit et on parle à Colin.**

- Une réponse ou un nouveau mail écrit sur l'iPhone part du Mac, avec sa signature, après le délai de Réglages › Mails :
  l'iPhone montre « Envoi dans 8 s · Annuler ».
- Colin sur l'iPhone, c'est le fil de l'Accueil : la question part au Mac, la réponse s'écrit sous les yeux, et ses
  changements de projets arrivent avec « Annuler ». Son verrou reste celui du Mac.
- L'app iPhone a ses cinq onglets : Mails, Calendrier, Colin, Projets, Réunions ; Réglages derrière la roue dentée.

## 0.51.1 — 20 novembre 2026

- Réglages › iPhone donne la commande Tailscale avec son chemin entier
  (`/Applications/Tailscale.app/Contents/MacOS/Tailscale serve …`) : le Terminal du Mac ne connaît pas `tailscale` tout
  court.
- L'app iPhone avance (mails, fils, calendrier, copie hors ligne) ; elle arrive par TestFlight.

## 0.51.0 — 20 novembre 2026

**Polhub s'ouvre à l'iPhone (première étape).**

- Réglages › iPhone : un interrupteur « Accès depuis l'iPhone », l'adresse du Mac sur Tailscale (lue toute seule), la
  commande à coller une fois pour que Tailscale publie Polhub, les iPhone reliés et « Retirer ».
- « Relier un iPhone » montre un QR code valable dix minutes : l'appareil photo de l'iPhone l'ouvre dans Polhub, qui garde
  sa clé. Le Mac n'en garde que l'empreinte.
- Polhub n'écoute que sur ce Mac (`127.0.0.1`), jamais sur le Wi-Fi ; Tailscale le publie pour tes seuls appareils. Sans
  la clé d'un iPhone relié, rien ne se lit.
- Ce que l'iPhone lira : les mails (Boîte de réception, Automatiques, Envoyés, Tous les messages, les fils et leurs pièces
  jointes), l'agenda, les projets et les réunions. L'app iPhone vient avec la prochaine étape.

## 0.50.0 — 20 novembre 2026

**Colin met à jour plusieurs projets d'un coup.**

- « Mets à jour mes projets d'après mes mails » : Colin change maintenant plusieurs projets dans la même question
  (statut, échéance, tâche du moment, actions, journal), même après avoir lu des mails. Chaque changement s'affiche dans
  son fil avec « Annuler ». Avant, son verrou le limitait à un projet par question.
- Le verrou reste pour ce qui sort ou se crée : un brouillon ne sort pas du fil qu'il a lu, et un projet ne se crée
  pas après la lecture d'un mail.

## 0.49.0 — 20 novembre 2026

**Envoyer ferme le mail ; les messages du bas, petits et passagers.**

- « Envoyer » ferme le fil ou le nouveau mail aussitôt. Le mail part toujours après le délai choisi : une petite
  pilule en bas dit « Envoi dans 8 s · Annuler », et « Annuler » rouvre le mail tel qu'il était.
- La pilule du bas (Mails, Inspiration) tient sur une ligne, en petit, jamais plus large que 520 points ; le texte
  entier est dans sa bulle. Un message s'en va seul au bout de 8 secondes (le ✕ le ferme avant).

## 0.48.0 — 20 novembre 2026

**Le panneau de Colin se règle à la main.**

- Sur l'Accueil, le filet entre ta journée et Colin se tire : au survol, le pointeur devient la flèche de
  redimensionnement, et le panneau va de 360 à 720 points. Ta journée garde toujours au moins 420 points ; dans une
  fenêtre plus étroite, le panneau cède d'abord. La largeur choisie est gardée d'une ouverture à l'autre.

## 0.47.1 — 20 novembre 2026

**Les mots choisis par Paul.**

- « Supprimer » une réunion (était « Mettre à la Corbeille » ; elle va toujours à la Corbeille).
- « Ne pas enregistrer » une réunion détectée (était « Pas cette fois »).
- « Livrer » dans À faire (était « Livré »).
- Le dossier de mails « Notifications » s'appelle « Automatiques » : plus de confusion avec la cloche.
- Coup d'œil dit « Partie 3 sur 5 » pendant un compte rendu en plusieurs parties.

## 0.47.0 — 20 novembre 2026

**Les mots : les mêmes partout, et des erreurs qui disent quoi faire.**

- **Un seul vocabulaire** : un rendez-vous est dans l'agenda, une visio est un rendez-vous avec un lien Meet, une
  réunion est ce que Polhub a enregistré. Plus de « call » ni de « RDV » : « Colin attend la fin de ta visio »,
  « visio demain 9:30 », « Rendez-vous demain 9:00 ». Coup d'œil dit « Compte rendu » (plus « Résumé »), Polhub dit
  « l'IA d'Apple » (plus « le modèle d'Apple ») et « newsletters ».
- **Une seule écriture des heures et des dates** : « 9:05 » (plus « 09:05 »), « demain 9:00 » (plus « demain 9 h »),
  « 18 nov. » (plus « 18/11 »), « 2 h » (plus « 2 h 00 »), « mardi 1er décembre à 8:00 ». Les nombres s'accordent :
  « + 1 autre », « 1 234 mails ».
- **Les erreurs disent ce qui n'a pas marché, pourquoi et quoi faire**, en français : « Le fil n'a pas pu être rangé :
  pas de connexion à Internet. Vérifie la connexion du Mac, puis réessaie. » Le texte du système, souvent en anglais, ne
  s'affiche plus ; celui d'un geste qui échoue va au Journal de Réglages.
- **Les bulles disent le geste, puis son raccourci** : « Ouvrir le fil précédent (↑) », « Mettre en gras (⌘B) »,
  « Rejoindre dans Dia avec le compte Pro (↩ ou J) », « Plus d'actions » sur chaque menu « … ». Plus jamais
  « cliquer », et VoiceOver dit la même chose que la bulle.
- **Les boutons disent où ils mènent** : « Ouvrir la réunion », « Ouvrir le compte rendu », « Voir moins »,
  « Actualiser » (plus « Synchroniser » ni « Rafraîchir »), « Connecter un compte Google… », « Ajouter à « Studio
  Nord » ».
- **La typographie française** : une espace insécable avant « : » et dans « », « 42 % », un nombre jamais séparé du
  mot qu'il compte, une plage d'heures jamais coupée (« 10:00 – 11:00 »). Les initiales en couleur d'une personne se
  lisent sur leur rond. « de » s'élide devant un nom : « Attend le retour d'Anne-Sophie », « Se désabonner d'Atelier ».

## 0.46.0 — 20 novembre 2026

**Coup d'œil, la cloche et la carte avant une visio : rien n'est dit deux fois, les mêmes cartes que dans l'app.**

- **Rien n'est dit deux fois** dans Coup d'œil : la carte des nouveaux mails n'a plus d'en-tête, et la tuile Mails ne
  redit plus les expéditeurs qu'elle liste. La tuile Calendrier donne le titre du prochain rendez-vous en entier, puis
  son heure ; sous « Libre jusqu'à 16:30 », elle ne redit pas 16:30. Un compte à reconnecter n'est dit que dans « À
  régler ». La carte de la journée se lit : « Ouvrir Polhub » est le seul chemin vers l'Accueil.
- **Plus de capitales** : « Dans 8 min », « Enregistrement », « Vendredi 20 novembre », en casse normale et en petit
  gris. Une seule chose y prend la couleur : le point de l'enregistrement, l'icône d'un problème, ou « Dans 8 min ».
- **Les cartes de l'app** : Coup d'œil et la cloche prennent le fond et le trait des cartes de la fenêtre, sans ombre.
  « À régler » se dessine comme les bandeaux de l'app, seule son icône en couleur. Une notification porte l'icône de sa
  section dans sa couleur, sans carré.
- **Plus d'air, à l'échelle de l'app** : 16 points autour du panneau et à l'intérieur de la vedette, 8 entre les
  cartes ; les boutons de la vedette ensemble à droite, plus collés au texte, et plus jamais coupés sur deux lignes
  (« Arrêter maintenant », « Ouvrir la réunion »).
- **La carte avant une visio** se lit comme Coup d'œil : son titre en 15 points, sa ligne en 13 (13 et 11 avant) ;
  « Rejoindre » répond au survol.
- **Le HUD** parle de même, et sa hauteur suit ses mots : le titre d'une réunion détectée et une alerte longue (« Polhub
  ne lit plus les onglets de Dia ») ne sont plus coupés.

## 0.45.0 — 20 novembre 2026

**Projets, Réunions, Calendrier, Contacts, Inspiration : un Kanban lisible, des erreurs en français, des en-têtes
cohérents.**

- **Le Kanban en teinte allégée** : chaque carte garde la couleur de son projet, deux fois plus légère, et tous ses
  textes sont en noir. Le retard et l'échéance du jour ne colorent plus que leur petit drapeau. Les colonnes n'ont plus
  de fond teinté.
- **Les statuts** (Liste, page d'un projet) : des pastilles neutres avec leur point de couleur ; seul « Terminé » est en
  vert, avec sa coche. « Priorité 2 » en orange se lisait comme un avertissement.
- **Une réunion dont l'audio ne se lit pas le dit en français** : « L'audio de cette réunion est introuvable : son
  dossier est incomplet. », au lieu d'un texte du système en anglais. Le texte d'origine reste derrière « Détails ».
- **Des en-têtes cohérents** : une réunion, un contact et une fiche d'Inspiration ont leur titre en grand, comme un
  projet. Une réunion se lit au milieu de la page, comme un fil de mails, et ses tours de parole commencent au bord
  de la page.
- **Le Calendrier** s'ouvre sur l'heure réglée sans la couper : « 08 h » se lit en entier.
- **Des cartes identiques** : vingt points d'air dans chaque carte (projet, contact, compte rendu), seize entre deux.
- **Contacts** : les projets d'une personne en pastilles neutres avec leur point ; sans contact choisi, la page dit
  « Choisis un contact dans la liste. ». Dans la bulle d'un rendez-vous, « Dans « Projet » » prend le même dessin.

## 0.44.0 — 20 novembre 2026

**Réglages : les familles dans l'ordre de la barre latérale, une ligne d'aide par réglage.**

- **L'ordre de la barre latérale** : Colin (celui de l'Accueil), Projets, Réunions, Calendrier, Mails, Inspiration, puis
  Comptes Google, Notifications, Mises à jour et Général. Diagnostic et Journal ne sont plus des familles : deux lignes
  en bas de Général, et leur flèche de retour ramène à Général.
- **Une ligne d'aide sous chaque réglage**, dans sa carte ; le détail (ce qui quitte le Mac, les règles exactes)
  s'ouvre d'un clic sur « ⓘ ». Plus de paragraphes sous les cartes.
- **Une seule largeur** pour toutes les pages, Diagnostic et Journal compris, et plus de bande grise coupée sous la
  barre d'outils.
- **Les rappels** se choisissent dans un menu, « Rappels   10 et 1 min avant », plusieurs à la fois.
  « Déconnecter… » un compte Google passe dans le menu « … » du compte.
- **Plus d'« onglet Personnes »** : « Nouveau mail dans la Boîte de réception ». Le tri des mails s'explique
  derrière « ⓘ », à côté de « Ce que Polhub a retenu ».
- **Ce qui quitte le Mac, dit là où on le choisit** : dans Mails, « Les mails de tes projets » est une préférence,
  pas une barrière ; dans Colin, ce qu'il lit pour te répondre (mails, transcriptions, agenda) part chez Anthropic.
- **La relance dans Diagnostic** passe par le même interrupteur que Général : elle attend la fin d'une réunion et
  demande avant de fermer Polhub.

## 0.43.0 — 20 novembre 2026

**Les mails : une seule grille pour tous les dossiers, un fil sur une seule colonne, un seul bouton plein.**

- **La liste** : la barre des gestes est là dans chaque dossier, à la même hauteur ; Brouillons, Programmés et
  Abonnements suivent les mêmes colonnes que la Boîte de réception. La date a sa colonne au bout de la ligne : au
  survol, les gestes prennent sa place, sans rien cacher de l'objet. Le filet de couleur d'une boîte n'apparaît que
  si la liste en montre plusieurs. Un mail lu est un cran plus bas, plus doux.
- **Une liste vide dit quoi faire** : ce qui arrive dans le dossier, « ⌘N pour écrire », ou « Tout est lu » avec
  « Afficher tous les mails », ou « 1 boîte est masquée » avec « Afficher toutes les boîtes ».
- **Le fil** : l'objet, les messages et la réponse commencent au même bord. « Répondre » est le bouton plein ; dès
  qu'une réponse est ouverte, c'est son « Envoyer ». La date d'un message est courte : « Aujourd'hui 17:55 »,
  « Hier 9:12 », « 14 nov. ».
- **Les bandeaux** (préparé par un agent, conflit avec Gmail, images masquées, corbeille ou spam, envoi programmé) ont
  tous le même dessin : seule leur icône est en couleur, leurs boutons ne s'écrasent plus.
- **« Envoyé · Annuler »** s'affiche dans la barre de la réponse qui part, plus par-dessus son texte.
- **Les adresses** : « Cc » et « Cci » en gris ; une adresse invalide porte un triangle, une adresse jamais écrite un
  « ? », pas seulement une couleur.

## 0.42.0 — 19 novembre 2026

**L'Accueil : ta journée est la page, Colin a son panneau à droite.**

- **Ta journée en page** : la date en grand titre, puis une seule ligne, « Depuis hier 19:40 · 1 mail de client, 2
  projets ont bougé  Voir › ». Dessous, « Aujourd'hui », « À valider » et « À faire », dans une colonne de lecture.
- **Colin a son panneau**, à droite, sur toute la hauteur, sur un fond à lui. Son en-tête dit enfin où il en est :
  prêt, répond…, attend ton call, en panne, à l'arrêt. Plus jamais « en marche » pendant un call ou une panne.
- **Des lignes calmes** : plus aucun bouton au repos. « Relire », « Ouvrir », « Ranger », « Reporter » et « Livré »
  apparaissent quand la souris passe sur la ligne, sans rien déplacer, et au clic droit.
- **« Rejoindre »** est le seul bouton plein de l'écran, dix minutes avant le rendez-vous.
- **Le fil de Colin** : chaque carte dit ce qu'elle est (« Projet modifié », « Nouveau projet », « Brouillon »,
  « Message à copier ») et se détache du panneau ; « Copier » n'est plus là deux fois ; « Annuler » devient un mot
  discret ; plus de trou sous une carte.
- **Fenêtre étroite** : la journée prend toute la page ; la barre de Colin flotte en bas et dit où il en est, ou le
  début de sa dernière réponse. Un clic ouvre son fil par-dessus, Échap le referme.

## 0.41.0 — 19 novembre 2026

**Une barre latérale courte, et « fermer » ramène d'où l'on vient.**

- **La barre latérale** ne liste plus que des lieux : sous Mails, Boîte de réception, Brouillons et Envoyés ; les
  autres dossiers sous « Plus », qui se déplie de lui-même quand l'un d'eux est ouvert. Inspiration tient sur une
  ligne, Contacts descend près de Réglages, et la cloche monte près du bouton de la barre latérale. Douze lignes au
  lieu de vingt-deux, dans une barre plus étroite.
- **Les boîtes** sont un menu « Boîtes » dans la barre de la liste des mails, à côté de « Non lus ». Il dit
  « Boîtes : 2 sur 3 » quand une est masquée.
- **Inspiration** : Websites, Branding et Mock-ups se choisissent en haut de la page, comme Kanban et Liste.
- **Fermer, c'est revenir** : ✕, Échap, un clic à côté et la flèche de retour ramènent d'où l'on vient. Un projet
  ouvert depuis l'Accueil revient à l'Accueil, sans ajouter de pas à « Précédent ». Le ✕ est toujours en haut à droite.
- **Les raccourcis marchent dans la fenêtre**, les mêmes que dans Coup d'œil : ⌘1 à ⌘7 dans l'ordre de la barre
  latérale (Inspiration ⌘6, Contacts ⌘7), ⌘, pour Réglages, ⌘N pour le « + » de la page, ⌘F pour sa recherche.
  ⌘← et ⌘→ vont au début et à la fin de la ligne dans un mail qu'on écrit.
- **Les titres** de la fenêtre disent la section, puis où l'on est dedans ; plus le nom de ce qui est déjà écrit en
  grand dans la page.
- **Les liens** : le projet d'un mail, d'une réunion ou d'un rendez-vous s'ouvre depuis son menu ; la date d'une
  réunion mène à son rendez-vous ; les prochains rendez-vous d'un projet mènent au Calendrier.

## 0.40.1 — 19 novembre 2026

**Dix-neuf défauts de logique corrigés**, trouvés par l'audit puis confirmés un par un, chacun avec son test.

- **Mails** : un mail en plusieurs morceaux de texte s'affiche en entier ; une invitation Outlook est reconnue comme
  un mail d'agenda ; tes gestes (archiver, lire, envoyer) ne font plus la queue derrière la synchronisation ; un
  retour après quelques jours ne bloque plus tout le rattrapage.
- **Ranger** : ranger un fil à la main ne déplace plus tous les fils de son expéditeur ; « Tous les mails de cet
  expéditeur » dit quand il en montre une partie.
- **L'Accueil** : « Pas besoin » sur une personne revient sur son nouveau message, pas sur l'ancien fil ; une réponse
  commencée puis laissée ne cache plus « attend ta réponse » indéfiniment ; un enregistrement mis à la corbeille
  n'est plus « à ranger ».
- **Agenda et réunions** : un rendez-vous qui en chevauche un autre ne lui prend plus son enregistrement ; « Aucun »
  tient ; corriger le projet d'un rendez-vous corrige celui de ses invités ; un projet à la corbeille ne reçoit plus
  rien ; un invité de deux projets se range d'après le titre ; une adresse tapée sans ↩ est bien invitée ; un
  rendez-vous créé par un agent est annoncé par la cloche.
- **Calendrier** : au-delà de 60 jours, il dit que sa copie s'arrête là.
- **Contacts** : une adresse déjà prise par un autre contact est refusée, en le disant.
- **Inspiration** : une image qui a échoué une fois est retentée.

## 0.40.0 — 19 novembre 2026

**Polhub a sa propre couleur, l'encre, et chaque couleur ne dit plus qu'une chose.**

- **L'encre** (presque noir en clair, presque blanc en sombre) remplace l'orange du Mac : le bouton principal, la
  sélection, les liens. L'orange ne voulait plus rien dire à force de tout dire.
- **Une couleur, un sens** : rouge pour ce qui est en retard, orangé pour ce qui est à vérifier, rouge vif pour un
  enregistrement, vert pour ce qui est fait, violet pour ce qu'un agent ou Colin a préparé. Toutes se lisent, en clair
  comme en sombre.
- **Les boutons** : un seul bouton plein par écran, l'action principale ; les autres à contour fin ou discrets. Plus
  de bouton en verre dans les pages, qui paraissait éteint quand Polhub n'était pas au premier plan.
- **Les erreurs** se disent par une icône et une phrase lisible, plus par une phrase en orange.
- **Les angles** : trois arrondis seulement, partout les mêmes.

## 0.39.2 — 19 novembre 2026

**Sécurité : les portes que l'audit a trouvées sont fermées. Presque rien ne change à l'écran.**

- **Google** : le fichier de la clé ne dit plus où partent les jetons ; les adresses de Google sont écrites dans l'app.
- **« Vérifié par Gmail »** ne se falsifie plus : seul compte le verdict DMARC de Gmail, pour le domaine de l'expéditeur.
- **Les pièces jointes d'un agent** : jamais une clé, un secret ou une base de données, où qu'ils soient. Un fichier
  Keynote passe.
- **Colin** ne reprend plus d'un contexte à l'autre une réponse tirée d'un mail ou d'une réunion : il relit la source.
- **Quitter** pendant un enregistrement, ou juste avant le départ d'un mail, demande confirmation.
- **Un lien trompeur** dans un mail le dit à côté du lien : « ⚠︎ mène à … ».
- **Mises à jour** : la notarisation d'Apple est exigée, et l'app copiée est revérifiée avant d'être lancée.
- **Réseau local** : une image de mail n'atteint plus le Mac lui-même, le NAS ni le routeur.
- **Agents** : trois rendez-vous par heure au plus ; une app n'est jamais un « dossier de code ».
- **Journaux** : la détection ne garde plus les codes Meet, les titres ni les adresses.

## 0.39.1 — 19 novembre 2026

**Polhub se fait oublier quand il ne fait rien.**

- **L'icône de la barre des menus** n'est plus redessinée que quand elle change. Elle l'était deux fois par seconde,
  sur chaque écran : c'était les trois quarts du travail de Polhub au repos (mesuré : 7 à 9 % d'un cœur).
- **La détection des Meet** ne relit plus chaque seconde l'état audio de toutes les apps du Mac, seulement celui de Dia.
- **Sur l'Accueil**, l'animation du texte de Colin s'arrête une fois sa réponse écrite.

## 0.39.0 — 19 novembre 2026

**Des fils de mails lisibles : l'historique et les signatures se replient.**

- **L'historique cité** de chaque réponse se replie derrière « Historique ▾ », y compris celui d'Outlook (le bloc
  « De / Envoyé / À / Objet ») et celui recopié à plat au milieu d'un paragraphe. Un clic le déplie.
- **Les signatures** se replient derrière « Signature ▾ » : coordonnées, logos, mentions légales. La formule et le
  prénom restent.
- **Les en-têtes** « De / Date / À / Cc / Objet » d'un message cité ou transféré sont petits et pâles.
- Un transfert reste lisible, et un message qui ne serait plus que vide ne se replie pas.
- Correction : la dernière ligne de certains mails Outlook n'est plus coupée.

## 0.38.1 — 19 novembre 2026

**Un projet qui change de colonne se met en haut.**

- Déplacé sur le tableau, changé de statut sur sa page, ou par un agent ou une règle de Colin : le projet arrive **en
  haut** de sa nouvelle colonne, visible tout de suite, au lieu de tout en bas. Posé sur une autre carte, il se met
  juste au-dessus d'elle, comme avant. « Annuler » le remet à sa place d'avant.

## 0.38.0 — 19 novembre 2026

**Colin crée un projet quand tu le lui demandes.**

- **« Crée-moi un projet… »** : Colin le crée avec son nom, son statut, son client et son échéance. Le projet arrive
  dans le fil en carte mise en avant, « Nouveau projet », avec « Ouvrir le projet » et « Annuler » (qui le met à la
  corbeille). Colin répond en une phrase.
- **Par prudence**, Colin ne crée pas de projet juste après avoir lu le mail d'un tiers : il le dit, et ta question
  suivante repart à neuf.

## 0.37.1 — 19 novembre 2026

**Des corrections d'affichage, petite et grande fenêtre.**

- **Plus de bande au-dessus des cartes** de l'Accueil, ni au-dessus de la liste de Réunions : la barre du haut est la
  même sur toute la largeur.
- **Un mail ouvert dans une fenêtre étroite** : « 1 sur 2 500 », les flèches, « Archiver » et « Supprimer » passent
  au-dessus du sujet au lieu de s'écraser.
- **Les traits du calendrier** restent nets à toutes les largeurs, aussi sur un écran qui n'est pas Retina.

## 0.37.0 — 19 novembre 2026

**L'Accueil respire : ta journée en cartes, et « À faire » qui se déplie.**

- **Des cartes** pour « Aujourd'hui », « À valider », « À faire » et « Comptes Claude », avec de l'air, un trait fin
  entre deux lignes, des titres plus grands et leur nombre dans une pastille. « Aujourd'hui » vient en premier, mis en
  avant. La colonne est un peu plus large.
- **« À faire » se déplie** : un clic sur un projet montre sa tâche du moment et toutes ses actions en cours, avec
  « Ouvrir le projet », « Reporter » et « Livré ».
- **« Livré » propose le prochain call** : quand le projet a un rendez-vous à venir, « Livré, prochaine échéance : call
  jeudi 9:30 » pose ce jour comme nouvelle échéance ; « Livré, sans échéance » l'efface. Les deux le notent au journal.

## 0.36.0 — 19 novembre 2026

**Ta journée, en clair : les rendez-vous du jour puis de demain, ce qu'il y a à faire, et tes comptes Claude.**

- **Plus de chiffres flous** : les tuiles « rendez-vous », « à livrer » et « à toi » sont parties. À la place, des
  listes qui disent quoi, quel projet et quand.
- **Le soir, demain** : à partir de 19 h, une fois ton dernier rendez-vous fini, l'Accueil montre « Demain · jeudi 19
  novembre » et tes rendez-vous du lendemain. L'heure se règle dans Réglages › Calendrier.
- **« À faire »** : tes projets en priorité 2 et ceux dont l'échéance est proche ou passée, rangés « En retard »,
  « Aujourd'hui », « Demain », « Cette semaine », « Ensuite ». Chaque ligne dit le projet, le client, quand
  (« depuis 6 j », « vendredi », « call demain 9:30 ») et, dessous, la tâche du moment.
- **« Reporter » et « Livré »** sur chaque ligne datée : reporter à demain, à lundi, dans une semaine ou à une date ;
  « Livré » efface l'échéance et le note au journal du projet. « Annuler » reste quelques secondes.
- **Tes comptes Claude**, lus chez Vigie sur ce Mac : une barre par compte, « tient jusqu'à lundi » ou « plein jeudi
  14 h ». Sans Vigie, rien ne s'affiche.
- **Le bouton pour dicter est retiré** de la barre de Colin : la dictée de Polhub viendra plus tard. VoiceInk écrit
  dans la barre comme partout.

## 0.35.0 — 18 novembre 2026

**L'Accueil refait : une conversation avec Colin comme dans Claude, et ta journée d'un regard.**

- **La conversation avec Colin**, à gauche : une colonne de lecture, tes questions en bulles, les jours entre deux
  traits, l'heure au survol. Le texte de Colin s'écrit mot à mot, en fondu, sans saut à la fin.
- **Ce que fait Colin, dans son texte** : « Lit le fil « Devis · Claire Morel »… » pendant qu'il travaille, puis « A lu
  2 fils › », qui se déplie. Ce qu'il change sur un projet devient une carte « avant → après » avec « Annuler » ; un
  brouillon, une carte avec « Relire ». Sous chaque réponse : combien de temps il a travaillé, « Copier », et
  « Réessayer » après un arrêt.
- **La barre est réparée** : le texte est centré, elle grandit jusqu'à huit lignes, le fil passe sous son verre. Un
  bouton pour dicter, un rond orange pour envoyer, ■ pour arrêter. Entrée envoie, Maj+Entrée va à la ligne, Échap
  arrête. Au-dessus, tant que tu n'as rien demandé aujourd'hui, trois questions tirées de ta journée.
- **Le fil ne te ramène plus en bas** quand tu remontes lire : une flèche ↓ apparaît.
- **À droite, ta journée** : la date et des chiffres (rendez-vous, à livrer, à toi) qui posent leur question à Colin
  d'un clic ; « Depuis… » et « Voir », qui liste aussi les mails des clients ; le prochain rendez-vous en grand, avec
  « Rejoindre » qui s'allume dix minutes avant ; « À valider » avec le visage de la personne et une seule action par
  ligne.
- **Une seule couleur pour ce qui compte** : l'orange ne sert plus qu'à envoyer, rejoindre, et dire un retard.
- **En fenêtre étroite**, une bande du jour en haut ; « À valider » se déplie par-dessus la conversation.

## 0.34.0 — 18 novembre 2026

**« Annuler » : ce qu'un agent change sur un projet se voit et s'annule, et Colin tient le kanban.**

- **Chaque changement d'un projet est noté** par la base elle-même : statut, échéance, tâche du moment, client,
  notes, actions ajoutées, cochées, reformulées ou retirées, entrées du journal, avec qui (toi, Colin, un agent) et
  quand. Même les conversations Claude Code ouvertes avant cette mise à jour sont notées.
- **« Annuler » remet ce qu'un agent a écrit** et laisse ce qui a changé depuis : la carte revient dans sa colonne,
  à côté de sa voisine d'avant. Ce qu'une conversation Claude Code change sur une carte (statut, échéance, tâche,
  client, notes, action retirée) s'affiche aussi dans le fil de Colin, signé « Un agent », avec « Annuler ».
- **Colin change le kanban quand tu le lui dis** : « passe Studio Nord en priorité 1 », « l'échéance, c'est
  vendredi », « coche le devis », « note au journal que… ». Jamais les notes, le client, les contacts ; jamais une
  action retirée. Après le mail d'un client, il ne change que le projet de ce client : une demande sur plusieurs
  projets se fait un projet par question. Chaque changement apparaît dans son fil, avec « Annuler ».
- **« Colin tient le kanban seul »** (Réglages › Colin, coupé par défaut) : après un mail que tu envoies dans un fil
  de projet, la carte passe en priorité 1 avec « En attente retour de … » et une ligne au journal ; un rendez-vous
  pris devient l'échéance si elle est vide ou passée. Jamais un projet en pause ou terminé, ni ce que tu as changé
  toi-même depuis 24 h. Sans modèle, sur le Mac. Le nom écrit dans la tâche n'est qu'un prénom ou une adresse.
- **« Le point »** compte aussi les projets qui ont bougé sans toi depuis ton dernier passage ; « Voir » les liste,
  qui et quand, avec « Annuler ».
- **Ce qu'un agent écrit ne compte plus comme un geste de toi** : la « Dernière activité » d'un projet reste la tienne.

## 0.33.0 — 18 novembre 2026

**Colin te répond : une barre sur l'Accueil, et un fil unique.**

- **Sur l'Accueil**, sous « Le point », le fil de Colin et sa barre : « Écris ou dicte à Colin… ». Il répond en cinq
  lignes au plus : « où on en est sur Cabinet Martin », « sur quoi je me lance demain », « raccourcis le brouillon
  pour Claire ». Il lit tes projets, tes réunions, tes mails (ceux que tu laisses lire à tes agents) et ton agenda.
- **Il prépare, raccourcit ou supprime un brouillon** préparé par un agent ; « Relire » l'ouvre par-dessus l'Accueil.
  Il n'envoie jamais rien. Un brouillon que tu viens de lui demander ne sonne pas.
- **Un message à copier** (un WhatsApp pour Marc) arrive avec « Copier ». **Une chose à retenir** arrive avec
  « Garder » : un clic l'ajoute à « Ce que Colin sait ».
- **Il ne touche pas encore au tableau des projets** : ça vient avec « Annuler », à la prochaine étape.
- **Colin est à l'arrêt par défaut.** « Allumer Colin » sur l'Accueil, ou Réglages › Colin. « Mettre à l'arrêt »
  coupe une réponse en cours.
- **Pendant un call ou sa transcription, la barre attend** (« Colin attend la fin de ton call »), et un call qui
  commence arrête une réponse. Après un réveil du Mac, une question attend quelques minutes avant de partir.
- **Réglages › Colin** : l'interrupteur, le compte de Claude Code, « Ce que Colin sait » (ce qu'il relit à chaque
  échange : ta façon d'écrire, ton lien de rendez-vous…) et ce qu'il a fait cette semaine.
- **Ce qui part chez Anthropic, et seulement Colin allumé** : ce que tu lui écris, « Ce que Colin sait », vos derniers
  échanges, les lignes de l'Accueil et ce qu'il lit pour te répondre, par le Claude Code de ton Mac et ton abonnement.
  Jamais l'audio, les pièces jointes ni tes jetons. Les pages publiques le disent.
- **Garde-fous** : Colin n'a que des outils de lecture et le brouillon, en texte simple. Ce qu'il lit d'un client
  verrouille ses brouillons sur ce fil ou ce projet : un mail piégé ne peut rien lui faire écrire ailleurs. Un lien
  qu'il écrit n'est jamais cliquable. Claude Code est vérifié à chaque échange, et arrêté au moindre écart.

## 0.32.0 — 18 novembre 2026

**Un nouvel Accueil : d'un regard, ce qui attend ton clic et où tu en es.**

- **« À valider »** liste ce qui t'attend, une phrase et un bouton par ligne : « Brouillon prêt pour Claire »
  (Relire), « Marc attend ta réponse » (Ouvrir), « Anne ne répond plus » (Ouvrir), « Réunion à ranger » (Ranger). Une
  ligne part toute seule quand la chose est faite.
- **« Marc attend ta réponse »** se lit par personne, pas par fil : Marc t'a écrit, et depuis tu ne lui as rien
  écrit, dans aucun fil d'aucune de tes boîtes. La ligne vient après 3 jours (réglable) et part après 14. Une seule
  ligne par personne. Jamais pour une invitation d'agenda, une réponse automatique, une lettre d'information ou un
  collègue ; ni quand un brouillon pour lui est en cours, commencé dans Polhub ou dans Gmail ; ni quand vous vous êtes
  vus en rendez-vous depuis, ou que vous vous voyez dans la semaine.
- **« Anne ne répond plus »** se lit par projet : ton dernier mail du projet a 7 jours ou plus (réglable, 45 au plus),
  et depuis personne n'a écrit dans un fil du projet, aucune des personnes à qui tu l'as envoyé ne t'a écrit ailleurs
  (une réponse automatique ne compte pas, tes collègues non plus), et aucun rendez-vous du projet ne s'est tenu ni
  n'est prévu. Une seule ligne par projet, jamais pour un projet terminé.
- Le brouillon ou le fil s'ouvre **par-dessus l'Accueil** : tu relis, tu envoies, tu fermes, et la ligne suivante est
  là. Rien ne part sans ton clic sur « Envoyer ».
- Une ligne fausse s'écarte par son menu « … » : « Pas besoin » (jusqu'au prochain message de la personne, ou
  jusqu'à ton prochain mail du projet), « Plus tard » (jusqu'à demain), et pour un client muet « Anne a répondu
  ailleurs ». Dit deux fois de suite pour un même projet, Polhub ne signale plus les silences de ce projet.
- **« Aujourd'hui »** montre ce qui reste de ta journée, le prochain rendez-vous en tête avec « Rejoindre ». S'il ne
  reste rien, le rendez-vous suivant (« Demain 10:00 »).
- **« Le point »** tient en quatre phrases au plus : ta semaine, ce qui est à livrer, les projets où c'est à toi de
  jouer, et les mails de clients arrivés depuis ton dernier passage. Il se prépare quand tu reviens : la première
  fois de la journée, ou après trois heures.
- Quand un agent a préparé un mail, une notification le dit : « Colin : Brouillon prêt pour Claire. On le valide ? ».
  Un clic ouvre l'Accueil.
- Ce qui quitte l'Accueil : le grand titre daté, la grande carte du prochain rendez-vous, « Priorité 2 », « Dernières
  réunions » et « À classer ». Ce qu'ils disaient est dans les trois parties ci-dessus ; les réunions restent dans
  Réunions.
- **Réglages › Colin** : après combien de jours signaler un mail sans réponse (3 par défaut) et un client muet (7 par
  défaut). **Réglages › Notifications › Colin** : « Un brouillon est prêt ».
- Tout cela est calculé sur ton Mac, par des règles : aucune IA, aucun token, rien ne sort. Une boîte que tu masques
  dans Mails ne porte jamais « attend ta réponse » ni « ne répond plus » (ce que tu en as envoyé compte) ; un
  brouillon préparé par un agent s'affiche quelle que soit sa boîte. Colin, l'agent à qui tu parleras, arrive à
  l'étape suivante.

## 0.31.3 — 18 novembre 2026

**Polhub recompte les règles du nouvel Accueil, autrement.**

- Rien ne change dans tes écrans.
- Le premier relevé a montré que les deux règles sur tes mails parlaient beaucoup trop. Elles regardaient fil par fil,
  alors que tu réponds le plus souvent par un nouveau mail, et que tes clients envoient leurs fichiers dans de nouveaux
  fils.
- Polhub refait donc le compte une fois, hors réunion, en regardant l'échange avec la personne : lui as-tu écrit depuis,
  dans n'importe quel fil ? T'a-t-elle écrit depuis ? Il met à part les invitations d'agenda, et rejoue les règles sur
  les sept dernières semaines pour voir lesquelles auraient eu raison.
- Comme la première fois, il n'écrit que des nombres dans le dossier des mesures : aucun objet, aucune adresse, aucun
  nom. Rien ne sort du Mac, et aucune IA n'est utilisée.

## 0.31.2 — 18 novembre 2026

**Polhub prépare le nouvel Accueil : il retient qui a parlé en dernier dans chaque fil de mails.**

- Rien ne change dans tes écrans de tous les jours. Seule la fenêtre des sondes, dans Réglages › Diagnostic, gagne une
  ligne : « Colin : les règles sur tes mails ».
- Pour chaque fil, Polhub retient la date du dernier message reçu et celle de ton dernier message. C'est ce qui dira
  bientôt sur l'Accueil « Marc attend ta réponse » ou « Anne ne répond plus ».
- Une fois après la mise à jour, hors réunion, Polhub compte tout seul sur ton Mac combien de lignes ces deux règles
  donneraient aujourd'hui, et combien elles en auraient donné il y a deux semaines. Il n'écrit que des nombres, dans le
  dossier des mesures : aucun objet, aucune adresse, aucun nom. Rien ne sort du Mac, et aucune IA n'est utilisée.
- Un même échange reçu dans deux de tes boîtes est reconnu comme un seul : dès que tu as répondu depuis l'une, il
  n'attend plus dans l'autre.
- Avant de modifier ta base, Polhub en garde une copie, comme à chaque fois. La mise à jour de la base ne fait
  qu'ajouter deux colonnes et une table ; le calcul qui suit ne peut pas empêcher Polhub de s'ouvrir.

## 0.31.1 — 18 novembre 2026

**Une sonde pour préparer Colin, l'agent qui arrive sur l'Accueil.**

- Réglages › Diagnostic a une nouvelle section, « Sonde de Colin ». Elle mesure si le Claude Code de ton Mac répond
  bien quand c'est Polhub qui le lance : la connexion, ce qu'il charge, un outil permis et un outil refusé, une
  petite conversation avec une interruption, le temps du premier mot, le coût.
- Tu choisis le compte Claude à utiliser (par défaut celui de Claude Code), puis tu cliques sur « Lancer la sonde de
  Colin ». Elle dure environ deux minutes, et tu peux continuer à travailler. Un bouton « Arrêter » l'arrête.
- Elle n'envoie que des textes inventés, jamais un de tes mails ni une de tes réunions, et utilise un peu de ton
  abonnement : l'équivalent d'une dizaine de centimes. Son relevé ne garde que des nombres et des mots techniques.
- Elle vérifie que Claude Code ne lit rien de toi : ni tes réglages, ni tes consignes, ni sa propre mémoire.
- Si Claude Code n'est pas connecté sur ce compte, a atteint sa limite, ne répond pas, est introuvable, a chargé
  plus que prévu ou ne dit pas ce qu'il a chargé, elle s'arrête tout de suite, sans nouvel essai, et te dit pourquoi.
- Elle ne se lance pas pendant une réunion ou une transcription, ni dans les minutes qui suivent le démarrage ou le
  réveil du Mac. Elle s'arrête si une réunion commence, si le Mac se met en veille ou si Polhub quitte. Polhub ne se
  met pas à jour pendant qu'elle tourne.
- Rien d'autre ne change : Colin n'est pas encore dans l'app.

## 0.31.0 — 17 novembre 2026

**Tes agents corrigent le brouillon qu'ils ont préparé, au lieu d'en refaire un.**

- Quand tu demandes une correction, l'agent modifie le brouillon existant : il garde sa place, ses destinataires et
  le message cité. Seul ce qu'il change bouge (texte, objet, destinataires d'un nouveau mail) ; les fichiers qu'il
  joint s'ajoutent.
- Il peut aussi le supprimer quand tu le lui demandes, dans Polhub et dans Gmail.
- Il ne touche jamais un brouillon que tu as écrit toi-même, ni un brouillon programmé ou en train de partir.
- Si tu as retouché son brouillon, il doit d'abord relire ta version et repartir de ton texte : il ne l'écrase pas
  de mémoire. Une correction qui arrive après ta retouche est refusée, et Polhub te le dit.
- La version corrigée reste dans Polhub, hors de Gmail, jusqu'à ce que tu l'aies vue : rien ne part par erreur depuis
  ton téléphone. Une correction qui tombe pendant les secondes d'annulation d'un envoi annule l'envoi.
- Un message en bas de Mails te dit ce qu'un agent a préparé, modifié, supprimé ou n'a pas pu changer.

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
