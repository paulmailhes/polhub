import Foundation

/// Raw audio takes about 1.4 GB per hour of meeting until step 2 compresses it: below 20 GB free, Paul
/// is warned once per meeting.
public enum DiskGuard {
    public static let thresholdBytes: Int64 = 20_000_000_000

    public static func isLow(availableBytes: Int64) -> Bool {
        availableBytes < thresholdBytes
    }

    public static func availableBytes(at url: URL) -> Int64? {
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }
}
