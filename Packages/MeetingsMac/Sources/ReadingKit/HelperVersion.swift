import Foundation

/// The commands embedded in `Polhub.app/Contents/Helpers/` have no Info.plist of their own: their
/// version is the app's.
public enum HelperVersion {
    /// `nil` when the helper does not sit in an app's `Contents/Helpers/`.
    public static func read(helper: URL) -> String? {
        let helpers = helper.resolvingSymlinksInPath().deletingLastPathComponent()
        guard helpers.lastPathComponent == "Helpers" else { return nil }
        let info = helpers.deletingLastPathComponent().appending(path: "Info.plist")
        return NSDictionary(contentsOf: info)?["CFBundleShortVersionString"] as? String
    }
}
