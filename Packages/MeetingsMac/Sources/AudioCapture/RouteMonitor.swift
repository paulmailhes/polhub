import CoreAudio
import Foundation

/// Something Core Audio said about the audio route.
public struct RouteEvent: Equatable, Sendable, Codable {
    /// `defaultInput`, `defaultOutput`, `deviceList`, `processDevices`, `tapFormat`, `streamFormat`,
    /// `deviceAlive` or `serviceRestarted`.
    public let source: String
    /// `input`, `output` or `both`: which side of the route the event is about.
    public let side: String
    public let objectID: UInt32
    /// Device UID and format read when the notification arrived.
    public let detail: String

    public init(source: String, side: String, objectID: UInt32, detail: String) {
        self.source = source
        self.side = side
        self.objectID = objectID
        self.detail = detail
    }
}

/// Listens to Core Audio's route notifications and reports them. It decides nothing.
///
/// It watches the system object, the given processes, the given tap, the microphones in use (the given
/// ones, else the default input) and the default output device. Aggregates created by this app are never
/// reported.
public final class RouteMonitor: @unchecked Sendable {
    private let processes: [AudioObjectID]
    private let tap: AudioObjectID?
    private let micDeviceUIDs: [String]
    private let onEvent: @Sendable (RouteEvent) -> Void
    private let queue = DispatchQueue(label: "fr.paulmailhes.transcriptor.route-monitor")

    // All of this is touched on `queue` only.
    private var listeners: [PropertyListener] = []
    private var knownDevices: Set<String> = []
    private var running = false

    /// `micDeviceUIDs`: the microphones being recorded. They are not always the system's default input: Meet
    /// lets the person pick another one.
    public init(
        processes: [AudioObjectID],
        tap: AudioObjectID?,
        micDeviceUIDs: [String] = [],
        onEvent: @escaping @Sendable (RouteEvent) -> Void
    ) {
        self.processes = processes
        self.tap = tap
        self.micDeviceUIDs = micDeviceUIDs
        self.onEvent = onEvent
    }

    public func start() {
        queue.sync {
            guard !running else { return }
            running = true
            knownDevices = Self.deviceUIDs()

            listen(HAL.system, kAudioHardwarePropertyDefaultInputDevice) { [weak self] in
                self?.reportDefault("defaultInput", side: "input", kAudioHardwarePropertyDefaultInputDevice)
            }
            listen(HAL.system, kAudioHardwarePropertyDefaultOutputDevice) { [weak self] in
                self?.reportDefault("defaultOutput", side: "output", kAudioHardwarePropertyDefaultOutputDevice)
            }
            listen(HAL.system, kAudioHardwarePropertyDevices) { [weak self] in
                self?.reportDeviceList()
            }
            listen(HAL.system, kAudioHardwarePropertyServiceRestarted) { [weak self] in
                self?.emit("serviceRestarted", side: "both", object: HAL.system, detail: "")
            }
            for process in processes {
                listen(process, kAudioProcessPropertyDevices, scope: kAudioObjectPropertyScopeWildcard) { [weak self] in
                    self?.emit("processDevices", side: "both", object: process, detail: "")
                }
            }
            if let tap {
                listen(tap, kAudioTapPropertyFormat) { [weak self] in
                    let format = (try? HAL.value(tap, kAudioTapPropertyFormat, as: AudioStreamBasicDescription.self))
                    self?.emit("tapFormat", side: "output", object: tap, detail: Self.describe(format))
                }
            }
            let recorded: [AudioObjectID?] = micDeviceUIDs.map { try? HAL.device(forUID: $0) }
            let microphones = recorded.isEmpty
                ? [try? HAL.value(HAL.system, kAudioHardwarePropertyDefaultInputDevice, as: AudioObjectID.self)]
                : recorded
            let output = try? HAL.value(HAL.system, kAudioHardwarePropertyDefaultOutputDevice, as: AudioObjectID.self)
            microphones.forEach { watchDevice($0, side: "input") }
            watchDevice(output, side: "output")
        }
    }

    public func stop() {
        queue.sync {
            running = false
            listeners.forEach { $0.remove() }
            listeners = []
        }
    }

    /// `+added -removed`, sorted, or nil when nothing changed once this app's own aggregates are set aside.
    static func deviceListChange(from old: Set<String>, to new: Set<String>) -> String? {
        let foreign: (String) -> Bool = { !$0.hasPrefix(TapAggregate.uidPrefix) }
        let before = old.filter(foreign)
        let after = new.filter(foreign)
        let added = after.subtracting(before).sorted().map { "+\($0)" }
        let removed = before.subtracting(after).sorted().map { "-\($0)" }
        let parts = added + removed
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    // MARK: - Listeners (all on `queue`)

    private func listen(
        _ object: AudioObjectID,
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        _ handler: @escaping () -> Void
    ) {
        // The handlers only touch state owned by `queue`, which is where the listener calls them.
        let handler = UncheckedHandler(handler)
        if let listener = PropertyListener(
            object: object, address: HAL.address(selector, scope), queue: queue, handler: { handler.call() }
        ) {
            listeners.append(listener)
        }
    }

    private struct UncheckedHandler: @unchecked Sendable {
        let call: () -> Void
        init(_ call: @escaping () -> Void) { self.call = call }
    }

    private func watchDevice(_ device: AudioObjectID?, side: String) {
        guard let device,
              device != kAudioObjectUnknown,
              let uid = try? HAL.string(device, kAudioDevicePropertyDeviceUID),
              !uid.hasPrefix(TapAggregate.uidPrefix)
        else { return }
        listen(device, kAudioDevicePropertyDeviceIsAlive) { [weak self] in
            let alive = (try? HAL.value(device, kAudioDevicePropertyDeviceIsAlive, as: UInt32.self)) ?? 0
            self?.emit("deviceAlive", side: side, object: device, detail: "\(uid) alive=\(alive)")
        }
        listen(device, kAudioDevicePropertyNominalSampleRate) { [weak self] in
            let rate = (try? HAL.value(device, kAudioDevicePropertyNominalSampleRate, as: Float64.self)) ?? 0
            self?.emit("streamFormat", side: side, object: device, detail: "\(uid) \(Int(rate)) Hz")
        }
    }

    private func reportDefault(_ source: String, side: String, _ selector: AudioObjectPropertySelector) {
        guard let device = try? HAL.value(HAL.system, selector, as: AudioObjectID.self) else { return }
        let uid = (try? HAL.string(device, kAudioDevicePropertyDeviceUID)) ?? "?"
        guard !uid.hasPrefix(TapAggregate.uidPrefix) else { return }
        let rate = (try? HAL.value(device, kAudioDevicePropertyNominalSampleRate, as: Float64.self)) ?? 0
        emit(source, side: side, object: device, detail: "\(uid) \(Int(rate)) Hz")
    }

    private func reportDeviceList() {
        let current = Self.deviceUIDs()
        defer { knownDevices = current }
        guard let change = Self.deviceListChange(from: knownDevices, to: current) else { return }
        emit("deviceList", side: "both", object: HAL.system, detail: change)
    }

    private func emit(_ source: String, side: String, object: AudioObjectID, detail: String) {
        guard running else { return }
        onEvent(RouteEvent(source: source, side: side, objectID: object, detail: detail))
    }

    private static func deviceUIDs() -> Set<String> {
        let devices = (try? HAL.array(HAL.system, kAudioHardwarePropertyDevices, of: AudioObjectID.self)) ?? []
        return Set(devices.compactMap { try? HAL.string($0, kAudioDevicePropertyDeviceUID) })
    }

    private static func describe(_ format: AudioStreamBasicDescription?) -> String {
        guard let format else { return "format illisible" }
        return "\(Int(format.mSampleRate)) Hz \(format.mChannelsPerFrame) canal(aux)"
    }
}
