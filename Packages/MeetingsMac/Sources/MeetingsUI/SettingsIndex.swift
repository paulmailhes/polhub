import Foundation
import HubDesign

/// A setting, as the search of Réglages finds it (21/11, Paul: « une barre de recherche pour rechercher des réglages »):
/// its page, its title as the page writes it, and the words someone may type for it.
struct SettingsEntry: Equatable, Hashable, Sendable {
    let pane: SettingsPane
    let title: String
    var words = ""
}

/// Every setting of Réglages, page by page, in the pages' order. A setting added to a page is added here too: the test
/// `SettingsIndexTests` checks the main ones.
enum SettingsIndex {
    static let entries: [SettingsEntry] = pages.flatMap { pane, settings in
        [SettingsEntry(pane: pane, title: pane.title, words: pane.subtitle)] + settings.map { SettingsEntry(pane: pane, title: $0.0, words: $0.1) }
    }

    static let pages: [(SettingsPane, [(String, String)])] = [
        (.addOns, [("Installer un add-on", "outil ajouter"), ("Désinstaller un add-on", "retirer supprimer"),
                   ("Revoir la bienvenue", "onboarding accueil premier lancement")]),
        (.projects, [("Taille des cartes", "kanban"), ("Logos des sites des clients", "icône site")]),
        (.meetings, [("Comptes rendus automatiques", "résumé ia apple"), ("Langue des réunions", "transcription anglais français"),
                     ("Compte rendu prêt", "notification"), ("Visio commencée sans enregistrement", "notification meet enregistrer")]),
        (.dictation, [("Touche", "raccourci option commande"), ("Façon", "appuyer tenir mode"), ("Arrêt seul", "silence automatique"),
                      ("Langue", "français automatique"), ("Place", "fenêtre en haut en bas encoche"), ("Mots en direct", "live temps réel"),
                      ("Sans les « euh »", "hésitations hum bah"), ("Ponctuation dite", "à la ligne virgule point"),
                      ("Nombres en chiffres", "heures euros pourcent"), ("Sans point final", "message chat"),
                      ("Paragraphes", "pause sujet retour"), ("Espace après", "coller"), ("Micros", "microphone casque bluetooth airpods"),
                      ("Petits sons", "bip son"), ("Couper le son du Mac", "muet volume sourdine"), ("Pause musique et vidéo", "spotify youtube"),
                      ("Garder le son", "audio enregistrement réécouter"), ("Garder l'historique", "effacer jours"),
                      ("Presse-papiers", "copier coller"), ("Accessibilité", "autorisation")]),
        (.vigie, [("Auto-accept", "claude code accepter automatique"), ("Quand je ne suis pas là, Claude choisit l'option recommandée", "questions réponse automatique absent"),
                  ("Garde-fous", "actions sensibles sudo refuser délai"), ("Mises à jour automatiques", "version vigie app"),
                  ("Arrêter les Chrome oubliés", "navigateur processus"), ("MCP du compte dans les nouvelles conversations", "connecteurs gmail drive"),
                  ("Relancer le moteur", "redémarrer vigie")]),
        (.calendar, [("Agenda par défaut", "compte nouveau rendez-vous"), ("Visio Google Meet", "lien meet"), ("Durée", "minutes rendez-vous"),
                     ("La grille s'ouvre à", "heure semaine"), ("Afficher le week-end", "samedi dimanche"),
                     ("L'Accueil montre demain à partir de", "lendemain soir"), ("Rappels avant un rendez-vous", "notification minutes"),
                     ("Seulement les visios", "rappels meet"), ("Carte qui reste à l'écran avant une visio", "notification rejoindre"),
                     ("Nouveau rendez-vous dans tes agendas", "notification")]),
        (.mails, [("Densité d'affichage", "liste compacte"), ("Séparer les jours", "aujourd'hui hier"), ("Images distantes", "pixel suivi"),
                  ("Délai d'annulation de l'envoi", "annuler envoyer"), ("Après un archivage ou une suppression", "suivant liste"),
                  ("Ce que lisent tes agents", "claude code mcp"), ("Nouveau mail dans la Boîte de réception", "notification"),
                  ("Seulement les mails de tes projets", "notification"), ("Tri", "ranger règles projets")]),
        (.inspiration, [("Pages LinkedIn", "suivre sources"), ("Collecte automatique", "awwwards"), ("Catégories par l'IA d'Apple", "ranger")]),
        (.colin, [("Colin en marche", "agent claude"), ("Colin tient le kanban seul", "projets priorité"),
                  ("Ce que Colin sait", "mémoire consignes"), ("Signaler un mail sans réponse après", "relance jours"),
                  ("Signaler un client muet après", "relance jours"), ("Un brouillon est prêt", "notification")]),
        (.iphone, [("Accès depuis l'iPhone", "tailscale"), ("Relier un iPhone", "qr code appairer"), ("iPhone reliés", "appareils retirer"),
                   ("Copie dans iCloud", "cloud synchronisation"), ("Notifications sur l'iPhone", "push")]),
        (.accounts, [("Ajouter un compte Google", "connecter gmail agenda"), ("Autoriser les mails", "gmail accès"),
                     ("Couleur d'un compte", "agenda"), ("Déconnecter un compte", "retirer")]),
        (.diagnostic, [("Autorisations", "confidentialité accès macos"), ("Micro", "microphone autorisation"),
                       ("Accessibilité", "autorisation dictée"), ("Notifications", "autorisation macos"),
                       ("Enregistrement de l'audio du système", "son des autres réunions"), ("Automatisation de Dia", "navigateur"),
                       ("Modèles de transcription", "whisper télécharger"), ("Comptes Google", "connexions"), ("Claude Code", "colin"),
                       ("Moteur de Vigie", "connexion"), ("iCloud", "iphone"), ("Sondes de mesure", "test")]),
        (.general, [("Ouvrir hub à l'ouverture de session", "démarrage relance login"), ("Ouvrir un mail ou un projet", "fenêtre flottante pleine page"),
                    ("Minutes avant une visio dans la barre des menus", "menu barre"), ("Son des notifications", "notification"),
                    ("Envoyer un essai", "notification test"), ("Installer automatiquement les mises à jour", "version update"),
                    ("Vérifier maintenant", "mise à jour version"), ("Version installée", "mise à jour")]),
        (.journal, [("Ce que hub a fait et vu", "historique événements")]),
    ]

    /// Small letters, no accents: « Écran » finds « ecran », « Réunions » finds « reunion ».
    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Words.locale)
            .replacingOccurrences(of: "’", with: "'")
    }

    /// The settings whose title, words or page hold every word typed, on the pages there are; a page's own entry when
    /// its name matches, then its settings.
    static func search(_ query: String, in panes: Set<SettingsPane>) -> [SettingsEntry] {
        let words = fold(query).split(whereSeparator: { $0.isWhitespace || $0 == "'" }).map(String.init)
        guard !words.isEmpty else { return [] }
        return entries.filter { entry in
            guard panes.contains(entry.pane) else { return false }
            let haystack = fold(entry.title + " " + entry.words + " " + entry.pane.title)
            return words.allSatisfy { haystack.contains($0) }
        }
    }
}
