import Notifications
import PolhubDesign
import SwiftUI

/// The four round buttons of « Coup d'œil » (15/11), as Control Center's toggles: a circle of glass, filled with its
/// color when it is « on », its name under it. Enregistrer becomes Arrêter (red) during a meeting, Suspendre becomes
/// Reprendre (orange) while detection is paused. A gesture leaves the panel open; the hero follows.
struct PanelButtons: View {
    let context: CoupDoeilContext
    let hasMailboxes: Bool
    let hasAgenda: Bool

    private var app: AppModel { context.app }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            record
            if hasMailboxes {
                RoundToggle(title: "Nouveau mail", systemImage: "square.and.pencil", help: "Écrire un nouveau mail (⌘N)") { context.newMail() }
            }
            if hasAgenda {
                RoundToggle(title: "Rendez-vous", systemImage: "calendar.badge.plus", help: "Créer un rendez-vous") { context.newEvent() }
            }
            detection
        }
        .padding(.top, 2)
    }

    @ViewBuilder
    private var record: some View {
        switch PanelModel.recordToggle(app.status) {
        case .stop:
            // A click only: no key ever stops a real meeting by mistake.
            RoundToggle(title: "Arrêter", systemImage: "stop.fill", lit: true, tint: PanelTint.red, help: "Arrêter l'enregistrement") {
                context.actions.user(.stop)
            }
        case .record(let enabled):
            RoundToggle(title: "Enregistrer", systemImage: "record.circle", help: enabled ? "Enregistrer le son du Mac maintenant"
                        : "La réunion détectée se règle dans la carte du haut") {
                context.actions.user(.recordNow)
            }
            .disabled(!enabled)
        }
    }

    @ViewBuilder
    private var detection: some View {
        if app.isDevelopment {
            // The development build never detects on its own: its switch, here.
            RoundToggle(title: "Détection", systemImage: app.detectionOn ? "dot.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash",
                        lit: app.detectionOn, tint: Color.accentColor,
                        help: app.detectionOn ? "Couper la détection (version de développement)" : "Activer la détection (version de développement)") {
                context.actions.setDetection(!app.detectionOn)
            }
        } else if let until = app.pausedUntil {
            RoundToggle(title: "Reprendre", systemImage: "play.fill", lit: true, tint: PanelTint.orange,
                        help: "Détection suspendue jusqu'à \(PanelModel.clock(until)) : la reprendre") {
                context.actions.resumeDetection()
            }
        } else {
            RoundToggle(title: "Suspendre", systemImage: "pause.fill", help: "Suspendre la détection une heure") {
                context.actions.pauseDetection()
            }
        }
    }
}

/// A round toggle: 44 points of glass, its color when on, its name in 12 points under it.
struct RoundToggle: View {
    let title: String
    let systemImage: String
    var lit = false
    var tint: Color = .accentColor
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                RoundToggleCircle(systemImage: systemImage, lit: lit, tint: tint)
                Text(title)
                    .font(.tag)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .fixedSize()
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(PanelPressStyle())
        .help(help)
        .accessibilityLabel(title)
        .accessibilityAddTraits(lit ? .isSelected : [])
    }
}

private struct RoundToggleCircle: View {
    let systemImage: String
    let lit: Bool
    let tint: Color
    @Environment(\.panelHovered) private var hovered
    @Environment(\.panelPressed) private var pressed

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(lit ? Color.white : Color.primary)
            .frame(width: 44, height: 44)
            .background {
                if lit { Circle().fill(tint) }
            }
            .overlay {
                Circle().fill((lit ? Color.white : Color.primary).opacity(pressed ? 0.16 : hovered ? 0.08 : 0))
            }
            .glassEffect(lit ? .regular.tint(tint) : .regular, in: .circle)
    }
}

/// A button that answers as Control Center's: lighter under the pointer, smaller while pressed; its label reads both
/// (`panelHovered`, `panelPressed`). With « Réduire les animations », it only darkens.
struct PanelPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PanelPressBody(configuration: configuration)
    }
}

private struct PanelPressBody: View {
    let configuration: ButtonStyleConfiguration
    @State private var hovering = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let pressed = configuration.isPressed
        configuration.label
            .environment(\.panelHovered, hovering && enabled)
            .environment(\.panelPressed, pressed)
            .scaleEffect(pressed && !reduceMotion ? 0.94 : 1)
            .opacity(enabled ? 1 : 0.4)
            .onHover { hovering = $0 }
            .animation(Motion.quick, value: hovering)
            .animation(Motion.quick, value: pressed)
    }
}

extension EnvironmentValues {
    @Entry var panelHovered = false
    @Entry var panelPressed = false
}

// MARK: - The footer

/// The footer, fixed: « Ouvrir Polhub », the notifications' bell, Réglages and « ⋯ » (Contacts, Diagnostic…, Quitter);
/// above them, a grey line while a version waits for a quiet moment.
struct PanelFooter: View {
    let context: CoupDoeilContext
    let updateLine: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Rectangle().fill(Color.primary.opacity(0.1)).frame(height: 1)
                .padding(.bottom, Space.xs)
            if let updateLine {
                Label(updateLine, systemImage: "arrow.down.circle")
                    .font(.meta)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            HStack(alignment: .center, spacing: 2) {
                Button { context.openHome() } label: {
                    Text("Ouvrir Polhub")
                        .font(.rowBody.weight(.medium))
                        .padding(.horizontal, Space.s)
                        .padding(.vertical, 7)
                }
                .buttonStyle(.hover(.capsule))
                .foregroundStyle(.primary)
                .padding(.leading, -Space.s)
                .help("Ouvrir la fenêtre de Polhub")
                Spacer(minLength: 0)
                if let inbox = context.notifications?.inbox {
                    NotificationBell(inbox: inbox, arrowEdge: .bottom) { context.actions.perform($0) }
                }
                Button { context.open(.settings(nil)) } label: {
                    AppIconImage(.settings, size: 20).frame(width: FooterMetrics.button, height: FooterMetrics.button)
                }
                .buttonStyle(.hover(.circle))
                .foregroundStyle(.secondary)
                .help("Réglages (⌘,)")
                .accessibilityLabel("Réglages")
                Menu {
                    if context.agenda != nil {
                        Button("Contacts") { context.open(.section(.contacts)) }
                    }
                    Button("Diagnostic…") { context.actions.showDiagnostic() }
                    Divider()
                    // No key: quitting must never cut a meeting by mistake.
                    Button("Quitter Polhub") { context.actions.quit() }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: FooterMetrics.button, height: FooterMetrics.button)
                }
                .menuStyle(.button)
                .buttonStyle(.hover(.circle))
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Plus")
                .accessibilityLabel("Plus")
            }
            .padding(.trailing, -Space.xs)
        }
    }
}

private enum FooterMetrics {
    /// The bell's size (`SidebarFooterMetrics.rowHeight`): the footer's icons line up with it.
    static let button: CGFloat = 36
}
