import AppKit
import PolhubDesign
import SwiftUI

/// The floating pop-up: a panel that shows above everything, on every desktop and over full-screen apps,
/// and whose buttons answer a click without activating the app or taking keyboard focus.
@MainActor
public final class HUDPanelController {
    public struct Style: Sendable {
        public var level: NSWindow.Level
        public var collectionBehavior: NSWindow.CollectionBehavior

        public init(level: NSWindow.Level, collectionBehavior: NSWindow.CollectionBehavior) {
            self.level = level
            self.collectionBehavior = collectionBehavior
        }

        /// The level phase 0 measured: above Dia, without taking the focus.
        public static let production = Style(
            level: .statusBar, collectionBehavior: [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        )
    }

    /// The window levels phase 0 compares.
    public nonisolated static let candidates: [String: Style] = {
        let behavior: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        return [
            "floating": Style(level: .floating, collectionBehavior: behavior),
            "statusBar": Style(level: .statusBar, collectionBehavior: behavior),
            "screenSaver": Style(level: .screenSaver, collectionBehavior: behavior),
        ]
    }()

    /// 480 wide (lot 9, 20/11: 440 before, where the panel's 15 and 13 points put « Enregistrement dans 7 s » on two lines
    /// beside its two buttons), 76 tall at least.
    public nonisolated static let panelSize = CGSize(width: 480, height: 76)

    private let style: Style
    private var panel: NSPanel?
    private var timer: Timer?
    private let model = HUDModel()

    public init(style: Style = .production) {
        self.style = style
    }

    /// Whether the panel held the keyboard focus when it was closed.
    public private(set) var wasKeyWhenClosed = false
    public var frame: CGRect? { panel?.frame }
    /// The frame of the screen the panel is on.
    public var screenFrame: CGRect? { panel?.screen?.frame }
    public var isShown: Bool { panel != nil }

    /// A panel that never activates the app and becomes key only if a control truly needs it.
    public static func makePanel(style: Style) -> NSPanel {
        let panel = KeyablePanel(
            contentRect: CGRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = style.level
        panel.collectionBehavior = style.collectionBehavior
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        return panel
    }

    // MARK: - The three pop-ups

    /// The start pop-up: the countdown runs to `deadline`; the coordinator closes it when the recording is
    /// confirmed.
    public func showPrompt(title: String, deadline: Date, onAccept: @escaping () -> Void, onDecline: @escaping () -> Void) {
        prepare(.prompt, title: HUDText.promptTitle(title), subtitle: "")
        model.deadline = deadline
        model.onAccept = { [weak self] in self?.close(); onAccept() }
        model.onDecline = { [weak self] in self?.close(); onDecline() }
        present()
        tickEverySecond { [weak self] in
            guard let self, let deadline = self.model.deadline else { return }
            self.model.remaining = Int(deadline.timeIntervalSinceNow.rounded(.up))
            // The coordinator closes it at the deadline; this only guards against a prompt left behind.
            if deadline.timeIntervalSinceNow < -3 { self.close() }
        }
        model.remaining = Int(deadline.timeIntervalSinceNow.rounded(.up))
    }

    public func showToast(title: String, subtitle: String, seconds: Double = 5, onClose: @escaping () -> Void) {
        prepare(.toast, title: title, subtitle: subtitle)
        model.onClose = onClose
        present()
        let closesAt = Date().addingTimeInterval(seconds)
        tickEverySecond { [weak self] in
            guard let self, Date() >= closesAt else { return }
            self.close()
            onClose()
        }
    }

    public func showAlert(title: String, message: String, action: String, onAction: @escaping () -> Void, onClose: @escaping () -> Void) {
        prepare(.alert, title: title, subtitle: message)
        model.actionTitle = action
        model.onAction = { [weak self] in self?.close(); onAction(); onClose() }
        model.onClose = { [weak self] in self?.close(); onClose() }
        present()
    }

    /// The probe of phase 0: a countdown of its own, and what happened when it ran out.
    public func show(
        title: String,
        subtitle: String,
        countdownSeconds: Int,
        onAccept: @escaping () -> Void,
        onDecline: @escaping () -> Void,
        onExpire: @escaping () -> Void
    ) {
        showPrompt(title: title, deadline: Date().addingTimeInterval(Double(countdownSeconds)), onAccept: onAccept, onDecline: onDecline)
        model.title = "\(title)"
        model.subtitle = subtitle
        tickEverySecond { [weak self] in
            guard let self, let deadline = self.model.deadline else { return }
            self.model.remaining = Int(deadline.timeIntervalSinceNow.rounded(.up))
            if self.model.remaining <= 0 {
                self.close()
                onExpire()
            }
        }
    }

    /// The start pop-up's title, once the tab's real title is known. A longer one may take a second line: the panel
    /// follows, once SwiftUI has laid it out (lot 9, 20/11).
    public func updatePromptTitle(_ title: String) {
        guard let panel else { return }
        model.title = HUDText.promptTitle(title)
        DispatchQueue.main.async { [weak self] in
            guard let self, self.panel === panel else { return }
            self.place(panel, on: panel.screen)
        }
    }

    public func close() {
        timer?.invalidate()
        timer = nil
        if let panel { wasKeyWhenClosed = panel.isKeyWindow }
        panel?.orderOut(nil)
        panel = nil
    }

    // MARK: - Pieces

    private func prepare(_ kind: HUDModel.Kind, title: String, subtitle: String) {
        close()
        model.kind = kind
        model.title = title
        model.subtitle = subtitle
        model.deadline = nil
        model.onAccept = {}
        model.onDecline = {}
        model.onAction = {}
        model.onClose = {}
    }

    private func present() {
        let panel = Self.makePanel(style: style)
        panel.contentView = FirstMouseHostingView(rootView: HUDView(model: model))
        let pointer = NSEvent.mouseLocation
        place(panel, on: NSScreen.screens.first { $0.frame.contains(pointer) } ?? NSScreen.main ?? NSScreen.screens.first)
        panel.orderFrontRegardless()
        self.panel = panel
    }

    /// Under the menu bar of `screen`, as tall as its words need.
    private func place(_ panel: NSPanel, on screen: NSScreen?) {
        guard let screen, let content = panel.contentView else { return }
        panel.setFrame(
            HUDPlacement.frame(
                screenFrame: screen.frame,
                safeAreaTop: screen.safeAreaInsets.top,
                menuBarHeight: screen.frame.maxY - screen.visibleFrame.maxY,
                size: Self.size(fitting: content)
            ),
            display: true
        )
    }

    /// The tallest the HUD grows to.
    nonisolated static let maxHeight: CGFloat = 120

    /// The HUD's size (lot 9, 20/11): 480 wide, as tall as its words need, from 76 to 120. In the panel's 15 and 13 points,
    /// a long alert (« Polhub ne lit plus les onglets de Dia ») takes two lines and its explanation two more: cut to one
    /// line, its title lost « onglets de Dia ».
    static func size(fitting content: NSView) -> CGSize {
        CGSize(width: panelSize.width, height: min(maxHeight, max(panelSize.height, content.fittingSize.height.rounded(.up))))
    }

    private func tickEverySecond(_ body: @escaping @MainActor () -> Void) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated { body() }
        }
    }
}

/// What floats over every app, the HUD and the card before a visio (lot 9, 20/11): it reads as « Coup d'œil », a title
/// of 15 points and its line of 13 (13 and 11 before, under the app's floor of 12), 16 points from its edge.
enum FloatingMetrics {
    static let title = Font.rowTitle.weight(.semibold)
    static let meta = Font.meta
    static let margin = Space.l
}

/// A borderless panel cannot become key by default; this one can, but only when a control needs it.
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Lets a button answer the first click even though the panel's app is not active (the HUD, the card before a
/// meeting).
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Internal for the captures (lot 9, 20/11: the HUD had none).
@MainActor
final class HUDModel: ObservableObject {
    enum Kind { case prompt, toast, alert }

    @Published var kind: Kind = .toast
    @Published var title = ""
    @Published var subtitle = ""
    @Published var remaining = 0
    @Published var actionTitle = ""
    var deadline: Date?
    var onAccept: () -> Void = {}
    var onDecline: () -> Void = {}
    var onAction: () -> Void = {}
    var onClose: () -> Void = {}
}

/// The HUD: what happens, in the panel's words (lot 9, 20/11: its title in 15 points and two lines at most, its line in
/// 13), and its buttons.
struct HUDView: View {
    @ObservedObject var model: HUDModel

    var body: some View {
        HStack(spacing: Space.m) {
            icon
            VStack(alignment: .leading, spacing: 2) {
                Text(model.title)
                    .font(FloatingMetrics.title)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(model.kind == .prompt ? HUDText.countdown(model.remaining) : model.subtitle)
                    .font(FloatingMetrics.meta)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // The words take all the room the buttons leave (lot 9, 20/11: the stack gave them an even share with the
            // space beside them, and cut « Google Meet · Rev… » with room to spare).
            .layoutPriority(1)
            Spacer(minLength: Space.s)
            // The principal and secondary roles (design system v2, 19/11): drawn by hand, they keep their ink in a panel
            // that never becomes key, where the system's prominent button turned grey (the meeting card's, the same
            // panel, 16/11). Never squeezed.
            HStack(spacing: Space.s) {
                switch model.kind {
                case .prompt:
                    Button("Pas cette fois") { model.onDecline() }
                        .buttonStyle(.secondary)
                    Button("Enregistrer") { model.onAccept() }
                        .buttonStyle(.primary)
                case .alert:
                    Button("Fermer") { model.onClose() }
                        .buttonStyle(.secondary)
                    if model.actionTitle != "OK" {
                        Button(model.actionTitle) { model.onAction() }
                            .buttonStyle(.primary)
                    }
                case .toast:
                    EmptyView()
                }
            }
            .fixedSize()
        }
        .padding(.horizontal, FloatingMetrics.margin)
        .padding(.vertical, Space.m)
        // 480 wide, and as tall as its words, 76 at least (`HUDPanelController.size(fitting:)`).
        .frame(width: HUDPanelController.panelSize.width)
        .frame(minHeight: HUDPanelController.panelSize.height)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        // The HUD's root: Polhub's accent, ink, whatever the Mac's (design system v2, 19/11).
        .tint(Tint.control.color)
    }

    @ViewBuilder private var icon: some View {
        switch model.kind {
        case .prompt:
            // Grey while nothing records, as the logo's outlined circle: the red starts with the recording (design system
            // v2, 19/11).
            Image(systemName: "record.circle").font(.title).foregroundStyle(.secondary)
        case .toast:
            Image(systemName: "waveform").font(.title).foregroundStyle(.secondary)
        case .alert:
            Image(systemName: "exclamationmark.triangle.fill").font(.title).foregroundStyle(Tint.attention)
        }
    }
}
