import CoreAudio
import Foundation

/// A microphone the Mac sees (20/11, the Dictée's « Micro »): its UID stays the same from one connection to the next.
public struct Microphone: Equatable, Hashable, Sendable, Identifiable {
    public var uid: String
    public var name: String
    public var id: String { uid }

    public init(uid: String, name: String) {
        self.uid = uid
        self.name = name
    }
}

/// The devices of the Mac, read and set through Core Audio.
public enum Devices {
    /// The devices that can record, as macOS lists them.
    public static func microphones() -> [Microphone] {
        let devices = (try? HAL.array(HAL.system, kAudioHardwarePropertyDevices, of: AudioObjectID.self)) ?? []
        return devices.compactMap { device in
            guard hasInput(device), let uid = try? HAL.string(device, kAudioDevicePropertyDeviceUID),
                  let name = try? HAL.string(device, kAudioObjectPropertyName) else { return nil }
            // The aggregates hub makes to record a meeting are not microphones.
            guard !uid.hasPrefix("fr.paulmailhes") else { return nil }
            return Microphone(uid: uid, name: name)
        }
    }

    public static func defaultInput() -> AudioObjectID? {
        try? HAL.value(HAL.system, kAudioHardwarePropertyDefaultInputDevice, as: AudioObjectID.self)
    }

    public static func defaultOutput() -> AudioObjectID? {
        try? HAL.value(HAL.system, kAudioHardwarePropertyDefaultOutputDevice, as: AudioObjectID.self)
    }

    /// Whether the device talks by Bluetooth: such a microphone takes up to a second to open (measured 20/11: 0,3 to
    /// 0,8 s of the first words lost, against 0,05 s for the Mac's own).
    public static func isBluetooth(_ device: AudioObjectID) -> Bool {
        guard let transport = try? HAL.value(device, kAudioDevicePropertyTransportType, as: UInt32.self) else { return false }
        return transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE
    }

    static func hasInput(_ device: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: kAudioObjectPropertyScopeInput,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr && size > 0
    }

    // MARK: - The sound of the Mac

    static func muteAddress(_ device: AudioObjectID) -> AudioObjectPropertyAddress? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeOutput,
                                                 mElement: kAudioObjectPropertyElementMain)
        if AudioObjectHasProperty(device, &address) { return address }
        address.mElement = 1
        return AudioObjectHasProperty(device, &address) ? address : nil
    }

    /// Whether the output is muted; nil when the device cannot say.
    public static func isMuted(_ device: AudioObjectID) -> Bool? {
        guard var address = muteAddress(device) else { return nil }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value != 0
    }

    /// Mutes or unmutes the output; false when the device does not let hub.
    @discardableResult
    public static func setMuted(_ muted: Bool, _ device: AudioObjectID) -> Bool {
        guard var address = muteAddress(device) else { return false }
        var settable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(device, &address, &settable) == noErr, settable.boolValue else { return false }
        var value: UInt32 = muted ? 1 : 0
        return AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value) == noErr
    }

    /// The device by its UID, when it is connected.
    public static func device(uid: String) -> AudioObjectID? {
        try? HAL.device(forUID: uid)
    }

    public static func uid(_ device: AudioObjectID) -> String? {
        try? HAL.string(device, kAudioDevicePropertyDeviceUID)
    }
}
