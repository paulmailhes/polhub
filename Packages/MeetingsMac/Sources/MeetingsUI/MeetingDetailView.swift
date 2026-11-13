import AppKit
import Domain
import GRDB
import Persistence
import Pipeline
import Recording
import ProjectsUI
import SwiftUI

/// One meeting: when, how long, how the recording went, and the player.
struct MeetingDetailView: View {
    let row: MeetingRow
    let store: MeetingStore
    let paths: AppPaths
    let transcripts: TranscriptStore
    /// The projects a meeting can be filed in.
    var projects: [ProjectRow] = []
    let queue: TranscriptionQueue?
    let job: JobRow?
    let meetingActive: Bool
    @ObservedObject var router: WindowRouter

    @State private var player: MeetingPlayer?
    @State private var file: MeetingFile?
    @State private var microphones: [String] = []
    @State private var loadError: String?
    @State private var confirmingDelete = false
    @State private var lines: [UtteranceRow] = []
    @State private var observation: AnyDatabaseCancellable?
    @State private var summary: String?
    @State private var participants: [ContactRow] = []

    private var folder: URL { paths.meetingFolder(row.id) }

    var body: some View {
        ScrollViewReader { scroll in
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(row.title).font(.title2.bold()).fixedSize(horizontal: false, vertical: true)
                    Text(row.startedAt.formatted(date: .complete, time: .shortened)).foregroundStyle(.secondary)
                    Text(MeetingListModel.durationText(row, now: .now)).foregroundStyle(.secondary)
                }

                if !projects.isEmpty {
                    Picker("Projet", selection: Binding(
                        get: { row.projectID },
                        set: { try? ProjectStore(store.database).setProject(meetingID: row.id, projectID: $0) }
                    )) {
                        Text("Aucun").tag(UUID?.none)
                        ForEach(projects.filter { $0.status != .termine || $0.id == row.projectID }
                            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) { project in
                            Text(project.name).tag(Optional(project.id))
                        }
                    }
                    .frame(maxWidth: 320)
                }

                if !participants.isEmpty {
                    HStack(spacing: 6) {
                        Text("Participants :").foregroundStyle(.secondary)
                        ForEach(participants) { contact in
                            Button(contact.name) { router.openContact(contact.id) }.buttonStyle(.link)
                        }
                    }
                }

                if let summary, !summary.isEmpty {
                    GroupBox("Résumé") {
                        MarkdownView(text: summary).frame(maxWidth: .infinity, alignment: .leading).padding(4)
                    }
                }

                if row.source == .imported {
                    Label("Réunion importée d'Obsidian : pas d'audio, transcription sans distinction des voix.", systemImage: "tray.and.arrow.down")
                        .foregroundStyle(.secondary)
                } else if row.status.isUnfinished {
                    Label("Enregistrement en cours. La réunion se réécoute dès qu'elle est terminée.", systemImage: "record.circle")
                        .foregroundStyle(.red)
                } else if let player {
                    PlayerView(player: player)
                } else if let loadError {
                    Label(loadError, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                } else if row.audioPurgedAt != nil {
                    Label("L'audio a été effacé (30 jours après la transcription).", systemImage: "trash")
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView().controlSize(.small)
                }

                if let status = TranscriptModel.status(job, meeting: row, meetingActive: meetingActive) {
                    VStack(alignment: .leading, spacing: 10) {
                        TranscriptHeader(status: status, meetingID: row.id, queue: queue,
                                         canRetranscribe: row.audioPurgedAt == nil && !row.status.isUnfinished)
                        if !lines.isEmpty {
                            if let player {
                                DialogueList(lines: lines, player: player, scroll: scroll)
                            } else {
                                DialogueRows(lines: lines, current: nil, seek: nil)
                            }
                        } else if case .done = status {
                            Text("Personne n'a parlé, ou rien n'a pu être transcrit.").foregroundStyle(.secondary)
                        }
                    }
                }

                if row.source != .imported {
                GroupBox("Enregistrement") {
                    VStack(alignment: .leading, spacing: 6) {
                        if !microphones.isEmpty {
                            LabeledContent("Micro retenu", value: microphones.joined(separator: ", "))
                        }
                        if let health = file?.health {
                            LabeledContent("Coupures", value: health.gapCount == 0 ? "Aucune" : "\(health.gapCount)")
                            LabeledContent("Changements de périphérique", value: "\(health.rebuilds)")
                            if health.selfTestPassed == false {
                                Text("Le son des autres n'a pas été entendu au début.").foregroundStyle(.orange)
                            }
                        }
                        if let reason = row.endReason {
                            LabeledContent("Fin", value: Self.words(reason))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(4)
                }
                }

                HStack {
                    Button("Afficher dans le Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([folder])
                    }
                    Spacer()
                    Button("Supprimer…", role: .destructive) { confirmingDelete = true }
                        .disabled(row.status.isUnfinished)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        }
        .task(id: row.status) {
            summary = try? store.summary(meetingID: row.id)
            participants = (try? ContactStore(store.database).participants(meetingID: row.id)) ?? []
            guard row.source != .imported else { return }
            await load()
        }
        .onAppear {
            observation = transcripts.observeUtterances(meetingID: row.id) { lines = $0 }
        }
        .onChange(of: player == nil) { _, _ in seekIfAsked() }
        .onChange(of: router.seekRequest?.seconds) { _, _ in seekIfAsked() }
        .onDisappear { player?.pause() }
        .confirmationDialog("Supprimer « \(row.title) » ?", isPresented: $confirmingDelete) {
            Button("Mettre à la Corbeille", role: .destructive) { delete() }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("L'audio va à la Corbeille, d'où tu peux encore le récupérer.")
        }
    }

    private func load() async {
        guard !row.status.isUnfinished, row.audioPurgedAt == nil, player == nil else { return }
        let fileURL = folder.appending(path: "meeting.json")
        do {
            let meeting = try MeetingFile.decoder.decode(MeetingFile.self, from: Data(contentsOf: fileURL))
            let timeline = try MeetingTimeline.read(folder.appending(path: "timeline.jsonl"))
            file = meeting
            let chosen = Set(meeting.moiSpans.map(\.runID))
            microphones = Array(Set(timeline.runs.filter { chosen.contains($0.id) }.compactMap(\.device)))
                .map(DeviceNames.name(forUID:))
                .sorted()
            let pieces = PlaybackPlan.pieces(
                folder: folder, timeline: timeline, moiSpans: meeting.moiSpans,
                originNanos: meeting.originNanos, segmentSeconds: MeetingRecorder.segmentSeconds,
                untilNanos: meeting.endNanos
            )
            guard !pieces.isEmpty else {
                loadError = "Aucun son enregistré pour cette réunion."
                return
            }
            player = try await MeetingPlayer(pieces: pieces)
        } catch {
            loadError = "La réunion ne se lit pas : \(error.localizedDescription)"
        }
    }

    /// The search asked for a moment of this meeting: play from there.
    private func seekIfAsked() {
        guard let request = router.seekRequest, request.meetingID == row.id, let player else { return }
        router.seekRequest = nil
        player.seek(to: max(0, request.seconds - 1))
        player.play()
    }

    private func delete() {
        player?.pause()
        let queue = queue, id = row.id
        Task { await queue?.forget(meetingID: id) }
        try? store.softDelete(id: row.id, at: .now)
        NSWorkspace.shared.recycle([folder])
    }

    static func words(_ reason: EndReason) -> String {
        switch reason {
        case .tabClosed: "onglet fermé"
        case .safetyElapsed: "micro rendu, fin confirmée 10 min après"
        case .diaQuit: "Dia quitté"
        case .userStopped: "arrêtée à la main"
        case .interrupted: "interrompue (l'app s'était arrêtée)"
        case .nextMeeting: "une autre réunion a commencé"
        }
    }
}

struct PlayerView: View {
    @ObservedObject var player: MeetingPlayer
    @State private var scrubbing: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Button {
                    player.isPlaying ? player.pause() : player.play()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 32))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.space, modifiers: [])

                Slider(
                    value: Binding(get: { scrubbing ?? player.currentSeconds }, set: { scrubbing = $0 }),
                    in: 0...max(player.durationSeconds, 1)
                ) { editing in
                    if !editing, let target = scrubbing {
                        player.seek(to: target)
                        scrubbing = nil
                    }
                }
                Text("\(DurationText.clock(Int(scrubbing ?? player.currentSeconds))) / \(DurationText.clock(Int(player.durationSeconds)))")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 18) {
                Toggle("Moi", isOn: $player.moiEnabled)
                Toggle("Les autres", isOn: $player.autresEnabled)
            }
            .toggleStyle(.checkbox)
        }
        .padding(14)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }
}
