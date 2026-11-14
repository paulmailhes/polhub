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

    public nonisolated static let panelSize = CGSize(width: 440, height: 76)

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

    /// The start pop-up's title, once the tab's real title is known.
    public func updatePromptTitle(_ title: String) {
        guard panel != nil else { return }
        model.title = HUDText.promptTitle(title)
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
        let screen = NSScreen.screens.first { $0.frame.contains(pointer) } ?? NSScreen.main ?? NSScreen.screens.first
        if let screen {
            panel.setFrame(
                HUDPlacement.frame(
                    screenFrame: screen.frame,
                    safeAreaTop: screen.safeAreaInsets.top,
                    menuBarHeight: screen.frame.maxY - screen.visibleFrame.maxY,
                    size: Self.panelSize
                ),
                display: true
            )
        }
        panel.orderFrontRegardless()
        self.panel = panel
    }

    private func tickEverySecond(_ body: @escaping @MainActor () -> Void) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated { body() }
        }
    }
}

/// A borderless panel cannot become key by default; this one can, but only when a control needs it.
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Lets a button answer the first click even though the panel's app is not active.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
private final class HUDModel: ObservableObject {
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

private struct HUDView: View {
    @ObservedObject var model: HUDModel

    var body: some View {
        HStack(spacing: 12) {
            icon
            VStack(alignment: .leading, spacing: 2) {
                Text(model.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(model.kind == .prompt ? HUDText.countdown(model.remaining) : model.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            switch model.kind {
            case .prompt:
                Button("Pas cette fois") { model.onDecline() }
                Button("Enregistrer") { model.onAccept() }
                    .buttonStyle(.borderedProminent)
            case .alert:
                Button("Fermer") { model.onClose() }
                if model.actionTitle != "OK" {
                    Button(model.actionTitle) { model.onAction() }
                        .buttonStyle(.borderedProminent)
                }
            case .toast:
                EmptyView()
            }
        }
        .padding(.horizontal, 14)
        .frame(width: HUDPanelController.panelSize.width, height: HUDPanelController.panelSize.height)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder private var icon: some View {
        switch model.kind {
        case .prompt:
            Image(systemName: "record.circle").font(.system(size: 22)).foregroundStyle(.red)
        case .toast:
            Image(systemName: "waveform").font(.system(size: 20)).foregroundStyle(.secondary)
        case .alert:
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 20)).foregroundStyle(.orange)
        }
    }
}
