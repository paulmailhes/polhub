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
    /// Computed once per change of the dialogue, not at each tick of the player (15/11).
    let paragraphs: [TranscriptModel.Paragraph]
    @ObservedObject var player: MeetingPlayer
    let scroll: ScrollViewProxy

    var body: some View {
        let heard = TranscriptModel.paragraph(containing: TranscriptModel.currentLine(lines, at: player.currentSeconds), in: paragraphs)
        DialogueParagraphs(paragraphs: paragraphs, heard: heard) { seconds in
            player.seek(to: seconds)
            if !player.isPlaying { player.play() }
        }
        .onChange(of: heard) { _, paragraph in
            guard player.isPlaying, let paragraph else { return }
            withAnimation(Motion.standard) { scroll.scrollTo("paragraphe-\(paragraph)", anchor: .center) }
        }
    }
}

/// One paragraph per turn of speech: the voice and its time on the left, the words on the right.
struct DialogueParagraphs: View {
    let paragraphs: [TranscriptModel.Paragraph]
    /// The paragraph being heard.
    let heard: Int?
    /// `nil` when there is no audio to play any more.
    let seek: ((Double) -> Void)?

    init(paragraphs: [TranscriptModel.Paragraph], heard: Int? = nil, seek: ((Double) -> Void)?) {
        self.paragraphs = paragraphs
        self.heard = heard
        self.seek = seek
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: Space.xs) {
            ForEach(Array(paragraphs.enumerated()), id: \.offset) { index, paragraph in
                Group {
                    if paragraph.speaker == .unknown {
                        // An imported transcript: plain paragraphs, no time, no voice (13/11).
                        Text(paragraph.text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, Space.xs)
                    } else {
                        DialogueParagraph(paragraph: paragraph, heard: index == heard, seek: seek)
                    }
                }
                .id("paragraphe-\(index)")
            }
        }
    }
}

/// A turn of speech: highlighted under the pointer, and while it is heard; its time plays it from there, a play
/// glyph shows beside it under the pointer (15/11). The text stays selectable: no click on the whole paragraph.
struct DialogueParagraph: View {
    let paragraph: TranscriptModel.Paragraph
    let heard: Bool
    let seek: ((Double) -> Void)?
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(paragraph.speaker.label)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(paragraph.speaker == .moi ? Color.accentColor : Color.primary)
                if let seek {
                    Button { seek(Double(paragraph.startMs) / 1_000) } label: {
                        HStack(spacing: 3) {
                            // Always laid out: the hover only shows it.
                            Image(systemName: "play.fill").font(.system(size: 8, weight: .bold)).opacity(hovering || heard ? 1 : 0)
                            Text(TranscriptModel.timestamp(paragraph.startMs)).font(.tag.monospacedDigit())
                        }
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                    }
                    .buttonStyle(.hover(.capsule))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, -5)
                    .help("Écouter à partir d'ici")
                } else {
                    Text(TranscriptModel.timestamp(paragraph.startMs)).font(.tag.monospacedDigit()).foregroundStyle(.secondary)
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
        .padding(.vertical, Space.s)
        .padding(.horizontal, 10)
        .hoverRow(selected: heard)
        .onHover { hovering = $0 }
        .animation(Motion.quick, value: hovering)
    }
}
