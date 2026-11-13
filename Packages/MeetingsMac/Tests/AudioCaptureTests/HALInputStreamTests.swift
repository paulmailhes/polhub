import CoreAudio
import Foundation
import Testing
@testable import AudioCapture

/// Core Audio's start and stop replaced by fakes: what is tested is the guarding and the ordering.
@Suite struct HALInputStreamTests {
    final class Calls: @unchecked Sendable {
        private let lock = NSLock()
        private var names: [String] = []
        func add(_ name: String) { lock.withLock { names.append(name) } }
        var all: [String] { lock.withLock { names } }
    }

    func stream(_ calls: Calls, startBlocksFor seconds: Double = 0, startStatus: OSStatus = noErr) -> HALInputStream {
        HALInputStream(
            format: PCMFormat(sampleRate: 48_000, channels: 1),
            operations: .init(
                start: {
                    if seconds > 0 { Thread.sleep(forTimeInterval: seconds) }
                    calls.add("start")
                    return startStatus
                },
                stop: { calls.add("stop"); return noErr },
                destroy: { calls.add("destroy") }
            )
        )
    }

    @Test func startThenStopCallsCoreAudioInOrder() throws {
        let calls = Calls()
        let s = stream(calls)
        try s.start()
        let stopped = s.stop(then: { calls.add("then") })
        #expect(stopped)
        #expect(calls.all == ["start", "stop", "destroy", "then"])
    }

    @Test func aBlockedStartTimesOutAndIsStoppedOnceItReturns() {
        let calls = Calls()
        let s = stream(calls, startBlocksFor: 0.3)
        #expect(throws: HALStartTimeout.self) { try s.start(timeout: .milliseconds(50)) }
        // The stop queues behind the start that is still blocked, and stops it when it finally returns.
        let stopped = s.stop(timeout: .seconds(2), then: { calls.add("then") })
        #expect(stopped)
        #expect(calls.all == ["start", "stop", "destroy", "then"])
    }

    @Test func stopGivesUpAfterItsOwnTimeoutButStillCleansUpLater() async throws {
        let calls = Calls()
        let s = stream(calls, startBlocksFor: 0.4)
        #expect(throws: HALStartTimeout.self) { try s.start(timeout: .milliseconds(50)) }
        let stopped = s.stop(timeout: .milliseconds(50), then: { calls.add("then") })
        #expect(stopped == false)
        #expect(calls.all.isEmpty)                     // nothing was torn down under a start still in flight
        try await Task.sleep(for: .milliseconds(700))
        #expect(calls.all == ["start", "stop", "destroy", "then"])
    }

    @Test func aStartThatFailedIsNotStopped() {
        let calls = Calls()
        let s = stream(calls, startStatus: kAudioHardwareIllegalOperationError)
        #expect(throws: HALError.self) { try s.start() }
        #expect(s.stop())
        #expect(calls.all == ["start", "destroy"])
    }

    @Test func stoppingTwiceDestroysOnce() throws {
        let calls = Calls()
        let s = stream(calls)
        try s.start()
        #expect(s.stop())
        #expect(s.stop())
        #expect(calls.all == ["start", "stop", "destroy"])
    }

    @Test func aStartAfterStopIsRefused() {
        let calls = Calls()
        let s = stream(calls)
        #expect(s.stop())
        #expect(throws: HALError.self) { try s.start() }
        #expect(calls.all == ["destroy"])
    }
}
