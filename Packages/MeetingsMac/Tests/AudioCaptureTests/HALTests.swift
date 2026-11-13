import CoreAudio
import Testing
@testable import AudioCapture

// Lit le vrai Core Audio, sans autorisation et sans produire de son.
@Suite struct HALTests {
    @Test func deviceLookupRoundTripsTheDefaultOutput() throws {
        let device = try HAL.value(HAL.system, kAudioHardwarePropertyDefaultOutputDevice, as: AudioObjectID.self)
        try #require(device != kAudioObjectUnknown)
        let uid = try HAL.string(device, kAudioDevicePropertyDeviceUID)
        #expect(try HAL.device(forUID: uid) == device)
    }

    @Test func unknownDeviceUIDThrows() {
        #expect(throws: HALError.self) { _ = try HAL.device(forUID: "fr.paulmailhes.polhub.inexistant") }
    }

    @Test func aProcessThatIsNotAnAudioClientHasNoProcessObject() {
        #expect(throws: HALError.self) { _ = try HAL.processObject(forPID: 1) }   // launchd
    }
}
