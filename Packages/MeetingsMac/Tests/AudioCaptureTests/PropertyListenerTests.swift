import CoreAudio
import Foundation
import os
import Testing
@testable import AudioCapture

// Vrai Core Audio, sans son ni autorisation : la liste des périphériques change quand ce processus crée
// puis détruit un aggregate privé et vide.
@Suite(.serialized) struct PropertyListenerTests {
    func makeEmptyPrivateAggregate() throws -> AudioObjectID {
        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Transcriptor (test)",
            kAudioAggregateDeviceUIDKey: "fr.paulmailhes.transcriptor.test." + UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
        ]
        var device = AudioObjectID(kAudioObjectUnknown)
        let status = AudioHardwareCreateAggregateDevice(description as CFDictionary, &device)
        try #require(status == noErr && device != kAudioObjectUnknown)
        return device
    }

    func churnDeviceList() throws {
        let device = try makeEmptyPrivateAggregate()
        AudioHardwareDestroyAggregateDevice(device)
    }

    @Test func aListenerIsCalledThenNeverAgainOnceRemoved() async throws {
        let count = OSAllocatedUnfairLock(initialState: 0)
        let queue = DispatchQueue(label: "fr.paulmailhes.transcriptor.test.listener")
        let listener = try #require(PropertyListener(
            object: HAL.system,
            address: HAL.address(kAudioHardwarePropertyDevices, kAudioObjectPropertyScopeGlobal),
            queue: queue
        ) { count.withLock { $0 += 1 } })

        try churnDeviceList()
        for _ in 0..<40 where count.withLock({ $0 }) == 0 {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(count.withLock { $0 } >= 1)

        try await Task.sleep(for: .milliseconds(300))
        listener.remove()
        let before = count.withLock { $0 }
        try churnDeviceList()
        try churnDeviceList()
        try await Task.sleep(for: .milliseconds(800))
        #expect(count.withLock { $0 } == before)
    }
}
