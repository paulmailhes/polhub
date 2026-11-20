import Colin
import Persistence
import HubDesign
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

    /// Late: past twice its threshold (the Accueil's pass, 18/11); its age is then said in red (`Tint.late`, design
    /// system v2, 19/11).
    static func late(_ line: ReviewRules.Line, thresholds: ReviewRules.Thresholds) -> Bool {
        guard let days = line.days else { return false }
        switch line.kind {
        case .reply: return days > 2 * thresholds.replyDays
        case .silent: return days > 2 * thresholds.silentDays
        case .draft, .unfiled: return false
        }
    }

    /// « aujourd'hui », « 1 jour », « 9 jours » (lot 10, 20/11: the count by `Words.dayCount`).
    static func days(_ count: Int) -> String {
        count <= 0 ? "aujourd'hui" : Words.dayCount(count)
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

    /// What a line offers (lot 5, 19/11), the same under the pointer and at the right click.
    struct Gestures: Equatable {
        /// « Relire », « Ouvrir »: what a click on the line does.
        var open: String
        /// A meeting to file: « Ranger », and its projects.
        var file: Bool
        /// The ways to set it aside.
        var dismissals: [Dismissal]
    }

    /// A meeting opens with a click, « Ranger » is its action; a draft is read again, a mail opened.
    static func gestures(_ line: ReviewRules.Line) -> Gestures {
        Gestures(open: line.kind == .unfiled ? "Ouvrir" : action(line.kind), file: line.kind == .unfiled, dismissals: dismissals(line))
    }
}

/// « À valider » (the Accueil's pass, 18/11): what waits for Paul's click — the face of the person, one sentence; the age
/// in red once late. Its action and its « … » come under the pointer only, on a place kept for them at the end of the line,
/// and at the right click (lot 5, 19/11: seven outlined buttons at rest made the Accueil loud). A line leaves by itself
/// once the thing is done.
struct ReviewCard: View {
    @ObservedObject var colin: ColinLibrary
    @ObservedObject var agenda: AgendaLibrary
    let mails: MailLibrary?
    @ObservedObject var router: WindowRouter
    var thresholds = ReviewRules.Thresholds()
    var limit = 5
    @State private var hovered: String?

    /// The place kept at the end of a line for its action and its « … »: nothing moves under the pointer.
    private static let actionsWidth: CGFloat = 100

    init(colin: ColinLibrary, agenda: AgendaLibrary, mails: MailLibrary?, router: WindowRouter, thresholds: ReviewRules.Thresholds = ReviewRules.Thresholds(),
         limit: Int = 5, hovered: String? = nil) {
        self.colin = colin
        self.agenda = agenda
        self.mails = mails
        self.router = router
        self.thresholds = thresholds
        self.limit = limit
        // The captures show a line under the pointer.
        _hovered = State(initialValue: hovered)
    }

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
        let gestures = ReviewText.gestures(line)
        let shown = hovered == line.id
        return RowButton(action: { open(line) }) {
            HStack(alignment: .center, spacing: Space.m) {
                face(line)
                VStack(alignment: .leading, spacing: 1) {
                    title(line).font(.rowBody).foregroundStyle(.primary).lineLimit(1)
                    if let detail = ReviewText.detail(line) {
                        let late = ReviewText.late(line, thresholds: thresholds)
                        // Late: red (design system v2, 19/11), and said in a word, never by the color alone — « 9 jours ·
                        // en retard » (lot 10, 20/11).
                        Text(late ? detail + " · en retard" : detail).font(.meta)
                            .foregroundStyle(late ? AnyShapeStyle(Tint.late) : AnyShapeStyle(.secondary))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                // The place of the action and its « … », kept at rest, laid over the row so that its highlight runs to the end.
                Color.clear.frame(width: Self.actionsWidth, height: 1)
            }
        }
        .overlay(alignment: .trailing) {
            // At the card's edge, the « … » on its left (lot 5, 19/11).
            HStack(spacing: Space.xs) {
                if !gestures.dismissals.isEmpty {
                    // « Écarter », the gesture of « À valider »; never « ligne », a word of the code (lot 10, 20/11).
                    IconMenu("ellipsis", help: "Écarter") { dismissals(line, gestures.dismissals) }
                }
                action(line)
            }
            .opacity(shown ? 1 : 0)
            .allowsHitTesting(shown)
            .animation(Motion.quick, value: shown)
        }
        .onHover { inside in hovered = inside ? line.id : (hovered == line.id ? nil : hovered) }
        .contextMenu {
            Button(gestures.open) { open(line) }
            if gestures.file { Menu(ReviewText.action(.unfiled)) { fileItems(line) } }
            if !gestures.dismissals.isEmpty {
                Divider()
                dismissals(line, gestures.dismissals)
            }
        }
        .help(ReviewText.title(line))
    }

    private func dismissals(_ line: ReviewRules.Line, _ ways: [ReviewText.Dismissal]) -> some View {
        ForEach(ways) { way in
            Button(way.title) { colin.dismiss(line, reason: way.reason) }
        }
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
                .font(.tag.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .background(Surface.fill, in: Circle())
        } else {
            let project = line.projectID.flatMap { id in agenda.projects.first { $0.id == id } }
            PersonAvatar(initials: PeopleIndex.initials(name: line.person, email: line.person), tint: project.map { PeopleStyle.color(of: $0) } ?? .secondary)
        }
    }

    /// « Relire », « Ouvrir »: the same as a click on the line. « Ranger »: the projects, and « Aucun ». One outline, small,
    /// as every button of a line (lot 5, 19/11).
    @ViewBuilder
    private func action(_ line: ReviewRules.Line) -> some View {
        if line.kind == .unfiled {
            Menu { fileItems(line) } label: { Text(ReviewText.action(line.kind)) }
                .menuStyle(.button)
                .buttonStyle(.secondary)
                .controlSize(.small)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Ranger cette réunion dans un projet")
        } else {
            Button(ReviewText.action(line.kind)) { open(line) }
                .buttonStyle(.secondary)
                .controlSize(.small)
                .fixedSize()
        }
    }

    /// The projects a meeting may be filed in, then « Aucun ».
    @ViewBuilder
    private func fileItems(_ line: ReviewRules.Line) -> some View {
        ForEach(projects) { project in
            Button(project.name) { Task { await colin.file(line, projectID: project.id) } }
        }
        Divider()
        Button("Aucun") { Task { await colin.file(line, projectID: nil) } }
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
