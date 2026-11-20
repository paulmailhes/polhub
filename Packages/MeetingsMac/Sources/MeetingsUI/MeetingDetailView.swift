import AppKit
import Domain
import GRDB
import Persistence
import Pipeline
import Recording
import ProjectsUI
import Summarization
import HubDesign
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
    /// Why the audio does not play, in French (lot 8, 19/11).
    @State private var audioProblem: AudioProblem?
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
                // A page's top and bottom, and the reading column of a mail, in the middle (lot 8, 19/11: it sat on the
                // left, 24 points down, while a thread is centered and a page starts 16 points under the toolbar).
                .padding(.top, PageMetrics.top)
                .padding(.bottom, PageMetrics.bottom)
                .readingColumn()
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
            Button("Supprimer", role: .destructive) { delete() }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("L'audio va à la Corbeille, d'où tu peux encore le récupérer.")
        }
        .alert("Export impossible", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            // French typography, laid at display (lot 10, 20/11).
            Text(Words.typeset(exportError ?? ""))
        }
    }

    // MARK: - Header

    /// « Lundi 16 novembre à 14:30 », the year when it is not this one's, by `Words` (lot 10, 20/11).
    private var dateText: String {
        Words.capitalizedFirst(Words.fullDate(row.startedAt, now: Date()) + " à " + Words.time(row.startedAt))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            // The large title of an object open, 26 points, as a project's (lot 8, 19/11).
            Text(row.title).font(.largeTitle.weight(.bold)).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            FlowLayout(spacing: Space.s) {
                // The date leads to its event, when one carries the meeting (lot 4, 19/11).
                if let event = agenda.flatMap({ Self.event(of: row.id, in: $0.shown) }) {
                    Button { router.openEvent(event.id) } label: { Chip(dateText, systemImage: "calendar") }
                        .buttonStyle(.hover(.capsule))
                        .help("Ouvrir le rendez-vous")
                } else {
                    Chip(dateText, systemImage: "calendar")
                }
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

    /// The event that carries the meeting, if the copy of the agendas has it.
    static func event(of meetingID: UUID, in events: [CalendarEventRow]) -> CalendarEventRow? {
        events.first { $0.meetingID == meetingID }
    }

    private var projectMenu: some View {
        Menu {
            // The project's name leads to the project, first in its menu (lot 4, 19/11).
            if let project {
                Button("Ouvrir le projet") { router.openProject(project.id) }
                Divider()
            }
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

    /// Through its event when the agenda is there: the loop then never files it back (audit of 19/11).
    private func file(_ projectID: UUID?) {
        if let agenda {
            Task { await agenda.file(meetingID: row.id, projectID: projectID) }
        } else {
            try? ProjectStore(store.database).setProject(meetingID: row.id, projectID: projectID)
        }
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
            // Short, no name of the past (lot 10, 20/11).
            Label(Words.typeset("Réunion importée : pas d'audio, voix non distinguées."), systemImage: "tray.and.arrow.down")
                .foregroundStyle(.secondary)
        } else if row.status.isUnfinished {
            // Being recorded: its own red; a meeting that does not play: said by `ErrorLine` (design system v2, 19/11).
            Label("Enregistrement en cours. La réunion se réécoute dès qu'elle est terminée.", systemImage: "record.circle")
                .foregroundStyle(Tint.recording)
        } else if let audioProblem {
            // In French, the system's text under « Détails » (lot 8, 19/11).
            AudioProblemLine(problem: audioProblem)
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
            // On the edges of the reading column, as the bar of a reply under a thread (lot 8, 19/11): it was centered on
            // the page while the text sat on the left.
            FloatingBar { PlayerView(player: player) }
                .padding(.horizontal, PageMetrics.horizontal - Space.xl)
                .frame(maxWidth: PageMetrics.readingWidth)
                .frame(maxWidth: .infinity)
        } else if row.audioPurgedAt != nil, row.source != .imported {
            FloatingBar {
                // « Supprimer » destroys; « Effacer » empties a list (lot 10, 20/11).
                Label("L'audio a été supprimé (30 jours après la transcription).", systemImage: "trash")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            // The summary and the dialogue in one Markdown page, to send (Paul, 16/11). A bubble: a verb and its object,
            // 60 characters at most, the parentheses for a shortcut only (lot 10, 20/11).
            Button(action: export) { Label("Exporter", systemImage: "square.and.arrow.up") }
                .help("Exporter le compte rendu et la transcription")
                .disabled(lines.isEmpty && summary?.isEmpty != false)
            if row.source != .imported {
                // An icon alone: the same words for its bubble and VoiceOver (lot 10, 20/11).
                Button { showingDetails = true } label: { Label("Voir les détails de l'enregistrement", systemImage: "info.circle") }
                    .help("Voir les détails de l'enregistrement")
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
                    // No word of the code on screen: « le moteur » (lot 10, 20/11).
                    Button("Détection automatique") { retranscribe(nil) }
                }
                .disabled(queue == nil || row.audioPurgedAt != nil || row.status.isUnfinished || row.source == .imported)
                Divider()
                Button("Afficher dans le Finder") { NSWorkspace.shared.activateFileViewerSelecting([folder]) }
                    .disabled(row.source == .imported)
                Button("Supprimer…", role: .destructive) { confirmingDelete = true }
                    .disabled(row.status.isUnfinished)
            } label: {
                // « Plus d'actions », the words of every « … » (lot 10, 20/11: no bubble before).
                Label(Words.moreActions, systemImage: "ellipsis")
            }
            .help(Words.moreActions)
        }
    }

    /// « Exporter »: where to save, then the page (« Lundi 16 novembre 2026 à 14:30 · 27 min », the summary, the
    /// actions, the dialogue).
    private func export() {
        // By `Words`, the year always: the page is read by others, later (lot 10, 20/11).
        let start = row.startedAt
        let day = Words.fullDate(start, now: start) + " \(Words.calendar.component(.year, from: start))"
        let date = Words.capitalizedFirst(day + " à " + Words.time(start))
        let duration = row.status.isUnfinished || row.endedAt == nil ? "" : MeetingListModel.durationText(row, now: .now)
        let page = MeetingExport.markdown(title: row.title, date: date, duration: duration,
                                          participants: participants.map(\.name), summary: summary, actions: actions, lines: lines,
                                          me: MeetingExport.firstName())
        if case .failure(let error) = MeetingExport.save(page, suggestedName: MeetingExport.fileName(title: row.title, date: row.startedAt)) {
            // Polhub's sentence in the alert, the system's text in the journal (lot 10, 20/11).
            let problem = Words.problem("Le fichier n'a pas pu être écrit", error)
            exportError = problem.sentence
            store.database.journal(problem)
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
                audioProblem = .silent
                return
            }
            player = try await MeetingPlayer(pieces: pieces)
        } catch {
            audioProblem = AudioProblem(error)
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
        // Polhub by its name, never « l'app » (lot 10, 20/11).
        case .interrupted: "interrompue (Polhub s'était arrêté)"
        case .nextMeeting: "une autre réunion a commencé"
        }
    }
}

/// Why a meeting's audio does not play, in French (lot 8, 19/11): Polhub's sentence for Paul, the system's own text
/// (English, a file's name) kept for « Détails ». It replaces « La réunion ne se lit pas : » and the system's text.
struct AudioProblem: Equatable {
    let sentence: String
    /// What the system said, under « Détails »; none when Polhub's sentence says it all.
    let details: String?

    /// Nothing was recorded for the meeting.
    static let silent = AudioProblem(sentence: "Aucun son enregistré pour cette réunion.", details: nil)

    init(sentence: String, details: String?) {
        self.sentence = sentence
        self.details = details
    }

    /// An error met while reading the meeting's folder or its audio.
    init(_ error: Error) {
        let sentence = switch Self.kind(of: error) {
        case .missing: "L'audio de cette réunion est introuvable : son dossier est incomplet."
        case .damaged: "L'audio de cette réunion ne se lit pas : un de ses fichiers est abîmé."
        case .other: "L'audio de cette réunion ne se lit pas."
        }
        self.init(sentence: sentence, details: error.localizedDescription)
    }

    enum Kind { case missing, damaged, other }

    /// A file that is not there, one that does not read, or anything else (the player).
    static func kind(of error: Error) -> Kind {
        if error is DecodingError { return .damaged }
        let error = error as NSError
        switch (error.domain, error.code) {
        case (NSCocoaErrorDomain, NSFileNoSuchFileError), (NSCocoaErrorDomain, NSFileReadNoSuchFileError), (NSPOSIXErrorDomain, Int(ENOENT)):
            return .missing
        case (NSCocoaErrorDomain, NSFileReadCorruptFileError), (NSCocoaErrorDomain, NSFileReadInapplicableStringEncodingError),
             (NSCocoaErrorDomain, NSFileReadUnknownStringEncodingError):
            return .damaged
        default:
            return .other
        }
    }
}

/// A problem of a meeting's audio in one line, by `ErrorLine`, and the system's text under « Détails » (lot 8, 19/11).
struct AudioProblemLine: View {
    let problem: AudioProblem
    @State private var open: Bool

    /// `open`: « Détails » already unfolded (the captures).
    init(problem: AudioProblem, open: Bool = false) {
        self.problem = problem
        _open = State(initialValue: open)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                ErrorLine(problem.sentence).fixedSize(horizontal: false, vertical: true)
                if problem.details != nil {
                    TextButton(open ? "Masquer les détails" : "Détails", quiet: true) {
                        withAnimation(Motion.standard) { open.toggle() }
                    }
                    .fixedSize()
                }
            }
            if open, let details = problem.details {
                Text(details)
                    .font(.meta)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
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
            // A verb, and Espace, which plays and pauses here; VoiceOver says the verb alone (lot 10, 20/11).
            let playLabel = player.isPlaying ? "Mettre en pause" : "Lire"
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
            .help(Words.help(playLabel, .space))
            .accessibilityLabel(playLabel)
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
            // « 12:34 / 47:05 », the clock by `Words` (lot 10, 20/11).
            Text("\(Words.clock(Int(scrubbing ?? player.currentSeconds))) / \(Words.clock(Int(player.durationSeconds)))")
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
            // A verb and its object, never a name (lot 10, 20/11).
            .help("Changer la vitesse")
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
            // An icon alone: the same words for its bubble and VoiceOver (lot 10, 20/11).
            .help("Choisir les voix")
            .accessibilityLabel("Choisir les voix")
        }
    }
}
