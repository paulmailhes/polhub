import Foundation

/// The key of the Dictée (20/11, ⌥ right by default), in three ways chosen in Réglages › Dictée:
/// - « Appuyer pour commencer et arrêter » (the default since Paul's try, 20/11 in the evening): a press starts, a press
///   finishes;
/// - « Tenir pour parler »: held, it records until released; two short presses record hands free until the next press;
/// - « Les deux »: a short press starts and a press finishes; held long, it finishes on release.
/// Used with another key, the key types a character and nothing is dictated; Échap cancels.
public struct KeyGesture: Sendable, Equatable {
    public enum Mode: String, CaseIterable, Sendable {
        case toggle, hold, hybrid
    }

    public enum Action: Equatable, Sendable {
        case start, finish, cancel, none
    }

    public enum State: Equatable, Sendable {
        case idle
        /// The key went down and the recording started; up next, or another key (typing).
        case holding(since: TimeInterval)
        /// « Tenir pour parler »: a short tap, the second may come.
        case tapped(at: TimeInterval)
        /// Recording, the key up: the next press finishes.
        case listening
        /// « Tenir pour parler »'s two taps.
        case handsFree
        /// Released after a finish or a cancel: the next release says nothing.
        case ignoringRelease
    }

    /// Shorter than this, a press is a tap.
    public static let hold: TimeInterval = 0.25
    /// The second tap comes within this.
    public static let doubleTap: TimeInterval = 0.4

    public let mode: Mode
    public private(set) var state: State = .idle

    public init(mode: Mode = .toggle) {
        self.mode = mode
    }

    /// Recording starts at once: the first words are not lost.
    public mutating func keyDown(at time: TimeInterval) -> Action {
        switch state {
        case .idle, .ignoringRelease:
            state = .holding(since: time)
            return .start
        case .tapped(let at) where time - at <= Self.doubleTap:
            state = .handsFree
            return .none
        case .tapped:
            state = .holding(since: time)
            return .start
        case .listening, .handsFree:
            state = .ignoringRelease
            return .finish
        case .holding:
            return .none
        }
    }

    public mutating func keyUp(at time: TimeInterval) -> Action {
        switch state {
        case .holding(let since):
            let long = time - since >= Self.hold
            switch mode {
            case .toggle:
                state = .listening
                return .none
            case .hold where long, .hybrid where long:
                state = .idle
                return .finish
            case .hold:
                state = .tapped(at: time)
                return .none
            case .hybrid:
                state = .listening
                return .none
            }
        case .ignoringRelease:
            state = .idle
            return .none
        case .idle, .tapped, .listening, .handsFree:
            return .none
        }
    }

    /// « Tenir pour parler »: a single tap whose second never came; what was recorded is dropped.
    public mutating func tick(at time: TimeInterval) -> Action {
        guard case .tapped(let at) = state, time - at > Self.doubleTap else { return .none }
        state = .idle
        return .cancel
    }

    /// Another key while the key is held, or just tapped: it is typing. A recording under way goes on.
    public mutating func otherKey() -> Action {
        switch state {
        case .holding:
            state = .ignoringRelease
            return .cancel
        case .tapped:
            state = .idle
            return .cancel
        case .idle, .listening, .handsFree, .ignoringRelease:
            return .none
        }
    }

    public mutating func escape() -> Action {
        switch state {
        case .holding:
            state = .ignoringRelease
            return .cancel
        case .tapped, .listening, .handsFree:
            state = .idle
            return .cancel
        case .idle, .ignoringRelease:
            return .none
        }
    }
}
