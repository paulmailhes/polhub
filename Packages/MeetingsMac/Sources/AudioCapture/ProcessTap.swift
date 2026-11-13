import CoreAudio
import Foundation

/// What a tap listens to.
public enum TapTarget: Equatable, Sendable {
    /// These Core Audio process objects, and nothing else.
    case processes([AudioObjectID])
    /// Every process of these bundle identifiers, re-tapped when they restart (macOS 26+).
    case bundleIDs([String])
    /// The whole system output, except these process objects.
    case globalExcluding([AudioObjectID])
}

/// A Core Audio process tap: a mono mixdown of what the target plays, private to this app.
/// It is never muted: the person keeps hearing the meeting.
///
/// Creating a tap asks for nothing; macOS asks for the "system audio recording" permission when an
/// aggregate device that contains the tap is started.
public final class ProcessTap: @unchecked Sendable {
    public let tapID: AudioObjectID
    public let uid: String

    private let tapDescription: CATapDescription
    private let lock = NSLock()
    private var valid = true

    public init(target: TapTarget, name: String) throws {
        let description: CATapDescription
        switch target {
        case .processes(let processes):
            description = CATapDescription(monoMixdownOfProcesses: processes)
        case .globalExcluding(let processes):
            description = CATapDescription(monoGlobalTapButExcludeProcesses: processes)
        case .bundleIDs(let bundleIDs):
            description = CATapDescription()
            description.bundleIDs = bundleIDs
            description.isMono = true
            description.isMixdown = true
            description.isExclusive = false
            description.isProcessRestoreEnabled = true
        }
        description.name = name
        description.uuid = UUID()
        description.isPrivate = true
        description.muteBehavior = .unmuted

        var tapID = AudioObjectID(kAudioObjectUnknown)
        let status = AudioHardwareCreateProcessTap(description, &tapID)
        guard status == noErr, tapID != kAudioObjectUnknown else {
            throw HALError(status: status, selector: kAudioHardwarePropertyTapList)
        }
        self.tapID = tapID
        tapDescription = description
        uid = (try? HAL.string(tapID, kAudioTapPropertyUID)) ?? description.uuid.uuidString
    }

    deinit {
        invalidate()
    }

    public func format() throws -> PCMFormat {
        let description = try HAL.value(tapID, kAudioTapPropertyFormat, as: AudioStreamBasicDescription.self)
        return PCMFormat(sampleRate: description.mSampleRate, channels: Int(description.mChannelsPerFrame))
    }

    /// Writes the tap's own description back to it. Measured in phase 0: does the status tell whether the
    /// system audio permission is granted, without playing any sound?
    public func rewriteDescription() -> OSStatus {
        var address = HAL.address(kAudioTapPropertyDescription, kAudioObjectPropertyScopeGlobal)
        var reference = tapDescription
        return withUnsafePointer(to: &reference) {
            AudioObjectSetPropertyData(tapID, &address, 0, nil, UInt32(MemoryLayout<CATapDescription>.size), $0)
        }
    }

    /// Destroys the tap, once. Call it after the aggregate device that reads it has been destroyed.
    public func invalidate() {
        lock.lock()
        defer { lock.unlock() }
        guard valid else { return }
        valid = false
        AudioHardwareDestroyProcessTap(tapID)
    }
}
