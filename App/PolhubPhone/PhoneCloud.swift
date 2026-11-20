import Foundation
import PolhubCloud
import PolhubLink

/// The copy the Mac keeps in the user's iCloud (20/11, lot 1 of « Polhub sans le Mac »): read into the iPhone's own copy,
/// so the projects, the meetings, the agenda and Colin show with the Mac off, at the time of the Mac's last copy.
@MainActor
final class PhoneCloudReader {
    static let tokenKey = "icloud.jeton"
    /// A look at iCloud at most this often, when the Mac does not answer.
    static let freshness: TimeInterval = 60

    let drive: any CloudDrive
    let cache: LinkCache
    let defaults: UserDefaults
    private(set) var lastLook: Date?
    private var looking: Task<Bool, Never>?

    init(drive: any CloudDrive, cache: LinkCache, defaults: UserDefaults = .standard) {
        self.drive = drive
        self.cache = cache
        self.defaults = defaults
    }

    /// What changed in iCloud since the last look, into the iPhone's copy; whether anything came.
    @discardableResult
    func refresh() async -> Bool {
        if let looking { return await looking.value }
        let task = Task { await look() }
        looking = task
        let found = await task.value
        looking = nil
        return found
    }

    /// Only when the last look is older than a minute.
    func refreshIfStale() async {
        if let lastLook, Date().timeIntervalSince(lastLook) < Self.freshness { return }
        await refresh()
    }

    /// The copy is read again from the start: after « Délier », which empties the iPhone's copy.
    func forget() {
        defaults.removeObject(forKey: Self.tokenKey)
    }

    private func look() async -> Bool {
        guard await drive.available() else { return false }
        var token = defaults.data(forKey: Self.tokenKey)
        var found = false
        while true {
            guard let changes = try? await drive.changes(since: token) else { break }
            for copy in changes.copies where cache.storeIfNewer(copy.data, for: copy.key, at: copy.date) { found = true }
            for key in changes.deleted { cache.remove(key) }
            token = changes.token
            defaults.set(token, forKey: Self.tokenKey)
            if !changes.more { break }
        }
        lastLook = Date()
        return found
    }
}
