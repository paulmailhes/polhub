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

    /// Late: past twice its threshold (the Accueil's pass, 18/11); its age is then said in the accent.
    static func late(_ line: ReviewRules.Line, thresholds: ReviewRules.Thresholds) -> Bool {
        guard let days = line.days else { return false }
        switch line.kind {
        case .reply: return days > 2 * thresholds.replyDays
        case .silent: return days > 2 * thresholds.silentDays
        case .draft, .unfiled: return false
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

/// « À valider » (the Accueil's pass, 18/11): what waits for Paul's click — the face of the person, one sentence, one
/// quiet action always at the same edge, the « … » under the pointer; the age in the accent once late. A line leaves
/// by itself once the thing is done.
struct ReviewCard: View {
    @ObservedObject var colin: ColinLibrary
    @ObservedObject var agenda: AgendaLibrary
    let mails: MailLibrary?
    @ObservedObject var router: WindowRouter
    var thresholds = ReviewRules.Thresholds()
    var limit = 5
    @State private var hovered: String?

    /// The room kept at the end of a line for its button, and for its menu.
    private static let actionWidth: CGFloat = 70
    private static let menuWidth: CGFloat = 28

    var body: some View {
        HomeCard("À valider", count: colin.review.isEmpty ? nil : colin.review.count) {
            if colin.review.isEmpty {
                Label("Rien à valider.", systemImage: "checkmark.circle").font(.rowBody).foregroundStyle(.secondary)
            }
            ShowMoreList(colin.review, limit: limit) { line in row(line).homeRow(first: line.id == colin.review.first?.id) }
        }
        .animation(Motion.standard, value: colin.review)
    }

    private func row(_ line: ReviewRules.Line) -> some View {
        let dismissals = ReviewText.dismissals(line)
        return RowButton(action: { open(line) }) {
            HStack(alignment: .center, spacing: Space.m) {
                face(line)
                VStack(alignment: .leading, spacing: 1) {
                    title(line).font(.rowBody).foregroundStyle(.primary).lineLimit(1)
                    if let detail = ReviewText.detail(line) {
                        Text(detail).font(.meta)
                            .foregroundStyle(ReviewText.late(line, thresholds: thresholds) ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                // Room for the line's button and its menu, laid over the row so that its highlight runs to the end.
                Color.clear.frame(width: Self.actionWidth + Self.menuWidth, height: 1)
            }
        }
        .overlay(alignment: .trailing) {
            HStack(spacing: Space.xs) {
                action(line)
                ZStack {
                    if !dismissals.isEmpty {
                        IconMenu("ellipsis", help: "Écarter cette ligne") {
                            ForEach(dismissals) { way in
                                Button(way.title) { colin.dismiss(line, reason: way.reason) }
                            }
                        }
                        .opacity(hovered == line.id ? 1 : 0)
                    }
                }
                .frame(width: Self.menuWidth)
            }
        }
        .onHover { inside in hovered = inside ? line.id : (hovered == line.id ? nil : hovered) }
        .help(ReviewText.title(line))
    }

    /// The person's name in bold, the rest in regular.
    private func title(_ line: ReviewRules.Line) -> Text {
        let said = ReviewText.title(line)
        guard !line.person.isEmpty, let range = said.range(of: line.person) else { return Text(said) }
        return Text("\(Text(said[..<range.lowerBound]))\(Text(line.person).fontWeight(.semibold))\(Text(said[range.upperBound...]))")
    }

    /// The face of the person, in the project's color; a meeting to file, its tray.
    @ViewBuilder
    private func face(_ line: ReviewRules.Line) -> some View {
        if line.kind == .unfiled || line.person.isEmpty {
            Image(systemName: ReviewText.symbol(line.kind))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .background(Surface.fill, in: Circle())
        } else {
            let project = line.projectID.flatMap { id in agenda.projects.first { $0.id == id } }
            PersonAvatar(initials: PeopleIndex.initials(name: line.person, email: line.person), tint: project.map { PeopleStyle.color(of: $0) } ?? .secondary)
        }
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
                Text(ReviewText.action(line.kind))
            }
            .menuStyle(.button)
            .buttonStyle(.subtle)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Ranger cette réunion dans un projet")
        } else {
            Button(ReviewText.action(line.kind)) { open(line) }.buttonStyle(.subtle)
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
