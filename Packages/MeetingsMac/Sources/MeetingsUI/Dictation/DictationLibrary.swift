import AppKit
import AVFoundation
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
    /// The dictation whose sound plays (« Écouter »).
    @Published public private(set) var playing: UUID?

    let store: DictationStore
    let database: AppDatabase
    /// Where each dictation's sound is kept, `<id>.m4a` (Réglages › Dictée › « Garder le son »): never in iCloud.
    let sounds: URL
    private var observations: [AnyDatabaseCancellable] = []
    private var player: AVAudioPlayer?
    private var playerWatch: Timer?

    /// The words every dictation of hub needs, before Paul's.
    static let builtIn = ["hub", "Vigie", "Colin", "Meet", "Claude Code"]
    /// The first corrections (20/11): what Whisper and the dictation of Paul's messages hear, measured on his messages.
    public static let firstCorrections: [(heard: String, written: String)] = [
        ("mythe", "Meet"), ("Paul Hub", "hub"), ("PollHub", "hub"), ("Polhub", "hub"), ("Eub", "hub"), ("Vigi", "Vigie"),
        ("eCloud", "iCloud"), ("cloud code", "Claude Code"),
    ]

    public init(database: AppDatabase, sounds: URL = FileManager.default.temporaryDirectory.appending(path: "hub-dictee-sons")) {
        self.database = database
        self.sounds = sounds
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

    public func delete(_ row: DictationRow) {
        try? store.delete(row.id)
        removeSound(row.id)
    }

    // MARK: - The sounds and the history

    public func soundURL(_ id: UUID) -> URL {
        sounds.appending(path: id.uuidString.lowercased() + ".m4a")
    }

    public func hasSound(_ row: DictationRow) -> Bool {
        FileManager.default.fileExists(atPath: soundURL(row.id).path(percentEncoded: false))
    }

    public func removeSound(_ id: UUID) {
        if playing == id { stopPlaying() }
        try? FileManager.default.removeItem(at: soundURL(id))
    }

    /// « Écouter », and again to stop.
    public func play(_ row: DictationRow) {
        if playing == row.id {
            stopPlaying()
            return
        }
        stopPlaying()
        guard let player = try? AVAudioPlayer(contentsOf: soundURL(row.id)) else { return }
        self.player = player
        player.play()
        playing = row.id
        playerWatch = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.player?.isPlaying != true else { return }
                self.stopPlaying()
            }
        }
    }

    public func stopPlaying() {
        player?.stop()
        player = nil
        playerWatch?.invalidate()
        playerWatch = nil
        playing = nil
    }

    func setText(_ id: UUID, text: String, raw: String) {
        try? store.setText(id, text: text, raw: raw)
    }

    /// The dictations whose words hold `query`, among all of them.
    public func search(_ query: String) -> [DictationRow] {
        (try? store.search(query, limit: 300)) ?? []
    }

    /// The dictations older than `keepDays` go with their sounds; and the sounds whose dictation is gone. 0: kept.
    func purge(keepDays: Int, now: Date = Date()) {
        if keepDays > 0, let ids = try? store.deleteOlder(than: now.addingTimeInterval(-Double(keepDays) * 86_400)) {
            for id in ids { removeSound(id) }
        }
        guard let ids = try? store.ids(),
              let files = try? FileManager.default.contentsOfDirectory(at: sounds, includingPropertiesForKeys: nil) else { return }
        for file in files where file.pathExtension == "m4a" {
            // A sound of the dictation under way has no line yet: only those older than a minute go.
            let created = (try? file.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? now
            guard now.timeIntervalSince(created) > 60, let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent),
                  !ids.contains(id) else { continue }
            try? FileManager.default.removeItem(at: file)
        }
    }
    public func addWord(_ word: String) { try? store.addWord(word, at: Date()) }
    public func removeWord(_ word: String) { try? store.removeWord(word) }
    public func setReplacement(heard: String, written: String) { try? store.setReplacement(heard: heard, written: written, at: Date()) }
    public func removeReplacement(_ heard: String) { try? store.removeReplacement(heard) }
}
