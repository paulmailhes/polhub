import Foundation
import Testing

/// The guard of the words (lot 10, 20/11), as `DesignGuardTests` is the design's: in the code that writes what the
/// screens say, what `Words` (PolhubDesign) replaces can only decrease. Each ceiling is the count left when lot 10 was
/// merged (its foundations had 3, 29, 67, 13, 63, 18, 4, 13); a pass that removes some lowers it here. What is left is
/// kept on purpose: the formats of the base, the dates given to Claude, the journal's own text. Read, never changed: the interface's code
/// and the modules whose words reach the screens.
@Suite struct WordsGuardTests {
    static let folders = DesignGuardTests.folders + ["Colin", "Notifications", "Mail", "Pipeline", "Updates", "Summarization", "Inspiration"]
        .map { "Packages/MeetingsMac/Sources/\($0)" }

    static let rules = [
        // A logic that reads a text shown: a typed state goes with the text (the fourteen places of the audit, lot 10).
        // Left: the brands « iPhone » and « MacBook » kept in capitals by Inspiration's tags, Gmail's labels (« INBOX »),
        // the line « _Partiel : … _ » of a summary kept in the base, a format.
        DesignGuardTests.Rule(name: "un texte affiché testé par le code",
                              pattern: #"(hasPrefix|hasSuffix)\("[^"]*[a-zà-ÿ] [^"]*"\)|[=!]= "[^"]*[a-zà-ÿ] [a-zà-ÿ][^"]*"|[=!]= "[A-ZÀ-Ý][A-Za-zà-ÿ]+""#,
                              ceiling: 3),
        // The language is fixed once, by `Words.locale`.
        DesignGuardTests.Rule(name: "la langue écrite à la main", pattern: #"Locale\(identifier: "fr_FR"\)"#, ceiling: 5),
        // A day or an hour comes from `Words`, never from a formatter of the system.
        DesignGuardTests.Rule(name: "un format de date du système",
                              pattern: #"DateFormatter\(\)|\.formatted\(date:|\.dateTime\b|Date\.FormatStyle|\.relative\(presentation:"#, ceiling: 6),
        // An hour, a length, a clock: `Words.time`, `Words.duration`, `Words.clock`.
        DesignGuardTests.Rule(name: "une heure ou une durée faite à la main", pattern: #"String\(format: "[^"]*%0?2?d"#, ceiling: 2),
        // An error is said by `Words.problem`: the system's text goes to the journal, never to the screen.
        DesignGuardTests.Rule(name: "une erreur brute", pattern: #"\\\(error\)|\.localizedDescription"#, ceiling: 18),
        // A capital at a line's head: `Words.capitalizedFirst`.
        DesignGuardTests.Rule(name: "une majuscule refaite à la main", pattern: #"\.prefix\(1\)\.uppercased\(\)"#, ceiling: 0),
        // A help bubble says what a button does, never the gesture.
        DesignGuardTests.Rule(name: "une bulle qui dit « cliquer »", pattern: #"\.help\(.*[Cc]liqu|help: ".*[Cc]liqu"#, ceiling: 0),
        // « rendez-vous », « visio », « réunion »: neither « call » nor « RDV » (the base keeps one « call » in the stop of an
        // answer of Colin, a format).
        DesignGuardTests.Rule(name: "« call » ou « RDV »", pattern: #""[^"]*\b(call|RDV)\b[^"]*""#, ceiling: 1),
    ]

    @Test func whatWordsReplacesCanOnlyDecrease() throws {
        for rule in Self.rules {
            let found = try DesignGuardTests.matches(rule.pattern, in: Self.folders)
            #expect(found.count <= rule.ceiling, "\(rule.name) : \(found.count), plafond \(rule.ceiling)\n\(found.prefix(20).joined(separator: "\n"))")
        }
    }
}
