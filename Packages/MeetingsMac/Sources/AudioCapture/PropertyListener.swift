import CoreAudio
import Foundation
import Synchronization

/// One Core Audio property listener that can really be removed.
///
/// The block-based API cannot be used from Swift for this: Swift hands Core Audio a new block object on
/// every call, so `AudioObjectRemovePropertyListenerBlock` never finds the block it was given and removes
/// nothing. The C-function form is identified by a function pointer and a context pointer, both stable.
final class PropertyListener: @unchecked Sendable {
    private final class Context: Sendable {
        let queue: DispatchQueue
        let handler: @Sendable () -> Void
        let active = Atomic<Bool>(true)

        init(queue: DispatchQueue, handler: @escaping @Sendable () -> Void) {
            self.queue = queue
            self.handler = handler
        }
    }

    private static let callback: AudioObjectPropertyListenerProc = { _, _, _, clientData in
        guard let clientData else { return noErr }
        let context = Unmanaged<Context>.fromOpaque(clientData).takeUnretainedValue()
        context.queue.async {
            if context.active.load(ordering: .acquiring) { context.handler() }
        }
        return noErr
    }

    private let object: AudioObjectID
    private var address: AudioObjectPropertyAddress
    private let context: Context
    private let pointer: UnsafeMutableRawPointer
    private let removed = Atomic<Bool>(false)

    /// Nil when Core Audio refuses the listener (unknown object, unknown property).
    init?(
        object: AudioObjectID,
        address: AudioObjectPropertyAddress,
        queue: DispatchQueue,
        handler: @escaping @Sendable () -> Void
    ) {
        self.object = object
        self.address = address
        context = Context(queue: queue, handler: handler)
        pointer = Unmanaged.passRetained(context).toOpaque()
        guard AudioObjectAddPropertyListener(object, &self.address, Self.callback, pointer) == noErr else {
            Unmanaged<Context>.fromOpaque(pointer).release()
            return nil
        }
    }

    deinit {
        remove()
    }

    /// After this returns the handler is never called again. Safe to call twice.
    func remove() {
        guard !removed.exchange(true, ordering: .acquiringAndReleasing) else { return }
        context.active.store(false, ordering: .releasing)
        AudioObjectRemovePropertyListener(object, &address, Self.callback, pointer)
        // A notification may still be on its way with this pointer: let it land before the release.
        let retained = Unmanaged<Context>.fromOpaque(pointer)
        context.queue.asyncAfter(deadline: .now() + 1) {
            retained.release()
        }
    }
}
