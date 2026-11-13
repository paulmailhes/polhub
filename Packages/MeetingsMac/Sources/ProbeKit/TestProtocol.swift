import Foundation

/// One instruction of a guided test, shown to the person running it.
public struct ProtocolStep: Equatable, Sendable, Codable {
    public let id: String
    public let instruction: String
    /// How long the step must last for the traces to say something.
    public let minSeconds: Int

    public init(id: String, instruction: String, minSeconds: Int) {
        self.id = id
        self.instruction = instruction
        self.minSeconds = minSeconds
    }
}

public enum TestProtocol {
    /// The guided test call of phase 0. Each step produces the trace one line of the report needs.
    public static let call: [ProtocolStep] = [
        .init(id: "S01", instruction: "Casque Bluetooth connecté, Dia ouvert, aucun onglet Meet. Attends.", minSeconds: 30),
        .init(id: "S02", instruction: "Ouvre le lien Meet d'essai. Reste dans la salle d'attente, sans rejoindre.", minSeconds: 40),
        .init(id: "S03", instruction: "Rejoins, micro ouvert. Fais rejoindre l'iPhone, puis lis-lui un texte à voix haute depuis l'autre pièce.", minSeconds: 45),
        .init(id: "S04", instruction: "Parle seul, l'iPhone se tait.", minSeconds: 30),
        .init(id: "S05", instruction: "Coupe ton micro dans Meet. L'iPhone parle de temps en temps.", minSeconds: 120),
        .init(id: "S06", instruction: "Rétablis ton micro. Silence complet des deux côtés.", minSeconds: 60),
        .init(id: "S07", instruction: "Dicte une phrase avec VoiceInk dans une autre application.", minSeconds: 20),
        .init(id: "S08", instruction: "Passe sur un autre onglet, puis sur un autre bureau, puis mets Dia en plein écran.", minSeconds: 60),
        .init(id: "S09", instruction: "Recharge l'onglet Meet (⌘R) et rejoins de nouveau.", minSeconds: 40),
        .init(id: "S10", instruction: "Retire le casque : le son passe sur les haut-parleurs. L'iPhone parle.", minSeconds: 30),
        .init(id: "S11", instruction: "Connecte les AirPods, attends, puis reviens au casque.", minSeconds: 60),
        .init(id: "S12", instruction: "Dans les réglages de Meet, choisis le micro de la webcam ou du MacBook, attends, puis remets celui du casque.", minSeconds: 40),
        .init(id: "S13", instruction: "Raccroche avec le bouton rouge. Reste sur l'écran qui s'affiche.", minSeconds: 60),
        .init(id: "S14", instruction: "Sans fermer l'onglet Meet, lance une vidéo avec du son dans un autre onglet de Dia.", minSeconds: 30),
        .init(id: "S15", instruction: "Arrête la vidéo. Reviens sur l'onglet Meet, réintègre la réunion, raccroche, ferme l'onglet.", minSeconds: 40),
        .init(id: "S16", instruction: "Rouvre le lien. Coupe ton micro dans la salle d'attente, rejoins micro coupé, reste, raccroche, ferme l'onglet.", minSeconds: 90),
        .init(id: "S17", instruction: "Terminé.", minSeconds: 0),
    ]
}

/// The state of the guided test, shared between the probe that records and the window that guides.
@MainActor
public final class ProtocolBoard: ObservableObject {
    public static let shared = ProtocolBoard()

    /// Two clicks closer than this are one click: a double-click must not skip a step.
    static let minimumSecondsBetweenMoves = 1.0

    /// Index of the current step; nil while no guided test is running.
    @Published public private(set) var stepIndex: Int?
    @Published public private(set) var stepStartedAt: Date?
    public let steps = TestProtocol.call

    private let now: () -> Date
    private var lastMoveAt: Date?
    private var advances: AsyncStream<Int>.Continuation?

    init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    public var currentStep: ProtocolStep? {
        stepIndex.flatMap { steps.indices.contains($0) ? steps[$0] : nil }
    }

    public var isFirstStep: Bool { stepIndex == 0 }
    public var isLastStep: Bool { stepIndex == steps.count - 1 }

    /// Starts at the first step. The stream yields the index of each step the person moves to.
    func begin() -> AsyncStream<Int> {
        advances?.finish()
        let (stream, continuation) = AsyncStream<Int>.makeStream()
        advances = continuation
        stepIndex = 0
        stepStartedAt = now()
        lastMoveAt = nil
        return stream
    }

    /// Called by the window's "Étape suivante" button.
    public func next() {
        guard let index = stepIndex, index + 1 < steps.count else { return }
        move(to: index + 1)
    }

    /// Called by the window's "Étape précédente" button: a step clicked through too early can be redone.
    public func previous() {
        guard let index = stepIndex, index > 0 else { return }
        move(to: index - 1)
    }

    private func move(to index: Int) {
        let moment = now()
        if let lastMoveAt, moment.timeIntervalSince(lastMoveAt) < Self.minimumSecondsBetweenMoves { return }
        lastMoveAt = moment
        stepIndex = index
        stepStartedAt = moment
        advances?.yield(index)
    }

    func end() {
        advances?.finish()
        advances = nil
        stepIndex = nil
        stepStartedAt = nil
        lastMoveAt = nil
    }
}
