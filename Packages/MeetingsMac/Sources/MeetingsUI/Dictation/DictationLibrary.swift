import AppKit
import Dictation
import Foundation
import GRDB
import Persistence

/// What the Dictée shows and keeps (20/11): the history of what Paul said, and the memory he tends — his words, those
/// hub already knows (his projects, their clients, his contacts), and his corrections.
@MainActor public final class DictationLibrary: ObservableObject {
    @Published public private(set) var history: [DictationRow] = []
    @Published public private(set) var words: [DictationWordRow] = []
    @Published public private(set) var replacements: [DictationReplacementRow] = []
    /// The names hub knows: projects, clients, contacts.
    @Published public private(set) var known: [String] = []

    let store: DictationStore
    let database: AppDatabase
    private var observations: [AnyDatabaseCancellable] = []

    /// The words every dictation of hub needs, before Paul's.
    static let builtIn = ["hub", "Vigie", "Colin", "Meet", "Claude Code"]
    /// The first corrections (20/11): what Whisper and the dictation of Paul's messages hear, measured on his messages.
    public static let firstCorrections: [(heard: String, written: String)] = [
        ("mythe", "Meet"), ("Paul Hub", "hub"), ("PollHub", "hub"), ("Polhub", "hub"), ("Eub", "hub"), ("Vigi", "Vigie"),
        ("eCloud", "iCloud"), ("cloud code", "Claude Code"),
    ]

    public init(database: AppDatabase) {
        self.database = database
        store = DictationStore(database)
        try? store.seed(Self.firstCorrections, at: Date())
        observations = [
            store.observeRecent(limit: 300) { [weak self] rows in self?.history = rows },
            store.observeMemory { [weak self] words, replacements in
                self?.words = words
                self?.replacements = replacements
            },
        ]
        refreshKnown()
    }

    /// The names of hub, read again when the Dictée starts listening: a new project or contact is known at once.
    public func refreshKnown() {
        let projects = (try? ProjectStore(database).projects()) ?? []
        let contacts = (try? ContactStore(database).contacts()) ?? []
        known = projects.map(\.name) + projects.compactMap(\.client) + contacts.map(\.name)
    }

    /// Whisper's prompt: Paul's words first, then hub's own, then the names hub knows.
    public var prompt: String {
        DictationPrompt.make(words.map(\.word) + Self.builtIn + known)
    }

    public var corrections: [DictationReplacement] {
        replacements.map { DictationReplacement(heard: $0.heard, written: $0.written) }
    }

    public func keep(_ row: DictationRow) {
        try? store.add(row)
    }

    public func copy(_ row: DictationRow) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(row.text, forType: .string)
    }

    /// Coup d'œil's « Copier la dernière dictée »; false when there is none.
    @discardableResult
    public func copyLast() -> Bool {
        guard let last = history.first else { return false }
        copy(last)
        return true
    }

    public func delete(_ row: DictationRow) { try? store.delete(row.id) }
    public func addWord(_ word: String) { try? store.addWord(word, at: Date()) }
    public func removeWord(_ word: String) { try? store.removeWord(word) }
    public func setReplacement(heard: String, written: String) { try? store.setReplacement(heard: heard, written: written, at: Date()) }
    public func removeReplacement(_ heard: String) { try? store.removeReplacement(heard) }
}
