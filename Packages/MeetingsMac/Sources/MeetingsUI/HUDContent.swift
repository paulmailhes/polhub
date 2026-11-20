import Foundation
import Pipeline
import HubDesign

/// What a pop-up shows. The prompt goes first, then an alert, then a short notice.
public enum HUDContent: Equatable, Sendable {
    case prompt(title: String, deadline: Date)
    case toast(title: String, subtitle: String)
    /// `action`: the button that goes with « Fermer », none when closing is all there is to do (lot 10, 20/11).
    case alert(title: String, message: String, action: String?)

    var priority: Int {
        switch self {
        case .prompt: 3
        case .alert: 2
        case .toast: 1
        }
    }
}

/// One pop-up at a time. A notice never covers the start prompt: it waits for it to close. A prompt or an
/// alert replaces a notice, which is dropped (it would be stale by then).
public struct HUDQueue: Sendable {
    public private(set) var showing: HUDContent?
    private var waiting: [HUDContent] = []

    public init() {}

    /// What to show now, or nil when the item waits.
    public mutating func enqueue(_ item: HUDContent) -> HUDContent? {
        guard let current = showing else {
            showing = item
            return item
        }
        if item.priority > current.priority {
            if current.priority > 1 { waiting.append(current) }
            showing = item
            return item
        }
        if case .toast = item { waiting.removeAll { if case .toast = $0 { true } else { false } } }
        waiting.append(item)
        return nil
    }

    /// The shown pop-up closed: what comes next, if anything.
    public mutating func closed() -> HUDContent? {
        guard let next = waiting.max(by: { $0.priority < $1.priority }) else {
            showing = nil
            return nil
        }
        waiting.removeAll { $0 == next }
        showing = next
        return next
    }
}

/// Device changes come in bursts (phase 0, S11): one notice once things have been quiet for two seconds,
/// with the final state.
public struct ToastCoalescer: Sendable {
    public static let quietSeconds = 2.0
    private var pending: (toast: Toast, at: Double)?

    public init() {}

    public mutating func add(_ toast: Toast, at time: Double) {
        pending = (toast, time)
    }

    public mutating func due(at time: Double) -> Toast? {
        guard let pending, time - pending.at >= Self.quietSeconds else { return nil }
        self.pending = nil
        return pending.toast
    }
}

/// The words of every pop-up.
public enum HUDText {
    public static func promptTitle(_ title: String) -> String { "Google Meet · \(title)" }
    /// « S'enregistre seule dans 7 s »: the HUD's and « Coup d'œil »'s words, the same (lot 10, 20/11: « Enregistrement dans
    /// 7 s » here), the seconds by `Words.preciseDuration`.
    public static func countdown(_ seconds: Int) -> String { "S'enregistre seule dans " + Words.preciseDuration(seconds) }
    /// The seconds left before the detected meeting records by itself, rounded up as the pop-up counts them: the
    /// pop-up, the menu bar and « Coup d'œil » show the same number.
    public static func remaining(until deadline: Date, now: Date) -> Int {
        max(0, Int(deadline.timeIntervalSince(now).rounded(.up)))
    }

    public static func toast(_ toast: Toast) -> (title: String, subtitle: String) {
        switch toast {
        case .devices(let mic, let output):
            let parts = [mic.map { "Micro : \($0)" }, output.map { "Sortie : \($0)" }].compactMap { $0 }
            return ("L'enregistrement continue", parts.isEmpty ? "Périphériques changés" : parts.joined(separator: " · "))
        case .ended(let title, let seconds):
            // « 42 min », « 1 h 05 », « 2 h » (`Words.duration`, lot 10, 20/11).
            return ("Réunion enregistrée", "\(title) · \(Words.duration(seconds))")
        case .resumed(let title):
            return ("Enregistrement repris", title)
        }
    }

    /// `action`: the button beside « Fermer », which opens the Diagnostic; `nil` when there is nothing to open (lot 10,
    /// 20/11: the HUD hid a button by its title, « OK »). A button is a verb and its object, never « Diagnostic »; no word
    /// of the code on screen, never « une piste » (lot 10, 20/11).
    public static func alert(_ alert: AppAlert) -> (title: String, message: String, action: String?) {
        switch alert {
        case .tabsUnreadable:
            ("hub ne lit plus les onglets de Dia", "Les réunions sont détectées par le micro seul.", "Ouvrir le Diagnostic")
        case .selfTestFailed:
            ("Le son des autres n'est pas capté", "Vérifie l'autorisation « Enregistrement de l'audio du système ».", "Ouvrir le Diagnostic")
        case .diskLow(let freeGB):
            ("Disque presque plein", "Il reste \(Words.number(freeGB)) Go. Une heure de réunion en prend environ 1,4.", nil)
        case .trackFailed(let message):
            ("L'enregistrement s'est interrompu", message, nil)
        }
    }
}
