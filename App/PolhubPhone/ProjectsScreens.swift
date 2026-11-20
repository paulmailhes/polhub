import PolhubLink
import SwiftUI

/// Projets: the board's columns as a list, a project's page (lot 4, 20/11). Read only: Colin changes them.
struct ProjectsScreen: View {
    @Environment(PhoneSession.self) private var session
    @State private var projects: [LinkProject] = []
    @State private var keptAt: Date?
    @State private var problem: String?
    @State private var showsDone = false

    static let columns = [("priorité 2", "Priorité 2"), ("priorité 1", "Priorité 1"), ("en pause", "En pause"), ("terminé", "Terminé")]

    var body: some View {
        NavigationStack {
            List {
                ForEach(Self.columns, id: \.0) { status, title in
                    let shown = projects.filter { $0.status == status }
                    if !shown.isEmpty, status != "terminé" || showsDone {
                        Section(title) {
                            ForEach(shown) { project in
                                NavigationLink(value: project) { ProjectRow(project: project) }
                            }
                        }
                    }
                }
                if projects.contains(where: { $0.status == "terminé" }) {
                    Button(showsDone ? "Masquer les terminés" : "Afficher les terminés") { showsDone.toggle() }
                }
            }
            .navigationTitle("Projets")
            .toolbar { SettingsButton() }
            .navigationDestination(for: LinkProject.self) { ProjectScreen(project: $0) }
            .safeAreaInset(edge: .top, spacing: 0) { StateLine(keptAt: keptAt, problem: problem) }
            .refreshable { await load() }
            .task { await load() }
        }
    }

    private func load() async {
        do throws(LinkFailure) {
            let fetched = try await session.fetch([LinkProject].self, LinkAPI.Path.projects)
            projects = fetched.value
            keptAt = fetched.keptAt
            problem = nil
        } catch {
            problem = error.message
        }
    }
}

struct ProjectRow: View {
    let project: LinkProject

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(Color(hex: project.color ?? "#8E8E93")).frame(width: 9, height: 9).padding(.top, 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(project.name).fontWeight(.medium)
                if let task = project.task, !task.isEmpty { Text(task).font(.subheadline).foregroundStyle(.secondary).lineLimit(2) }
                if let due = project.due { DueLine(due: due) }
            }
        }
    }
}

/// « Échéance 24 nov. », red once passed.
struct DueLine: View {
    let due: Date

    var body: some View {
        let late = due < LinkWords.calendar.startOfDay(for: Date())
        Text("Échéance \(LinkWords.shortDate(due))").font(.footnote).foregroundStyle(late ? .red : .secondary)
    }
}

struct ProjectScreen: View {
    let project: LinkProject
    @Environment(PhoneSession.self) private var session
    @State private var detail: LinkProjectDetail?
    @State private var keptAt: Date?
    @State private var problem: String?

    var body: some View {
        List {
            Section {
                if let client = project.client { LabeledContent("Client", value: client) }
                LabeledContent("Statut", value: project.status.prefix(1).uppercased() + project.status.dropFirst())
                if let due = project.due { LabeledContent("Échéance", value: LinkWords.shortDate(due)) }
                if let task = project.task, !task.isEmpty { LabeledContent("Tâche du moment", value: task) }
            }
            if let detail {
                if !detail.events.isEmpty {
                    Section("Rendez-vous") { ForEach(detail.events) { EventRow(event: $0) } }
                }
                if !detail.actions.isEmpty {
                    Section("Actions") {
                        ForEach(detail.actions) { action in
                            Label(action.text, systemImage: action.done ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(action.done ? .secondary : .primary)
                        }
                    }
                }
                if !detail.journal.isEmpty {
                    Section("Journal") {
                        ForEach(detail.journal) { entry in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.title)
                                Text(LinkWords.shortDate(entry.date)).font(.footnote).foregroundStyle(.secondary)
                                if !entry.text.isEmpty { Text(entry.text).font(.subheadline).foregroundStyle(.secondary) }
                            }
                        }
                    }
                }
                if !detail.notes.isEmpty {
                    Section("Notes") { Text(detail.notes).font(.subheadline) }
                }
            }
        }
        .navigationTitle(project.name)
        .safeAreaInset(edge: .top, spacing: 0) { StateLine(keptAt: keptAt, problem: problem) }
        .task {
            do throws(LinkFailure) {
                let fetched = try await session.fetch(LinkProjectDetail.self, LinkAPI.Path.project, query: ["id": project.id.uuidString])
                detail = fetched.value
                keptAt = fetched.keptAt
            } catch {
                problem = error.message
            }
        }
    }
}

/// Réunions: what Polhub recorded, newest first; a meeting's summary and its dialogue (lot 4, 20/11).
struct MeetingsScreen: View {
    @Environment(PhoneSession.self) private var session
    @State private var meetings: [LinkMeeting] = []
    @State private var keptAt: Date?
    @State private var problem: String?

    var body: some View {
        NavigationStack {
            List(meetings) { meeting in
                NavigationLink(value: meeting) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(meeting.title).fontWeight(.medium)
                        Text(([LinkWords.listDate(meeting.start)] + [meeting.seconds.map(LinkWords.duration), meeting.project].compactMap { $0 })
                            .joined(separator: " · "))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Réunions")
            .toolbar { SettingsButton() }
            .navigationDestination(for: LinkMeeting.self) { MeetingScreen(meeting: $0) }
            .safeAreaInset(edge: .top, spacing: 0) { StateLine(keptAt: keptAt, problem: problem) }
            .refreshable { await load() }
            .task { await load() }
        }
    }

    private func load() async {
        do throws(LinkFailure) {
            let fetched = try await session.fetch([LinkMeeting].self, LinkAPI.Path.meetings)
            meetings = fetched.value
            keptAt = fetched.keptAt
            problem = nil
        } catch {
            problem = error.message
        }
    }
}

struct MeetingScreen: View {
    let meeting: LinkMeeting
    @Environment(PhoneSession.self) private var session
    @State private var detail: LinkMeetingDetail?
    @State private var problem: String?
    @State private var page = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("Page", selection: $page) {
                Text("Compte rendu").tag(0)
                Text("Transcription").tag(1)
            }
            .pickerStyle(.segmented)
            .padding()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let detail {
                        if page == 0 {
                            if let summary = detail.summary {
                                MarkdownBlock(text: summary)
                            } else {
                                Text("Pas encore de compte rendu.").foregroundStyle(.secondary)
                            }
                        } else if detail.turns.isEmpty {
                            Text("Pas encore transcrite.").foregroundStyle(.secondary)
                        } else {
                            ForEach(Array(detail.turns.enumerated()), id: \.offset) { _, turn in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(turn.speaker) · \(turn.start / 60):" + String(format: "%02d", turn.start % 60))
                                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                    Text(turn.text + (turn.doubtful ? " (à vérifier)" : ""))
                                }
                            }
                        }
                    } else if let problem {
                        Text(problem).foregroundStyle(.secondary)
                    } else {
                        ProgressView().frame(maxWidth: .infinity)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
            }
        }
        .navigationTitle(meeting.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do throws(LinkFailure) {
                detail = try await session.fetch(LinkMeetingDetail.self, LinkAPI.Path.meeting, query: ["id": meeting.id.uuidString]).value
            } catch {
                problem = error.message
            }
        }
    }
}

/// A markdown text as Polhub writes it (a summary, Colin's answer): its titles, its lists, its bold words.
struct MarkdownBlock: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(text.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("#") {
                    Self.inline(String(trimmed.drop { $0 == "#" }).trimmingCharacters(in: .whitespaces)).font(.headline).padding(.top, 6)
                } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•")
                        Self.inline(String(trimmed.dropFirst(2)))
                    }
                } else if !trimmed.isEmpty {
                    Self.inline(trimmed)
                }
            }
        }
    }

    static func inline(_ text: String) -> Text {
        Text((try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text))
    }
}
