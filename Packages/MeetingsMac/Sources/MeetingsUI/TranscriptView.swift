import Domain
import Persistence
import Pipeline
import PolhubDesign
import SwiftUI

/// The state of the transcription and « Réessayer »; « Retranscrire » is in the « … » menu (14/11).
struct TranscriptHeader: View {
    let status: TranscriptStatus?
    let meetingID: UUID
    let queue: TranscriptionQueue?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Label("Transcription", systemImage: "text.quote").font(.headline)
                if case .running(let progress)? = status {
                    ProgressView(value: progress).frame(maxWidth: 120).controlSize(.small)
                }
                Spacer(minLength: 8)
                if case .failed? = status {
                    Button("Réessayer") { Task { await queue?.retry(meetingID: meetingID) } }.buttonStyle(.glass).controlSize(.small)
                }
            }
            // On its own line, so that a long sentence wraps instead of widening the window.
            if let text = TranscriptModel.text(status) {
                Text(text)
                    .foregroundStyle(color)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var color: Color {
        switch status {
        case .failed?, .done(doubtful: true)?: .orange
        default: .secondary
        }
    }
}

/// The dialogue, following the player: the paragraph being heard is highlighted, a time moves the player.
struct DialogueList: View {
    let lines: [UtteranceRow]
    @ObservedObject var player: MeetingPlayer
    let scroll: ScrollViewProxy

    var body: some View {
        let current = TranscriptModel.currentLine(lines, at: player.currentSeconds)
        DialogueParagraphs(lines: lines, current: current) { seconds in
            player.seek(to: seconds)
            if !player.isPlaying { player.play() }
        }
        .onChange(of: TranscriptModel.paragraph(containing: current, in: TranscriptModel.paragraphs(lines))) { _, paragraph in
            guard player.isPlaying, let paragraph else { return }
            withAnimation { scroll.scrollTo("paragraphe-\(paragraph)", anchor: .center) }
        }
    }
}

/// One paragraph per turn of speech: the voice and its time on the left, the words on the right.
struct DialogueParagraphs: View {
    let lines: [UtteranceRow]
    let current: Int?
    /// `nil` when there is no audio to play any more.
    let seek: ((Double) -> Void)?

    var body: some View {
        let paragraphs = TranscriptModel.paragraphs(lines)
        let heard = TranscriptModel.paragraph(containing: current, in: paragraphs)
        LazyVStack(alignment: .leading, spacing: 4) {
            ForEach(Array(paragraphs.enumerated()), id: \.offset) { index, paragraph in
                Group {
                    if paragraph.speaker == .unknown {
                        // An imported transcript: plain paragraphs, no time, no voice (13/11).
                        Text(paragraph.text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
                    } else {
                        HStack(alignment: .firstTextBaseline, spacing: 14) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(paragraph.speaker.label)
                                    .font(.callout.weight(.semibold))
                                    .foregroundStyle(paragraph.speaker == .moi ? Color.accentColor : Color.primary)
                                if let seek {
                                    Button(TranscriptModel.timestamp(paragraph.startMs)) { seek(Double(paragraph.startMs) / 1_000) }
                                        .buttonStyle(.link)
                                        .font(.caption.monospacedDigit())
                                } else {
                                    Text(TranscriptModel.timestamp(paragraph.startMs)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                }
                            }
                            .frame(width: 84, alignment: .leading)
                            Text(paragraph.text)
                                .textSelection(.enabled)
                                .lineSpacing(3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if paragraph.doubtful {
                                Image(systemName: "exclamationmark.triangle")
                                    .foregroundStyle(.orange)
                                    .help("À vérifier : le moteur a peut-être inventé un passage.")
                            }
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 10)
                        .background(index == heard ? Color.accentColor.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
                .id("paragraphe-\(index)")
            }
        }
    }
}
