import Foundation
import Testing
@testable import PolhubDesign

/// Polhub's words (lot 10, 20/11): one way to write an hour, a day, a length, a count, a help bubble, a problem. The
/// examples are the ones the app's own functions were tested on (`Briefing`, `MailText`, `DurationText`, `ContactsModel`,
/// `PanelModel`, `ClaudeAccountsText`), kept. Every date is made up.
@Suite struct WordsTests {
    var paris: Calendar {
        var calendar = Words.calendar
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }

    /// Wednesday 18/11/2026, 10:00 in Paris.
    var now: Date { at(18, 10) }

    /// A day of November 2026 (or another month, another year), in Paris.
    func at(_ day: Int, _ hour: Int = 0, _ minute: Int = 0, month: Int = 11, year: Int = 2026) -> Date {
        paris.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    // MARK: - The language

    @Test func theLanguageIsFixedOnce() {
        #expect(Words.locale.identifier == "fr_FR")
        #expect(Words.calendar.firstWeekday == 2 && Words.calendar.identifier == .gregorian && Words.calendar.locale == Words.locale)
    }

    // MARK: - Hours

    @Test func anHourHasNoZeroBeforeIt() {
        #expect(Words.time(at(18, 9, 5), calendar: paris) == "9:05")
        #expect(Words.time(at(18, 16, 30), calendar: paris) == "16:30")
        #expect(Words.time(at(18, 0, 30), calendar: paris) == "0:30")
        #expect(Words.time(at(18, 14), calendar: paris) == "14:00")
        #expect(Words.hour(8) == "8 h" && Words.hour(14) == "14 h")
        #expect(Words.timeRange(from: at(18, 9, 30), to: at(18, 10), calendar: paris) == "9:30 – 10:00")
    }

    // MARK: - Days

    @Test func daysAreCountedFromMidnightToMidnight() {
        #expect(Words.days(from: at(18, 23), to: at(19, 0, 30), calendar: paris) == 1)
        #expect(Words.days(from: at(18, 0, 5), to: at(18, 23, 55), calendar: paris) == 0)
        #expect(Words.days(from: now, to: at(17, 23, 59), calendar: paris) == -1)
        #expect(Words.weekday(now, calendar: paris) == "mercredi" && Words.weekday(now, short: true, calendar: paris) == "mer.")
    }

    /// A day in a sentence, as `Briefing` and `TodoRules` said it.
    @Test func aDayInASentenceIsSaidAsPaulWouldSayIt() {
        #expect(Words.day(at(18, 23), now: now, calendar: paris) == "aujourd'hui")
        #expect(Words.day(at(19), now: now, calendar: paris) == "demain")
        #expect(Words.day(at(17, 23, 59), now: now, calendar: paris) == "hier")
        #expect(Words.day(at(20), now: now, calendar: paris) == "vendredi")
        #expect(Words.day(at(24), now: now, calendar: paris) == "mardi")
        #expect(Words.day(at(13), now: now, calendar: paris) == "vendredi")
        // A week ahead or more: the day of the month; another month, its name; another year, the year.
        #expect(Words.day(at(30), now: now, calendar: paris) == "lundi 30")
        #expect(Words.day(at(2, month: 12), now: now, calendar: paris) == "mercredi 2 décembre")
        #expect(Words.day(at(1, month: 12), now: now, calendar: paris) == "mardi 1er décembre")
        #expect(Words.day(at(6, month: 1, year: 2027), now: now, calendar: paris) == "mercredi 6 janvier 2027")
        // A week back or more: « le », the month always.
        #expect(Words.day(at(2), now: now, calendar: paris) == "le 2 novembre")
        #expect(Words.day(at(12, month: 11, year: 2025), now: now, calendar: paris) == "le 12 novembre 2025")
    }

    /// A day and its hour in a sentence: `Briefing.dayLabel`'s words, all of them.
    @Test func aMomentInASentenceIsBriefingsOne() {
        #expect(Words.moment(at(18, 16, 30), now: now, calendar: paris) == "aujourd'hui 16:30")
        #expect(Words.moment(at(19, 10), now: now, calendar: paris) == "demain 10:00")
        #expect(Words.moment(at(21, 9, 5), now: now, calendar: paris) == "samedi 9:05")
        #expect(Words.moment(at(24, 9), now: now, calendar: paris) == "mardi 9:00")
        #expect(Words.moment(at(25, 9), now: now, calendar: paris) == "mercredi 25 à 9:00")
        #expect(Words.moment(at(2, 14, month: 12), now: now, calendar: paris) == "mercredi 2 décembre à 14:00")
        #expect(Words.moment(at(17, 19, 40), now: now, calendar: paris) == "hier 19:40")
        #expect(Words.moment(at(13, 19, 40), now: now, calendar: paris) == "vendredi 19:40")
        #expect(Words.moment(at(2, 9), now: now, calendar: paris) == "le 2 novembre")
    }

    /// A day in a meta: abbreviated, as `PanelModel.day(short:)` and `MailText.scheduledShort` wrote it.
    @Test func aDayInAMetaIsShort() {
        #expect(Words.shortDay(at(18, 8), now: now, calendar: paris) == "aujourd'hui")
        #expect(Words.shortDay(at(17, 8), now: now, calendar: paris) == "hier")
        #expect(Words.shortDay(at(19, 8), now: now, calendar: paris) == "demain")
        #expect(Words.shortDay(at(17, 8), now: at(19, 10), calendar: paris) == "mar.")
        #expect(Words.shortDay(at(23, 8), now: now, calendar: paris) == "lun.")
        #expect(Words.shortDay(at(12), now: now, calendar: paris) == "jeu.")
        #expect(Words.shortDay(at(11), now: now, calendar: paris) == "11 nov.")
        #expect(Words.shortDay(at(12, month: 11, year: 2025), now: now, calendar: paris) == "12 nov. 2025")
        // With its hour: the hour alone today.
        #expect(Words.shortMoment(at(18, 18, 30), now: now, calendar: paris) == "18:30")
        #expect(Words.shortMoment(at(19, 8), now: now, calendar: paris) == "demain 8:00")
        #expect(Words.shortMoment(at(17, 8), now: now, calendar: paris) == "hier 8:00")
        #expect(Words.shortMoment(at(23, 8), now: now, calendar: paris) == "lun. 8:00")
        #expect(Words.shortMoment(at(24, 8, month: 12), now: now, calendar: paris) == "24 déc. 8:00")
    }

    /// Never in digits (« 18/11 »): a date in a list, and a date in full for a heading.
    @Test func aDateIsInWordsNeverInDigits() {
        #expect(Words.shortDate(at(18), now: now, calendar: paris) == "18 nov.")
        #expect(Words.shortDate(at(1, month: 12), now: now, calendar: paris) == "1er déc.")
        #expect(Words.shortDate(at(3, month: 2), now: now, calendar: paris) == "3 févr.")
        #expect(Words.shortDate(at(12, month: 11, year: 2025), now: now, calendar: paris) == "12 nov. 2025")
        #expect(Words.fullDate(now, now: now, calendar: paris) == "mercredi 18 novembre")
        #expect(Words.fullDate(at(1, month: 11), now: now, calendar: paris) == "dimanche 1er novembre")
        #expect(Words.fullDate(at(12, month: 11, year: 2025), now: now, calendar: paris) == "mercredi 12 novembre 2025")
        #expect(Words.capitalizedFirst(Words.fullDate(now, now: now, calendar: paris)) == "Mercredi 18 novembre")
        #expect(Words.month(now, year: false, calendar: paris) == "novembre" && Words.month(at(3, month: 8), year: true, calendar: paris) == "août 2026")
    }

    /// `PanelModel.ago` to the minute, `ContactsModel.ago` by days.
    @Test func agoIsToTheMinuteOrByDays() {
        #expect(Words.ago(now.addingTimeInterval(-30), now: now) == "à l'instant")
        #expect(Words.ago(now.addingTimeInterval(-4 * 60), now: now) == "il y a 4 min")
        #expect(Words.ago(now.addingTimeInterval(-70 * 60), now: now) == "il y a 1 h 10")
        #expect(Words.ago(now.addingTimeInterval(60), now: now) == "à l'instant")
        func back(_ days: Int) -> Date { paris.date(byAdding: .day, value: -days, to: now)! }
        #expect(Words.daysAgo(back(0), now: now, calendar: paris) == "aujourd'hui")
        #expect(Words.daysAgo(back(1), now: now, calendar: paris) == "hier")
        #expect(Words.daysAgo(back(3), now: now, calendar: paris) == "il y a 3 jours")
        #expect(Words.daysAgo(back(8), now: now, calendar: paris) == "il y a 1 semaine")
        #expect(Words.daysAgo(back(20), now: now, calendar: paris) == "il y a 2 semaines")
        #expect(Words.daysAgo(back(95), now: now, calendar: paris) == "il y a 3 mois")
        #expect(Words.daysAgo(back(400), now: now, calendar: paris) == "il y a 1 an")
        #expect(Words.daysAgo(back(800), now: now, calendar: paris) == "il y a 2 ans")
    }

    /// Rounded up, as the card before a visio and the menu bar count.
    @Test func untilIsRoundedUp() {
        #expect(Words.until(now, now: now) == "maintenant")
        #expect(Words.until(now.addingTimeInterval(-90), now: now) == "maintenant")
        #expect(Words.until(now.addingTimeInterval(10), now: now) == "dans 1 min")
        #expect(Words.until(now.addingTimeInterval(61), now: now) == "dans 2 min")
        #expect(Words.until(now.addingTimeInterval(12 * 60), now: now) == "dans 12 min")
        #expect(Words.until(now.addingTimeInterval(65 * 60), now: now) == "dans 1 h 05")
    }

    // MARK: - Lengths

    @Test func aLengthIsInMinutesOrInHours() {
        // `DurationText.short`'s, kept; a round hour loses its « 00 ».
        #expect(Words.duration(2_520) == "42 min")
        #expect(Words.duration(3_900) == "1 h 05")
        #expect(Words.duration(20) == "moins d'une minute")
        #expect(Words.duration(7_200) == "2 h")
        #expect(Words.preciseDuration(7) == "7 s" && Words.preciseDuration(125) == "2 min 05" && Words.preciseDuration(3_900) == "1 h 05")
        // `DurationText.clock`'s, kept.
        #expect(Words.clock(0) == "0:00" && Words.clock(754) == "12:34" && Words.clock(3_723) == "1:02:03")
        #expect(Words.dayCount(1) == "1 jour" && Words.dayCount(6) == "6 jours" && Words.dayCount(6, short: true) == "6 j")
    }

    // MARK: - Numbers

    @Test func aNumberAccordsItsWord() {
        #expect(Words.number(7) == "7")
        #expect(Words.number(1_234) == "1\u{202F}234")
        #expect(Words.number(12_345_678) == "12\u{202F}345\u{202F}678")
        #expect(Words.number(-1_234) == "-1\u{202F}234")
        #expect(Words.count(1, "contact") == "1 contact" && Words.count(3, "contact") == "3 contacts")
        // The plural starts at 2.
        #expect(Words.count(0, "contact") == "0 contact")
        #expect(Words.count(2, "mois") == "2 mois" && Words.count(2, "prix") == "2 prix")
        #expect(Words.count(4, "mail de client", "mails de clients") == "4 mails de clients")
        #expect(Words.plural(1, "autre") == "autre" && Words.plural(2, "autre") == "autres")
        #expect(Words.plural(3, "a bougé", "ont bougé") == "ont bougé")
        #expect(Words.count(1_200, "mail") == "1\u{202F}200 mails")
        // `ClaudeAccountsText.percent`'s narrow space, kept.
        #expect(Words.percent(0.71) == "71\u{202F}%" && Words.percent(1) == "100\u{202F}%")
    }

    // MARK: - Punctuation

    @Test func theTypographyIsFrenchAtDisplay() {
        let nb = "\u{00A0}", narrow = "\u{202F}"
        #expect(Words.typeset("Rangé dans « Atelier » : 3 fils ?") == "Rangé dans «\(nb)Atelier\(nb)»\(nb): 3\(nb)fils\(nb)?")
        #expect(Words.typeset("Transcription 42 %") == "Transcription 42\(narrow)%")
        #expect(Words.typeset("42%") == "42\(narrow)%")
        // A number keeps what follows it: « 1 h 05 » whole, « 05 de » too.
        #expect(Words.typeset("1 h 05 de réunion") == "1\(nb)h\(nb)05\(nb)de réunion")
        #expect(Words.typeset("9:30 – 10:00") == "9:30\(nb)– 10:00")
        #expect(Words.typeset("Aujourd'hui, l'Accueil") == "Aujourd’hui, l’Accueil")
        // Neither an hour, a link, an address nor a quote at a word's edge.
        #expect(Words.typeset("https://exemple.fr/a?b=c à 9:05") == "https://exemple.fr/a?b=c à 9:05")
        #expect(Words.typeset("claire@exemple.fr") == "claire@exemple.fr")
        #expect(Words.typeset("'cité'") == "'cité'")
        #expect(Words.typeset("a%20b") == "a%20b")
        // Twice is once.
        let once = Words.typeset("Depuis hier 19:40 : 2 mails de clients.")
        #expect(Words.typeset(once) == once)
        #expect(Words.capitalizedFirst("aujourd'hui 16:30") == "Aujourd'hui 16:30" && Words.capitalizedFirst("") == "")
    }

    // MARK: - Help bubbles

    @Test func aHelpBubbleIsAVerbAndItsShortcut() {
        #expect(Words.help("Répondre", .command("r")) == "Répondre (⌘R)")
        #expect(Words.help("Répondre à tous", .shiftCommand("R")) == "Répondre à tous (⇧⌘R)")
        #expect(Words.help("Supprimer", .delete) == "Supprimer (⌫)")
        #expect(Words.help("Sélectionner", .space) == "Sélectionner (Espace)")
        #expect(Words.help("Arrêter la réponse", .escape) == "Arrêter la réponse (Échap)")
        #expect(Words.help("Ouvrir le fil précédent", .up) == "Ouvrir le fil précédent (↑)")
        #expect(Words.help(Words.joinHelp(account: "Exemple"), .return, .key("j")) == "Rejoindre dans Dia avec le compte Exemple (↩ ou J)")
        #expect(Words.help("Envoyer", .command("↩"), detail: "10 s pour annuler") == "Envoyer (⌘↩) : 10 s pour annuler")
        #expect(Words.help("Archiver") == "Archiver")
        #expect(Words.help("Archiver", shortcuts: []) == "Archiver")
        // The Mac's order of the modifiers: ⌃ ⌥ ⇧ ⌘.
        #expect(Words.Shortcut("K", modifiers: [.command, .shift, .option, .control]).glyphs == "⌃⌥⇧⌘K")
        #expect(Words.Shortcut.command(",").glyphs == "⌘," && Words.Shortcut.command("1").glyphs == "⌘1")
        #expect(Words.moreActions == "Plus d'actions")
    }

    // MARK: - Problems

    /// An error of Polhub's own, as a module makes it speak French here.
    enum Expired: Error, LocalizedError {
        case token
        var failureReason: String? { "la connexion à ce compte a expiré" }
        var recoverySuggestion: String? { "Reconnecte le compte dans Réglages › Comptes Google." }
    }

    enum Silent: Error { case crash }

    @Test func aProblemSaysWhatFailedThenWhatToDo() {
        let offline = Words.problem("Le fil n'a pas pu être rangé", URLError(.notConnectedToInternet))
        #expect(offline.sentence == "Le fil n'a pas pu être rangé : pas de connexion à Internet. Vérifie la connexion du Mac, puis réessaie.")
        #expect(offline.fragment == "pas de connexion à Internet")
        // The system's own words go to the journal, never to the screen.
        #expect(offline.journal?.hasPrefix("Le fil n'a pas pu être rangé : ") == true)
        #expect(!offline.sentence.contains("NSURLErrorDomain") && offline.journal?.contains("NSURLErrorDomain") == true)

        let expired = Words.problem("Le mail n'est pas parti.", Expired.token)
        #expect(expired.sentence == "Le mail n'est pas parti : la connexion à ce compte a expiré. Reconnecte le compte dans Réglages › Comptes Google.")
        #expect(expired.journal == nil)

        let disk = Words.problem("La pièce jointe n'a pas pu être copiée", CocoaError(.fileWriteOutOfSpace))
        #expect(disk.sentence == "La pièce jointe n'a pas pu être copiée : le disque est plein. Libère de la place sur le disque, puis réessaie.")
        #expect(Words.reason(of: POSIXError(.ENOSPC)) == "le disque est plein")
        #expect(Words.reason(of: URLError(.timedOut)) == "le serveur n'a pas répondu à temps")

        // What Polhub does not know: what failed, and « Réessaie. »; the remedy said by the caller wins.
        let vous = NSError(domain: "WebKitErrorDomain", code: 102, userInfo: [NSLocalizedFailureReasonErrorKey: "Vous n'avez pas l'autorisation."])
        let unknown = Words.problem("La page n'a pas pu s'ouvrir", vous)
        #expect(unknown.reason == nil && unknown.sentence == "La page n'a pas pu s'ouvrir. Réessaie." && unknown.journal != nil)
        #expect(unknown.fragment == "la page n'a pas pu s'ouvrir")
        #expect(Words.problem("Le fil n'a pas pu être rangé", Silent.crash).sentence == "Le fil n'a pas pu être rangé. Réessaie.")
        #expect(Words.problem("Le mail n'est pas parti", Silent.crash, remedy: "Il t'attend dans Brouillons.").sentence
                == "Le mail n'est pas parti. Il t'attend dans Brouillons.")
        #expect(Words.problem("Les projets ne s'ouvrent pas", remedy: "Quitte Polhub et rouvre-le.").sentence
                == "Les projets ne s'ouvrent pas. Quitte Polhub et rouvre-le.")
    }
}
