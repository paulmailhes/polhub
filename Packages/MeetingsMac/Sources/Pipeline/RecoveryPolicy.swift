import Darwin
import Foundation
import Persistence

/// After a crash, a meeting goes on in its folder only if its timeline was written moments ago, since
/// this boot of the Mac: anything older is a meeting the app lost, closed as interrupted.
public enum RecoveryPolicy {
    public static let freshSeconds = 600.0

    public static func canResume(lastWrite: Date?, bootTime: Date, now: Date) -> Bool {
        guard let lastWrite else { return false }
        return lastWrite > bootTime && now.timeIntervalSince(lastWrite) < freshSeconds
    }

    /// When the meeting's timeline was last written.
    public static func lastWrite(of row: MeetingRow, paths: AppPaths) -> Date? {
        let url = paths.meetingFolder(row.id).appending(path: "timeline.jsonl")
        return (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    /// When this Mac last started.
    public static func bootTime() -> Date {
        var time = timeval()
        var size = MemoryLayout<timeval>.size
        sysctlbyname("kern.boottime", &time, &size, nil, 0)
        return Date(timeIntervalSince1970: Double(time.tv_sec) + Double(time.tv_usec) / 1e6)
    }
}
