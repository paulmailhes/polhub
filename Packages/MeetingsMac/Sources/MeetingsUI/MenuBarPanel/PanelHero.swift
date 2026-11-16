import Agenda
import Persistence
import PolhubDesign
import SwiftUI

/// The hero of « Coup d'œil » (15/11): a large calm card, tinted with what it speaks of, that says what matters now and
/// offers one main action (`.glassProminent`, ↩), sometimes a second (`.glass`). It changes with a fade. The
/// countdown and the recording's clock tick in their own timeline; the rest follows the panel's, every 30 s.
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
        return HeroCard(tint: PanelTint.red) {
            HStack(alignment: .firstTextBaseline) {
                HeroEyebrow("Réunion détectée", systemImage: "record.circle", tint: PanelTint.red)
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
                    .buttonStyle(.glass)
                    .keyboardShortcut(.delete, modifiers: [])
                    .help("Ne pas enregistrer cette réunion (⌫)")
                Button { actions.user(.accept) } label: {
                    Label("Enregistrer", systemImage: "record.circle").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .tint(PanelTint.red)
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

    /// Red, the only red of the panel with the round button: voices are recorded. Arrêter is a click, never a key.
    private func recording(title: String, since: Date, detail: String?, meetingID: UUID?) -> some View {
        HeroCard(tint: PanelTint.red) {
            HStack(alignment: .firstTextBaseline) {
                HeroEyebrow("Enregistre", systemImage: "circle.fill", tint: PanelTint.red, pulse: true)
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
                    Button("Voir la réunion") { context.open(.meeting(meetingID)) }.buttonStyle(.glass)
                }
            } primary: {
                Button { actions.user(.stop) } label: { Label("Arrêter", systemImage: "stop.fill") }
                    .buttonStyle(.glassProminent)
                    .tint(PanelTint.red)
                    .help("Arrêter l'enregistrement")
            }
        }
    }

    private func presumedEnded(title: String, stopsAt: Date?, meetingID: UUID?, canForget: Bool) -> some View {
        HeroCard(tint: PanelTint.orange) {
            HeroEyebrow("Fin de réunion ?", systemImage: "record.circle", tint: PanelTint.orange)
            HeroTitle(title)
            HeroDetail(stopsAt.map { "S'arrête seule à \(PanelModel.clock($0)), sauf si l'on reparle" }
                       ?? "S'arrête seule, sauf si l'on reparle", lines: 2)
            HeroButtons {
                if canForget {
                    PanelLink("Jamais pour ce lien", help: "Ne plus jamais enregistrer ce lien Meet") { actions.user(.neverForThisLink) }
                } else if let meetingID {
                    Button("Voir la réunion") { context.open(.meeting(meetingID)) }.buttonStyle(.glass)
                }
            } primary: {
                Button { actions.user(.stop) } label: { Label("Arrêter maintenant", systemImage: "stop.fill") }
                    .buttonStyle(.glassProminent)
                    .tint(PanelTint.red)
                    .help("Arrêter l'enregistrement")
            }
        }
    }

    // MARK: - The calendar

    /// In the account's color: « Rejoindre » opens the Meet in Dia under that account (↩ or J).
    private func upcoming(_ upcoming: PanelModel.Upcoming) -> some View {
        let event = upcoming.event
        let color = agenda?.color(for: event.account) ?? PanelTint.gray
        return HeroCard(tint: upcoming.started ? PanelTint.orange : color) {
            HStack(alignment: .firstTextBaseline) {
                if upcoming.started {
                    HeroEyebrow("En cours · pas enregistrée", systemImage: "exclamationmark.circle.fill", tint: PanelTint.orange)
                } else {
                    HeroEyebrow(HomeModel.when(event, now: now), systemImage: "calendar", tint: color)
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
                        .buttonStyle(.glass)
                        .disabled(context.app.status != .idle)
                        .help("Enregistrer le son du Mac maintenant")
                } else if event.meetCode != nil {
                    Button("Détails") { context.open(.event(event.id)) }.buttonStyle(.glass)
                }
            } primary: {
                if event.meetCode != nil {
                    Button { agenda?.join(event) } label: { Label("Rejoindre", systemImage: "video.fill") }
                        .buttonStyle(.glassProminent)
                        .tint(color)
                        .keyboardShortcut(.defaultAction)
                        .help("Ouvrir le Meet dans Dia avec le compte \(event.account) (↩ ou J)")
                } else {
                    Button("Détails") { context.open(.event(event.id)) }
                        .buttonStyle(.glass)
                        .keyboardShortcut(.defaultAction)
                        .help("Ouvrir le rendez-vous (↩)")
                }
            }
        }
    }

    /// One action, beside the title: the card stays short.
    private func paused(until: Date, missed: CalendarEventRow?) -> some View {
        HeroCard(tint: PanelTint.gray) {
            HeroEyebrow("Détection suspendue", systemImage: "pause.circle.fill", tint: PanelTint.gray)
            HStack(alignment: .center, spacing: Space.m) {
                HeroTitle("Jusqu'à \(PanelModel.clock(until))")
                Spacer(minLength: Space.s)
                // Orange, as the lit round Reprendre under it: one action, one color, whatever the Mac's accent.
                Button { actions.resumeDetection() } label: { Label("Reprendre", systemImage: "play.fill") }
                    .buttonStyle(.glassProminent)
                    .tint(PanelTint.orange)
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
        let tint = failed ? PanelTint.orange : PanelTint.violet
        return HeroCard(tint: tint) {
            HStack(alignment: .firstTextBaseline) {
                HeroEyebrow(eyebrow(report), systemImage: failed ? "exclamationmark.triangle.fill" : report.isPreparing ? "sparkles" : "checkmark.circle.fill",
                            tint: tint)
                Spacer(minLength: Space.s)
                // When it got ready; while it is prepared, the meeting's length.
                if let since = report.since, !report.isPreparing {
                    Text(PanelModel.ago(since, now: now)).font(.meta).foregroundStyle(.secondary).lineLimit(1)
                } else if let seconds = report.seconds {
                    Text(DurationText.short(seconds)).font(.meta).foregroundStyle(.secondary).lineLimit(1)
                }
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
                    HeroProgress(value: progress, tint: PanelTint.violet).padding(.vertical, 4)
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
                        Button("Ouvrir la réunion") { context.open(.meeting(report.meetingID)) }.buttonStyle(.glass)
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
        default: "Compte rendu en préparation"
        }
    }

    @ViewBuilder
    private func reportAction(_ report: PanelModel.Report) -> some View {
        let open = { context.open(.meeting(report.meetingID)) }
        switch report.stage {
        case .ready:
            Button("Lire le compte rendu", action: open)
                .buttonStyle(.glassProminent).tint(PanelTint.violet)
                .keyboardShortcut(.defaultAction).help("Ouvrir la réunion sur son compte rendu (↩)")
        case .transcriptReady:
            Button("Lire la transcription", action: open)
                .buttonStyle(.glassProminent).tint(PanelTint.violet)
                .keyboardShortcut(.defaultAction).help("Ouvrir la réunion (↩)")
        case .transcriptionFailed:
            if let queue = library?.queue {
                Button { Task { await queue.retry(meetingID: report.meetingID) } } label: { Label("Réessayer", systemImage: "arrow.clockwise") }
                    .buttonStyle(.glassProminent).tint(PanelTint.orange)
                    .keyboardShortcut(.defaultAction).help("Relancer la transcription (↩)")
            } else {
                Button("Ouvrir la réunion", action: open).buttonStyle(.glass).keyboardShortcut(.defaultAction)
            }
        default:
            Button("Ouvrir la réunion", action: open)
                .buttonStyle(.glass)
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
            .background(PanelSurface.card, in: RoundedRectangle(cornerRadius: Radius.hero, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Radius.hero, style: .continuous))
        }
        .buttonStyle(PanelCardStyle(radius: Radius.hero))
        .help(context.agenda != nil ? "Ouvrir l'Accueil (⌘1)" : "Ouvrir Polhub")
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

/// The hero's card: its color at 10 % (16 % in dark), a firmer edge of it, radius 22. No glass under its text. From
/// 90 to 130 points tall, as the brief wants, so the grid under it moves little from one state to the next: a little
/// less padding above and below than on the sides, buttons of the regular size. One exception: « Réunion détectée »
/// with a Meet link, the five lines of the brief's mockup, for its ten seconds.
private struct HeroCard<Content: View>: View {
    let tint: Color
    let content: Content
    @Environment(\.colorScheme) private var scheme

    init(tint: Color, @ViewBuilder content: () -> Content) {
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.hero, style: .continuous)
        VStack(alignment: .leading, spacing: Space.xs) { content }
            .padding(HeroMetrics.padding)
            .frame(maxWidth: .infinity, minHeight: HeroMetrics.minHeight, alignment: .topLeading)
            // Never squeezed under its content: short of room, its buttons spilled over the tiles (16/11).
            .fixedSize(horizontal: false, vertical: true)
            .background(PanelTint.fill(tint, dark: scheme == .dark), in: shape)
            .overlay(shape.strokeBorder(PanelTint.edge(tint, dark: scheme == .dark)))
    }
}

/// The transcription's or the summary's progress: a thin bar in the hero's color, whatever the Mac's accent; it
/// moves smoothly, without a jump.
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

/// What will go wrong if nothing is done: in orange, a shade that reads.
private struct HeroWarning: View {
    let text: String
    @Environment(\.self) private var environment

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Label(text, systemImage: "exclamationmark.circle.fill")
            .font(.meta.weight(.medium))
            .foregroundStyle(PanelTint.orange.readable(in: environment))
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// « DANS 8 MIN », « ENREGISTRE »: the hero's first line, in a shade of its color that reads.
private struct HeroEyebrow: View {
    let text: String
    let systemImage: String
    let tint: Color
    var pulse = false
    @Environment(\.self) private var environment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(_ text: String, systemImage: String, tint: Color, pulse: Bool = false) {
        self.text = text
        self.systemImage = systemImage
        self.tint = tint
        self.pulse = pulse
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .bold))
                .symbolEffect(.pulse, isActive: pulse && !reduceMotion)
            Text(text.uppercased()).tracking(0.3).lineLimit(1)
        }
        .font(.meta.weight(.semibold))
        .foregroundStyle(tint.readable(in: environment))
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
