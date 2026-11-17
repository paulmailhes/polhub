import AppKit
import SwiftUI
import Testing
@testable import MeetingsUI

/// « Sonde de Colin » as the Diagnostic page shows it, in each of its states: only with `POLHUB_SNAPSHOTS=<folder>`.
/// The section alone: the page's own checks test the microphone, which a capture must not do.
@MainActor @Suite(.enabled(if: ProcessInfo.processInfo.environment["POLHUB_SNAPSHOTS"] != nil))
struct ColinProbeScreenTests {
    func control(quiet: Bool = true, verdict: Bool? = true) -> ColinProbeControl {
        let name = "colin-sonde-capture-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return ColinProbeControl(defaults: defaults, isQuiet: { quiet }, start: { _, _ in true }, stop: {}, report: { verdict.map { (ok: $0, reason: nil) } },
                                 folderExists: { _ in true }, isAccount: { _ in true })
    }

    @Test func theProbeSection() async throws {
        let folder = URL(fileURLWithPath: ProcessInfo.processInfo.environment["POLHUB_SNAPSHOTS"]!, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let idle = control()
        let chosen = control()
        chosen.choose("/Users/essai/comptes/second")
        let running = control()
        await running.launch()
        let refused = control(quiet: false)
        await refused.launch()

        let view = VStack(alignment: .leading, spacing: 24) {
            ColinProbeSection(control: idle)
            Divider()
            ColinProbeSection(control: chosen)
            Divider()
            ColinProbeSection(control: running)
            Divider()
            ColinProbeSection(control: refused)
        }
        .padding(24)
        .frame(maxWidth: 720, maxHeight: .infinity, alignment: .topLeading)

        for dark in [false, true] {
            try await LiveWindow.capture(view, to: folder.appending(path: dark ? "sonde-colin-sombre.png" : "sonde-colin.png"),
                                         size: NSSize(width: 760, height: 620), dark: dark)
        }
    }
}
