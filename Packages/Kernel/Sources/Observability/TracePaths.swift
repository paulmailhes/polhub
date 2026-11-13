import Foundation

public enum TracePaths {
    /// `~/Library/Application Support/Polhub/Mesures`
    public static var root: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Polhub/Mesures", directoryHint: .isDirectory)
    }

    /// `<root>/<yyyyMMdd-HHmmss>Z-<probe>/`, stamped in UTC.
    public static func sessionDirectory(root: URL, probe: String, at date: Date) -> URL {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let stamp = String(format: "%04d%02d%02d-%02d%02d%02dZ", c.year!, c.month!, c.day!, c.hour!, c.minute!, c.second!)
        return root.appending(path: "\(stamp)-\(probe)", directoryHint: .isDirectory)
    }
}
