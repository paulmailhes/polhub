import Foundation
import VigieKit

/// Vigie in hub (21/11): what its engine says, read again every few seconds, and what Paul decides, sent back to it.
/// The engine is Vigie's own, already on the Mac; hub only talks to it.
@MainActor public final class VigieLibrary: ObservableObject {
    public enum Link: Equatable, Sendable {
        /// Not asked yet.
        case unknown
        /// The engine is not on this Mac.
        case absent
        /// It does not answer.
        case stopped
        case running
        /// It answers, but hub cannot use what it says: why.
        case trouble(String)
    }

    @Published public private(set) var link: Link = .unknown
    @Published public private(set) var overview = VigieOverview()
    /// What a gesture said when it failed, once.
    @Published public var problem: String?
    /// What is being sent: their buttons wait.
    @Published public private(set) var sending: Set<String> = []
    /// The page is on screen: read every 3 s; else every 20 s, for the count beside the section.
    public var isVisible = false {
        didSet {
            guard isVisible, !oldValue else { return }
            Task { await refresh() }
        }
    }

    let client: VigieClient
    private var loop: Task<Void, Never>?

    public init(client: VigieClient = VigieClient()) {
        self.client = client
    }

    public func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(self?.isVisible == true ? 3 : 20))
            }
        }
    }

    public func stop() {
        loop?.cancel()
        loop = nil
    }

    /// What waits for a decision or an answer, the most recent first.
    public var waiting: [VigieReview] { overview.toReview.filter(\.needsPaul) }
    /// What is only to see: a limit reached, an account to connect again.
    public var notices: [VigieReview] { overview.toReview.filter { !$0.needsPaul } }
    public var openConversations: [VigieConversation] { overview.conversations.filter { $0.status != .closed } }
    public var closedCount: Int { overview.conversations.count - openConversations.count }

    public func refresh() async {
        do {
            let fresh = try await client.overview()
            if fresh != overview { overview = fresh }
            set(.running)
        } catch VigieFailure.absent {
            if overview != VigieOverview() { overview = VigieOverview() }
            set(.absent)
        } catch VigieFailure.stopped {
            set(.stopped)
        } catch {
            set(.trouble(Self.sentence(error)))
        }
    }

    private func set(_ link: Link) {
        if self.link != link { self.link = link }
    }

    /// « Autoriser » or « Refuser » on a sensitive action that waits.
    public func decide(_ review: VigieReview, allow: Bool) async {
        guard let pending = review.pendingID else { return }
        await send(review.id) { try await self.client.decide(pending: pending, allow: allow) }
    }

    /// « Ça me va » on a question Vigie answered for Paul.
    public func approve(_ review: VigieReview) async {
        guard let question = review.question else { return }
        await send(review.id) { try await self.client.approve(question: question.id) }
    }

    /// Takes a notice away.
    public func dismiss(_ review: VigieReview) async {
        await send(review.id) { try await self.client.dismiss(review: review.id) }
    }

    /// Opens the conversation in VS Code.
    public func open(conversation id: String) async {
        await send("ouvrir:" + id) { try await self.client.open(conversation: id) }
    }

    /// One at a time for the same thing: a second click while the first is on its way does nothing.
    private func send(_ id: String, _ work: () async throws -> Void) async {
        guard !sending.contains(id) else { return }
        sending.insert(id)
        defer { sending.remove(id) }
        do {
            try await work()
            problem = nil
        } catch {
            problem = Self.sentence(error)
        }
        await refresh()
    }

    /// What went wrong, in French: the engine's own sentence when it gave one.
    static func sentence(_ error: any Error) -> String {
        switch error as? VigieFailure {
        case .absent: "Le moteur de Vigie n'est pas sur ce Mac."
        case .stopped: "Le moteur de Vigie ne répond pas."
        case .refused(_, let sentence?): sentence
        case .refused(401, nil): "Le moteur de Vigie ne reconnaît pas hub : rouvre l'app Vigie."
        case .refused: "Le moteur de Vigie a refusé."
        case .unreadable, nil: "hub n'a pas compris la réponse de Vigie : l'un des deux est peut-être à mettre à jour."
        }
    }
}
