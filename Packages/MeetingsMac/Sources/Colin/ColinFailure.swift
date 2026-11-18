import Foundation

/// Why Colin cannot answer (18/11), as the bar says it. Read from what Claude Code left: a result in error, a limit
/// refused, its error output, or a process gone before its turn ended.
public enum ColinFailure: Equatable, Sendable {
    /// No Claude Code on this Mac, or Polhub cannot say where to launch it.
    case missing
    /// The account is not connected: nothing is tried again.
    case notConnected
    /// The account's limit is reached, until `resetsAt` when Claude Code said it.
    case limit(resetsAt: Date?)
    /// The process could not start.
    case launch
    /// No answer: gone, or silent past the turn's limit.
    case noAnswer
    /// The launch loaded more than Polhub asked (its `init`, or a hook): stopped before anything of Paul's left.
    case isolation(String)

    /// What a result in error, or a process gone, says that will go on: its limit, its connection; for a process
    /// gone (`result` nil), its launch or its silence. `nil`: an error of the turn's own, which names nothing.
    public static func of(result: ClaudeResult?, rateLimit: ClaudeRateLimit?, errors: String, initialized: Bool) -> ColinFailure? {
        if rateLimit?.status == "rejected" || result?.apiErrorStatus == 429 { return .limit(resetsAt: rateLimit?.resetsAt) }
        if result?.apiErrorStatus == 401 || saysNotConnected((result?.text ?? "") + " " + errors) { return .notConnected }
        guard result == nil else { return nil }
        return initialized ? .noAnswer : .launch
    }

    /// What Claude Code says when the account is not connected (measured on 17/11).
    public static func saysNotConnected(_ text: String) -> Bool {
        let said = text.lowercased()
        return ["log in", "login", "authenticat", "api key"].contains(where: said.contains)
    }
}
