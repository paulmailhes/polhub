import CoreAudio
import Foundation

/// The private aggregate device through which a tap is read.
///
/// By default it holds the tap alone, with no physical device: a Bluetooth output inside the aggregate is
/// reported to add several hundred milliseconds of latency. `mainSubDeviceUID` anchors it on an output
/// device instead; phase 0 measures whether that is ever needed.
public final class TapAggregate: @unchecked Sendable {
    /// Every aggregate created here has a UID starting with this, so route monitoring can ignore them.
    public static let uidPrefix = "fr.paulmailhes.polhub.agg."

    public let deviceID: AudioObjectID
    public let uid: String

    private let lock = NSLock()
    private var valid = true

    public init(tap: ProcessTap, mainSubDeviceUID: String? = nil) throws {
        let uid = Self.uidPrefix + UUID().uuidString
        var description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "hub (capture)",
            kAudioAggregateDeviceUIDKey: uid,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            // true would make AudioDeviceStart wait until the tapped process plays its first sound.
            kAudioAggregateDeviceTapAutoStartKey: false,
            kAudioAggregateDeviceTapListKey: [
                [kAudioSubTapUIDKey: tap.uid, kAudioSubTapDriftCompensationKey: true],
            ],
        ]
        if let mainSubDeviceUID {
            description[kAudioAggregateDeviceMainSubDeviceKey] = mainSubDeviceUID
            description[kAudioAggregateDeviceSubDeviceListKey] = [[kAudioSubDeviceUIDKey: mainSubDeviceUID]]
        }

        var deviceID = AudioObjectID(kAudioObjectUnknown)
        let status = AudioHardwareCreateAggregateDevice(description as CFDictionary, &deviceID)
        guard status == noErr, deviceID != kAudioObjectUnknown else {
            throw HALError(status: status, selector: kAudioHardwarePropertyDevices)
        }
        self.deviceID = deviceID
        self.uid = uid
    }

    deinit {
        invalidate()
    }

    /// Destroys the aggregate, once. Call it after the stream that reads it has stopped.
    public func invalidate() {
        lock.lock()
        defer { lock.unlock() }
        guard valid else { return }
        valid = false
        AudioHardwareDestroyAggregateDevice(deviceID)
    }
}
