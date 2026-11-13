import CoreAudio
import Foundation

public struct HALStartTimeout: Error, Equatable, Sendable {
    public init() {}
}

/// Reads the input of one Core Audio device, a microphone or a tap aggregate, through an IOProc.
///
/// The handler runs on the real-time audio thread: no lock, no allocation, no file access in it.
///
/// Every call into Core Audio that can block (start, stop, removal of the IOProc) runs on one private
/// serial queue, and the caller waits for it with a timeout: never more than 3 s by default. Because the
/// queue is serial, a stop always runs after a start that is still blocked, and stops it if it finally
/// succeeded. Neither `start` nor `stop` may be called from the main thread.
public final class HALInputStream: @unchecked Sendable {
    public typealias Handler = @Sendable (_ samples: UnsafeBufferPointer<Float>, _ frames: Int, _ hostTime: UInt64) -> Void

    /// The three Core Audio calls, replaceable in tests.
    struct Operations: Sendable {
        var start: @Sendable () -> OSStatus
        var stop: @Sendable () -> OSStatus
        var destroy: @Sendable () -> Void
    }

    /// Touched on the control queue only.
    private final class State: @unchecked Sendable {
        var startSucceeded = false
        var destroyed = false

        func tearDown(_ operations: Operations) {
            guard !destroyed else { return }
            if startSucceeded { _ = operations.stop() }
            operations.destroy()
            destroyed = true
            startSucceeded = false
        }
    }

    public let deviceID: AudioObjectID
    /// Format of the device's first input stream, the one handed to the handler.
    public let format: PCMFormat

    private let operations: Operations
    private let state = State()
    private let control = DispatchQueue(label: "fr.paulmailhes.polhub.hal-control")

    public init(deviceID: AudioObjectID, handler: @escaping Handler) throws {
        self.deviceID = deviceID
        let stream = try HAL.value(
            deviceID, kAudioDevicePropertyStreamFormat, scope: kAudioObjectPropertyScopeInput,
            as: AudioStreamBasicDescription.self
        )
        format = PCMFormat(sampleRate: stream.mSampleRate, channels: Int(stream.mChannelsPerFrame))

        var created: AudioDeviceIOProcID?
        let status = AudioDeviceCreateIOProcIDWithBlock(&created, deviceID, nil) { _, input, inputTime, _, _ in
            // Only the first buffer is read: one stream, interleaved float samples.
            guard input.pointee.mNumberBuffers > 0 else { return }
            let first = input.pointee.mBuffers
            guard let data = first.mData else { return }
            let sampleCount = Int(first.mDataByteSize) / MemoryLayout<Float>.size
            let channels = max(1, Int(first.mNumberChannels))
            handler(
                UnsafeBufferPointer(start: data.assumingMemoryBound(to: Float.self), count: sampleCount),
                sampleCount / channels,
                inputTime.pointee.mHostTime
            )
        }
        guard status == noErr, let procID = created else {
            throw HALError(status: status, selector: kAudioDevicePropertyStreamFormat)
        }
        operations = Operations(
            start: { AudioDeviceStart(deviceID, procID) },
            stop: { AudioDeviceStop(deviceID, procID) },
            destroy: { AudioDeviceDestroyIOProcID(deviceID, procID) }
        )
    }

    /// For tests: no device, the three calls are the ones given.
    init(format: PCMFormat, operations: Operations) {
        deviceID = AudioObjectID(kAudioObjectUnknown)
        self.format = format
        self.operations = operations
    }

    deinit {
        // Never synchronously: the last reference may be released on the control queue itself.
        control.async { [state, operations] in state.tearDown(operations) }
    }

    /// Starts the device. Throws `HALStartTimeout` when Core Audio has not answered in time: a start is
    /// reported to block while another process holds a tap on the same device. The start may still
    /// succeed later; `stop` deals with that.
    public func start(timeout: Duration = .seconds(3)) throws {
        let done = DispatchSemaphore(value: 0)
        let result = StatusBox()
        control.async { [state, operations] in
            if state.destroyed {
                result.status = kAudioHardwareIllegalOperationError
            } else {
                result.status = operations.start()
                state.startSucceeded = result.status == noErr
            }
            done.signal()
        }
        guard done.wait(timeout: .now() + Self.seconds(timeout)) == .success else { throw HALStartTimeout() }
        guard result.status == noErr else {
            throw HALError(status: result.status, selector: kAudioDevicePropertyDeviceIsRunning)
        }
    }

    /// Stops the device and removes the IOProc, behind any start still in flight. Safe to call twice.
    ///
    /// Waits up to `timeout` and returns false when Core Audio has not answered by then. `completion`
    /// runs on the control queue once the stream is really torn down, however late: destroy the aggregate
    /// device and the tap there, never before.
    @discardableResult
    public func stop(timeout: Duration = .seconds(3), then completion: (@Sendable () -> Void)? = nil) -> Bool {
        let done = DispatchSemaphore(value: 0)
        control.async { [state, operations] in
            state.tearDown(operations)
            completion?()
            done.signal()
        }
        return done.wait(timeout: .now() + Self.seconds(timeout)) == .success
    }

    private static func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }

    private final class StatusBox: @unchecked Sendable {
        var status: OSStatus = noErr
    }
}
