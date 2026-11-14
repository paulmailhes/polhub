import AppKit
import Domain
import GRDB
import Persistence
import Pipeline
import Recording
import ProjectsUI
import Summarization
import SwiftUI

/// One meeting: who and when, its summary and actions, the dialogue, and the player floating at the bottom
/// (14/11). The rare gestures live in the « … » menu of the toolbar.
struct MeetingDetailView: View {
    let row: MeetingRow
    let store: MeetingStore
    let paths: AppPaths
    let transcripts: TranscriptStore
    /// The projects a meeting can be filed in.
    var projects: [ProjectRow] = []
    let queue: TranscriptionQueue?
    var summaries: SummaryQueue?
    var summaryUnavailable: String?
    let job: JobRow?
    let meetingActive: Bool
    @ObservedObject var router: WindowRouter

    @State private var player: MeetingPlayer?
    @State private var file: MeetingFile?
    @State private var microphones: [String] = []
    @State private var loadError: String?
    @State private var confirmingDelete = false
    @State private var showingDetails = false
    @State private var lines: [UtteranceRow] = []
    @State private var observations: [AnyDatabaseCancellable] = []
    @State private var summary: String?
    @State private var summaryJob: SummaryJobRow?
    @State private var actions: [ActionRow] = []
    @State private var participants: [ContactRow] = []

    private var folder: URL { paths.meetingFolder(row.id) }
    private var project: ProjectRow? { row.projectID.flatMap { id in projects.first { $0.id == id } } }

    var body: some View {
        ScrollViewReader { scroll in
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    summaryCard
                    transcript(scroll)
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 24)
                .frame(maxWidth: 860, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .safeAreaInset(edge: .bottom) { playerBar }
        .toolbar { toolbar }
        .task(id: row.status) {
            participants = (try? ContactStore(store.database).participants(meetingID: row.id)) ?? []
            reloadSummary()
            guard row.source != .imported else { return }
            await load()
        }
        .onAppear {
            observations = [
                transcripts.observeUtterances(meetingID: row.id) { lines = $0 },
                SummaryStore(store.database).observeJob(meetingID: row.id) { job in
                    summaryJob = job
                    reloadSummary()
                },
            ]
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

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(row.title).font(.largeTitle.bold()).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Text(row.startedAt.formatted(.dateTime.weekday(.wide).day().month(.wide).hour().minute().locale(Locale(identifier: "fr_FR"))))
                Text("·")
                Text(MeetingListModel.durationText(row, now: .now))
                if row.status.isUnfinished {
                    Badge(text: "En cours", color: .red)
                }
            }
            .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                if !projects.isEmpty {
                    Menu {
                        Button("Aucun") { file(nil) }
                        Divider()
                        ForEach(projects.filter { $0.status != .termine || $0.id == row.projectID }
                            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) { project in
                            Button(project.name) { file(project.id) }
                        }
                    } label: {
                        Label(project?.name ?? "Ranger dans un projet", systemImage: "square.grid.3x2")
                    }
                    .menuStyle(.button)
                    .buttonStyle(.glass)
                    .fixedSize()
                }
                ForEach(participants.prefix(6)) { contact in
                    Button { router.openContact(contact.id) } label: {
                        HStack(spacing: 6) {
                            InitialsBadge(text: contact.initials, size: 22)
                            Text(contact.name).lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                    .help(contact.email ?? contact.name)
                }
                if participants.count > 6 {
                    Text("+\(participants.count - 6)").foregroundStyle(.secondary)
                }
            }
        }
    }

    private func file(_ projectID: UUID?) {
        try? ProjectStore(store.database).setProject(meetingID: row.id, projectID: projectID)
    }

    // MARK: - Summary

    @ViewBuilder
    private var summaryCard: some View {
        let status = TranscriptModel.summaryText(summaryJob, hasSummary: summary?.isEmpty == false, unavailable: summaryUnavailable)
        if summary?.isEmpty == false || status != nil || !actions.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("Compte rendu", systemImage: "sparkles").font(.headline)
                    Spacer()
                    if summaryJob?.state == .running { ProgressView().controlSize(.small) }
                    if summaryJob?.state == .failed {
                        Button("Réessayer") { redoSummary() }.buttonStyle(.glass).controlSize(.small)
                    }
                }
                if let status {
                    Text(status).foregroundStyle(summaryJob?.state == .failed ? Color.orange : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let summary, !summary.isEmpty {
                    MarkdownView(text: summary).frame(maxWidth: .infinity, alignment: .leading)
                }
                if !actions.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Actions").font(.title3.bold())
                        ForEach(actions) { action in actionRow(action) }
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.primary.opacity(0.06)))
        }
    }

    private func actionRow(_ action: ActionRow) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Toggle(isOn: Binding(get: { action.done }, set: { done in
                var changed = action
                changed.done = done
                changed.updatedAt = Date()
                try? ProjectStore(store.database).saveAction(changed)
                reloadSummary()
            })) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(action.text).strikethrough(action.done).foregroundStyle(action.done ? .secondary : .primary)
                    if let owner = action.owner { Text(owner).font(.caption).foregroundStyle(.secondary) }
                }
            }
            .toggleStyle(.checkbox)
            Spacer(minLength: 8)
            if action.projectID != nil {
                Label("Dans le projet", systemImage: "checkmark.circle").font(.caption).foregroundStyle(.secondary).labelStyle(.titleAndIcon)
            } else if let project {
                Button { addToProject(action, project: project) } label: { Label("Ajouter au projet", systemImage: "plus") }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .help("Ajoute cette action à celles de « \(project.name) »")
            }
        }
    }

    private func addToProject(_ action: ActionRow, project: ProjectRow) {
        let projects = ProjectStore(store.database)
        var changed = action
        changed.projectID = project.id
        changed.position = ((try? projects.actions(projectID: project.id).map(\.position).max()) ?? -1) + 1
        changed.updatedAt = Date()
        try? projects.saveAction(changed)
        reloadSummary()
    }

    private func reloadSummary() {
        summary = try? store.summary(meetingID: row.id)
        actions = (try? ProjectStore(store.database).actions(meetingID: row.id)) ?? []
    }

    private func redoSummary() {
        let summaries = summaries, id = row.id
        Task { await summaries?.redo(meetingID: id) }
    }

    // MARK: - Transcript

    @ViewBuilder
    private func transcript(_ scroll: ScrollViewProxy) -> some View {
        if row.source == .imported {
            Label("Réunion importée d'Obsidian : pas d'audio, transcription sans distinction des voix.", systemImage: "tray.and.arrow.down")
                .foregroundStyle(.secondary)
        } else if row.status.isUnfinished {
            Label("Enregistrement en cours. La réunion se réécoute dès qu'elle est terminée.", systemImage: "record.circle")
                .foregroundStyle(.red)
        } else if let loadError {
            Label(loadError, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
        }
        if let status = TranscriptModel.status(job, meeting: row, meetingActive: meetingActive) {
            VStack(alignment: .leading, spacing: 12) {
                TranscriptHeader(status: status, meetingID: row.id, queue: queue)
                if !lines.isEmpty {
                    if let player {
                        DialogueList(lines: lines, player: player, scroll: scroll)
                    } else {
                        DialogueParagraphs(lines: lines, current: nil, seek: nil)
                    }
                } else if case .done = status {
                    Text("Personne n'a parlé, ou rien n'a pu être transcrit.").foregroundStyle(.secondary)
                }
            }
        } else if row.source == .imported, !lines.isEmpty {
            DialogueParagraphs(lines: lines, current: nil, seek: nil)
        }
    }

    // MARK: - Player and toolbar

    @ViewBuilder
    private var playerBar: some View {
        if let player {
            PlayerView(player: player)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .glassEffect(.regular, in: .capsule)
                .padding(.horizontal, 24)
                .padding(.bottom, 14)
                .frame(maxWidth: 760)
        } else if row.audioPurgedAt != nil, row.source != .imported {
            Label("L'audio a été effacé (30 jours après la transcription).", systemImage: "trash")
                .font(.callout).foregroundStyle(.secondary)
                .padding(.horizontal, 16).padding(.vertical, 8)
                .glassEffect(.regular, in: .capsule)
                .padding(.bottom, 14)
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if row.source != .imported {
                Button { showingDetails = true } label: { Label("Enregistrement", systemImage: "info.circle") }
                    .help("Comment s'est passé l'enregistrement")
                    .popover(isPresented: $showingDetails, arrowEdge: .bottom) { recordingDetails }
            }
            Menu {
                Button("Refaire le compte rendu") { redoSummary() }
                    .disabled(summaries == nil || lines.isEmpty || row.source == .imported || summaryJob?.state == .running)
                Button("Copier la transcription") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(TranscriptModel.plainText(lines, title: row.title), forType: .string)
                }
                .disabled(lines.isEmpty)
                Menu("Retranscrire") {
                    Button("En français") { retranscribe("fr") }
                    Button("En anglais") { retranscribe("en") }
                    Button("Langue détectée par le moteur") { retranscribe(nil) }
                }
                .disabled(queue == nil || row.audioPurgedAt != nil || row.status.isUnfinished || row.source == .imported)
                Divider()
                Button("Afficher dans le Finder") { NSWorkspace.shared.activateFileViewerSelecting([folder]) }
                    .disabled(row.source == .imported)
                Button("Supprimer…", role: .destructive) { confirmingDelete = true }
                    .disabled(row.status.isUnfinished)
            } label: {
                Label("Plus", systemImage: "ellipsis")
            }
        }
    }

    private var recordingDetails: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Enregistrement").font(.headline)
            if !microphones.isEmpty { LabeledContent("Micro retenu", value: microphones.joined(separator: ", ")) }
            if let health = file?.health {
                LabeledContent("Coupures", value: health.gapCount == 0 ? "Aucune" : "\(health.gapCount)")
                LabeledContent("Changements de périphérique", value: "\(health.rebuilds)")
                if health.selfTestPassed == false {
                    Text("Le son des autres n'a pas été entendu au début.").foregroundStyle(.orange)
                }
            }
            if let reason = row.endReason { LabeledContent("Fin", value: Self.words(reason)) }
            if microphones.isEmpty, file == nil, row.endReason == nil { Text("Rien à signaler.").foregroundStyle(.secondary) }
        }
        .padding(16)
        .frame(width: 320, alignment: .leading)
    }

    private func retranscribe(_ language: String?) {
        let queue = queue, id = row.id
        Task { await queue?.retranscribe(meetingID: id, language: language) }
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
        HStack(spacing: 12) {
            Button {
                player.isPlaying ? player.pause() : player.play()
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.space, modifiers: [])
            .help(player.isPlaying ? "Pause" : "Lecture")

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
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
            Menu {
                Toggle("Moi", isOn: $player.moiEnabled)
                Toggle("Les autres", isOn: $player.autresEnabled)
            } label: {
                Image(systemName: "person.2.wave.2")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Les voix à écouter")
        }
    }
}
