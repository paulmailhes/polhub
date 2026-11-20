import Agenda
import Persistence
import PolhubDesign
import SwiftUI

/// The hero of « Coup d'œil » (15/11): a large calm card that says what matters now and offers one main action
/// (`.primary`, ↩, Polhub's ink), sometimes a second (`.secondary`). It is tinted only while a meeting records
/// (`Tint.recording`) or when something asks for a look (`Tint.attention`), neutral otherwise (design system v2, 19/11:
/// one color, one meaning). It changes with a fade. The countdown and the recording's clock tick in their own
/// timeline; the rest follows the panel's, every 30 s.
struct PanelHero: View {
    let hero: PanelModel.Hero
    let now: Date
    let context: CoupDoeilContext
    let agenda: AgendaLibrary?
    let library: MeetingLibrary?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var actions: CoupDoeilActions { context.actions }

    var body: some View {
        ZStack {
            content
                .id(hero.kind)
                .transition(.opacity)
        }
        .animation(Motion.gentle, value: hero.kind)
    }

    @ViewBuilder
    private var content: some View {
        switch hero {
        case .detected(let title, let deadline, let canForget): detected(title: title, deadline: deadline, canForget: canForget)
        case .recording(let title, let since, let detail, let meetingID): recording(title: title, since: since, detail: detail, meetingID: meetingID)
        case .presumedEnded(let title, let stopsAt, let meetingID, let canForget):
            presumedEnded(title: title, stopsAt: stopsAt, meetingID: meetingID, canForget: canForget)
        case .upcoming(let upcoming): self.upcoming(upcoming)
        case .paused(let until, let missed): paused(until: until, missed: missed)
        case .report(let report): self.report(report)
        case .day(let title, let line): day(title: title, line: line)
        }
    }

    // MARK: - The meeting

    /// The hero's first line, in its own case (lot 9, 20/11).
    private var eyebrow: HeroEyebrow {
        HeroEyebrow(PanelModel.eyebrow(hero, now: now))
    }

    /// The HUD's question, here too, with the same countdown: both answers go through the coordinator, so the HUD
    /// and the panel close together. As the brief's mockup: what happens at the end of the countdown under the title,
    /// the two answers, then « Jamais pour ce lien » under them, only for a Meet link.
    private func detected(title: String, deadline: Date, canForget: Bool) -> some View {
        // Aligned on the deadline, so both turn with the HUD's.
        let countdown = PeriodicTimelineSchedule(from: deadline.addingTimeInterval(-60), by: 1)
        // Neutral, as the logo's outlined circle: nothing records yet, the red starts with the recording (design
        // system v2, 19/11).
        return HeroCard(tint: nil) {
            HStack(alignment: .firstTextBaseline) {
                eyebrow
                Spacer(minLength: Space.s)
                TimelineView(countdown) { timeline in
                    // « 7 s » (`Words.preciseDuration`, lot 10, 20/11).
                    Text(Words.preciseDuration(HUDText.remaining(until: deadline, now: timeline.date)))
                        .font(HeroMetrics.clock)
                        .contentTransition(reduceMotion ? .identity : .numericText(countsDown: true))
                        .animation(Motion.quick, value: HUDText.remaining(until: deadline, now: timeline.date))
                }
            }
            HeroTitle(title)
            TimelineView(countdown) { timeline in
                // The HUD's own words, from one place (`HUDText.countdown`, lot 10, 20/11).
                HeroDetail(HUDText.countdown(HUDText.remaining(until: deadline, now: timeline.date)))
                    .monospacedDigit()
            }
            HStack(spacing: Space.s) {
                Button { actions.user(.decline) } label: { Text("Ne pas enregistrer").frame(maxWidth: .infinity) }
                    .buttonStyle(.secondary)
                    .keyboardShortcut(.delete, modifiers: [])
                    // « Verbe + objet (raccourci) », by `Words.help` (lot 10, 20/11).
                    .help(Words.help("Ne pas enregistrer cette réunion", .delete))
                Button { actions.user(.accept) } label: {
                    Label("Enregistrer", systemImage: "record.circle").frame(maxWidth: .infinity)
                }
                // The panel's ink, as every main action but Arrêter (design system v2, 19/11).
                .buttonStyle(.primary)
                .keyboardShortcut(.defaultAction)
                .help(Words.help("Enregistrer maintenant", .return))
            }
            .controlSize(HeroMetrics.buttons)
            .padding(.top, HeroMetrics.aboveButtons)
            if canForget {
                PanelLink("Jamais pour ce lien", help: "Ne plus jamais enregistrer ce lien Meet") { actions.user(.neverForThisLink) }
                    // Its capsule spills into the gaps: the line costs only its text.
                    .padding(.vertical, -2)
            }
        }
    }

    /// The recording's red (`Tint.recording`), the panel's only red with « Arrêter »: voices are recorded. Arrêter is a
    /// click, never a key.
    private func recording(title: String, since: Date, detail: String?, meetingID: UUID?) -> some View {
        HeroCard(tint: Tint.recording) {
            HStack(alignment: .firstTextBaseline) {
                eyebrow.pulsing()
                Spacer(minLength: Space.s)
                TimelineView(.periodic(from: since, by: 1)) { timeline in
                    // « 12:47 » (`Words.clock`, lot 10, 20/11).
                    Text(Words.clock(Int(timeline.date.timeIntervalSince(since))))
                        .font(HeroMetrics.clock)
                }
            }
            HeroTitle(title)
            if let detail { HeroDetail(detail) }
            HeroButtons {
                if let meetingID {
                    // « Ouvrir » goes to a thing; « Voir » unfolds in place (lot 10, 20/11).
                    Button("Ouvrir la réunion") { context.open(.meeting(meetingID)) }.buttonStyle(.secondary)
                }
            } primary: {
                Button { actions.user(.stop) } label: { Label("Arrêter", systemImage: "stop.fill") }
                    .buttonStyle(.primary(.recording))
                    .help("Arrêter l'enregistrement")
            }
        }
    }

    /// It still records, and asks for a look: attention's orange (`Tint.attention`, design system v2, 19/11).
    private func presumedEnded(title: String, stopsAt: Date?, meetingID: UUID?, canForget: Bool) -> some View {
        HeroCard(tint: Tint.attention) {
            eyebrow
            HeroTitle(title)
            // « 16:30 » (`Words.time`, lot 10, 20/11).
            HeroDetail(stopsAt.map { "S'arrête seule à \(Words.time($0)), sauf si l'on reparle" }
                       ?? "S'arrête seule, sauf si l'on reparle", lines: 2)
            HeroButtons {
                if canForget {
                    PanelLink("Jamais pour ce lien", help: "Ne plus jamais enregistrer ce lien Meet") { actions.user(.neverForThisLink) }
                } else if let meetingID {
                    // « Ouvrir » goes to a thing (lot 10, 20/11: « Voir la réunion »).
                    Button("Ouvrir la réunion") { context.open(.meeting(meetingID)) }.buttonStyle(.secondary)
                }
            } primary: {
                Button { actions.user(.stop) } label: { Label("Arrêter maintenant", systemImage: "stop.fill") }
                    .buttonStyle(.primary(.recording))
                    .help("Arrêter l'enregistrement")
            }
        }
    }

    // MARK: - The calendar

    /// « Rejoindre » opens the Meet in Dia under the event's account (↩ or J). The account is in its dot, never on the
    /// card nor on the button, which is ink (design system v2, 19/11): a red or orange account read as an alert.
    /// Attention's orange says « dans N min », and tints the card once the Meet started without being recorded.
    private func upcoming(_ upcoming: PanelModel.Upcoming) -> some View {
        let event = upcoming.event
        let color = agenda?.color(for: event.account) ?? Color.secondary
        return HeroCard(tint: upcoming.started ? Tint.attention : nil) {
            HStack(alignment: .firstTextBaseline) {
                eyebrow
                Spacer(minLength: Space.s)
                HStack(spacing: Space.xs) {
                    ColorDot(color, size: 8)
                    Text(AccountStyle.label(for: event.account)).font(.meta).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            HeroTitle(event.title)
            HeroDetail(upcoming.detail)
            if upcoming.pausedThrough {
                // A sentence, its period (lot 10, 20/11).
                HeroWarning("Détection suspendue : elle ne s'enregistrera pas.")
            }
            HeroButtons {
                if upcoming.started {
                    Button { actions.user(.recordNow) } label: { Label("Enregistrer", systemImage: "record.circle") }
                        .buttonStyle(.secondary)
                        .disabled(context.app.status != .idle)
                        .help("Enregistrer le son du Mac maintenant")
                } else if event.meetCode != nil {
                    // A verb and its object, never « Détails » (lot 10, 20/11).
                    Button("Ouvrir le rendez-vous") { context.open(.event(event.id)) }.buttonStyle(.secondary)
                }
            } primary: {
                if event.meetCode != nil {
                    Button { agenda?.join(event) } label: { Label("Rejoindre", systemImage: "video.fill") }
                        .buttonStyle(.primary)
                        .keyboardShortcut(.defaultAction)
                        // « Rejoindre dans Dia avec le compte Pro (↩ ou J) »: the account's label, never its address (lot 10, 20/11).
                        .help(Words.help(Words.joinHelp(account: AccountStyle.label(for: event.account)), .return, .key("J")))
                } else {
                    Button("Ouvrir le rendez-vous") { context.open(.event(event.id)) }
                        .buttonStyle(.secondary)
                        .keyboardShortcut(.defaultAction)
                        .help(Words.help("Ouvrir le rendez-vous", .return))
                }
            }
        }
    }

    /// One action, beside the title: the card stays short.
    private func paused(until: Date, missed: CalendarEventRow?) -> some View {
        HeroCard(tint: nil) {
            eyebrow
            HStack(alignment: .center, spacing: Space.m) {
                // « 16:30 » (`Words.time`, lot 10, 20/11).
                HeroTitle("Jusqu'à \(Words.time(until))")
                Spacer(minLength: Space.s)
                // The panel's ink, as every main action but Arrêter, and as the lit round Reprendre under it: one
                // action, one color (design system v2, 19/11).
                Button { actions.resumeDetection() } label: { Label("Reprendre", systemImage: "play.fill") }
                    .buttonStyle(.primary)
                    .controlSize(HeroMetrics.buttons)
                    .fixedSize()
                    .keyboardShortcut(.defaultAction)
                    .help(Words.help("Reprendre la détection", .return))
            }
            // Sentences, their period (lot 10, 20/11).
            if let missed {
                HeroWarning("« \(missed.title) » à \(Words.time(missed.startAt)) ne sera pas enregistrée.")
            } else {
                HeroDetail("Les réunions ne s'enregistrent pas toutes seules.", lines: 2)
            }
        }
    }

    // MARK: - The summary

    private func report(_ report: PanelModel.Report) -> some View {
        let failed: Bool = switch report.stage {
        case .transcriptionFailed, .summaryFailed: true
        default: false
        }
        // A failure asks for a look (`Tint.attention`); a summary on its way or ready is neutral: the violet said
        // nothing (design system v2, 19/11).
        let tint: Color? = failed ? Tint.attention : nil
        return HeroCard(tint: tint) {
            HStack(alignment: .firstTextBaseline) {
                // A failure colors its icon only: never a colored sentence.
                eyebrow
                Spacer(minLength: Space.s)
                // When it got ready; while it is prepared, the meeting's length.
                if let since = report.since, !report.isPreparing {
                    Text(PanelModel.ago(since, now: now)).font(.meta).foregroundStyle(.secondary).lineLimit(1)
                } else if let seconds = report.seconds {
                    // « 38 min », « 1 h 05 », « 2 h » (`Words.duration`, lot 10, 20/11).
                    Text(Words.duration(seconds)).font(.meta).foregroundStyle(.secondary).lineLimit(1)
                }
                // Paul, 16/11: a summary already dealt with goes with a click, for good. The app's discreet button (lot 9,
                // 20/11); its circle spills into the margins, the line keeps the eyebrow's height.
                IconButton("xmark", help: "Ne plus afficher ce compte rendu ici", size: 13) { context.app.putAway(report: report.meetingID) }
                    .padding(.vertical, -Space.s)
                    .padding(.trailing, -Space.s)
            }
            HeroTitle(report.title, lines: 1)
            switch report.stage {
            case .ready(let overview):
                HeroDetail(overview, lines: 2)
            case .transcriptReady(let reason):
                HeroDetail(reason ?? "Pas de compte rendu pour cette réunion", lines: 2)
            // Polhub's sentence, then what to do (`Words.problem`, lot 10, 20/11): the text a job kept may be the system's,
            // it never shows.
            case .transcriptionFailed:
                HeroDetail(Words.problem("La transcription a échoué").sentence, lines: 2)
            case .summaryFailed:
                HeroDetail(Words.problem("Le compte rendu n'a pas pu se faire", remedy: "Refais-le depuis la réunion.").sentence, lines: 2)
            default:
                if let progress = report.progress {
                    HeroProgress(value: progress, tint: .secondary).padding(.vertical, 4)
                }
            }
            if report.isPreparing {
                // Where it stands, and the way to the meeting, on one line; short of room, the button goes under it, on
                // the right, as every bar of buttons (lot 9, 20/11: « Ouvrir la réunion » broke on two lines beside
                // « Transcription en attente »). Neither is ever squeezed.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: Space.s) {
                        stage(report).fixedSize()
                        Spacer(minLength: Space.s)
                        reportAction(report).controlSize(HeroMetrics.buttons).fixedSize()
                    }
                    VStack(alignment: .trailing, spacing: Space.s) {
                        stage(report).frame(maxWidth: .infinity, alignment: .leading)
                        reportAction(report).controlSize(HeroMetrics.buttons).fixedSize()
                    }
                }
                .padding(.top, 2)
            } else {
                HeroButtons {
                    if case .transcriptionFailed = report.stage, library?.queue != nil {
                        Button("Ouvrir la réunion") { context.open(.meeting(report.meetingID)) }.buttonStyle(.secondary)
                    }
                } primary: {
                    reportAction(report)
                }
            }
        }
    }

    /// Where a summary on its way stands: « Transcription 58 % », and « Puis le compte rendu » under it (lot 10, 20/11:
    /// « Puis le résumé »).
    private func stage(_ report: PanelModel.Report) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            // French typography: « Compte rendu : partie 2 sur 3 », « 58 % » (`Words.typeset`, lot 10, 20/11).
            Text(Words.typeset(report.stageText)).font(.meta.weight(.semibold).monospacedDigit()).lineLimit(1)
            if case .transcribing = report.stage, report.summaryToCome {
                Text("Puis le compte rendu").font(.meta).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }

    /// « Ouvrir » goes to a thing (lot 10, 20/11: « Lire le compte rendu », « Lire la transcription »); its bubble, the same
    /// words and the key, by `Words.help`.
    @ViewBuilder
    private func reportAction(_ report: PanelModel.Report) -> some View {
        let open = { context.open(.meeting(report.meetingID)) }
        // The panel's ink, as every main action but Arrêter (design system v2, 19/11).
        switch report.stage {
        case .ready:
            Button("Ouvrir le compte rendu", action: open)
                .buttonStyle(.primary)
                .keyboardShortcut(.defaultAction).help(Words.help("Ouvrir le compte rendu", .return))
        case .transcriptReady:
            Button("Ouvrir la transcription", action: open)
                .buttonStyle(.primary)
                .keyboardShortcut(.defaultAction).help(Words.help("Ouvrir la transcription", .return))
        case .transcriptionFailed:
            if let queue = library?.queue {
                Button { Task { await queue.retry(meetingID: report.meetingID) } } label: { Label("Réessayer", systemImage: "arrow.clockwise") }
                    .buttonStyle(.primary)
                    .keyboardShortcut(.defaultAction).help(Words.help("Réessayer la transcription", .return))
            } else {
                Button("Ouvrir la réunion", action: open).buttonStyle(.secondary)
                    .keyboardShortcut(.defaultAction).help(Words.help("Ouvrir la réunion", .return))
            }
        default:
            Button("Ouvrir la réunion", action: open)
                .buttonStyle(.secondary)
                .keyboardShortcut(.defaultAction).help(Words.help("Ouvrir la réunion", .return))
        }
    }

    // MARK: - The day

    /// Nothing else to say: the day, calm. A card to read, as the others (lot 9, 20/11): « Ouvrir Polhub », at the foot,
    /// is the one way to the Accueil; the day's chevron was a second.
    private func day(title: String, line: String?) -> some View {
        HeroCard(tint: nil, centered: true) {
            eyebrow
            // The detection is active or suspended, never « coupée » (lot 10, 20/11).
            HeroTitle(line ?? (context.app.isWatching ? "Polhub guette les réunions" : "La détection est suspendue"))
        }
    }
}

// MARK: - The hero's pieces

/// The hero's sizes. Its text is larger than the brief's `.title3` / `.title2`, which are 15 and 17 points on macOS: the hero's
/// title would be no larger than a tile's value.
enum HeroMetrics {
    /// 17 points (`.title2` on macOS).
    static let title = Font.title2.weight(.semibold)
    /// 22 points with fixed digits (`.title` on macOS): the recording's clock, the countdown.
    static let clock = Font.title.weight(.semibold).monospacedDigit()
    /// The buttons' size: the regular one, the large took the hero past 130 points (finding of 16/11).
    static let buttons = ControlSize.regular
    /// The buttons' gap to the text, besides the card's spacing (4 points): 8 in all (lot 9, 20/11: the buttons, no longer
    /// in glass, touched the text).
    static let aboveButtons: CGFloat = Space.xs
    /// The card's padding: 16 on every side (lot 9, 20/11: 12 above and 10 below, the bottom button 9 points from the
    /// edge).
    static let padding = EdgeInsets(top: Space.l, leading: Space.l, bottom: Space.l, trailing: Space.l)
    /// The brief's floor: the day, alone in its card, is not shorter than the others.
    static let minHeight: CGFloat = 90
}

/// The hero's card: its color at 10 % (16 % in dark), a firmer edge of it; without a color (`tint` nil), the panel's
/// calm card (`PanelSurface`), as the tiles and the mails (design system v2, 19/11). Radius 16 (`Radius.card`), 16 of
/// padding on every side (lot 9, 20/11). No glass under its text. From 90 to 145 points tall, so the grid under it moves
/// little from one state to the next: buttons of the regular size. One exception: « Réunion détectée » with a Meet
/// link, the five lines of the brief's mockup, for its ten seconds.
private struct HeroCard<Content: View>: View {
    /// `Tint.recording` or `Tint.attention`; nil, neutral.
    let tint: Color?
    /// The day's two lines sit in the middle of the card's least height, not at its top (lot 9, 20/11).
    var centered = false
    let content: Content
    @Environment(\.colorScheme) private var scheme

    init(tint: Color?, centered: Bool = false, @ViewBuilder content: () -> Content) {
        self.tint = tint
        self.centered = centered
        self.content = content()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        let dark = scheme == .dark
        VStack(alignment: .leading, spacing: Space.xs) { content }
            .padding(HeroMetrics.padding)
            .frame(maxWidth: .infinity, minHeight: HeroMetrics.minHeight, alignment: centered ? .leading : .topLeading)
            // Never squeezed under its content: short of room, its buttons spilled over the tiles (16/11).
            .fixedSize(horizontal: false, vertical: true)
            .background(tint.map { PanelTint.fill($0, dark: dark) } ?? PanelSurface.card, in: shape)
            .overlay(shape.strokeBorder(tint.map { PanelTint.edge($0, dark: dark) } ?? PanelSurface.edge))
    }
}

/// The transcription's or the summary's progress: a thin bar in `tint`, grey in the hero (design system v2, 19/11: the
/// violet said nothing); it moves smoothly, without a jump.
private struct HeroProgress: View {
    let value: Double
    let tint: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.1))
                Capsule().fill(tint).frame(width: max(6, geometry.size.width * min(1, max(0, value))))
            }
        }
        .frame(height: 6)
        .animation(Motion.standard, value: value)
        .accessibilityElement()
        .accessibilityLabel("Avancement")
        // « 58 % » (`Words.percent`, lot 10, 20/11).
        .accessibilityValue(Words.percent(value))
    }
}

/// What will go wrong if nothing is done: a problem in one line (`ErrorLine`, design system v2, 19/11), its icon in
/// attention's orange, its sentence in the text's color, never a colored sentence.
private struct HeroWarning: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        ErrorLine(text)
            .font(.meta.weight(.medium))
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// « Dans 8 min », « Enregistrement »: the hero's first line (lot 9, 20/11), a grey label of 12 points in its own case,
/// as « En retard » on the Accueil (« DANS 8 MIN » in capitals of 13 before). One thing of it takes its color (a `Tint`,
/// already one text reads in), never the whole line: the symbol of a state, or the words of a delay.
private struct HeroEyebrow: View {
    let eyebrow: PanelModel.Eyebrow
    var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(_ eyebrow: PanelModel.Eyebrow) {
        self.eyebrow = eyebrow
    }

    /// The recording's dot beats.
    func pulsing() -> HeroEyebrow {
        var copy = self
        copy.pulse = true
        return copy
    }

    var body: some View {
        let tint = eyebrow.tint.map { AnyShapeStyle($0.color) } ?? AnyShapeStyle(.secondary)
        HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
            if let systemImage = eyebrow.systemImage {
                Image(systemName: systemImage)
                    .symbolEffect(.pulse, isActive: pulse && !reduceMotion)
                    .foregroundStyle(eyebrow.colored == .symbol ? tint : AnyShapeStyle(.secondary))
            }
            // French typography: « Fin de réunion ? » never breaks before its « ? » (`Words.typeset`, lot 10, 20/11).
            Text(Words.typeset(eyebrow.text))
                .lineLimit(1)
                .foregroundStyle(eyebrow.colored == .words ? tint : AnyShapeStyle(.secondary))
        }
        .font(.tag.weight(.semibold))
    }
}

private struct HeroTitle: View {
    let text: String
    var lines = 2

    init(_ text: String, lines: Int = 2) {
        self.text = text
        self.lines = lines
    }

    var body: some View {
        Text(text)
            .font(HeroMetrics.title)
            .lineLimit(lines)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct HeroDetail: View {
    let text: String
    var lines = 1

    init(_ text: String, lines: Int = 1) {
        self.text = text
        self.lines = lines
    }

    var body: some View {
        Text(text)
            .font(.rowBody)
            .foregroundStyle(.secondary)
            .lineLimit(lines)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The hero's buttons, together on the right: the second action, then the main one, as a dialog of macOS (lot 9, 20/11:
/// « Détails » sat alone on the left).
private struct HeroButtons<Secondary: View, Primary: View>: View {
    let secondary: Secondary
    let primary: Primary

    init(@ViewBuilder secondary: () -> Secondary, @ViewBuilder primary: () -> Primary) {
        self.secondary = secondary()
        self.primary = primary()
    }

    var body: some View {
        HStack(spacing: Space.s) {
            Spacer(minLength: 0)
            // Each at its own width: the stack shared the row evenly and broke « Arrêter maintenant » on two lines
            // beside « Jamais pour ce lien », with room for both (lot 9, 20/11).
            secondary.fixedSize()
            primary.fixedSize()
        }
        .controlSize(HeroMetrics.buttons)
        .padding(.top, HeroMetrics.aboveButtons)
    }
}
