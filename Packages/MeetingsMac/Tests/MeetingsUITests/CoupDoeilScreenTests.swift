import AppKit
import Foundation
import Pipeline
import PolhubDesign
import SwiftUI
import Testing
@testable import MeetingsUI

/// The menu bar's logo in each state, and « Coup d'œil », with made-up meetings (15/11): `POLHUB_SNAPSHOTS=<dossier>
/// swift test --filter CoupDoeilScreenTests` (add `POLHUB_LIVE=1` for the glass). Nothing of them is kept in the
/// repository.
@MainActor @Suite(.enabled(if: ProcessInfo.processInfo.environment["POLHUB_SNAPSHOTS"] != nil))
struct CoupDoeilScreenTests {
    private var output: URL {
        get throws {
            let folder = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["POLHUB_SNAPSHOTS"]), isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            return folder
        }
    }

    @Test func theLogoInEachState() async throws {
        let output = try output
        let now = Date()
        let states: [(String, MenuBarLabel)] = [
            ("Repos", MenuBarLabel.make(status: .idle, now: now)),
            ("Avant un Meet", MenuBarLabel.make(status: .idle, now: now, minutesToMeet: 8)),
            ("Menacé", MenuBarLabel.make(status: .idle, now: now, danger: true)),
            ("Suspendue", MenuBarLabel.make(status: .paused(until: now), now: now)),
            ("Suspendue, menacé", MenuBarLabel.make(status: .paused(until: now), now: now, danger: true)),
            ("Détectée", MenuBarLabel.make(status: .prompting(title: "Point"), now: now, promptDeadline: now.addingTimeInterval(6.5))),
            ("Enregistre", MenuBarLabel.make(status: .recording(title: "Point", since: now.addingTimeInterval(-767)), now: now)),
            ("Fin ?", MenuBarLabel.make(status: .presumedEnded(title: "Point"), now: now)),
        ]
        for dark in [false, true] {
            try await LiveWindow.capture(LogoSheet(states: states).environment(\.colorScheme, dark ? .dark : .light),
                                         to: output.appending(path: "logo-\(dark ? "sombre" : "clair").png"),
                                         size: NSSize(width: 760, height: 420), dark: dark)
        }
    }

    @Test func theStandInPanel() async throws {
        let output = try output
        let now = Date()
        func context(_ configure: (AppModel) -> Void, development: Bool = false) -> CoupDoeilContext {
            let model = AppModel(isDevelopment: development)
            model.detectionOn = !development
            model.tick(now: now)
            configure(model)
            return CoupDoeilContext(app: model, router: WindowRouter())
        }
        let cases: [(String, CoupDoeilContext)] = [
            ("repos", context { _ in }),
            ("detectee", context {
                $0.status = .prompting(title: "Revue de maquettes")
                $0.setPromptDeadline(now.addingTimeInterval(7))
                $0.setMeetCode("abc-defg-hij")
            }),
            ("enregistre", context {
                $0.status = .recording(title: "Revue de maquettes", since: now.addingTimeInterval(-767))
                $0.setMeetCode("abc-defg-hij")
                $0.pausedUntil = now.addingTimeInterval(1_800)
            }),
            ("developpement", context({ _ in }, development: true)),
        ]
        for (name, context) in cases {
            for dark in [false, true] {
                try await LiveWindow.capture(MenuBarPanel(context: context).background(Color(nsColor: .windowBackgroundColor)),
                                             to: output.appending(path: "panneau-\(name)-\(dark ? "sombre" : "clair").png"),
                                             size: NSSize(width: MenuBarPanel.width, height: 440), dark: dark)
            }
        }
    }

    @Test func theGeneralSettings() async throws {
        let output = try output
        try await LiveWindow.capture(GeneralSettingsPane(startup: nil).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top),
                                     to: output.appending(path: "reglages-general.png"), size: NSSize(width: 700, height: 420))
    }
}

/// Each state at its real size on a strip like the menu bar's, then six times larger.
private struct LogoSheet: View {
    let states: [(String, MenuBarLabel)]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            HStack(spacing: Space.l) {
                ForEach(states.indices, id: \.self) { index in
                    label(states[index].1).fixedSize()
                }
            }
            .padding(.horizontal, Space.m)
            .frame(height: 24)
            .background(Color.primary.opacity(0.06))
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(170), alignment: .leading), count: 4), alignment: .leading, spacing: Space.l) {
                ForEach(states.indices, id: \.self) { index in
                    VStack(alignment: .leading, spacing: Space.xs) {
                        icon(states[index].1)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 108, height: 96)
                            .background(Color.primary.opacity(0.04))
                        Text(states[index].0).font(.meta).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func icon(_ label: MenuBarLabel) -> Image {
        let image = label.image
        return image.isTemplate ? Image(nsImage: image).renderingMode(.template) : Image(nsImage: image)
    }

    private func label(_ label: MenuBarLabel) -> some View {
        HStack(spacing: 4) {
            icon(label)
            if let text = label.text { Text(text).font(.system(size: 13)).monospacedDigit() }
        }
    }
}
