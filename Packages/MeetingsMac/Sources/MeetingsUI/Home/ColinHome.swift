import Colin
import PolhubDesign
import SwiftUI

/// What Colin is, said at the head of his panel (lot 5, 19/11): his real state — prêt, répond…, attend ta visio, se
/// réveille, en panne, à l'arrêt —, never « en marche » during a call or a breakdown, as the switch alone said before.
enum ColinState: Equatable {
    case ready, answering, waitingCall, waking, broken, off

    /// The color of the dot beside it.
    enum Dot: Equatable {
        /// Green, the color of what works.
        case done
        /// Out of order: the color of a problem.
        case attention
        /// Grey: off, or waiting.
        case quiet
    }

    /// `answering`: a question is on its way, before Colin's first word.
    init(_ status: ColinThread.Status, answering: Bool = false) {
        switch status {
        case .off: self = .off
        case .waitingCall: self = .waitingCall
        case .settling: self = .waking
        case .starting, .working: self = .answering
        case .idle: self = answering ? .answering : .ready
        case .broken: self = answering ? .answering : .broken
        }
    }

    var label: String {
        switch self {
        case .ready: "prêt"
        case .answering: "répond…"
        // « visio », never « call » (lot 10, 20/11).
        case .waitingCall: "attend ta visio"
        case .waking: "se réveille"
        case .broken: "en panne"
        case .off: "à l'arrêt"
        }
    }

    var dot: Dot {
        switch self {
        case .ready, .answering: .done
        case .broken: .attention
        case .waitingCall, .waking, .off: .quiet
        }
    }

    /// The dot beats while Colin answers.
    var beats: Bool { self == .answering }

    /// The narrow window's bar, at its head: the state, or, ready, the start of his last answer.
    static func barLine(_ state: ColinState, lastAnswer: String?) -> String {
        if state == .ready, let lastAnswer, !lastAnswer.isEmpty { return lastAnswer }
        return state.label
    }
}

/// The dot of Colin's state: green while he works — beating while he answers —, the color of attention out of order,
/// grey otherwise (lot 5, 19/11).
struct ColinStateDot: View {
    let state: ColinState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var color: Color {
        switch state.dot {
        case .done: Tint.done
        case .attention: Tint.attention
        case .quiet: Color.secondary
        }
    }

    var body: some View {
        ColorDot(color, size: 7)
            .phaseAnimator(state.beats && !reduceMotion ? [1.0, 0.3] : [1.0]) { dot, opacity in
                dot.opacity(opacity)
            } animation: { _ in .easeInOut(duration: 0.8) }
            .accessibilityHidden(true)
    }
}

/// « Colin · prêt », at the head of his panel (lot 5, 19/11): his name in 17 points, his real state, and a « … » with
/// « Mettre à l'arrêt » and his settings; ✕ when the panel floats over the day (a narrow window).
struct ColinHeader: View {
    @ObservedObject var thread: ColinThread
    @ObservedObject var router: WindowRouter
    /// The panel open over the day: ✕ closes it, as Échap.
    var close: (() -> Void)?

    var body: some View {
        let state = ColinState(thread.status, answering: thread.isAnswering)
        HStack(alignment: .center, spacing: Space.s) {
            Text("Colin").font(.title2.weight(.semibold))
            ColinStateDot(state: state)
            Text(state.label).font(.meta).foregroundStyle(.secondary)
            Spacer(minLength: Space.s)
            // « Plus d'actions », the help of every « … » (lot 10, 20/11: `IconMenu`'s own).
            IconMenu("ellipsis") {
                if thread.isOn { Button("Mettre à l'arrêt") { thread.turnOff() } }
                Button("Réglages…") { router.openSettings(.colin) }
            }
            // « Fermer (Échap) » in the bubble, « Fermer » for VoiceOver (lot 10, 20/11).
            if let close { IconButton("xmark", help: "Fermer", shortcut: .escape, action: close) }
        }
    }
}
