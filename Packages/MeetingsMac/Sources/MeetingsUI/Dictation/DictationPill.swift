import AppKit
import HubDesign
import SwiftUI

/// The Dictée's window at the bottom of the screen (20/11; redrawn the same evening after Paul's try, « plus de place,
/// plus logique, une courbe »): the words as they come on up to three lines, then a bar with the voice's curve, the
/// clock and what to press. It never takes the focus: the text goes to the app that had it.
@MainActor final class DictationPill {
    static let width: CGFloat = 520
    private let panel: NSPanel

    init(service: DictationService) {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 180), styleMask: [.nonactivatingPanel, .borderless],
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

    /// Centered at the bottom of the screen the pointer is on; the window grows upwards with the text.
    func show() {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2, y: frame.minY + 24))
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
        VStack(alignment: .leading, spacing: Space.s) {
            if let words = words {
                Text(words)
                    .font(.rowTitle)
                    .lineLimit(3)
                    .truncationMode(.head)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
            HStack(spacing: Space.m) {
                state
                Spacer(minLength: Space.s)
                Text(hint).font(.meta).foregroundStyle(.secondary)
            }
            .frame(height: 28)
        }
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.m)
        .frame(width: DictationPill.width)
        .glassEffect(.regular, in: .rect(cornerRadius: Radius.card))
        .animation(.easeOut(duration: 0.18), value: words)
        .frame(width: DictationPill.width, height: 180, alignment: .bottom)
    }

    /// The words said so far, or what the window says once.
    private var words: String? {
        if let notice = service.notice { return notice }
        guard !service.partial.isEmpty else { return nil }
        return service.partial
    }

    @ViewBuilder private var state: some View {
        switch service.phase {
        case .listening:
            HStack(spacing: Space.s) {
                VoiceCurve(level: service.level).frame(width: 120, height: 26)
                if let started = service.startedAt {
                    TimelineView(.periodic(from: started, by: 1)) { context in
                        Text(Words.clock(Int(context.date.timeIntervalSince(started)))).font(.meta.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            }
        case .writing:
            HStack(spacing: Space.s) {
                ProgressView().controlSize(.small)
                Text("J'écris…").font(.meta).foregroundStyle(.secondary)
            }
        case .loading:
            HStack(spacing: Space.s) {
                ProgressView().controlSize(.small)
                Text("La Dictée se prépare…").font(.meta).foregroundStyle(.secondary)
            }
        case .failed(let reason):
            Text(Words.typeset(reason)).font(.meta).foregroundStyle(.secondary).lineLimit(1)
        case .ready:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Tint.done)
        }
    }

    private var hint: String {
        switch service.phase {
        case .listening:
            switch DictationService.mode {
            case .toggle, .hybrid: "\(DictationKey.current.title) pour finir · Échap pour annuler"
            case .hold: "Relâche pour finir · Échap pour annuler"
            }
        case .writing: "Le texte arrive là où tu écrivais"
        default: ""
        }
    }

}

/// The voice's curve: bars that breathe with the level, highest in the middle, moving even in a short silence.
struct VoiceCurve: View {
    let level: Double
    static let bars = 21

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<Self.bars, id: \.self) { index in
                    Capsule()
                        .fill(Color(hex: Palette.indigo))
                        .frame(width: 3, height: height(index, time: time))
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    private func height(_ index: Int, time: TimeInterval) -> CGFloat {
        let center = abs(Double(index) - Double(Self.bars - 1) / 2) / (Double(Self.bars - 1) / 2)
        let envelope = 1 - center * 0.65
        let wave = (sin(time * 7 + Double(index) * 0.55) + 1) / 2
        let voiced = min(1, level * 1.4)
        return CGFloat(3 + 23 * envelope * (0.12 + voiced * (0.45 + 0.55 * wave)))
    }
}
