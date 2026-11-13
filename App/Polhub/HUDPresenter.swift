import AppKit
import Foundation
import MeetingsUI
import Observability
import Pipeline

/// Draws what the coordinator decides: one pop-up at a time at the top of the screen, and the menu bar.
@MainActor
final class HUDPresenter: MeetingPresenter {
    private let model: AppModel
    private weak var app: AppDelegate?
    private let panel = HUDPanelController(style: .production)
    private var queue = HUDQueue()
    private var coalescer = ToastCoalescer()
    private var promptTitle = ""

    init(model: AppModel, app: AppDelegate) {
        self.model = model
        self.app = app
    }

    func showPrompt(title: String, deadline: Date) {
        promptTitle = title
        display(queue.enqueue(.prompt(title: title, deadline: deadline)))
    }

    func hidePrompt() {
        guard case .prompt = queue.showing else { return }
        panel.close()
        display(queue.closed())
    }

    func show(_ toast: Toast) {
        if case .devices = toast {
            coalescer.add(toast, at: ContinuousTime.seconds())
        } else {
            let text = HUDText.toast(toast)
            display(queue.enqueue(.toast(title: text.title, subtitle: text.subtitle)))
        }
    }

    func show(_ alert: AppAlert) {
        model.attention = true
        let text = HUDText.alert(alert)
        display(queue.enqueue(.alert(title: text.title, message: text.message, action: text.action)))
    }

    func retitle(_ title: String) {
        promptTitle = title
        if case .prompt = queue.showing { panel.updatePromptTitle(title) }
    }

    func update(_ status: RecorderStatus) {
        model.status = status
        app?.statusChanged(status)
    }

    /// Called every half second: shows a burst of device changes once it has settled.
    func tick() {
        if let toast = coalescer.due(at: ContinuousTime.seconds()) {
            let text = HUDText.toast(toast)
            display(queue.enqueue(.toast(title: text.title, subtitle: text.subtitle)))
        }
    }

    private func display(_ content: HUDContent?) {
        guard let content else { return }
        switch content {
        case .prompt(let title, let deadline):
            panel.showPrompt(
                title: title, deadline: deadline,
                onAccept: { [weak self] in self?.closed(); self?.app?.user(.accept) },
                onDecline: { [weak self] in self?.closed(); self?.app?.user(.decline) }
            )
        case .toast(let title, let subtitle):
            panel.showToast(title: title, subtitle: subtitle) { [weak self] in self?.closed() }
        case .alert(let title, let message, let action):
            panel.showAlert(
                title: title, message: message, action: action,
                onAction: { [weak self] in self?.app?.showDiagnostic() },
                onClose: { [weak self] in
                    self?.model.attention = false
                    self?.closed()
                }
            )
        }
    }

    private func closed() {
        display(queue.closed())
    }
}
