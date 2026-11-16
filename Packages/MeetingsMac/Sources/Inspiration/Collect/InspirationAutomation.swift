import Foundation
import Persistence

/// What the app asks of « Inspiration » (16/11): the collection on its own (Awwwards, LinkedIn) at the slots of
/// `CollectionSchedule`, the categories of the items that have none, and Paul's gestures (add a site or a mock-up,
/// « Collecter maintenant », « Proposer des catégories »).
///
/// The app owns the clock: it calls `tick()` at launch, at wake and every few minutes, and `stop()` when a meeting
/// starts. Work on its own runs one pass at a time, at utility priority, only when `Conditions` allow it; a pass
/// cancelled midway records nothing (the slot stays due). Paul's gestures do not wait for a pass.
public actor InspirationAutomation {
    /// When work may run, asked at each pass: the app's settings and what it is doing.
    public struct Conditions: Sendable {
        /// The collection may run on its own now: « Collecte automatique » on, production build, no meeting under way.
        public var mayCollect: @Sendable () async -> Bool
        /// Categories may be asked of Apple's model on its own now: « Catégories par l'IA d'Apple » on, production
        /// build, no meeting, transcription nor summary under way.
        public var mayTag: @Sendable () async -> Bool
        /// « Catégories par l'IA d'Apple » is on: an item Paul adds is tagged at once, and « Proposer des
        /// catégories » works.
        public var aiCategories: @Sendable () -> Bool

        public init(mayCollect: @escaping @Sendable () async -> Bool, mayTag: @escaping @Sendable () async -> Bool,
                    aiCategories: @escaping @Sendable () -> Bool) {
            self.mayCollect = mayCollect
            self.mayTag = mayTag
            self.aiCategories = aiCategories
        }
    }

    /// The items one pass tags at most, every five minutes: under a minute of Apple's model as a rule (≈ 4 s an
    /// item), a quarter of an hour at the very worst (45 s an answer, two answers an item, 16/11).
    public static let tagsPerPass = 10

    let collector: InspirationCollector
    let tagger: InspirationTagger
    let runLog: CollectionRunLog
    let schedule: CollectionSchedule
    let conditions: Conditions
    private var pass: Task<Void, Never>?
    private var passID = 0

    public init(collector: InspirationCollector, tagger: InspirationTagger, runLog: CollectionRunLog,
                schedule: CollectionSchedule = CollectionSchedule(), conditions: Conditions) {
        self.collector = collector
        self.tagger = tagger
        self.runLog = runLog
        self.schedule = schedule
        self.conditions = conditions
    }

    // MARK: - On its own

    /// A look at the clock: the collections due (when they may run), then the items left without categories (when
    /// the model may run). Nothing when a pass is already under way.
    public func tick(now: Date = Date()) async {
        await runPass(collect: true, now: now)
    }

    /// A meeting starts, or the app quits: the pass under way stops at once (nothing is recorded as a failure).
    public func stop() {
        pass?.cancel()
    }

    /// A pass is under way.
    public var isRunning: Bool { pass != nil }

    private func runPass(collect: Bool, now: Date) async {
        guard pass == nil else { return }
        passID += 1
        let id = passID
        let task = Task(priority: .utility) { await self.work(collect: collect, now: now) }
        pass = task
        await task.value
        if passID == id { pass = nil }
    }

    private func work(collect: Bool, now: Date) async {
        if await conditions.mayCollect() {
            if collect {
                for job in schedule.due(lastRuns: runLog.lastRuns, now: now) {
                    guard !Task.isCancelled else { return }
                    _ = job == .websites ? await collector.collectWebsites(now: now) : await collector.collectBranding(now: now)
                }
            }
            // The imported sites whose image is only an address get it (each address once).
            guard !Task.isCancelled else { return }
            _ = await collector.completeImages(now: now)
        }
        guard !Task.isCancelled, conditions.aiCategories(), await conditions.mayTag() else { return }
        await tagger.tagPending(limit: Self.tagsPerPass)
    }

    // MARK: - Paul's gestures

    /// « Collecter maintenant »: both collections, whatever the slots and the setting; the new items are tagged by a
    /// pass right after, when the model may run.
    public func collectNow() async {
        _ = await collector.collectWebsites()
        _ = await collector.collectBranding()
        guard conditions.aiCategories() else { return }
        Task(priority: .utility) { await self.runPass(collect: false, now: Date()) }
    }

    /// « Ajouter un site »: read as a collected one, then tagged at once when the AI is on. Returns its id.
    public func addSite(url: URL) async throws -> UUID {
        let item = try await collector.addSite(url: url)
        if conditions.aiCategories(), InspirationTagger.needsTagging(item) {
            let tagger = tagger
            Task(priority: .utility) { await tagger.tag(id: item.id) }
        }
        return item.id
    }

    /// « Ajouter un mock-up »: its folder on the Mac. Returns its id.
    public func addMockup(folder: URL) async throws -> UUID {
        try await collector.addMockup(folder: folder).id
    }

    /// « Proposer des catégories »: Apple's model on this item now; what stops it, in plain words.
    public func tag(id: UUID) async throws {
        guard conditions.aiCategories() else { throw InspirationTagError.turnedOff }
        switch await tagger.tag(id: id) {
        case .tagged, .notFound, .cancelled: return
        case .byPaul: throw InspirationTagError.byPaul
        case .tooShort: throw InspirationTagError.tooShort
        case .notTaggable: throw InspirationTagError.notTaggable
        case .unavailable: throw InspirationTagError.unavailable
        case .failed(let reason): throw InspirationTagError.failed(reason)
        }
    }

    /// The last reading of each place (Awwwards first, then the LinkedIn pages).
    public func statuses() async -> [CollectionStatus] {
        await collector.statuses()
    }
}

/// Why « Proposer des catégories » did nothing, in plain words.
public enum InspirationTagError: Error, Equatable, Sendable, CustomStringConvertible, LocalizedError {
    case turnedOff
    case byPaul
    case tooShort
    case notTaggable
    case unavailable
    case failed(String)

    public var description: String {
        switch self {
        case .turnedOff: "Les catégories par l'IA d'Apple sont coupées dans Réglages › Inspiration."
        case .byPaul: "Tu as choisi ces catégories : l'IA n'y touche plus."
        case .tooShort: "Le texte est trop court pour proposer des catégories."
        case .notTaggable: "Pas de catégories proposées pour un mock-up."
        case .unavailable: "L'IA d'Apple n'est pas disponible sur ce Mac pour l'instant."
        case .failed(let reason): reason
        }
    }

    public var errorDescription: String? { description }
}
