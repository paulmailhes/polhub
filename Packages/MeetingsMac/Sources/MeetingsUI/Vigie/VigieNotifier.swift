import AppKit
import Foundation
import Notifications
import VigieKit

/// hub notifies for Vigie (21/11, the migration: Paul turns the app Vigie off): after each reading, what
/// `VigieNotifications` decides goes to macOS and to hub's list. While the app Vigie runs, it notifies itself: hub stays
/// silent, never twice the same notification. What was notified is remembered from one launch to the next.
@MainActor public final class VigieNotifier {
    /// The app Vigie's bundle.
    nonisolated public static let appBundle = "io.github.paulmailhes.vigie"
    static let stateKey = "vigie.notifications.state"

    let defaults: UserDefaults
    let post: (PlannedNotice) async -> Void
    let remove: ([String]) async -> Void
    let appRunning: @MainActor () -> Bool
    private var state: VigieNotifications.State

    public init(defaults: UserDefaults = .standard, post: @escaping (PlannedNotice) async -> Void, remove: @escaping ([String]) async -> Void,
                appRunning: (@MainActor () -> Bool)? = nil) {
        self.defaults = defaults
        self.post = post
        self.remove = remove
        self.appRunning = appRunning ?? { VigieNotifier.isAppRunning() }
        state = (defaults.data(forKey: Self.stateKey)).flatMap { try? JSONDecoder().decode(VigieNotifications.State.self, from: $0) }
            ?? VigieNotifications.State()
    }

    /// The app Vigie runs: it notifies.
    public static func isAppRunning() -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == appBundle }
    }

    /// A kind Paul turned off in Réglages › Vigie.
    static func isOn(_ kind: VigieNotifications.Kind, in defaults: UserDefaults) -> Bool {
        defaults.object(forKey: key(kind)) as? Bool ?? true
    }

    nonisolated static func key(_ kind: VigieNotifications.Kind) -> String {
        "vigie.notify." + kind.rawValue
    }

    /// After a reading. `inFront`: the page of this conversation is in front of Paul.
    public func process(_ overview: VigieOverview, now: Date = Date(), inFront: (String?) -> Bool = { _ in false }) async {
        let defaults = defaults
        let outcome = VigieNotifications.plan(overview, state: &state, now: now, enabled: { Self.isOn($0, in: defaults) }, inFront: inFront,
                                              silent: appRunning())
        if let data = try? JSONEncoder().encode(state) { defaults.set(data, forKey: Self.stateKey) }
        if !outcome.remove.isEmpty { await remove(outcome.remove) }
        for notice in outcome.post {
            // A notice that makes no banner still reaches the center: `quiet`.
            let quiet = notice.quiet || !outcome.banners.contains(notice.key)
            await post(PlannedNotice(id: notice.key, fireDate: now, title: notice.title, body: notice.body, eventID: nil, meetCode: nil,
                                     account: nil, kind: .vigie, subtitle: notice.subtitle, vigie: notice.conversationID ?? "", quiet: quiet))
        }
    }
}
