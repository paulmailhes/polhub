/// Finds which application a process belongs to, from its executable path.
///
/// Dia's sound comes out of a helper whose bundle identifier is the same as Arc's helper
/// (`company.thebrowser.browser.helper`). The path is what tells the two browsers apart.
public enum AppOwnership {
    /// `/Applications/Dia.app/Contents/…/Browser Helper.app/Contents/MacOS/Browser Helper` → `/Applications/Dia.app`.
    /// Returns nil for a process that lives outside any `.app` bundle.
    public static func outermostAppPath(forExecutablePath path: String) -> String? {
        let components = path.split(separator: "/", omittingEmptySubsequences: true)
        guard let index = components.firstIndex(where: { $0.hasSuffix(".app") }) else { return nil }
        return "/" + components[...index].joined(separator: "/")
    }
}
