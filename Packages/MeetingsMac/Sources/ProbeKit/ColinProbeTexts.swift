import Foundation

/// What the probe of Colin says to Claude Code: invented texts only, never a real mail nor a real meeting.
enum ColinProbeTexts {
    static let system = "Tu es Colin, l'assistant de Polhub. Réponds en français, en une ou deux phrases."

    static let ping = "Réponds seulement : ok"

    static let tools = "Appelle l'outil projets. Puis ajoute au journal du projet « Projet d'essai » la ligne « essai de la sonde ». Réponds ensuite : fini."

    static let turns = [
        "Dis bonjour en une phrase.",
        "Combien de projets vois-tu ? Sers-toi de l'outil projets.",
        "Compte de 1 à 300, un nombre par ligne.",
        "Dis seulement : encore là.",
    ]

    /// A client's mail with six remarks and a date.
    static let mail = """
        Objet : Retours sur la page d'accueil

        Bonjour,

        Merci pour la nouvelle version, elle nous plaît beaucoup. Voici nos retours après la réunion d'équipe de ce matin :

        1. Le titre principal est un peu long sur mobile : peut-on le couper en deux lignes ?
        2. La photo d'ouverture est trop sombre, nous préférons celle de l'atelier vu de la rue.
        3. Le bouton « Prendre rendez-vous » devrait rester visible quand on fait défiler la page.
        4. Dans la partie « Nos réalisations », il manque le projet de la médiathèque.
        5. Le texte sur l'équipe parle encore de huit personnes : nous sommes dix depuis septembre.
        6. Le pied de page affiche notre ancienne adresse.

        Pour le reste, rien à changer. Nous aimerions une mise en ligne avant jeudi 26 novembre, parce que nous présentons le site au salon le lendemain. Si ce délai est trop court, dis-le-nous vite et nous verrons ce qui peut attendre.

        Dernier point : pourrais-tu nous dire combien de temps demande l'ajout d'une page « Presse » ? Ce n'est pas urgent, c'est pour prévoir le budget de l'an prochain.

        Merci encore, et bonne fin de semaine.

        Claire Morel
        Atelier Dupont
        """

    static let mailRequest = "Voici un mail reçu. Rends seulement un objet JSON avec ces clés : sorte, retours (un nombre), echeance, citation (la phrase du mail qui donne l'échéance).\n\n" + mail

    static let threadRequest = "Voici un mail reçu. Écris une réponse courte, au tutoiement, qui accuse réception des retours et propose un point jeudi.\n\n" + mail

    private static let lines = [
        "Moi : On commence par la page d'accueil, j'ai intégré vos retours de la semaine dernière.",
        "Les autres : Oui, on a vu, le titre est mieux, mais la photo reste un peu sombre à notre goût.",
        "Moi : D'accord, je la remplace par celle de l'atelier vu de la rue, je l'ai déjà sous la main.",
        "Les autres : Parfait. Et pour le bouton de rendez-vous, il peut rester visible en bas de l'écran ?",
        "Moi : Oui, je le fixe en bas sur mobile, et je le laisse dans l'en-tête sur ordinateur.",
        "Les autres : Très bien. Il nous faut aussi la page des réalisations avec la médiathèque.",
        "Moi : Je l'ajoute, il me faut seulement trois photos et un texte de cinq lignes.",
        "Les autres : On vous envoie ça demain matin, Claire s'en occupe.",
        "Moi : Alors je peux tout mettre en ligne jeudi 26 novembre, avant votre salon.",
        "Les autres : C'est ce qu'il nous faut. On valide jeudi matin, et vous publiez l'après-midi.",
        "Moi : Entendu. La page Presse, on la garde pour janvier, avec le budget de l'an prochain.",
        "Les autres : Oui, janvier. Merci, on se dit à jeudi.",
    ]

    /// A meeting's dialogue of about 1 800 words: the same twelve lines, said again and again.
    static let call = Array(repeating: lines, count: 12).flatMap { $0 }.joined(separator: "\n")

    static let callRequest = "Voici la transcription d'une réunion. Rends les décisions, les actions et l'échéance, chacune avec la phrase qui la prouve.\n\n" + call
}
