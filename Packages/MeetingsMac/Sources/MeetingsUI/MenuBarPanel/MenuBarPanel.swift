import MeetingDetection
import PolhubDesign
import ProjectsUI
import SwiftUI

/// « Coup d'œil », the panel under the menu bar's logo (15/11). FOR NOW a stand-in that keeps the menu's gestures
/// within reach (answer a detected meeting, record, stop, pause, open Polhub, Diagnostic, quit); the tiles of
/// the brief replace its body, with the same entry point: `MenuBarPanel(context:)`.
///
/// What the panel may count on (see `CoupDoeilContext`): it is drawn in the window of `MenuBarExtra`
/// (`.menuBarExtraStyle(.window)`); a gesture on the meeting goes through `context.actions.user`, a page through
/// `context.open(_:)`. It never opens by itself (the HUD stays the alert), never closes its window by hand, never runs
/// a hardware test, and reads `AppModel.now` nowhere: a clock lives in its own `TimelineView`.
public struct MenuBarPanel: View {
    let context: CoupDoeilContext

    public static let width: CGFloat = 360

    public init(context: CoupDoeilContext) {
        self.context = context
    }

    private var app: AppModel { context.app }

    public var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            status
            if let prompt = app.prompt { promptButtons(prompt) }
            Divider().padding(.vertical, Space.xs)
            meetingRows
            Divider().padding(.vertical, Space.xs)
            row("Ouvrir Polhub", systemImage: "macwindow") { context.openHome() }
            row("Diagnostic…", systemImage: "stethoscope") { context.actions.showDiagnostic() }
            Divider().padding(.vertical, Space.xs)
            row("Quitter Polhub", systemImage: "power") { context.actions.quit() }
        }
        .padding(14)
        .frame(width: Self.width, alignment: .leading)
        .environment(\.projectLogos, context.projectLogos)
        .animation(Motion.standard, value: app.prompt)
    }

    /// What Polhub does now; the recording's clock ticks in its own timeline.
    private var status: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            VStack(alignment: .leading, spacing: 2) {
                Text(MenuBarLabel.statusLine(app.shownStatus, now: timeline.date))
                    .font(.rowTitle.weight(.semibold).monospacedDigit())
                    .lineLimit(2)
                if let prompt = app.prompt {
                    Text(HUDText.countdown(HUDText.remaining(until: prompt.deadline, now: timeline.date)))
                        .font(.meta.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// The HUD's two answers, here too: the same gestures, so both close together.
    private func promptButtons(_ prompt: DetectedPrompt) -> some View {
        HStack(spacing: Space.s) {
            Button("Pas cette fois") { context.actions.user(.decline) }
                .buttonStyle(.glass)
                .keyboardShortcut(.delete, modifiers: [])
            Spacer(minLength: 0)
            Button { context.actions.user(.accept) } label: { Label("Enregistrer", systemImage: "record.circle") }
                .buttonStyle(.glassProminent)
                .tint(.red)
                .keyboardShortcut(.defaultAction)
        }
        .controlSize(.large)
        .transition(.opacity)
    }

    @ViewBuilder
    private var meetingRows: some View {
        if app.isRecording {
            // A click only: no key ever stops a real meeting by mistake.
            row("Arrêter l'enregistrement", systemImage: "stop.circle") { context.actions.user(.stop) }
        } else {
            row("Enregistrer maintenant", systemImage: "record.circle") { context.actions.user(.recordNow) }
                .disabled(app.status != .idle)
        }
        if app.canForgetLink {
            row("Jamais pour ce lien", systemImage: "nosign") { context.actions.user(.neverForThisLink) }
        }
        if app.isPaused {
            row("Reprendre la détection", systemImage: "play.circle") { context.actions.resumeDetection() }
        } else {
            row("Suspendre la détection une heure", systemImage: "pause.circle") { context.actions.pauseDetection() }
        }
        if app.isDevelopment {
            Toggle("Détection automatique (version de développement)", isOn: Binding(
                get: { app.detectionOn }, set: { context.actions.setDetection($0) }
            ))
            .font(.rowBody)
            .toggleStyle(.switch)
            .padding(.vertical, Space.xs)
        }
    }

    private func row(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        RowButton(action: action) {
            Label(title, systemImage: systemImage)
                .font(.rowBody)
                .foregroundStyle(.primary)
        }
    }
}
