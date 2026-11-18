import Colin
import Persistence
import PolhubDesign
import SwiftUI

/// The words of « À valider »: one sentence and one button by line.
enum ReviewText {
    /// A way to set a line aside.
    struct Dismissal: Equatable, Identifiable {
        let title: String
        let reason: ColinDismissalRow.Reason
        var id: String { reason.rawValue }
    }

    static func title(_ line: ReviewRules.Line) -> String {
        switch line.kind {
        case .draft: line.person.isEmpty ? "Brouillon prêt" : "Brouillon prêt pour \(line.person)"
        case .reply: line.person.isEmpty ? "Un mail attend ta réponse" : "\(line.person) attend ta réponse"
        case .silent: line.person.isEmpty ? "Un client ne répond plus" : "\(line.person) ne répond plus"
        case .unfiled: "Réunion à ranger"
        }
    }

    /// The project and the days; for a draft its project, else its subject; for a meeting its title.
    static func detail(_ line: ReviewRules.Line) -> String? {
        switch line.kind {
        case .draft:
            return line.detail
        case .unfiled:
            return line.person.isEmpty ? nil : line.person
        case .reply, .silent:
            let parts = [line.detail, line.days.map(days)].compactMap { $0 }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        }
    }

    static func days(_ count: Int) -> String {
        count <= 0 ? "aujourd'hui" : count == 1 ? "1 jour" : "\(count) jours"
    }

    static func action(_ kind: ReviewRules.Kind) -> String {
        switch kind {
        case .draft: "Relire"
        case .reply, .silent: "Ouvrir"
        case .unfiled: "Ranger"
        }
    }

    static func symbol(_ kind: ReviewRules.Kind) -> String {
        switch kind {
        case .draft: "sparkles"
        case .reply: "arrowshape.turn.up.left"
        case .silent: "hourglass"
        case .unfiled: "tray"
        }
    }

    /// A draft leaves when it is sent or deleted, a meeting when it is filed (under « Aucun » too): neither is set
    /// aside. The silence of a client is said with the name, never with « elle » or « il ».
    static func dismissals(_ line: ReviewRules.Line) -> [Dismissal] {
        switch line.kind {
        case .draft, .unfiled:
            return []
        case .reply:
            return [Dismissal(title: "Pas besoin", reason: .notNeeded), Dismissal(title: "Plus tard", reason: .later)]
        case .silent:
            return [Dismissal(title: line.person.isEmpty ? "Réponse reçue ailleurs" : "\(line.person) a répondu ailleurs", reason: .answeredElsewhere),
                    Dismissal(title: "Pas besoin", reason: .notNeeded), Dismissal(title: "Plus tard", reason: .later)]
        }
    }
}

/// « À valider » (18/11): what waits for Paul's click, one sentence and one button by line. A line leaves by
/// itself once the thing is done.
struct ReviewCard: View {
    @ObservedObject var colin: ColinLibrary
    @ObservedObject var agenda: AgendaLibrary
    let mails: MailLibrary?
    @ObservedObject var router: WindowRouter

    /// The room kept at the end of a line for its button, and for its menu.
    private static let actionWidth: CGFloat = 66
    private static let menuWidth: CGFloat = 32

    var body: some View {
        Card {
            SectionTitle("À valider", count: colin.review.isEmpty ? nil : colin.review.count)
            if colin.review.isEmpty { EmptyLine("Rien n'attend ton clic.") }
            ShowMoreList(colin.review, limit: 5) { line in row(line) }
        }
        .animation(Motion.standard, value: colin.review)
    }

    private func row(_ line: ReviewRules.Line) -> some View {
        let dismissals = ReviewText.dismissals(line)
        return RowButton(action: { open(line) }) {
            HStack(alignment: .center, spacing: Space.m) {
                Image(systemName: ReviewText.symbol(line.kind))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(line.kind == .draft ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(ReviewText.title(line)).font(.rowTitle).foregroundStyle(.primary).lineLimit(1)
                    if let detail = ReviewText.detail(line) { Text(detail).font(.meta).foregroundStyle(.secondary).lineLimit(1) }
                }
                Spacer(minLength: 0)
                // Room for the line's button and its menu, laid over the row so that its highlight runs to the end.
                Color.clear.frame(width: Self.actionWidth + (dismissals.isEmpty ? 0 : Self.menuWidth), height: 1)
            }
        }
        .overlay(alignment: .trailing) {
            HStack(spacing: 0) {
                action(line)
                if !dismissals.isEmpty {
                    IconMenu("ellipsis", help: "Écarter cette ligne") {
                        ForEach(dismissals) { way in
                            Button(way.title) { colin.dismiss(line, reason: way.reason) }
                        }
                    }
                }
            }
        }
        .help(ReviewText.title(line))
    }

    /// « Relire », « Ouvrir »: the same as a click on the line. « Ranger »: the projects, and « Aucun ».
    @ViewBuilder
    private func action(_ line: ReviewRules.Line) -> some View {
        if line.kind == .unfiled {
            Menu {
                ForEach(projects) { project in
                    Button(project.name) { Task { await colin.file(line, projectID: project.id) } }
                }
                Divider()
                Button("Aucun") { Task { await colin.file(line, projectID: nil) } }
            } label: {
                // Drawn as the other lines' word (`TextButton`).
                Text(ReviewText.action(line.kind)).font(.meta.weight(.medium)).foregroundStyle(Color.accentColor)
                    .padding(.horizontal, Space.s).padding(.vertical, 3)
            }
            .menuStyle(.button)
            .buttonStyle(.hover(.capsule))
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Ranger cette réunion dans un projet")
        } else {
            TextButton(ReviewText.action(line.kind)) { open(line) }
        }
    }

    /// The projects a meeting may go in, as the calendar offers them: by name, the finished ones apart.
    private var projects: [ProjectRow] {
        agenda.projects.filter { $0.status != .termine }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func open(_ line: ReviewRules.Line) {
        switch line.kind {
        case .draft:
            // Over the Accueil: a reply under its thread, a new mail in its panel.
            guard let mails, let draft = mails.drafts.first(where: { $0.id == line.draftID }) else { return }
            mails.open(draft) { router.homeMail = $0 }
        case .reply, .silent:
            // The thread over the Accueil too: Paul answers, closes, and the next line is there.
            router.homeMail = line.threadKey
        case .unfiled:
            if let id = line.eventID { router.openEvent(id) }
        }
    }
}
