import AppKit
import SwiftUI
import Testing
@testable import MeetingsUI

/// « Sonde de Colin » as the Diagnostic page shows it, in each of its states: only with `HUB_SNAPSHOTS=<folder>`.
/// The section alone: the page's own checks test the microphone, which a capture must not do.
@MainActor @Suite(.enabled(if: ProcessInfo.processInfo.environment["HUB_SNAPSHOTS"] != nil))
struct ColinProbeScreenTests {
    /// Holds what the app's runner would call when the probe ends.
    @MainActor final class Ending {
        var finish: (@MainActor (String?) -> Void)?
    }

    func control(quiet: Bool = true, verdict: Bool? = true, reason: String? = nil) -> (control: ColinProbeControl, ending: Ending) {
        let name = "colin-sonde-capture-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let ending = Ending()
        let control = ColinProbeControl(defaults: defaults, home: URL(fileURLWithPath: "/Users/essai", isDirectory: true), isQuiet: { quiet },
                                        start: { _, onFinish in
                                            ending.finish = onFinish
                                            return nil
                                        }, stop: {}, report: { verdict.map { (ok: $0, reason: reason) } },
                                        folderExists: { _ in true }, isAccount: { _ in true }, uptime: { 86_400 }, sinceWake: { nil })
        return (control, ending)
    }

    @Test func theProbeSection() async throws {
        let folder = URL(fileURLWithPath: ProcessInfo.processInfo.environment["HUB_SNAPSHOTS"]!, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let idle = control().control
        let chosen = control().control
        chosen.choose("/Users/essai/comptes/second")
        let running = control().control
        await running.launch()
        let refused = control(quiet: false).control
        await refused.launch()
        let done = control()
        await done.control.launch()
        done.ending.finish?(nil)
        let limited = control(verdict: false, reason: "limite-atteinte")
        await limited.control.launch()
        limited.ending.finish?(nil)
        let stopped = control(verdict: nil)
        await stopped.control.launch()
        stopped.control.stopByHand()
        stopped.ending.finish?(nil)

        let view = VStack(alignment: .leading, spacing: 20) {
            ColinProbeSection(control: idle)
            Divider()
            ColinProbeSection(control: chosen)
            Divider()
            ColinProbeSection(control: running)
            Divider()
            ColinProbeSection(control: refused)
            Divider()
            ColinProbeSection(control: done.control)
            Divider()
            ColinProbeSection(control: limited.control)
            Divider()
            ColinProbeSection(control: stopped.control)
        }
        .padding(24)
        .frame(width: 720, height: 1_320, alignment: .topLeading)
        // The page gives the section its background; alone, it needs one to be read in the dark.
        .background(Color(nsColor: .windowBackgroundColor))

        for dark in [false, true] {
            try await LiveWindow.capture(view, to: folder.appending(path: dark ? "sonde-colin-sombre.png" : "sonde-colin.png"),
                                         size: NSSize(width: 720, height: 1_320), dark: dark)
        }
    }
}
