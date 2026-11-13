import AppKit
import Foundation

/// The versions the checks were last run on.
public struct VersionPair: Codable, Equatable, Sendable {
    public let macOS: String
    public let dia: String?

    public init(macOS: String, dia: String?) {
        self.macOS = macOS
        self.dia = dia
    }

    public static func current() -> VersionPair {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let dia = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "company.thebrowser.dia")
            .flatMap { Bundle(url: $0)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String }
        return VersionPair(macOS: "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)", dia: dia)
    }
}

/// A new macOS or a new Dia can take a permission away without a word: the checks run again then.
public enum DiagnosticTrigger {
    public static func shouldReplay(last: VersionPair?, current: VersionPair) -> Bool {
        last != current
    }
}
