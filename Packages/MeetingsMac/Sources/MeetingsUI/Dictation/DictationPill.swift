import AppKit
import HubDesign
import SwiftUI

/// The pill at the bottom of the screen while Paul talks (20/11): his voice's level and his words as they come. It never
/// takes the focus: the text goes to the app that had it.
@MainActor final class DictationPill {
    private let panel: NSPanel

    init(service: DictationService) {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 64), styleMask: [.nonactivatingPanel, .borderless],
                        backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = NSHostingView(rootView: DictationPillView(service: service))
    }

    /// Centered at the bottom of the screen the pointer is on.
    func show() {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2, y: frame.minY + 40))
        }
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }
}

struct DictationPillView: View {
    @ObservedObject var service: DictationService

    var body: some View {
        HStack(spacing: Space.m) {
            Waveform(level: service.phase == .listening ? service.level : 0)
                .frame(width: 44, height: 22)
            Text(line)
                .font(.body)
                .lineLimit(1)
                .truncationMode(.head)
                .foregroundStyle(service.partial.isEmpty && service.notice == nil ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Space.l)
        .frame(width: 420, height: 48)
        .glassEffect(.regular, in: .capsule)
        .frame(width: 420, height: 64)
    }

    private var line: String {
        if let notice = service.notice { return notice }
        switch service.phase {
        case .listening: return service.partial.isEmpty ? "Je t'écoute…" : service.partial
        case .writing: return service.partial.isEmpty ? "J'écris…" : service.partial
        case .loading: return "La Dictée se prépare…"
        case .failed(let reason): return reason
        case .ready: return ""
        }
    }
}

/// Five bars that follow the voice.
struct Waveform: View {
    let level: Double

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<5, id: \.self) { index in
                Capsule()
                    .fill(Color(hex: Palette.indigo))
                    .frame(width: 4, height: 4 + 18 * CGFloat(level) * [0.5, 0.8, 1, 0.8, 0.5][index])
            }
        }
        .animation(.easeOut(duration: 0.12), value: level)
    }
}
