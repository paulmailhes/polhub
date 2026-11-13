import Darwin
import Foundation
import os
import Persistence

public enum MemoryPressureLevel: String, Sendable {
    case normal, warning, critical

    public static func from(_ event: DispatchSource.MemoryPressureEvent) -> MemoryPressureLevel {
        if event.contains(.critical) { return .critical }
        if event.contains(.warning) { return .warning }
        return .normal
    }
}

/// The Mac's memory every five minutes, from step 1 on: step 3 decides from a week of it whether the
/// summary model fits next to Paul's apps.
public final class MemorySampler: @unchecked Sendable {
    private let store: MeetingStore
    private let interval: Double
    private let level = OSAllocatedUnfairLock(initialState: MemoryPressureLevel.normal)
    private var pressureSource: DispatchSourceMemoryPressure?
    private var timer: DispatchSourceTimer?

    public init(store: MeetingStore, every seconds: Double = 300) {
        self.store = store
        interval = seconds
    }

    public func start() {
        let queue = DispatchQueue(label: "fr.paulmailhes.polhub.memory", qos: .utility)
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.normal, .warning, .critical], queue: queue)
        source.setEventHandler { [weak self, weak source] in
            guard let self, let event = source?.data else { return }
            let newLevel = MemoryPressureLevel.from(event)
            self.level.withLock { $0 = newLevel }
        }
        source.resume()
        pressureSource = source

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 5, repeating: interval)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            try? self.store.addMemorySample(Self.sample(pressure: self.level.withLock { $0 }, at: Date()))
        }
        timer.resume()
        self.timer = timer
    }

    public static func sample(pressure: MemoryPressureLevel, at date: Date) -> MemorySample {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        _ = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        let page = Int64(getpagesize())
        var swap = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        sysctlbyname("vm.swapusage", &swap, &size, nil, 0)
        return MemorySample(
            at: date, pressure: pressure.rawValue,
            freeBytes: Int64(stats.free_count) * page, activeBytes: Int64(stats.active_count) * page,
            inactiveBytes: Int64(stats.inactive_count) * page, wiredBytes: Int64(stats.wire_count) * page,
            compressedBytes: Int64(stats.compressor_page_count) * page, swapUsedBytes: Int64(swap.xsu_used)
        )
    }
}
