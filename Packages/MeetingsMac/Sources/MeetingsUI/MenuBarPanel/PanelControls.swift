import Notifications
import HubDesign
import SwiftUI

/// The three round buttons of « Coup d'œil », as Control Center's toggles: a circle of glass, filled with its color
/// when it is « on », its name under it. Enregistrer only starts a recording, from rest: a meeting is answered and
/// stopped in the hero, so Arrêter is never there twice (« Tuiles allégées », Paul, 16/11). Suspendre becomes Reprendre,
/// lit in hub's ink as the hero's Reprendre (design system v2, 19/11), while detection is paused. A gesture leaves
/// the panel open; the hero follows.
struct PanelButtons: View {
    let context: CoupDoeilContext
    let hasMailboxes: Bool

    private var app: AppModel { context.app }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            let canRecord = PanelModel.canRecord(app.status)
            RoundToggle(title: "Enregistrer", systemImage: "record.circle",
                        help: canRecord ? "Enregistrer le son du Mac maintenant" : "La réunion se règle dans la carte du haut") {
                context.actions.user(.recordNow)
            }
            .disabled(!canRecord)
            if hasMailboxes {
                // « Écrire un nouveau mail (⌘N) », by `Words.help` (lot 10, 20/11).
                RoundToggle(title: "Nouveau mail", systemImage: "square.and.pencil", help: Words.help("Écrire un nouveau mail", .command("N"))) {
                    context.newMail()
                }
            }
            detection
        }
        .padding(.top, 2)
    }

    @ViewBuilder
    private var detection: some View {
        if app.isDevelopment {
            // The development build never detects on its own: its switch, here.
            // The detection is active or suspended, never « coupée »; the parentheses of a bubble keep for a key (lot 10, 20/11).
            RoundToggle(title: "Détection", systemImage: app.detectionOn ? "dot.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash",
                        lit: app.detectionOn, tint: Tint.accent,
                        help: app.detectionOn ? "Suspendre la détection" : "Activer la détection") {
                context.actions.setDetection(!app.detectionOn)
            }
        } else if app.pausedUntil != nil {
            // Lit in hub's ink, as the hero's Reprendre above it: one action, one color (design system v2, 19/11). A verb
            // and its object (lot 10, 20/11: « Détection suspendue jusqu'à 16:30 : la reprendre »; the hero says until when).
            RoundToggle(title: "Reprendre", systemImage: "play.fill", lit: true, tint: Tint.accent, help: "Reprendre la détection") {
                context.actions.resumeDetection()
            }
        } else {
            RoundToggle(title: "Suspendre", systemImage: "pause.fill", help: "Suspendre la détection une heure") {
                context.actions.pauseDetection()
            }
        }
    }
}

/// A round toggle: 44 points of glass, its color when on (hub's ink unless told otherwise, design system v2, 19/11),
/// its name in 12 points under it.
struct RoundToggle: View {
    let title: String
    let systemImage: String
    var lit = false
    var tint: Color = Tint.accent
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
        // Lit, the glyph and its veil take the accent's opposite (`Tint.onAccent`), as a `.primary` button's label:
        // white on ink in light, ink on the near-white ink of dark, where a white glyph would vanish (design system v2,
        // 19/11).
        let onTint = lit ? Tint.onAccent.color : Color.primary
        Image(systemName: systemImage)
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(onTint)
            .frame(width: 44, height: 44)
            .background {
                if lit { Circle().fill(tint) }
            }
            .overlay {
                Circle().fill(onTint.opacity(pressed ? 0.16 : hovered ? 0.08 : 0))
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

/// The footer, fixed: « Ouvrir hub », the notifications' bell, Réglages and « ⋯ » (Contacts, Diagnostic…, Quitter);
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
                    Text("Ouvrir hub")
                        .font(.rowBody.weight(.medium))
                        .padding(.horizontal, Space.s)
                        .padding(.vertical, 7)
                }
                .buttonStyle(.hover(.capsule))
                .foregroundStyle(.primary)
                .padding(.leading, -Space.s)
                // Where it goes and its key, as the tiles' (lot 10, 20/11: « Ouvrir la fenêtre de hub » said the label
                // again): the Accueil (⌘1), or Réunions without the agenda (`CoupDoeilContext.openHome`).
                .help(context.agenda != nil
                      ? Words.help("Ouvrir l'Accueil", shortcuts: SidebarItem.home.shortcut.map { [Words.Shortcut.command("\($0)")] } ?? [])
                      : Words.help("Ouvrir Réunions", shortcuts: SidebarItem.meetings.shortcut.map { [Words.Shortcut.command("\($0)")] } ?? []))
                Spacer(minLength: 0)
                if let inbox = context.notifications?.inbox {
                    NotificationBell(inbox: inbox, arrowEdge: .bottom) { context.actions.perform($0) }
                }
                Button { context.open(.settings(nil)) } label: {
                    AppIconImage(.settings, size: 20).frame(width: FooterMetrics.button, height: FooterMetrics.button)
                }
                .buttonStyle(.hover(.circle))
                .foregroundStyle(.secondary)
                // A verb and its object, the key in the bubble only; VoiceOver the same words (lot 10, 20/11).
                .help(Words.help("Ouvrir Réglages", .command(",")))
                .accessibilityLabel("Ouvrir Réglages")
                Menu {
                    // Verbs, as every button (lot 10, 20/11: « Contacts », « Diagnostic… »).
                    if context.agenda != nil {
                        Button("Ouvrir Contacts") { context.open(.section(.contacts)) }
                    }
                    Button("Ouvrir le Diagnostic") { context.actions.showDiagnostic() }
                    Divider()
                    // No key: quitting must never cut a meeting by mistake.
                    Button("Quitter hub") { context.actions.quit() }
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
                // The help of every « … » menu (`Words.moreActions`, lot 10, 20/11).
                .help(Words.moreActions)
                .accessibilityLabel(Words.moreActions)
            }
            .padding(.trailing, -Space.xs)
        }
    }
}

private enum FooterMetrics {
    /// The bell's size (`SidebarFooterMetrics.rowHeight`): the footer's icons line up with it.
    static let button: CGFloat = 36
}
