import Foundation

/// hub's words (lot 10, 20/11): the one place where an hour, a day, a length, a count, a help bubble and a problem
/// are written, so that each says the same thing the same way everywhere. The language is fixed here, once: French,
/// whatever the Mac's. The rules are in docs/design-system.md, « Les mots ». Pure: tested on made-up dates, no screen.
///
/// The formats keep the behaviors the app's own functions were tested on (`Briefing`, `MailText`, `DurationText`,
/// `ContactsModel`, `PanelModel`, `ClaudeAccountsText`). They write plain spaces: the typography of the screen (spaces
/// that never break) is laid at display by `typeset`, which the components call. Two exceptions,
/// part of the number itself: the thousands' separator and the space before « % », narrow and unbreakable.
public enum Words {
    // MARK: - The language

    /// French, whatever language the Mac speaks.
    public static let locale = Locale(identifier: "fr_FR")

    /// Paul's calendar: gregorian, French, weeks from Monday, the Mac's time zone (as Calendrier's and Coup d'œil's).
    public static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        calendar.firstWeekday = 2
        return calendar
    }

    static let weekdays = ["dimanche", "lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi"]
    static let shortWeekdays = ["dim.", "lun.", "mar.", "mer.", "jeu.", "ven.", "sam."]
    static let months = ["janvier", "février", "mars", "avril", "mai", "juin", "juillet", "août", "septembre", "octobre", "novembre", "décembre"]
    static let shortMonths = ["janv.", "févr.", "mars", "avr.", "mai", "juin", "juil.", "août", "sept.", "oct.", "nov.", "déc."]

    // MARK: - Hours

    /// « 9:05 », « 14:00 », « 0:30 »: an hour of a day, never a zero before it.
    public static func time(_ date: Date, calendar: Calendar = Words.calendar) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return "\(parts.hour ?? 0):\(twoDigits(parts.minute ?? 0))"
    }

    /// « 9 h », « 14 h »: an hour as such, without a day — the grid of the calendar, a setting (« s'ouvre à 8 h »).
    public static func hour(_ hour: Int) -> String {
        "\(hour) h"
    }

    /// « 9:30 – 10:00 »: from one hour to another, an en dash between them.
    public static func timeRange(from start: Date, to end: Date, calendar: Calendar = Words.calendar) -> String {
        "\(time(start, calendar: calendar)) – \(time(end, calendar: calendar))"
    }

    // MARK: - Days

    /// Whole days from one date to another, as a calendar counts them: from one midnight to the next, whatever the hours.
    /// Negative when `end` is before `start`.
    public static func days(from start: Date, to end: Date, calendar: Calendar = Words.calendar) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: end)).day ?? 0
    }

    /// « jeudi »; `short`, « jeu. » (a meta).
    public static func weekday(_ date: Date, short: Bool = false, calendar: Calendar = Words.calendar) -> String {
        let index = (calendar.component(.weekday, from: date) - 1 + 7) % 7
        return short ? shortWeekdays[index] : weekdays[index]
    }

    /// A day in a sentence, as Paul says it (`Briefing`'s, the most right): « aujourd'hui », « demain », « hier »; within
    /// six days, « jeudi »; further ahead, « lundi 30 », « mercredi 2 décembre », « mercredi 2 décembre 2027 »;
    /// further back, « le 2 novembre », « le 2 novembre 2025 ». The first of a month is « 1er ».
    public static func day(_ date: Date, now: Date, calendar: Calendar = Words.calendar) -> String {
        switch days(from: now, to: date, calendar: calendar) {
        case 0: "aujourd'hui"
        case 1: "demain"
        case -1: "hier"
        case -6 ... -2, 2...6: weekday(date, calendar: calendar)
        case 7...: "\(weekday(date, calendar: calendar)) \(dayOfMonth(date, now: now, calendar: calendar, month: false))"
        default: "le \(dayOfMonth(date, now: now, calendar: calendar, month: true))"
        }
    }

    /// A day and its hour in a sentence: « aujourd'hui 16:30 », « demain 10:00 », « hier 19:40 », « samedi 9:05 »; a
    /// week ahead or more, « mercredi 25 à 9:00 », « mercredi 2 décembre à 14:00 »; a week back or more, the day alone,
    /// « le 2 novembre ».
    public static func moment(_ date: Date, now: Date, calendar: Calendar = Words.calendar) -> String {
        let away = days(from: now, to: date, calendar: calendar)
        if away <= -7 { return day(date, now: now, calendar: calendar) }
        return day(date, now: now, calendar: calendar) + (away >= 7 ? " à " : " ") + time(date, calendar: calendar)
    }

    /// A day in a meta (a list, a chip, the end of a line), short: « aujourd'hui », « demain », « hier »; within six days,
    /// « jeu. »; else « 12 nov. », « 12 nov. 2025 » (another year).
    public static func shortDay(_ date: Date, now: Date, calendar: Calendar = Words.calendar) -> String {
        switch days(from: now, to: date, calendar: calendar) {
        case 0: "aujourd'hui"
        case 1: "demain"
        case -1: "hier"
        case -6 ... -2, 2...6: weekday(date, short: true, calendar: calendar)
        default: shortDate(date, now: now, calendar: calendar)
        }
    }

    /// A day and its hour in a meta: the hour alone today (« 16:30 »), else « demain 8:00 », « hier 8:00 »,
    /// « jeu. 8:00 », « 24 nov. 8:00 », « 24 nov. 2025 8:00 ».
    public static func shortMoment(_ date: Date, now: Date, calendar: Calendar = Words.calendar) -> String {
        if days(from: now, to: date, calendar: calendar) == 0 { return time(date, calendar: calendar) }
        return "\(shortDay(date, now: now, calendar: calendar)) \(time(date, calendar: calendar))"
    }

    /// A date, short, without words of time: « 12 nov. », « 1er déc. », « 12 nov. 2025 » (another year than `now`'s).
    /// A list's column, as Gmail's.
    public static func shortDate(_ date: Date, now: Date, calendar: Calendar = Words.calendar) -> String {
        let parts = calendar.dateComponents([.day, .month, .year], from: date)
        let text = "\(ordinal(parts.day ?? 1)) \(shortMonths[((parts.month ?? 1) - 1 + 12) % 12])"
        return parts.year == calendar.component(.year, from: now) ? text : "\(text) \(parts.year ?? 0)"
    }

    /// A date in full, for a heading: « jeudi 19 novembre », « jeudi 19 novembre 2025 » (another year than `now`'s).
    /// At a line's head, `capitalizedFirst` gives « Jeudi 19 novembre ».
    public static func fullDate(_ date: Date, now: Date, calendar: Calendar = Words.calendar) -> String {
        "\(weekday(date, calendar: calendar)) \(dayOfMonth(date, now: now, calendar: calendar, month: true))"
    }

    /// « novembre »; `year`, « novembre 2026 »: a month, for a heading (the calendar's, a group of a list).
    public static func month(_ date: Date, year: Bool, calendar: Calendar = Words.calendar) -> String {
        let parts = calendar.dateComponents([.month, .year], from: date)
        let name = months[((parts.month ?? 1) - 1 + 12) % 12]
        return year ? "\(name) \(parts.year ?? 0)" : name
    }

    /// How long ago, to the minute: « à l'instant », « il y a 4 min », « il y a 1 h 10 ». For what is recent (a
    /// notification, a summary just written); by days, `daysAgo`.
    public static func ago(_ date: Date, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        return seconds < 60 ? "à l'instant" : "il y a " + duration(seconds)
    }

    /// How long ago, by days: « aujourd'hui », « hier », « il y a 3 jours », « il y a 1 semaine », « il y a 2 semaines »,
    /// « il y a 3 mois », « il y a 1 an », « il y a 2 ans ».
    public static func daysAgo(_ date: Date, now: Date, calendar: Calendar = Words.calendar) -> String {
        let ago = max(0, days(from: date, to: now, calendar: calendar))
        switch ago {
        case 0: return "aujourd'hui"
        case 1: return "hier"
        case ..<7: return "il y a \(ago) jours"
        case ..<35: return ago / 7 == 1 ? "il y a 1 semaine" : "il y a \(ago / 7) semaines"
        case ..<365: return "il y a \(max(1, ago / 30)) mois"
        default: return ago / 365 == 1 ? "il y a 1 an" : "il y a \(ago / 365) ans"
        }
    }

    /// How long until, to the minute: « maintenant », « dans 1 min », « dans 12 min », « dans 1 h 05 ». The minutes are
    /// rounded up, as Coup d'œil, the menu bar and the card before a visio count them.
    public static func until(_ date: Date, now: Date) -> String {
        let seconds = date.timeIntervalSince(now)
        guard seconds > 0 else { return "maintenant" }
        return "dans " + duration(max(1, Int((seconds / 60).rounded(.up))) * 60)
    }

    // MARK: - Lengths

    /// A length, to the minute: « moins d'une minute », « 42 min », « 1 h 05 », « 2 h ».
    public static func duration(_ seconds: Int) -> String {
        if seconds < 60 { return "moins d'une minute" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes) min" }
        let rest = minutes % 60
        return rest == 0 ? "\(minutes / 60) h" : "\(minutes / 60) h \(twoDigits(rest))"
    }

    /// A length to the second, for what is counted in seconds (a countdown, Colin's work): « 7 s », « 2 min 05 »; from an
    /// hour, as `duration`.
    public static func preciseDuration(_ seconds: Int) -> String {
        let seconds = max(0, seconds)
        if seconds < 60 { return "\(seconds) s" }
        if seconds < 3_600 { return "\(seconds / 60) min \(twoDigits(seconds % 60))" }
        return duration(seconds)
    }

    /// A clock that counts (a recording, the player, a turn of speech): « 0:00 », « 12:34 », « 1:02:03 ».
    public static func clock(_ seconds: Int) -> String {
        let seconds = max(0, seconds)
        let (hours, minutes, rest) = (seconds / 3_600, (seconds % 3_600) / 60, seconds % 60)
        return hours > 0 ? "\(hours):\(twoDigits(minutes)):\(twoDigits(rest))" : "\(minutes):\(twoDigits(rest))"
    }

    /// A number of days: « 1 jour », « 6 jours »; `short`, in a meta, « 6 j » (never in a sentence).
    public static func dayCount(_ days: Int, short: Bool = false) -> String {
        short ? "\(number(days)) j" : count(days, "jour")
    }

    // MARK: - Numbers

    /// « 7 », « 1 234 », « -12 345 »: the thousands apart by a narrow space that never breaks, as French writes them.
    public static func number(_ value: Int) -> String {
        let digits = String(value.magnitude)
        var grouped = ""
        for (index, digit) in digits.enumerated() {
            if index > 0, (digits.count - index) % 3 == 0 { grouped.append(narrowSpace) }
            grouped.append(digit)
        }
        return value < 0 ? "-" + grouped : grouped
    }

    /// The word for `count` of a thing: the singular for 0 and 1, the plural from 2 (French counts so). The plural is the
    /// word and an « s », a word ending in s, x or z keeping its form; give it when it is another (« mail de client »,
    /// « mails de clients »; « nouveau », « nouveaux »; « a bougé », « ont bougé »).
    public static func plural(_ count: Int, _ singular: String, _ plural: String? = nil) -> String {
        guard count.magnitude >= 2 else { return singular }
        if let plural { return plural }
        return ["s", "x", "z"].contains(where: singular.hasSuffix) ? singular : singular + "s"
    }

    /// « 1 contact », « 3 contacts », « 1 234 mails »: a number and its word, accorded.
    public static func count(_ count: Int, _ singular: String, _ plural: String? = nil) -> String {
        "\(number(count)) \(Words.plural(count, singular, plural))"
    }

    /// « 42 % »: a share from 0 to 1, rounded, a narrow space that never breaks before « % ».
    public static func percent(_ fraction: Double) -> String {
        "\(number(Int((fraction * 100).rounded())))\(narrowSpace)%"
    }

    // MARK: - Punctuation

    /// A space that never breaks, and its narrow kind.
    public static let unbreakableSpace: Character = "\u{00A0}"
    public static let narrowSpace: Character = "\u{202F}"

    /// French typography, laid at display (lot 10, 20/11): a space that never breaks before « : », « ; », « ? », « ! »
    /// and inside « », a narrow one before « % »; a number never parted from what it counts (« 3 contacts », « 45 min »,
    /// « 1 h 05 »); a range of hours never parted (« 9:30 – 10:00 »). The apostrophe stays straight (merge of lot
    /// 10, 20/11): only the components call `typeset`, and a page showed « d’affichage » beside « Aujourd'hui »; it curls
    /// once every text goes through here. The components that show a text call it; never an address, a link, a path or
    /// what Paul types. Applied twice, it changes nothing more.
    public static func typeset(_ text: String) -> String {
        let characters = Array(text)
        var result = ""
        result.reserveCapacity(characters.count)
        for (index, character) in characters.enumerated() {
            let previous = index > 0 ? characters[index - 1] : nil
            let next = index + 1 < characters.count ? characters[index + 1] : nil
            switch character {
            case " ":
                // A line may break after a dash whatever follows it: a word joiner holds « – » to the hour after it.
                if previous == "–", next?.isNumber == true { result.append("\u{2060}") }
                result.append(space(previous: previous, next: next, twoBack: index > 1 ? characters[index - 2] : nil,
                                    threeBack: index > 2 ? characters[index - 3] : nil))
            case "%" where previous?.isNumber == true && (next.map { !$0.isLetter && !$0.isNumber } ?? true):
                result.append(narrowSpace)
                result.append("%")
            default:
                result.append(character)
            }
        }
        return result
    }

    /// The space between `previous` and `next`: unbreakable when what follows must not start a line, or what precedes
    /// must not end one.
    private static func space(previous: Character?, next: Character?, twoBack: Character?, threeBack: Character?) -> Character {
        if let next, [":", ";", "?", "!", "»", "–"].contains(next) { return unbreakableSpace }
        if previous == "«" { return unbreakableSpace }
        // « 9:30 – 10:00 » whole: a line broke after « 10:00 – » in the calendar's bubble (merge of lot 10, 20/11).
        if previous == "–", next?.isNumber == true { return unbreakableSpace }
        if next == "%", previous?.isNumber == true { return narrowSpace }
        // « 3 contacts », « 45 min », « 12 nov. »: a number keeps the word it counts.
        if previous?.isNumber == true, next?.isLetter == true { return unbreakableSpace }
        // « 1 h 05 »: the minutes keep their hour.
        if previous == "h", next?.isNumber == true, twoBack == " " || twoBack == unbreakableSpace, threeBack?.isNumber == true {
            return unbreakableSpace
        }
        return " "
    }

    /// « aujourd'hui 16:30 » → « Aujourd'hui 16:30 »: a fragment at the head of a line or a title.
    public static func capitalizedFirst(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst()
    }

    /// « de Marc », « d'Anne-Sophie »: « de » before a name, a project or a sender, elided before a vowel (merge of lot
    /// 10, 20/11). A « y » counts as a vowel before a consonant (« d'Yves », « de Yasmine »); an « h » never does, as it
    /// may be aspirated.
    public static func of(_ name: String) -> String {
        let letters = Array(name.prefix(2).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: locale))
        let vowels: Set<Character> = ["a", "e", "i", "o", "u", "æ", "œ"]
        guard let first = letters.first else { return "de \(name)" }
        let elided = vowels.contains(first) || (first == "y" && letters.count > 1 && !vowels.contains(letters[1]) && letters[1].isLetter)
        return elided ? "d'\(name)" : "de \(name)"
    }

    // MARK: - Words said in many places

    /// A thread without a subject.
    public static let noSubject = "(sans objet)"
    /// A whole day, in a meta or after a day: « Jeudi, toute la journée ».
    public static let allDay = "toute la journée"
    /// The help of every « … » menu (`IconMenu("ellipsis", help: Words.moreActions)`).
    public static let moreActions = "Plus d'actions"

    /// The help of every « Rejoindre »: « Rejoindre dans Dia avec le compte Pro ». `Words.help` adds the shortcut where
    /// one exists.
    public static func joinHelp(account: String) -> String {
        "Rejoindre dans Dia avec le compte \(account)"
    }

    // MARK: - Help bubbles

    /// A shortcut, as a help bubble writes it: the Mac's glyphs (⌘ ⇧ ⌥ ⌃ ↩ ⌫ ↑ ↓), « Échap » and « Espace » in letters.
    public struct Shortcut: Equatable, Sendable {
        public struct Modifiers: OptionSet, Equatable, Sendable {
            public let rawValue: Int
            public init(rawValue: Int) { self.rawValue = rawValue }
            public static let control = Modifiers(rawValue: 1 << 0)
            public static let option = Modifiers(rawValue: 1 << 1)
            public static let shift = Modifiers(rawValue: 1 << 2)
            public static let command = Modifiers(rawValue: 1 << 3)
        }

        public let key: String
        public let modifiers: Modifiers

        /// A key and its modifiers; a letter is written in capital, as on the keyboard.
        public init(_ key: String, modifiers: Modifiers = []) {
            self.key = key.count == 1 ? key.uppercased() : key
            self.modifiers = modifiers
        }

        /// « ⇧⌘R », « ⌫ », « Échap »: the modifiers in the Mac's order (⌃ ⌥ ⇧ ⌘), then the key.
        public var glyphs: String {
            let marks: [(Modifiers, String)] = [(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
            return marks.filter { modifiers.contains($0.0) }.map(\.1).joined() + key
        }

        public static let `return` = Shortcut("↩")
        public static let delete = Shortcut("⌫")
        public static let escape = Shortcut("Échap")
        public static let space = Shortcut("Espace")
        public static let tab = Shortcut("⇥")
        public static let up = Shortcut("↑")
        public static let down = Shortcut("↓")
        public static let left = Shortcut("←")
        public static let right = Shortcut("→")

        /// « ⌘R », « ⌘↩ », « ⌘, », « ⌘1 ».
        public static func command(_ key: String) -> Shortcut { Shortcut(key, modifiers: .command) }
        /// « ⇧⌘R ».
        public static func shiftCommand(_ key: String) -> Shortcut { Shortcut(key, modifiers: [.shift, .command]) }
        /// A key alone: « J ».
        public static func key(_ key: String) -> Shortcut { Shortcut(key) }
    }

    /// A help bubble (« Verbe + objet (raccourci) »), without a period: « Répondre (⌘R) », « Supprimer (⌫) »,
    /// « Rejoindre dans Dia avec le compte Pro (↩ ou J) »; a consequence after « : », « Envoyer (⌘↩) : 10 s pour
    /// annuler ». Say only a shortcut that works where the button is.
    public static func help(_ action: String, _ shortcuts: Shortcut..., detail: String? = nil) -> String {
        help(action, shortcuts: shortcuts, detail: detail)
    }

    /// The same, the shortcuts in a list (none: the action alone).
    public static func help(_ action: String, shortcuts: [Shortcut], detail: String? = nil) -> String {
        var text = action
        if !shortcuts.isEmpty { text += " (" + shortcuts.map(\.glyphs).joined(separator: " ou ") + ")" }
        if let detail, !detail.isEmpty { text += " : " + detail }
        return text
    }

    // MARK: - Problems

    /// A problem said in French (lot 10, 20/11): what did not work, why in Paul's words, then what to do. The system's
    /// own text never shows: `journal` keeps it, for the journal of Réglages, never for the screen.
    public struct Problem: Equatable, Sendable {
        /// What did not work, without a period: « Le fil n'a pas pu être rangé ».
        public let failed: String
        /// Why, a fragment: « pas de connexion à Internet »; `nil` when the error says nothing Paul can use.
        public let reason: String?
        /// What to do, a sentence: « Réessaie. »
        public let remedy: String
        /// What failed and the system's own text, for the journal; `nil` for hub's own errors, already in French.
        public let journal: String?

        /// « Le fil n'a pas pu être rangé : pas de connexion à Internet. Vérifie la connexion du Mac, puis réessaie. »
        public var sentence: String {
            failed + (reason.map { " : \($0)" } ?? "") + ". " + remedy
        }

        /// After a label (« Pro : … »), or where a sentence is too long: the reason, else what failed in small letters.
        public var fragment: String {
            reason ?? (failed.prefix(1).lowercased() + failed.dropFirst())
        }
    }

    /// The problem of a gesture that failed: `failed` says what did not work, without a period (« Le fil n'a pas pu être
    /// rangé »); `error` gives the reason, in Paul's words when hub knows it; `remedy`, what to do, when it is not
    /// « Réessaie. ».
    public static func problem(_ failed: String, _ error: (any Error)? = nil, remedy: String? = nil) -> Problem {
        let failed = failed.hasSuffix(".") ? String(failed.dropLast()) : failed
        guard let error else { return Problem(failed: failed, reason: nil, remedy: remedy ?? "Réessaie.", journal: nil) }
        let cause = cause(of: error)
        let raw = cause.own ? nil : "\(failed) : \(String(describing: error))"
        return Problem(failed: failed, reason: cause.reason, remedy: remedy ?? cause.remedy ?? "Réessaie.", journal: raw)
    }

    /// Why an error happened, in Paul's words: a fragment to follow « : » (« pas de connexion à Internet »), or `nil`
    /// when hub does not know it — the system's own text is never one.
    public static func reason(of error: any Error) -> String? {
        cause(of: error).reason
    }

    /// What hub knows of an error: the network and the files by their codes; hub's own errors by `LocalizedError`
    /// (`failureReason`, else `errorDescription`, and `recoverySuggestion`), which they adopt to speak French here.
    static func cause(of error: any Error) -> (reason: String?, remedy: String?, own: Bool) {
        if let network = error as? URLError {
            switch network.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff:
                return ("pas de connexion à Internet", "Vérifie la connexion du Mac, puis réessaie.", false)
            case .timedOut:
                return ("le serveur n'a pas répondu à temps", "Réessaie dans un moment.", false)
            case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                return ("le serveur est injoignable", "Réessaie dans un moment.", false)
            case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateNotYetValid,
                 .serverCertificateHasUnknownRoot:
                return ("la connexion sécurisée a échoué", nil, false)
            default:
                return ("le réseau a échoué", nil, false)
            }
        }
        if let file = error as? CocoaError {
            switch file.code {
            case .fileNoSuchFile, .fileReadNoSuchFile: return ("le fichier est introuvable", nil, false)
            case .fileWriteOutOfSpace: return ("le disque est plein", "Libère de la place sur le disque, puis réessaie.", false)
            case .fileReadNoPermission, .fileWriteNoPermission: return ("hub n'a pas le droit d'y accéder", nil, false)
            case .fileWriteFileExists: return ("un fichier du même nom existe déjà", nil, false)
            case .fileWriteVolumeReadOnly: return ("le disque est en lecture seule", nil, false)
            case .fileReadCorruptFile: return ("le fichier est abîmé", nil, false)
            default: return (nil, nil, false)
            }
        }
        if let posix = error as? POSIXError {
            switch posix.code {
            case .ENOSPC: return ("le disque est plein", "Libère de la place sur le disque, puis réessaie.", false)
            case .EACCES, .EPERM: return ("hub n'a pas le droit d'y accéder", nil, false)
            case .ENOENT: return ("le fichier est introuvable", nil, false)
            case .ETIMEDOUT: return ("le serveur n'a pas répondu à temps", "Réessaie dans un moment.", false)
            case .ENETDOWN, .ENETUNREACH, .ENOTCONN: return ("pas de connexion à Internet", "Vérifie la connexion du Mac, puis réessaie.", false)
            default: return (nil, nil, false)
            }
        }
        // Another of the system's errors: its words are the system's (English, or « vous »), never hub's.
        if type(of: error) is NSError.Type { return (nil, nil, false) }
        if let own = error as? LocalizedError, let reason = own.failureReason ?? own.errorDescription, !reason.isEmpty {
            return (reason, own.recoverySuggestion, true)
        }
        return (nil, nil, false)
    }

    // MARK: - Pieces

    /// « 05 ».
    static func twoDigits(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }

    /// « 25 », « 1er ».
    static func ordinal(_ day: Int) -> String {
        day == 1 ? "1er" : "\(day)"
    }

    /// « 25 » within the month of `now`, else « 2 décembre », « 2 décembre 2027 » (another year); `month`, always the month.
    static func dayOfMonth(_ date: Date, now: Date, calendar: Calendar, month: Bool) -> String {
        let parts = calendar.dateComponents([.day, .month, .year], from: date)
        let sameYear = parts.year == calendar.component(.year, from: now)
        let sameMonth = sameYear && parts.month == calendar.component(.month, from: now)
        let number = ordinal(parts.day ?? 1)
        guard month || !sameMonth else { return number }
        let name = months[((parts.month ?? 1) - 1 + 12) % 12]
        return sameYear ? "\(number) \(name)" : "\(number) \(name) \(parts.year ?? 0)"
    }
}
