import Foundation

/// The text that writes itself (the Accueil's pass, 18/11): Claude Code sends the answer in bursts; the screen takes
/// it out whole words at a time, at a steady pace, more words when it falls behind, everything at the end. A word not
/// finished yet (no space, no line after it) waits for the rest.
public struct StreamPacer: Sendable {
    /// What the screen shows.
    public private(set) var shown = ""
    /// What came and is not shown yet.
    private var pending = ""

    public init() {}

    /// The characters waiting.
    public var backlog: Int { pending.count }

    public mutating func push(_ text: String) {
        pending += text
    }

    /// One pace: at least one word, and one more for each twelve characters waiting.
    @discardableResult
    public mutating func tick() -> String {
        let wanted = max(1, pending.count / 12)
        var words = 0
        var inWord = false
        var cut: String.Index?
        var index = pending.startIndex
        while index < pending.endIndex {
            if pending[index].isWhitespace {
                if inWord {
                    words += 1
                    inWord = false
                }
                cut = pending.index(after: index)
                // The spaces after the last word wanted go with it.
                if words >= wanted, let next = cut, next < pending.endIndex, !pending[next].isWhitespace { break }
            } else {
                if words >= wanted { break }
                inWord = true
            }
            index = pending.index(after: index)
        }
        guard let cut else { return shown }
        shown += pending[..<cut]
        pending.removeSubrange(..<cut)
        return shown
    }

    /// Everything, now: the end of the answer, or its stop.
    @discardableResult
    public mutating func flush() -> String {
        shown += pending
        pending = ""
        return shown
    }
}
