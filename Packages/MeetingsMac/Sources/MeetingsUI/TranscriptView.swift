import Domain
import Persistence
import Pipeline
import SwiftUI

/// The state of the transcription, « Réessayer » and « Retranscrire ».
struct TranscriptHeader: View {
    let status: TranscriptStatus?
    let meetingID: UUID
    let queue: TranscriptionQueue?
    let canRetranscribe: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            row
            // On its own line, so that a long sentence wraps instead of widening the window.
            if let text = TranscriptModel.text(status) {
                Text(text)
                    .foregroundStyle(color)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var row: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("Transcription").font(.headline)
            if case .running(let progress)? = status {
                ProgressView(value: progress).frame(maxWidth: 120).controlSize(.small)
            }
            Spacer(minLength: 8)
            if case .failed? = status {
                Button("Réessayer") { Task { await queue?.retry(meetingID: meetingID) } }
            }
            Menu("Retranscrire") {
                Button("En français") { retranscribe("fr") }
                Button("En anglais") { retranscribe("en") }
                Button("Langue détectée par le moteur") { retranscribe(nil) }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(queue == nil || !canRetranscribe)
        }
    }

    private var color: Color {
        switch status {
        case .failed?, .done(doubtful: true)?: .orange
        default: .secondary
        }
    }

    private func retranscribe(_ language: String?) {
        Task { await queue?.retranscribe(meetingID: meetingID, language: language) }
    }
}

/// The dialogue, following the player: the line being heard is highlighted, a time moves the player.
struct DialogueList: View {
    let lines: [UtteranceRow]
    @ObservedObject var player: MeetingPlayer
    let scroll: ScrollViewProxy

    var body: some View {
        let current = TranscriptModel.currentLine(lines, at: player.currentSeconds)
        DialogueRows(lines: lines, current: current) { seconds in
            player.seek(to: seconds)
            if !player.isPlaying { player.play() }
        }
        .onChange(of: current) { _, line in
            guard player.isPlaying, let line else { return }
            withAnimation { scroll.scrollTo(line, anchor: .center) }
        }
    }
}

struct DialogueRows: View {
    let lines: [UtteranceRow]
    let current: Int?
    /// `nil` when there is no audio to play any more.
    let seek: ((Double) -> Void)?

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 6) {
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Group {
                        if let seek {
                            Button(TranscriptModel.timestamp(line.startMs)) { seek(Double(line.startMs) / 1_000) }
                                .buttonStyle(.link)
                        } else {
                            Text(TranscriptModel.timestamp(line.startMs)).foregroundStyle(.secondary)
                        }
                    }
                    .font(.caption.monospacedDigit())
                    .frame(width: 56, alignment: .trailing)
                    Text(line.speaker.label)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(line.speaker == .moi ? Color.accentColor : Color.primary)
                        .frame(width: 78, alignment: .leading)
                    Text(line.text)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if line.doubtful {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .help("À vérifier : le moteur a peut-être inventé ce passage.")
                    }
                }
                .padding(.vertical, 3)
                .padding(.horizontal, 6)
                .background(index == current ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 6))
                .id(index)
            }
        }
    }
}
