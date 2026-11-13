import AppKit
import Domain
import Foundation

/// Reads Dia's Meet tabs through its AppleScript dictionary (`Dia.sdef`: window, tab, profile).
/// Only `meet.google.com` tabs leave Dia; other addresses are never returned to the app.
public struct DiaAdapter: BrowserAdapter {
    /// Two ways to filter tabs. Whether Dia accepts `whose` is one of the phase 0 measurements.
    public enum Variant: String, Sendable {
        case whose
        case loop
    }

    public static let diaBundleID = "company.thebrowser.dia"

    /// Where Dia is installed, `/Applications/Dia.app` by default.
    public static func appPath() -> String {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: diaBundleID)?.path ?? "/Applications/Dia.app"
    }
    public var bundleID: String { Self.diaBundleID }

    private let variant: Variant
    private let isRunning: @Sendable () -> Bool
    private let runScript: @Sendable (String) async -> Result<String, ScriptFailure>

    public init(
        variant: Variant = .whose,
        isRunning: @escaping @Sendable () -> Bool = DiaAdapter.systemIsRunning,
        runScript: @escaping @Sendable (String) async -> Result<String, ScriptFailure> = DiaAdapter.mainThreadRunScript
    ) {
        self.variant = variant
        self.isRunning = isRunning
        self.runScript = runScript
    }

    public func meetTabs() async -> TabProbeResult {
        // An Apple Event to an app that is not running would launch it.
        guard isRunning() else { return .browserNotRunning }
        switch await runScript(Self.source(for: variant)) {
        case .success(let raw):
            guard raw != DiaTabParser.notRunningSentinel else { return .browserNotRunning }
            var output = DiaTabParser.parseDetailed(raw)
            // The script matches any address that contains "meet.google.com"; a search or a mail that
            // merely mentions it is not a Meet tab and goes no further.
            output.tabs.removeAll { MeetLink.parse($0.url) == nil }
            guard let firstFailure = output.windowFailures.first else { return .tabs(output.tabs) }
            // Not one window could be read: that is a failure, never "no meeting".
            guard output.windowsRead > 0 else {
                return .failed(code: firstFailure.code, message: firstFailure.message)
            }
            return .partial(tabs: output.tabs, failures: output.windowFailures)
        case .failure(let failure):
            switch failure.code {
            case -1743: return .permissionDenied           // errAEEventNotPermitted
            case -600, -609: return .browserNotRunning     // procNotFound, connectionInvalid
            default: return .failed(code: failure.code, message: failure.message)
            }
        }
    }

    // MARK: - System implementations

    public static let systemIsRunning: @Sendable () -> Bool = {
        NSRunningApplication.runningApplications(withBundleIdentifier: diaBundleID)
            .contains { isUsable(finishedLaunching: $0.isFinishedLaunching, terminated: $0.isTerminated) }
    }

    /// A browser that is still starting, or already quitting, is not there to be asked anything.
    static func isUsable(finishedLaunching: Bool, terminated: Bool) -> Bool {
        finishedLaunching && !terminated
    }

    /// NSAppleScript, on the main thread where it must run.
    public static let mainThreadRunScript: @Sendable (String) async -> Result<String, ScriptFailure> = { source in
        await MainActor.run { systemRunScript(source) }
    }

    /// osascript, in its own process, off the main thread.
    public static let outOfProcessRunScript: @Sendable (String) async -> Result<String, ScriptFailure> = { source in
        await OsascriptRunner.run(source)
    }

    public static let systemRunScript: @MainActor @Sendable (String) -> Result<String, ScriptFailure> = { source in
        func failure(_ info: NSDictionary?) -> ScriptFailure {
            ScriptFailure(
                code: info?[NSAppleScript.errorNumber] as? Int ?? 0,
                message: info?[NSAppleScript.errorMessage] as? String ?? "erreur AppleScript inconnue"
            )
        }
        let script: NSAppleScript
        if let cached = CompiledScripts.bySource[source] {
            script = cached
        } else {
            guard let fresh = NSAppleScript(source: source) else {
                return .failure(ScriptFailure(code: 0, message: "script illisible"))
            }
            var compileError: NSDictionary?
            guard fresh.compileAndReturnError(&compileError) else { return .failure(failure(compileError)) }
            CompiledScripts.bySource[source] = fresh
            script = fresh
        }
        var runError: NSDictionary?
        let result = script.executeAndReturnError(&runError)
        if let runError { return .failure(failure(runError)) }
        return .success(result.stringValue ?? "")
    }

    // MARK: - Scripts

    /// Each window is read inside its own `try`: one window that cannot be read (picture-in-picture,
    /// settings…) reports its error and leaves the others readable. The script checks by itself that Dia
    /// is running, so it can never wake it up if Dia quit after `isRunning` was asked.
    static func source(for variant: Variant) -> String {
        let record = """
        set out to out & wid & fs & (id of t) & fs & (loading of t) & fs & (isFocused of t) & fs & (isPinned of t) & fs & (URL of t) & fs & (title of t) & rs
        """
        let windowTabs: String
        let profileTabs: String
        switch variant {
        case .whose:
            windowTabs = """
                  set found to (every tab of w whose URL contains "meet.google.com")
                  repeat with t in found
                    \(record)
                  end repeat
            """
            profileTabs = """
                    set found to (every tab of p whose URL contains "meet.google.com")
                    repeat with t in found
                      \(record)
                    end repeat
            """
        case .loop:
            windowTabs = """
                  repeat with t in (every tab of w)
                    if (URL of t) contains "meet.google.com" then
                      \(record)
                    end if
                  end repeat
            """
            profileTabs = """
                    repeat with t in (every tab of p)
                      if (URL of t) contains "meet.google.com" then
                        \(record)
                      end if
                    end repeat
            """
        }
        return """
        set fs to character id 31
        set rs to character id 30
        set out to ""
        if application id "\(diaBundleID)" is not running then return "\(DiaTabParser.notRunningSentinel)"
        with timeout of 3 seconds
          tell application id "\(diaBundleID)"
            repeat with w in (every window)
              try
                set wid to id of w
        \(windowTabs)
                repeat with p in (every profile of w)
        \(profileTabs)
                end repeat
                set out to out & "+" & rs
              on error errorMessage number errorNumber
                set out to out & "!" & fs & errorNumber & fs & errorMessage & rs
              end try
            end repeat
          end tell
        end timeout
        return out
        """
    }
}

@MainActor
private enum CompiledScripts {
    static var bySource: [String: NSAppleScript] = [:]
}
