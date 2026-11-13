/// One browser tab showing a `meet.google.com` page.
public struct BrowserTab: Equatable, Sendable, Codable {
    public let windowID: String
    public let tabID: String
    public let url: String
    public let title: String
    public let isLoading: Bool
    public let isFocused: Bool
    public let isPinned: Bool

    public init(windowID: String, tabID: String, url: String, title: String, isLoading: Bool, isFocused: Bool, isPinned: Bool) {
        self.windowID = windowID
        self.tabID = tabID
        self.url = url
        self.title = title
        self.isLoading = isLoading
        self.isFocused = isFocused
        self.isPinned = isPinned
    }
}

public struct ScriptFailure: Error, Equatable, Sendable {
    public let code: Int
    public let message: String

    public init(code: Int, message: String) {
        self.code = code
        self.message = message
    }
}

/// A reading of the browser's Meet tabs. A failure is never read as "no meeting".
public enum TabProbeResult: Equatable, Sendable {
    case tabs([BrowserTab])
    /// Some windows could be read, some could not: the tabs found, and what failed.
    case partial(tabs: [BrowserTab], failures: [ScriptFailure])
    case browserNotRunning
    case permissionDenied
    case failed(code: Int, message: String)
}

/// One implementation per browser. Dia is the only one in v1.
public protocol BrowserAdapter: Sendable {
    var bundleID: String { get }
    func meetTabs() async -> TabProbeResult
}
