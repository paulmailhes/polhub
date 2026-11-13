import Domain
import Persistence
import SwiftUI

/// « Tableau »: every project, the most recent activity first.
struct AllProjectsTable: View {
    @ObservedObject var library: ProjectLibrary

    var body: some View {
        Table(ProjectViews.table(library.projects)) {
            TableColumn("Projet") { project in Text(project.name).fontWeight(.medium) }
            TableColumn("Statut") { project in Text(project.status.label.capitalizedFirst) }
            TableColumn("Client") { project in Text(project.client ?? "") }
            TableColumn("Dans") { project in Text(ProjectViews.dueLabel(project.dueDate, today: Date()) ?? "") }
            TableColumn("Réunion") { project in Text(relative(ProjectViews.lastMeeting(project, appMeeting: library.lastAppMeetings[project.id]))) }
            TableColumn("Activité") { project in Text(relative(project.lastActivity)) }
            TableColumn("To do") { project in Text(project.todo ?? "").lineLimit(2) }
        }
        .contextMenu(forSelectionType: ProjectRow.ID.self) { _ in } primaryAction: { ids in
            library.selected = ids.first
        }
    }
}

/// « À rendre »: what is due, the late first.
struct HandInTable: View {
    @ObservedObject var library: ProjectLibrary

    var body: some View {
        Table(ProjectViews.toHandIn(library.projects, today: Date())) {
            TableColumn("Projet") { project in Text(project.name).fontWeight(.medium) }
                .width(min: 120, ideal: 180)
            TableColumn("Dans") { project in Text(ProjectViews.dueLabel(project.dueDate, today: Date()) ?? "Sans échéance") }
                .width(min: 90, ideal: 118)
            TableColumn("To do") { project in Text(project.todo ?? "").lineLimit(2) }
        }
        .contextMenu(forSelectionType: ProjectRow.ID.self) { _ in } primaryAction: { ids in
            library.selected = ids.first
        }
    }
}

/// « À surveiller »: priorities silent for two weeks.
struct WatchTable: View {
    @ObservedObject var library: ProjectLibrary

    struct Row: Identifiable {
        let project: ProjectRow
        let sign: Date
        var id: UUID { project.id }
    }

    var body: some View {
        let rows = ProjectViews.toWatch(library.projects, lastAppMeeting: library.lastAppMeetings, today: Date()).map { Row(project: $0.0, sign: $0.sign) }
        Table(rows) {
            TableColumn("Projet") { row in Text(row.project.name).fontWeight(.medium) }
            TableColumn("Pourquoi") { _ in Text("Silence") }
            TableColumn("Dernier signe") { row in Text(relative(row.sign)) }
        }
        .contextMenu(forSelectionType: UUID.self) { _ in } primaryAction: { ids in
            library.selected = ids.first
        }
    }
}

/// « il y a 3 jours ».
func relative(_ date: Date?) -> String {
    guard let date else { return "" }
    let formatter = RelativeDateTimeFormatter()
    formatter.locale = Locale(identifier: "fr_FR")
    formatter.unitsStyle = .full
    return formatter.localizedString(for: date, relativeTo: Date())
}
