import AppKit
import HubDesign
import SwiftUI
import Testing

/// A probe for lot 3 (19/11), kept out of the app: how the system's own controls and glass buttons take a tint posed
/// at the root, in a window that says it is in front (never activated: Paul works meanwhile).
@MainActor @Suite(.enabled(if: ProcessInfo.processInfo.environment["HUB_SONDE_TEINTE"] != nil))
struct ControlsTintProbeTests {
    final class FrontWindow: NSWindow {
        override var isKeyWindow: Bool { true }
        override var isMainWindow: Bool { true }
    }

    @Test func theTints() async throws {
        let output = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["HUB_SONDE_TEINTE"]), isDirectory: true)
        let graphite = Tint.Pair("#1D1D1F", "#8E8E93").color
        for dark in [false, true] {
            let view = HStack(alignment: .top, spacing: 28) {
                Column(title: "Sans teinte", tint: nil)
                Column(title: "Encre", tint: Tint.accent)
                Column(title: "Encre / graphite", tint: graphite)
            }
            .padding(24)
            .environment(\.controlActiveState, .key)
            .background(Color(nsColor: .windowBackgroundColor))
            let window = FrontWindow(contentViewController: NSHostingController(rootView: view))
            window.styleMask = [.titled, .fullSizeContentView]
            window.setContentSize(NSSize(width: 1_180, height: 420))
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) - 1)
            window.setFrameTopLeftPoint(NSPoint(x: 40, y: (NSScreen.main?.visibleFrame.maxY ?? 900) - 20))
            window.orderBack(nil)
            try await Task.sleep(for: .milliseconds(1_500))
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = ["-l", "\(window.windowNumber)", "-o", "-x", output.appending(path: "teintes\(dark ? "-sombre" : "").png").path]
            try process.run()
            process.waitUntilExit()
            window.close()
        }
    }

    struct Column: View {
        let title: String
        let tint: Color?
        @State private var on = true
        @State private var off = false
        @State private var ticked = true
        @State private var choice = 1

        var body: some View {
            let content = VStack(alignment: .leading, spacing: 14) {
                Text(title).font(.headline)
                Toggle("Activé", isOn: $on).toggleStyle(.switch)
                Toggle("Coché", isOn: $ticked).toggleStyle(.checkbox)
                Picker("", selection: $choice) { Text("Kanban").tag(0); Text("Liste").tag(1) }.pickerStyle(.segmented).labelsHidden().frame(width: 160)
                HStack {
                    Button("Rejoindre") {}.buttonStyle(.glassProminent)
                    Button("Détails") {}.buttonStyle(.glass)
                    Button("Neutre") {}.buttonStyle(.glass).tint(nil)
                    Button { } label: { Image(systemName: "xmark").font(.body.weight(.semibold)).frame(width: 28, height: 28) }
                        .buttonStyle(.glass).buttonBorderShape(.circle).tint(nil)
                }
                HStack {
                    Button("Répondre") {}.buttonStyle(.primary)
                    Button("Transférer") {}.buttonStyle(.secondary)
                }
                List(selection: .constant(Optional(1))) { Text("Choisie").tag(1); Text("Autre").tag(2) }.frame(width: 160, height: 60)
            }
            if let tint { content.tint(tint) } else { content }
        }
    }
}

/// The system's buttons' heights, size by size, to match hub's own roles to them (lot 3, 19/11).
@MainActor @Suite(.enabled(if: ProcessInfo.processInfo.environment["HUB_SONDE_TEINTE"] != nil))
struct ButtonHeightsProbeTests {
    @Test func theHeights() {
        _ = NSApplication.shared
        func height(_ view: some View) -> CGFloat { NSHostingController(rootView: view).view.fittingSize.height }
        var lines: [String] = []
        for (name, size) in [("mini", ControlSize.mini), ("small", .small), ("regular", .regular), ("large", .large)] {
            let glass = height(Button("Rejoindre") {}.buttonStyle(.glassProminent).controlSize(size))
            let plain = height(Button("Rejoindre") {}.buttonStyle(.glass).controlSize(size))
            let bordered = height(Button("Rejoindre") {}.buttonStyle(.bordered).controlSize(size))
            let primary = height(Button("Rejoindre") {}.buttonStyle(.primary).controlSize(size))
            lines.append("\(name): glassProminent \(glass), glass \(plain), bordered \(bordered), primary \(primary)")
        }
        let subtle = height(Button("Rejoindre") {}.buttonStyle(.subtle))
        lines.append("subtle: \(subtle)")
        print(lines.joined(separator: "\n"))
    }
}
