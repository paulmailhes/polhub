import Foundation

/// The key of the Dictée (20/11, ⌥ right by default): held, it records until released; two short presses record hands
/// free until the next press; used with another key, it types a character and nothing is dictated; Échap cancels.
public struct KeyGesture: Sendable, Equatable {
    public enum Action: Equatable, Sendable {
        case start, finish, cancel, none
    }

    public enum State: Equatable, Sendable {
        case idle
        case holding(since: TimeInterval)
        case tapped(at: TimeInterval)
        case handsFree
        /// Released after a cancel: the next release says nothing.
        case ignoringRelease
    }

    /// Shorter than this, a press is a tap.
    public static let hold: TimeInterval = 0.25
    /// The second tap comes within this.
    public static let doubleTap: TimeInterval = 0.4

    public private(set) var state: State = .idle

    public init() {}

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
        case .handsFree:
            state = .ignoringRelease
            return .finish
        case .holding:
            return .none
        }
    }

    public mutating func keyUp(at time: TimeInterval) -> Action {
        switch state {
        case .holding(let since) where time - since >= Self.hold:
            state = .idle
            return .finish
        case .holding:
            state = .tapped(at: time)
            return .none
        case .ignoringRelease:
            state = .idle
            return .none
        case .idle, .tapped, .handsFree:
            return .none
        }
    }

    /// A single tap whose second never came: what was recorded is dropped.
    public mutating func tick(at time: TimeInterval) -> Action {
        guard case .tapped(let at) = state, time - at > Self.doubleTap else { return .none }
        state = .idle
        return .cancel
    }

    /// Another key while ⌥ is held or just tapped: it is typing.
    public mutating func otherKey() -> Action {
        switch state {
        case .holding:
            state = .ignoringRelease
            return .cancel
        case .tapped:
            state = .idle
            return .cancel
        case .idle, .handsFree, .ignoringRelease:
            return .none
        }
    }

    public mutating func escape() -> Action {
        switch state {
        case .holding:
            state = .ignoringRelease
            return .cancel
        case .tapped, .handsFree:
            state = .idle
            return .cancel
        case .idle, .ignoringRelease:
            return .none
        }
    }
}
