import AudioCapture
import CoreAudio
import Darwin
import Foundation

/// One Core Audio client process: who it is, and whether it is recording or playing right now.
public struct AudioProcessInfo: Equatable, Sendable, Codable {
    public let objectID: UInt32
    public let pid: Int32
    public let bundleID: String?
    public let executablePath: String?
    public let owningAppPath: String?
    public let isRunningInput: Bool
    public let isRunningOutput: Bool
    public let inputDeviceUIDs: [String]
    public let outputDeviceUIDs: [String]

    public init(
        objectID: UInt32, pid: Int32, bundleID: String?, executablePath: String?, owningAppPath: String?,
        isRunningInput: Bool, isRunningOutput: Bool, inputDeviceUIDs: [String], outputDeviceUIDs: [String]
    ) {
        self.objectID = objectID
        self.pid = pid
        self.bundleID = bundleID
        self.executablePath = executablePath
        self.owningAppPath = owningAppPath
        self.isRunningInput = isRunningInput
        self.isRunningOutput = isRunningOutput
        self.inputDeviceUIDs = inputDeviceUIDs
        self.outputDeviceUIDs = outputDeviceUIDs
    }
}

/// Lists Core Audio's client processes. Reading this list needs no permission and makes no sound.
public struct AudioProcessMonitor: Sendable {
    public init() {}

    /// A property that cannot be read on one process leaves that field empty; it never fails the whole reading.
    public func snapshot() throws -> [AudioProcessInfo] {
        let objects = try HAL.array(HAL.system, kAudioHardwarePropertyProcessObjectList, of: AudioObjectID.self)
        return objects.compactMap { object in
            guard let pid = try? HAL.value(object, kAudioProcessPropertyPID, as: pid_t.self), pid > 0 else {
                return nil
            }
            let bundleID = (try? HAL.string(object, kAudioProcessPropertyBundleID)).flatMap { $0.isEmpty ? nil : $0 }
            let path = Self.executablePath(of: pid)
            return AudioProcessInfo(
                objectID: object,
                pid: pid,
                bundleID: bundleID,
                executablePath: path,
                owningAppPath: path.flatMap(AppOwnership.outermostAppPath(forExecutablePath:)),
                isRunningInput: Self.flag(object, kAudioProcessPropertyIsRunningInput),
                isRunningOutput: Self.flag(object, kAudioProcessPropertyIsRunningOutput),
                inputDeviceUIDs: Self.deviceUIDs(object, scope: kAudioObjectPropertyScopeInput),
                outputDeviceUIDs: Self.deviceUIDs(object, scope: kAudioObjectPropertyScopeOutput)
            )
        }
    }

    /// Whether an app records or plays right now.
    public struct Activity: Equatable, Sendable {
        public var input: Bool
        public var output: Bool

        public init(input: Bool, output: Bool) {
            self.input = input
            self.output = output
        }
    }

    /// What one app does with sound, read lightly (19/11): each client's pid, its path (no Core Audio call), and the two
    /// flags of that app's own processes only. `snapshot()` reads nine properties per client, the device lists
    /// included: asked every second by the watcher, it kept `coreaudiod` busy all day (measured in a profile).
    public func activity(ofAppAt appPath: String) throws -> Activity {
        let objects = try HAL.array(HAL.system, kAudioHardwarePropertyProcessObjectList, of: AudioObjectID.self)
        var activity = Activity(input: false, output: false)
        for object in objects {
            guard let pid = try? HAL.value(object, kAudioProcessPropertyPID, as: pid_t.self), pid > 0,
                  let path = Self.executablePath(of: pid), AppOwnership.outermostAppPath(forExecutablePath: path) == appPath else { continue }
            activity.input = activity.input || Self.flag(object, kAudioProcessPropertyIsRunningInput)
            activity.output = activity.output || Self.flag(object, kAudioProcessPropertyIsRunningOutput)
        }
        return activity
    }

    private static func flag(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> Bool {
        ((try? HAL.value(object, selector, as: UInt32.self)) ?? 0) != 0
    }

    private static func deviceUIDs(_ object: AudioObjectID, scope: AudioObjectPropertyScope) -> [String] {
        let devices = (try? HAL.array(object, kAudioProcessPropertyDevices, scope: scope, of: AudioObjectID.self)) ?? []
        return devices.compactMap { try? HAL.string($0, kAudioDevicePropertyDeviceUID) }
    }

    static func executablePath(of pid: pid_t) -> String? {
        var buffer = [UInt8](repeating: 0, count: 4096)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(decoding: buffer.prefix(Int(length)), as: UTF8.self)
    }
}
