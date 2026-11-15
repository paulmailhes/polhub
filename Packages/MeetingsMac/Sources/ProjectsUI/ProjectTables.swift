import Domain
import Persistence
import PolhubDesign
import SwiftUI

/// « Liste » (14/11): every project, its columns sortable, a status to filter by; a double click opens it.
struct ProjectListView: View {
    @ObservedObject var library: ProjectLibrary
    let projects: [ProjectRow]
    @State private var status: ProjectStatus?
    @State private var order = [KeyPathComparator(\ProjectListRow.statusRank), KeyPathComparator(\ProjectListRow.name)]
    @State private var selection: ProjectRow.ID?

    var body: some View {
        let rows = ProjectListRow.rows(projects, lastMeetings: library.lastAppMeetings, status: status).sorted(using: order)
        Table(rows, selection: $selection, sortOrder: $order) {
            TableColumn("Projet", value: \.name) { row in
                // The name opens the project in one click, with the design system's hover and press (15/11); a double
                // click on the row still does.
                Button { library.selected = row.project.id } label: {
                    HStack(spacing: Space.s) {
                        ProjectLogo(row.project, size: 20)
                        Text(row.project.name).font(.rowBody.weight(.medium)).foregroundStyle(.primary).lineLimit(1)
                    }
                    .padding(.horizontal, Space.s).padding(.vertical, 3)
                }
                .buttonStyle(.hover)
                .padding(.horizontal, -Space.s)
                .help("Ouvrir « \(row.project.name) »")
            }
            .width(min: 180, ideal: 260)
            TableColumn("Statut", value: \.statusRank) { row in
                Chip(row.project.status.title, tint: ProjectViews.statusColor(row.project.status))
            }
            .width(min: 100, ideal: 120)
            TableColumn("Client", value: \.clientSort) { row in Text(row.project.client ?? "").foregroundStyle(.secondary) }
                .width(min: 90, ideal: 150)
            TableColumn("Échéance", value: \.dueSort) { row in
                if let label = ProjectViews.dueLabel(row.project.dueDate, today: Date()) {
                    Text(label).foregroundStyle(label.hasPrefix("En retard") ? .red : label == "Aujourd'hui" ? .orange : .secondary)
                }
            }
            .width(min: 80, ideal: 100)
            TableColumn("Dernière activité", value: \.activitySort) { row in
                Text(row.lastSign.formatted(.relative(presentation: .named).locale(Locale(identifier: "fr_FR")))).foregroundStyle(.secondary)
            }
            .width(min: 110, ideal: 140)
            TableColumn("Prochaine étape") { row in Text(row.project.todo ?? "").lineLimit(2).foregroundStyle(.secondary) }
        }
        .contextMenu(forSelectionType: ProjectRow.ID.self) { _ in } primaryAction: { ids in
            library.selected = ids.first
        }
        .toolbar {
            ToolbarItem {
                Menu {
                    Picker("Statut", selection: $status) {
                        Text("Tous les statuts").tag(ProjectStatus?.none)
                        Divider()
                        ForEach(ProjectStatus.allCases, id: \.self) { status in
                            Text(status.title).tag(Optional(status))
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label("Filtrer", systemImage: status == nil ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill")
                }
                .help("Filtrer par statut")
            }
        }
    }
}
