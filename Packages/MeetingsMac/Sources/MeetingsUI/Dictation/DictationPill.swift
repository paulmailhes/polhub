import AppKit
import HubDesign
import SwiftUI

/// The Dictée's window (20/11). 21/11, after Paul's « je ne vois rien… beaucoup plus expliqué » : it says what is
/// happening at every moment — the microphone that opens, the listening and his words as they come, the final writing
/// and its progress, where the text went, or why nothing happened. It never takes the focus: the text goes to the app
/// that had it.
@MainActor final class DictationPill {
    static let width: CGFloat = 540
    static let height: CGFloat = 220
    /// Paul's words: three lines, the window's width less its margins and a few points, as SwiftUI lays a line a hair
    /// wider than AppKit measures it.
    static let wordsLines = 3
    static let wordsWidth: CGFloat = width - 2 * Space.l - 8
    private let panel: NSPanel
    let service: DictationService

    init(service: DictationService) {
        self.service = service
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: Self.height), styleMask: [.nonactivatingPanel, .borderless],
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

    /// Centered at the bottom of the screen the pointer is on, growing upwards with the text; or at its top, under the
    /// menu bar and the notch, growing downwards (Réglages › Dictée › « Place »).
    func show() {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            let y = service.windowAtTop ? frame.maxY - panel.frame.height - 8 : frame.minY + 24
            panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2, y: y))
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
        let content = DictationWindowContent(service.windowState)
        let hearing = content.mark == .listening || content.mark == .opening
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(alignment: .center, spacing: Space.s) {
                DictationMark(mark: content.mark)
                Text(Words.typeset(content.title))
                    .font(.headline)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Space.s)
                if content.mark == .listening, let started = service.startedAt {
                    TimelineView(.periodic(from: started, by: 1)) { context in
                        Text(Words.clock(max(0, Int(context.date.timeIntervalSince(started)))))
                            .font(.meta.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            }
            if let words = content.words {
                // While he talks, the end of what he said, the first words going up and fading (21/11); once pasted, the
                // first ones.
                let shown = content.mark == .done ? (text: words, cut: false)
                    : DictationWords.tail(words, width: DictationPill.wordsWidth, lines: DictationPill.wordsLines)
                Text(shown.text)
                    .font(.rowTitle)
                    .lineLimit(DictationPill.wordsLines)
                    .truncationMode(.tail)
                    .foregroundStyle(content.mark == .writing ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .mask {
                        if shown.cut {
                            LinearGradient(stops: [.init(color: .black.opacity(0.2), location: 0), .init(color: .black, location: 0.34)],
                                           startPoint: .top, endPoint: .bottom)
                        } else {
                            Color.black
                        }
                    }
            } else if let placeholder = content.placeholder {
                Text(Words.typeset(placeholder)).font(.rowTitle).foregroundStyle(.tertiary)
            }
            if let progress = content.progress {
                DictationProgressBar(value: progress)
            }
            if hearing || content.hint != nil {
                HStack(spacing: Space.m) {
                    if hearing {
                        VoiceCurve(level: content.mark == .listening ? service.level : 0, quiet: content.mark == .opening)
                            .frame(width: 120, height: 26)
                        Spacer(minLength: Space.s)
                    }
                    if let hint = content.hint {
                        Text(Words.typeset(hint)).font(.meta).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.85)
                    }
                    if !hearing { Spacer(minLength: 0) }
                }
            }
        }
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.m)
        .frame(width: DictationPill.width)
        .glassEffect(.regular, in: .rect(cornerRadius: Radius.card))
        .animation(.easeOut(duration: 0.18), value: content)
        .frame(width: DictationPill.width, height: DictationPill.height, alignment: service.windowAtTop ? .top : .bottom)
    }
}

/// The final writing's progress. Drawn here: this window never has the focus, and the system's bar is then grey.
struct DictationProgressBar: View {
    let value: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(Color(hex: Palette.indigo)).frame(width: max(6, proxy.size.width * min(1, max(0, value))))
            }
        }
        .frame(height: 6)
        .animation(.linear(duration: 0.15), value: value)
        .accessibilityLabel("Relecture")
        .accessibilityValue(Words.percent(value))
    }
}

/// The sign before the window's title: what is happening, at a glance.
struct DictationMark: View {
    let mark: DictationWindowContent.Mark

    var body: some View {
        switch mark {
        case .opening, .writing:
            ProgressView().controlSize(.small)
        case .listening:
            Image(systemName: "mic.fill").foregroundStyle(Color(hex: Palette.indigo))
        case .done:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Tint.done)
        case .notice:
            Image(systemName: "info.circle").foregroundStyle(.secondary)
        case .problem:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Tint.attention)
        }
    }
}

/// The voice's curve: bars that breathe with the level, highest in the middle, moving even in a short silence; flat and
/// grey while the microphone opens.
struct VoiceCurve: View {
    let level: Double
    var quiet = false
    static let bars = 21

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: quiet)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<Self.bars, id: \.self) { index in
                    Capsule()
                        .fill(quiet ? AnyShapeStyle(.tertiary) : AnyShapeStyle(Color(hex: Palette.indigo)))
                        .frame(width: 3, height: quiet ? 3 : height(index, time: time))
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

/// Paul's words as they come, in the Dictée's window (21/11, Paul: « on dirait qu'il veut garder le début de la phrase…
/// il met des trois petits points au milieu… faut que ça continue de défiler le paragraphe et que ça coupe le début ») :
/// a text cut by SwiftUI over several lines kept its start and its end. The window shows the end of what was said that
/// holds in its lines, in whole words; the first ones go up and fade.
enum DictationWords {
    /// The end of `text` that holds in `lines` lines `width` points wide, starting with a whole word; `cut` when the first
    /// words were left out.
    static func tail(_ text: String, width: CGFloat, lines: Int,
                     font: NSFont = .systemFont(ofSize: TextSize.rowTitle)) -> (text: String, cut: Bool) {
        let limit = height(lines: lines, font: font)
        guard height(of: text, width: width, font: font) > limit else { return (text, false) }
        let words = text.split(separator: " ", omittingEmptySubsequences: true)
        guard words.count > 1 else { return (text, false) }
        // The fewest first words to leave out.
        var low = 1, high = words.count - 1
        while low < high {
            let middle = (low + high) / 2
            if height(of: words[middle...].joined(separator: " "), width: width, font: font) <= limit { high = middle } else { low = middle + 1 }
        }
        return (words[low...].joined(separator: " "), true)
    }

    /// How tall a text is, laid out `width` points wide.
    static func height(of text: String, width: CGFloat, font: NSFont) -> CGFloat {
        (text as NSString).boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                                        options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font]).height.rounded(.up)
    }

    /// How tall `lines` lines are.
    static func height(lines: Int, font: NSFont) -> CGFloat {
        height(of: Array(repeating: "Ag", count: max(1, lines)).joined(separator: "\n"), width: 10_000, font: font)
    }
}
