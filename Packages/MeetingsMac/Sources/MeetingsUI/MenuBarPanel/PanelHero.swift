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
                HeroEyebrow("Réunion détectée", systemImage: "record.circle", tint: nil)
                Spacer(minLength: Space.s)
                TimelineView(countdown) { timeline in
                    Text("\(HUDText.remaining(until: deadline, now: timeline.date)) s")
                        .font(HeroMetrics.clock)
                        .contentTransition(reduceMotion ? .identity : .numericText(countsDown: true))
                        .animation(Motion.quick, value: HUDText.remaining(until: deadline, now: timeline.date))
                }
            }
            HeroTitle(title)
            TimelineView(countdown) { timeline in
                HeroDetail("S'enregistre seule dans \(HUDText.remaining(until: deadline, now: timeline.date)) s")
                    .monospacedDigit()
            }
            HStack(spacing: Space.s) {
                Button { actions.user(.decline) } label: { Text("Pas cette fois").frame(maxWidth: .infinity) }
                    .buttonStyle(.secondary)
                    .keyboardShortcut(.delete, modifiers: [])
                    .help("Ne pas enregistrer cette réunion (⌫)")
                Button { actions.user(.accept) } label: {
                    Label("Enregistrer", systemImage: "record.circle").frame(maxWidth: .infinity)
                }
                // The panel's ink, as every main action but Arrêter (design system v2, 19/11).
                .buttonStyle(.primary)
                .keyboardShortcut(.defaultAction)
                .help("Enregistrer maintenant (↩)")
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
                HeroEyebrow("Enregistre", systemImage: "circle.fill", tint: Tint.recording, pulse: true)
                Spacer(minLength: Space.s)
                TimelineView(.periodic(from: since, by: 1)) { timeline in
                    Text(DurationText.clock(Int(timeline.date.timeIntervalSince(since))))
                        .font(HeroMetrics.clock)
                }
            }
            HeroTitle(title)
            if let detail { HeroDetail(detail) }
            HeroButtons {
                if let meetingID {
                    Button("Voir la réunion") { context.open(.meeting(meetingID)) }.buttonStyle(.secondary)
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
            HeroEyebrow("Fin de réunion ?", systemImage: "record.circle", tint: Tint.attention)
            HeroTitle(title)
            HeroDetail(stopsAt.map { "S'arrête seule à \(PanelModel.clock($0)), sauf si l'on reparle" }
                       ?? "S'arrête seule, sauf si l'on reparle", lines: 2)
            HeroButtons {
                if canForget {
                    PanelLink("Jamais pour ce lien", help: "Ne plus jamais enregistrer ce lien Meet") { actions.user(.neverForThisLink) }
                } else if let meetingID {
                    Button("Voir la réunion") { context.open(.meeting(meetingID)) }.buttonStyle(.secondary)
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
                if upcoming.started {
                    HeroEyebrow("En cours · pas enregistrée", systemImage: "exclamationmark.circle.fill", tint: Tint.attention)
                } else {
                    HeroEyebrow(HomeModel.when(event, now: now), systemImage: "calendar", tint: Tint.attention)
                }
                Spacer(minLength: Space.s)
                HStack(spacing: 5) {
                    ColorDot(color, size: 8)
                    Text(AccountStyle.label(for: event.account)).font(.meta).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            HeroTitle(event.title)
            HeroDetail(upcoming.detail)
            if upcoming.pausedThrough {
                HeroWarning("Détection suspendue : elle ne s'enregistrera pas")
            }
            HeroButtons {
                if upcoming.started {
                    Button { actions.user(.recordNow) } label: { Label("Enregistrer", systemImage: "record.circle") }
                        .buttonStyle(.secondary)
                        .disabled(context.app.status != .idle)
                        .help("Enregistrer le son du Mac maintenant")
                } else if event.meetCode != nil {
                    Button("Détails") { context.open(.event(event.id)) }.buttonStyle(.secondary)
                }
            } primary: {
                if event.meetCode != nil {
                    Button { agenda?.join(event) } label: { Label("Rejoindre", systemImage: "video.fill") }
                        .buttonStyle(.primary)
                        .keyboardShortcut(.defaultAction)
                        .help("Ouvrir le Meet dans Dia avec le compte \(event.account) (↩ ou J)")
                } else {
                    Button("Détails") { context.open(.event(event.id)) }
                        .buttonStyle(.secondary)
                        .keyboardShortcut(.defaultAction)
                        .help("Ouvrir le rendez-vous (↩)")
                }
            }
        }
    }

    /// One action, beside the title: the card stays short.
    private func paused(until: Date, missed: CalendarEventRow?) -> some View {
        HeroCard(tint: nil) {
            HeroEyebrow("Détection suspendue", systemImage: "pause.circle.fill", tint: nil)
            HStack(alignment: .center, spacing: Space.m) {
                HeroTitle("Jusqu'à \(PanelModel.clock(until))")
                Spacer(minLength: Space.s)
                // The panel's ink, as every main action but Arrêter, and as the lit round Reprendre under it: one
                // action, one color (design system v2, 19/11).
                Button { actions.resumeDetection() } label: { Label("Reprendre", systemImage: "play.fill") }
                    .buttonStyle(.primary)
                    .controlSize(HeroMetrics.buttons)
                    .keyboardShortcut(.defaultAction)
                    .help("Reprendre la détection (↩)")
            }
            if let missed {
                HeroWarning("« \(missed.title) » à \(PanelModel.clock(missed.startAt)) ne sera pas enregistrée")
            } else {
                HeroDetail("Les réunions ne s'enregistrent pas toutes seules", lines: 2)
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
                HeroEyebrow(eyebrow(report), systemImage: failed ? "exclamationmark.triangle.fill" : report.isPreparing ? "sparkles" : "checkmark.circle.fill",
                            tint: tint, iconOnly: failed)
                Spacer(minLength: Space.s)
                // When it got ready; while it is prepared, the meeting's length.
                if let since = report.since, !report.isPreparing {
                    Text(PanelModel.ago(since, now: now)).font(.meta).foregroundStyle(.secondary).lineLimit(1)
                } else if let seconds = report.seconds {
                    Text(DurationText.short(seconds)).font(.meta).foregroundStyle(.secondary).lineLimit(1)
                }
                // Paul, 16/11: a summary already dealt with goes with a click, for good.
                Button { context.app.putAway(report: report.meetingID) } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.hover(.circle))
                .foregroundStyle(.secondary)
                // Its circle spills into the margins: the line keeps the eyebrow's height.
                .padding(.vertical, -5)
                .padding(.trailing, -Space.xs)
                .help("Ne plus afficher ce compte rendu ici")
                .accessibilityLabel("Ranger ce compte rendu")
            }
            HeroTitle(report.title, lines: 1)
            switch report.stage {
            case .ready(let overview):
                HeroDetail(overview, lines: 2)
            case .transcriptReady(let reason):
                HeroDetail(reason ?? "Pas de résumé pour cette réunion", lines: 2)
            case .transcriptionFailed(let message), .summaryFailed(let message):
                HeroDetail(message, lines: 2)
            default:
                if let progress = report.progress {
                    HeroProgress(value: progress, tint: .secondary).padding(.vertical, 4)
                }
            }
            if report.isPreparing {
                // Where it stands, and the way to the meeting, on one line.
                HStack(alignment: .center, spacing: Space.s) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(report.stageText).font(.meta.weight(.semibold).monospacedDigit()).lineLimit(1)
                        if case .transcribing = report.stage, report.summaryToCome {
                            Text("Puis le résumé").font(.meta).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    // Where it stands, on one line: the button keeps its size, the text takes the rest first.
                    .layoutPriority(1)
                    Spacer(minLength: Space.s)
                    reportAction(report).controlSize(HeroMetrics.buttons)
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

    private func eyebrow(_ report: PanelModel.Report) -> String {
        switch report.stage {
        case .ready: "Résumé prêt"
        case .transcriptReady: "Transcription prête"
        case .transcriptionFailed: "Transcription échouée"
        case .summaryFailed: "Résumé impossible"
        default: "Compte rendu en cours"
        }
    }

    @ViewBuilder
    private func reportAction(_ report: PanelModel.Report) -> some View {
        let open = { context.open(.meeting(report.meetingID)) }
        // The panel's ink, as every main action but Arrêter (design system v2, 19/11).
        switch report.stage {
        case .ready:
            Button("Lire le compte rendu", action: open)
                .buttonStyle(.primary)
                .keyboardShortcut(.defaultAction).help("Ouvrir la réunion sur son compte rendu (↩)")
        case .transcriptReady:
            Button("Lire la transcription", action: open)
                .buttonStyle(.primary)
                .keyboardShortcut(.defaultAction).help("Ouvrir la réunion (↩)")
        case .transcriptionFailed:
            if let queue = library?.queue {
                Button { Task { await queue.retry(meetingID: report.meetingID) } } label: { Label("Réessayer", systemImage: "arrow.clockwise") }
                    .buttonStyle(.primary)
                    .keyboardShortcut(.defaultAction).help("Relancer la transcription (↩)")
            } else {
                Button("Ouvrir la réunion", action: open).buttonStyle(.secondary).keyboardShortcut(.defaultAction)
            }
        default:
            Button("Ouvrir la réunion", action: open)
                .buttonStyle(.secondary)
                .keyboardShortcut(.defaultAction).help("Ouvrir la réunion (↩)")
        }
    }

    // MARK: - The day

    /// Nothing else to say: the day, calm; a click opens Accueil.
    private func day(title: String, line: String?) -> some View {
        Button { context.openHome() } label: {
            HStack(alignment: .center, spacing: Space.m) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(title.uppercased())
                        .font(.meta.weight(.semibold))
                        .tracking(0.3)
                        .foregroundStyle(.secondary)
                    HeroTitle(line ?? (context.app.isWatching ? "Polhub guette les réunions" : "La détection est coupée"))
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(Space.l)
            .frame(maxWidth: .infinity, minHeight: HeroMetrics.minHeight, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .background(PanelSurface.card, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        }
        .buttonStyle(PanelCardStyle(radius: Radius.card))
        .help(context.agenda != nil ? "Ouvrir l'Accueil" + (SidebarItem.home.shortcut.map { " (⌘\($0))" } ?? "") : "Ouvrir Polhub")
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
    /// The buttons' gap to the text, besides the card's spacing (4 points): none, the glass of a button draws its own
    /// margin.
    static let aboveButtons: CGFloat = 0
    /// The card's padding: 16 on the sides, 12 above, 10 below, where a button's glass draws its own margin.
    static let padding = EdgeInsets(top: Space.m, leading: Space.l, bottom: 10, trailing: Space.l)
    /// The brief's floor: the day, alone in its card, is not shorter than the others.
    static let minHeight: CGFloat = 90
}

/// The hero's card: its color at 10 % (16 % in dark), a firmer edge of it; without a color (`tint` nil), the panel's
/// calm card (`PanelSurface`), as the tiles and the mails (design system v2, 19/11). Radius 16 (`Radius.card`). No
/// glass under its text. From 90 to 130 points tall, as the brief wants, so the grid under it moves little from one
/// state to the next: a little less padding above and below than on the sides, buttons of the regular size. One
/// exception: « Réunion détectée » with a Meet link, the five lines of the brief's mockup, for its ten seconds.
private struct HeroCard<Content: View>: View {
    /// `Tint.recording` or `Tint.attention`; nil, neutral.
    let tint: Color?
    let content: Content
    @Environment(\.colorScheme) private var scheme

    init(tint: Color?, @ViewBuilder content: () -> Content) {
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        let dark = scheme == .dark
        VStack(alignment: .leading, spacing: Space.xs) { content }
            .padding(HeroMetrics.padding)
            .frame(maxWidth: .infinity, minHeight: HeroMetrics.minHeight, alignment: .topLeading)
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
        .accessibilityValue("\(Int((value * 100).rounded())) %")
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

/// « DANS 8 MIN », « ENREGISTRE »: the hero's first line, in its color (a `Tint`, already one text reads in), grey
/// without one. A problem colors its icon only (`iconOnly`), never its words (design system v2, 19/11).
private struct HeroEyebrow: View {
    let text: String
    let systemImage: String
    let tint: Color?
    var iconOnly = false
    var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(_ text: String, systemImage: String, tint: Color?, iconOnly: Bool = false, pulse: Bool = false) {
        self.text = text
        self.systemImage = systemImage
        self.tint = tint
        self.iconOnly = iconOnly
        self.pulse = pulse
    }

    var body: some View {
        let colored = tint.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.secondary)
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .bold))
                .symbolEffect(.pulse, isActive: pulse && !reduceMotion)
                .foregroundStyle(colored)
            Text(text.uppercased()).tracking(0.3).lineLimit(1)
                .foregroundStyle(iconOnly ? AnyShapeStyle(.secondary) : colored)
        }
        .font(.meta.weight(.semibold))
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

/// The hero's buttons, on the right: the second action, then the main one.
private struct HeroButtons<Secondary: View, Primary: View>: View {
    let secondary: Secondary
    let primary: Primary

    init(@ViewBuilder secondary: () -> Secondary, @ViewBuilder primary: () -> Primary) {
        self.secondary = secondary()
        self.primary = primary()
    }

    var body: some View {
        HStack(spacing: Space.s) {
            secondary
            Spacer(minLength: Space.s)
            primary
        }
        .controlSize(HeroMetrics.buttons)
        .padding(.top, HeroMetrics.aboveButtons)
    }
}
