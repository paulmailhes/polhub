import Foundation

/// The instant search of the list (15/11): as Paul types, the whole copy is filtered on the Mac (the subjects,
/// the extracts, the people, senders and recipients, by name and address, the names of the files), capitals
/// and accents aside. Enter also asks Gmail, which reads the bodies. No index in the base: a list in memory.
public enum MailSearch {
    /// What the list does with the text of the search field.
    public enum Mode: Equatable, Sendable {
        /// Nothing typed: no search.
        case none
        /// One letter: too little to filter on.
        case tooShort
        /// The words to find, folded: each must start a word of the thread.
        case local([String])
        /// An operator of Gmail's (`from:`, `has:attachment`…): only Gmail answers it, on Enter.
        case gmailOnly
    }

    /// Two letters at least before the list filters.
    public static let minimumLength = 2

    /// Gmail's search operators, as `from:camille`.
    static let operators: Set<String> = [
        "from", "to", "cc", "bcc", "subject", "label", "has", "is", "in", "filename", "after", "before", "older", "newer", "older_than",
        "newer_than", "larger", "smaller", "size", "category", "list", "deliveredto", "rfc822msgid", "around",
    ]

    public static func mode(_ text: String) -> Mode {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .none }
        let asksGmail = trimmed.split(whereSeparator: \.isWhitespace).contains { part in
            guard let colon = part.firstIndex(of: ":") else { return false }
            return operators.contains(part[..<colon].lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "-+(")))
        }
        if asksGmail { return .gmailOnly }
        let words = fold(trimmed)
        guard trimmed.count >= minimumLength, !words.isEmpty else { return .tooShort }
        return .local(words)
    }

    /// What the copy answers of a text: the words it filters by; or a sender's address, as « Tous les mails de cet
    /// expéditeur » writes it (`from:camille@exemple.fr`), for every thread he wrote in. Gmail's search gives one page
    /// of a sender's mails, the copy holds them all (audit of 19/11).
    public enum Local: Equatable, Sendable {
        case words([String])
        case sender(String)
    }

    /// `nil` for what only Gmail answers, on Enter: an operator of Gmail's, a name alone after `from:` included.
    public static func local(_ text: String) -> Local? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.hasPrefix("from:") {
            let address = String(trimmed.dropFirst("from:".count))
            let parts = address.split(separator: "@", omittingEmptySubsequences: false)
            guard parts.count == 2, !parts[0].isEmpty, PublicMailDomains.domain(of: address) != nil,
                  !address.contains(where: { $0.isWhitespace || "():\"".contains($0) }) else { return nil }
            return .sender(address)
        }
        guard case .local(let words) = mode(text) else { return nil }
        return .words(words)
    }

    /// The threads that answer, in the order of the entries (the most recent first), from these mailboxes only.
    public static func filter(_ entries: [MailSearchEntry], _ local: Local, accounts: Set<String>? = nil) -> [MailThreadRow] {
        switch local {
        case .words(let words):
            return filter(entries, words: words, accounts: accounts)
        case .sender(let address):
            return entries.filter { entry in
                (accounts?.contains(entry.thread.account) ?? true) && entry.thread.senders.contains { $0.email.lowercased() == address }
            }.map(\.thread)
        }
    }

    /// The words of a search typed in « Corbeille » or « Spam », which never reaches Gmail (wave B, 15/11): an
    /// operator of Gmail's keeps only its value (« from:camille » looks for « camille »). `nil` under two letters.
    public static func localWords(_ text: String) -> [String]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= minimumLength else { return nil }
        let parts = trimmed.split(whereSeparator: \.isWhitespace).map { part -> Substring in
            guard let colon = part.firstIndex(of: ":"),
                  operators.contains(part[..<colon].lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "-+("))) else { return part }
            return part[part.index(after: colon)...]
        }
        let words = fold(parts.joined(separator: " "))
        return words.isEmpty ? nil : words
    }

    /// Lower case, without accents, cut into words.
    static func fold(_ text: String) -> [String] {
        ProjectNames.tokens(text)
    }

    /// The words a thread is found by, folded, once each: one space before each, so that looking for a word's
    /// start is looking for « space + word ».
    public static func words(of thread: MailThreadRow, messages: [MailMessageRow]) -> String {
        var parts: [String] = [thread.subject, thread.snippet]
        for person in thread.senders { parts += [person.name ?? "", person.email] }
        for message in messages {
            parts += [message.subject, message.snippet]
            for person in (message.sender.map { [$0] } ?? []) + message.to + message.cc { parts += [person.name ?? "", person.email] }
            parts += message.files.map(\.filename)
        }
        var seen: Set<String> = []
        var result = ""
        for word in fold(parts.joined(separator: " ")) where seen.insert(word).inserted {
            result += " " + word
        }
        return result
    }

    /// Every word typed starts a word of the thread.
    public static func matches(_ words: [String], in found: String) -> Bool {
        matches(needles(words), in: found)
    }

    /// « space + word », as bytes: the search runs at every key, over the whole copy, on the main thread; a
    /// search of bytes is about fifteen times faster than `String.contains` (measured on 15/11, 6 000 threads).
    static func needles(_ words: [String]) -> [[UInt8]] {
        words.map { Array((" " + $0).utf8) }
    }

    static func matches(_ needles: [[UInt8]], in found: String) -> Bool {
        let fast = found.utf8.withContiguousStorageIfAvailable { haystack in
            needles.allSatisfy { needle in
                needle.withUnsafeBufferPointer { needle in
                    memmem(haystack.baseAddress, haystack.count, needle.baseAddress, needle.count) != nil
                }
            }
        }
        if let fast { return fast }
        return needles.allSatisfy { found.contains(String(decoding: $0, as: UTF8.self)) }
    }

    /// The threads that answer, in the order of the entries (the most recent first), from these mailboxes only.
    public static func filter(_ entries: [MailSearchEntry], words: [String], accounts: Set<String>? = nil) -> [MailThreadRow] {
        let needles = needles(words)
        return entries.filter { entry in (accounts?.contains(entry.thread.account) ?? true) && matches(needles, in: entry.words) }.map(\.thread)
    }
}

/// A thread of the copy, and the words it is found by.
public struct MailSearchEntry: Sendable {
    public var thread: MailThreadRow
    /// `MailSearch.words(of:messages:)`.
    public var words: String

    public init(thread: MailThreadRow, words: String) {
        self.thread = thread
        self.words = words
    }
}
