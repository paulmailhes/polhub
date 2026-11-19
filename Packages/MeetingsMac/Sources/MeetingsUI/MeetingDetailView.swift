import AppKit
import Domain
import GRDB
import Persistence
import Pipeline
import Recording
import ProjectsUI
import Summarization
import PolhubDesign
import SwiftUI

/// One meeting, on one page (14/11, 15/11): who and when, its summary in four parts and its actions, then the
/// dialogue, and the player floating at the bottom. The rare gestures live in the « … » menu of the toolbar.
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
    /// Where the summary under way is, part by part.
    var summaryProgress: SummaryProgress?
    let job: JobRow?
    let meetingActive: Bool
    @ObservedObject var router: WindowRouter
    /// The contacts and their projects: the participants' small menu works through it.
    var agenda: AgendaLibrary?

    @AppStorage(Preferences.Key.summariesEnabled) private var summariesEnabled = true
    @State private var player: MeetingPlayer?
    @State private var file: MeetingFile?
    @State private var microphones: [String] = []
    @State private var loadError: String?
    @State private var confirmingDelete = false
    @State private var showingDetails = false
    @State private var lines: [UtteranceRow] = []
    /// The turns of speech, computed when the dialogue changes, never at the player's ticks (15/11).
    @State private var paragraphs: [TranscriptModel.Paragraph] = []
    @State private var observations: [AnyDatabaseCancellable] = []
    @State private var summary: String?
    @State private var summaryJob: SummaryJobRow?
    @State private var actions: [ActionRow] = []
    @State private var participants: [ContactRow] = []
    @State private var exportError: String?

    private var folder: URL { paths.meetingFolder(row.id) }
    private var project: ProjectRow? { row.projectID.flatMap { id in projects.first { $0.id == id } } }

    var body: some View {
        ScrollViewReader { scroll in
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    header
                    summaryCard
                    transcript(scroll)
                }
                .padding(.horizontal, PageMetrics.horizontal)
                .padding(.top, Space.xl)
                .padding(.bottom, PageMetrics.bottom)
                .frame(maxWidth: PageMetrics.readingWidth, alignment: .leading)
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
                transcripts.observeUtterances(meetingID: row.id) { utterances in
                    lines = utterances
                    paragraphs = TranscriptModel.paragraphs(utterances)
                },
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
        .alert("Export impossible", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportError ?? "")
        }
    }

    // MARK: - Header

    private var dateText: String {
        let text = row.startedAt.formatted(.dateTime.weekday(.wide).day().month(.wide).hour().minute().locale(Locale(identifier: "fr_FR")))
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text(row.title).font(.title.bold()).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            FlowLayout(spacing: Space.s) {
                Chip(dateText, systemImage: "calendar")
                // Being recorded: its own red; interrupted: to check (design system v2, 19/11).
                if row.status.isUnfinished {
                    Chip("En cours", systemImage: "record.circle", tint: Tint.recording).symbolEffect(.pulse)
                } else {
                    Chip(MeetingListModel.durationText(row, now: .now), systemImage: "clock")
                    if row.status == .interrupted { Chip("Interrompue", tint: Tint.attention) }
                }
            }
            if !projects.isEmpty || !participants.isEmpty {
                FlowLayout(spacing: Space.s) {
                    if !projects.isEmpty { projectMenu }
                    // Who took part, and who of them is in the meeting's project; a click opens their small
                    // menu here, as in the mails and the calendar (15/11: Paul never opens Contacts).
                    ForEach(participants.prefix(MeetingPersonChip.shown)) { contact in
                        MeetingPersonChip(contact: contact, project: project, agenda: agenda, router: router)
                    }
                    if participants.count > MeetingPersonChip.shown {
                        MeetingMorePeople(people: Array(participants.dropFirst(MeetingPersonChip.shown)), project: project, agenda: agenda, router: router)
                    }
                }
            }
        }
    }

    private var projectMenu: some View {
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
        // No glass in the content: the secondary role (design system v2, 19/11).
        .buttonStyle(.secondary)
        .fixedSize()
    }

    private func file(_ projectID: UUID?) {
        try? ProjectStore(store.database).setProject(meetingID: row.id, projectID: projectID)
    }

    // MARK: - Summary

    @ViewBuilder
    private var summaryCard: some View {
        let hasSummary = summary?.isEmpty == false
        // Transcribed, and the queue has not taken it yet: it is waiting, it says so (15/11).
        let waiting = summariesEnabled && row.source != .imported && row.transcribedAt != nil && !row.status.isUnfinished && !lines.isEmpty
        let status = TranscriptModel.summaryText(summaryJob, hasSummary: hasSummary, unavailable: summaryUnavailable,
                                                 progress: summaryProgress, waiting: waiting)
        if hasSummary || status != nil || !actions.isEmpty {
            let redo: (() -> Void)? = canRedo ? { redoSummary() } : nil
            SummaryCard(title: row.title, subtitle: dateText, summary: summary, job: summaryJob, status: status, progress: summaryProgress,
                        actions: actions, project: project, redo: redo,
                        setDone: { action, done in setDone(action, done) },
                        addToProject: { action, project in addToProject(action, project: project) })
                .transition(.opacity)
        }
    }

    private var canRedo: Bool {
        summaries != nil && !lines.isEmpty && row.source != .imported && summaryJob?.state != .running
    }

    private func setDone(_ action: ActionRow, _ done: Bool) {
        var changed = action
        changed.done = done
        changed.updatedAt = Date()
        try? ProjectStore(store.database).saveAction(changed)
        reloadSummary()
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
            // Being recorded: its own red; a meeting that does not play: said by `ErrorLine` (design system v2, 19/11).
            Label("Enregistrement en cours. La réunion se réécoute dès qu'elle est terminée.", systemImage: "record.circle")
                .foregroundStyle(Tint.recording)
        } else if let loadError {
            ErrorLine(loadError)
        }
        if let status = TranscriptModel.status(job, meeting: row, meetingActive: meetingActive) {
            VStack(alignment: .leading, spacing: Space.m) {
                TranscriptHeader(status: status, meetingID: row.id, queue: queue)
                if !lines.isEmpty {
                    if let player {
                        DialogueList(lines: lines, paragraphs: paragraphs, player: player, scroll: scroll)
                    } else {
                        DialogueParagraphs(paragraphs: paragraphs, seek: nil)
                    }
                } else if case .done = status {
                    Text("Personne n'a parlé, ou rien n'a pu être transcrit.").foregroundStyle(.secondary)
                }
            }
        } else if row.source == .imported, !lines.isEmpty {
            DialogueParagraphs(paragraphs: paragraphs, seek: nil)
        }
    }

    // MARK: - Player and toolbar

    @ViewBuilder
    private var playerBar: some View {
        if let player {
            FloatingBar { PlayerView(player: player) }
                .frame(maxWidth: 760)
        } else if row.audioPurgedAt != nil, row.source != .imported {
            FloatingBar {
                Label("L'audio a été effacé (30 jours après la transcription).", systemImage: "trash")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            // The summary and the dialogue in one Markdown page, to send (Paul, 16/11).
            Button(action: export) { Label("Exporter", systemImage: "square.and.arrow.up") }
                .help("Exporter le compte rendu et la transcription en Markdown (.md)")
                .disabled(lines.isEmpty && summary?.isEmpty != false)
            if row.source != .imported {
                Button { showingDetails = true } label: { Label("Enregistrement", systemImage: "info.circle") }
                    .help("Comment s'est passé l'enregistrement")
                    .popover(isPresented: $showingDetails, arrowEdge: .bottom) { recordingDetails }
            }
            Menu {
                Button("Refaire le compte rendu") { redoSummary() }
                    .disabled(!canRedo)
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

    /// « Exporter »: where to save, then the page (« Lundi 16 novembre 2026 à 14:30 · 27 min », the summary, the
    /// actions, the dialogue).
    private func export() {
        let date = row.startedAt.formatted(.dateTime.weekday(.wide).day().month(.wide).year().hour().minute().locale(Locale(identifier: "fr_FR")))
        let duration = row.status.isUnfinished || row.endedAt == nil ? "" : MeetingListModel.durationText(row, now: .now)
        let page = MeetingExport.markdown(title: row.title, date: date.prefix(1).uppercased() + date.dropFirst(), duration: duration,
                                          participants: participants.map(\.name), summary: summary, actions: actions, lines: lines,
                                          me: MeetingExport.firstName())
        if case .failure(let error) = MeetingExport.save(page, suggestedName: MeetingExport.fileName(title: row.title, date: row.startedAt)) {
            exportError = "Le fichier n'a pas pu être écrit : \(error.localizedDescription)"
        }
    }

    private var recordingDetails: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text("Enregistrement").font(.headline)
            if !microphones.isEmpty { LabeledContent("Micro retenu", value: microphones.joined(separator: ", ")) }
            if let health = file?.health {
                LabeledContent("Coupures", value: health.gapCount == 0 ? "Aucune" : "\(health.gapCount)")
                LabeledContent("Changements de périphérique", value: "\(health.rebuilds)")
                if health.selfTestPassed == false {
                    // A problem: said by `ErrorLine` (design system v2, 19/11).
                    ErrorLine("Le son des autres n'a pas été entendu au début.")
                }
            }
            if let reason = row.endReason { LabeledContent("Fin", value: Self.words(reason)) }
            if microphones.isEmpty, file == nil, row.endReason == nil { Text("Rien à signaler.").foregroundStyle(.secondary) }
        }
        .padding(Space.l)
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

/// The player, in its glass capsule: −15 s, play, +15 s, the time, the speed and the voices. Its buttons stay plain
/// with a circle under the pointer: no glass on glass (15/11).
struct PlayerView: View {
    @ObservedObject var player: MeetingPlayer
    @State private var scrubbing: Double?

    var body: some View {
        HStack(spacing: Space.s) {
            IconButton("gobackward.15", help: "Reculer de 15 secondes", size: 16) { player.skip(by: -MeetingPlayer.skipSeconds) }
            Button {
                player.isPlaying ? player.pause() : player.play()
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.hover(.circle))
            .keyboardShortcut(.space, modifiers: [])
            .help(player.isPlaying ? "Pause" : "Lecture")
            .accessibilityLabel(player.isPlaying ? "Pause" : "Lecture")
            IconButton("goforward.15", help: "Avancer de 15 secondes", size: 16) { player.skip(by: MeetingPlayer.skipSeconds) }

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
                .fixedSize()
            Menu {
                Picker("Vitesse", selection: $player.rate) {
                    ForEach(MeetingPlayer.rates, id: \.self) { rate in Text(MeetingPlayer.rateLabel(rate)).tag(rate) }
                }
                .pickerStyle(.inline)
            } label: {
                Text(MeetingPlayer.rateLabel(player.rate)).font(.callout.monospacedDigit().weight(.semibold))
                    .frame(minWidth: 44, minHeight: 32)
            }
            .menuStyle(.button)
            .buttonStyle(.hover(.capsule))
            .menuIndicator(.hidden)
            .fixedSize()
            .help("La vitesse de lecture")
            Menu {
                Toggle("Moi", isOn: $player.moiEnabled)
                Toggle("Les autres", isOn: $player.autresEnabled)
            } label: {
                Image(systemName: "person.2.wave.2").frame(width: 36, height: 32)
            }
            .menuStyle(.button)
            .buttonStyle(.hover(.capsule))
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Les voix à écouter")
        }
    }
}
