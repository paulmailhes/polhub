import Foundation
import notify

/// « The base changed »: posted by `polhub mcp` after a write, heard by the app, which then refreshes its
/// views (`AppDatabase.notifyExternalChanges`). A Darwin notification: no payload, no network.
public enum ExternalChangeSignal {
    public static let name = "fr.paulmailhes.polhub.base-modifiee"

    public static func post(name: String = name) {
        notify_post(name)
    }

    /// Stops listening when cancelled.
    public final class Listener: @unchecked Sendable {
        private let lock = NSLock()
        private var token: Int32?

        init(token: Int32) {
            self.token = token
        }

        public func cancel() {
            lock.withLock {
                if let token { notify_cancel(token) }
                token = nil
            }
        }

        deinit { cancel() }
    }

    public static func listen(name: String = name, queue: DispatchQueue, _ handler: @escaping @Sendable () -> Void) -> Listener {
        var token: Int32 = 0
        notify_register_dispatch(name, &token, queue) { _ in handler() }
        return Listener(token: token)
    }
}
