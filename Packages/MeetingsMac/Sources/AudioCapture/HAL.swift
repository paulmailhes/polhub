import CoreAudio
import Foundation

public struct HALError: Error, Equatable, Sendable {
    public let status: OSStatus
    public let selector: UInt32

    public init(status: OSStatus, selector: UInt32) {
        self.status = status
        self.selector = selector
    }
}

/// Thin typed readers over `AudioObjectGetPropertyData`.
public enum HAL {
    public static let system = AudioObjectID(kAudioObjectSystemObject)

    static func address(
        _ selector: AudioObjectPropertySelector,
        _ scope: AudioObjectPropertyScope
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    /// Reads a plain value (integer, float, C struct). Use `string` for CFString properties.
    public static func value<T>(
        _ object: AudioObjectID,
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        as type: T.Type
    ) throws -> T {
        var address = address(selector, scope)
        var size = UInt32(MemoryLayout<T>.size)
        let pointer = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { pointer.deallocate() }
        let status = AudioObjectGetPropertyData(object, &address, 0, nil, &size, pointer)
        guard status == noErr else { throw HALError(status: status, selector: selector) }
        return pointer.pointee
    }

    public static func array<T>(
        _ object: AudioObjectID,
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        of type: T.Type
    ) throws -> [T] {
        var address = address(selector, scope)
        var size: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size)
        guard status == noErr else { throw HALError(status: status, selector: selector) }
        let capacity = Int(size) / MemoryLayout<T>.stride
        guard capacity > 0 else { return [] }
        let buffer = UnsafeMutablePointer<T>.allocate(capacity: capacity)
        defer { buffer.deallocate() }
        status = AudioObjectGetPropertyData(object, &address, 0, nil, &size, buffer)
        guard status == noErr else { throw HALError(status: status, selector: selector) }
        return Array(UnsafeBufferPointer(start: buffer, count: Int(size) / MemoryLayout<T>.stride))
    }

    public static func string(
        _ object: AudioObjectID,
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) throws -> String {
        var address = address(selector, scope)
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var value: Unmanaged<CFString>?
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0)
        }
        guard status == noErr, let value else { throw HALError(status: status, selector: selector) }
        return value.takeRetainedValue() as String
    }

    /// The device that has this UID, or an error when no such device is connected.
    public static func device(forUID uid: String) throws -> AudioObjectID {
        let selector = kAudioHardwarePropertyTranslateUIDToDevice
        var address = address(selector, kAudioObjectPropertyScopeGlobal)
        var qualifier = uid as CFString
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = withUnsafePointer(to: &qualifier) {
            AudioObjectGetPropertyData(system, &address, UInt32(MemoryLayout<CFString>.size), $0, &size, &device)
        }
        guard status == noErr, device != kAudioObjectUnknown else {
            throw HALError(status: status, selector: selector)
        }
        return device
    }

    /// The Core Audio process object of a process, or an error when it is not an audio client.
    public static func processObject(forPID pid: pid_t) throws -> AudioObjectID {
        let selector = kAudioHardwarePropertyTranslatePIDToProcessObject
        var address = address(selector, kAudioObjectPropertyScopeGlobal)
        var pid = pid
        var object = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            system, &address, UInt32(MemoryLayout<pid_t>.size), &pid, &size, &object
        )
        guard status == noErr, object != kAudioObjectUnknown else {
            throw HALError(status: status, selector: selector)
        }
        return object
    }
}
