import AppKit
import Recording
import HubDesign
import SwiftUI
import Transcription

public enum ChecklistItem: String, CaseIterable, Identifiable, Sendable {
    case microphone, systemAudio, diaAutomation, models, relaunch

    public var id: String { rawValue }

    var title: String {
        switch self {
        case .microphone: "Micro"
        case .systemAudio: "Enregistrement de l'audio du système"
        case .diaAutomation: "Automatisation de Dia"
        case .models: "Modèles de transcription"
        case .relaunch: "Relancer hub s'il plante, et l'ouvrir à chaque session"
        }
    }

    var explanation: String {
        switch self {
        case .microphone: "Pour enregistrer ta voix."
        case .systemAudio: "Pour enregistrer le son des autres, dans Dia. Vérifié par un son inaudible."
        case .diaAutomation: "Pour voir qu'un onglet Google Meet s'ouvre."
        case .models: "Pour transcrire sur ton Mac, hors ligne : WhisperKit et le détecteur de voix, téléchargés une fois."
        case .relaunch: "Sans cela, une réunion n'est enregistrée que si tu as ouvert hub toi-même."
        }
    }

    var settingsURL: URL? {
        switch self {
        case .microphone: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        case .systemAudio: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
        case .diaAutomation: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
        case .models: nil
        case .relaunch: URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")
        }
    }
}

public enum ItemState: Equatable, Sendable {
    case unknown, ok, missing
    case denied(String)
    /// Dia is not open: nothing is refused, its answer waits for it to open (lot 10, 20/11: a state, no longer the words
    /// of a refusal that the replay compared).
    case notRunning

    /// What the line says under its explanation: why it is refused, or that Dia is not open.
    public var reason: String? {
        switch self {
        case .denied(let reason): reason
        case .notRunning: "Dia n'est pas ouvert"
        case .unknown, .ok, .missing: nil
        }
    }
}

/// The checks of the first launch, run again from the Diagnostic page or when macOS or Dia changes.
@MainActor
public final class DiagnosticModel: ObservableObject {
    @Published public private(set) var states: [ChecklistItem: ItemState] = [:]
    @Published public private(set) var testing: Set<ChecklistItem> = []
    @Published public var relaunchMessage: String?
    /// A check of the others' sound just gave its answer: told only then, never when another line is checked again
    /// while an earlier answer stays in `states` (the self-test's badge goes on a fresh « ok » only).
    public var systemAudioChecked: ((ItemState) -> Void)?
    public let showsRelaunch: Bool
    private let amplitude: Float
    private let relaunchEnabled: () -> Bool
    private let setRelaunch: (Bool) -> String?
    private let missingModels: () -> [String]

    public init(
        amplitude: Float, showsRelaunch: Bool, relaunchEnabled: @escaping () -> Bool, setRelaunch: @escaping (Bool) -> String?,
        missingModels: @escaping () -> [String] = { ModelLocations.standard.missing() }
    ) {
        self.amplitude = amplitude
        self.showsRelaunch = showsRelaunch
        self.relaunchEnabled = relaunchEnabled
        self.setRelaunch = setRelaunch
        self.missingModels = missingModels
    }

    private func checkModels() {
        let missing = missingModels()
        states[.models] = missing.isEmpty ? .ok : .denied("Manque : " + missing.joined(separator: ", "))
    }

    public var items: [ChecklistItem] {
        ChecklistItem.allCases.filter { $0 != .relaunch || showsRelaunch }
    }

    public var allGood: Bool {
        items.allSatisfy { states[$0] == .ok }
    }

    /// What a replay after an update checks: the permissions only. Dia being closed, or the relaunch left
    /// off, is not a permission taken away.
    public var permissionsGood: Bool {
        states[.microphone] == .ok && states[.systemAudio] == .ok
            && (states[.diaAutomation] == .ok || states[.diaAutomation] == .notRunning)
    }

    /// A line's answer; the others' sound is told as it comes (`systemAudioChecked`).
    func set(_ item: ChecklistItem, _ state: ItemState) {
        states[item] = state
        if item == .systemAudio { systemAudioChecked?(state) }
    }

    /// One check; `prompt` lets macOS ask the question it has never asked.
    public func test(_ item: ChecklistItem, prompt: Bool) async {
        testing.insert(item)
        defer { testing.remove(item) }
        if item == .relaunch {
            states[.relaunch] = relaunchEnabled() ? .ok : .missing
            return
        }
        if item == .models {
            checkModels()
            return
        }
        let status = await PermissionCheck.run(prompt: prompt, testSystemAudio: item == .systemAudio, amplitude: amplitude)
        switch item {
        case .microphone: set(item, Self.state(item, from: status.microphone))
        case .systemAudio: set(item, Self.state(item, from: status.systemAudio))
        case .diaAutomation: set(item, Self.state(item, from: status.appleEventsDia))
        case .models, .relaunch: break
        }
    }

    public func testAll(prompt: Bool) async {
        states[.relaunch] = relaunchEnabled() ? .ok : .missing
        checkModels()
        testing = Set(items).subtracting([.models, .relaunch])
        let status = await PermissionCheck.run(prompt: prompt, testSystemAudio: true, amplitude: amplitude)
        set(.microphone, Self.state(.microphone, from: status.microphone))
        set(.systemAudio, Self.state(.systemAudio, from: status.systemAudio))
        set(.diaAutomation, Self.state(.diaAutomation, from: status.appleEventsDia))
        testing = []
    }

    /// Switches the relaunch without Général's guards: the page no longer calls it (lot 7, 19/11), its line goes through
    /// `StartupControl`. Left for the app, which still gives `setRelaunch`.
    public func toggleRelaunch(_ on: Bool) {
        relaunchMessage = setRelaunch(on)
        states[.relaunch] = relaunchEnabled() ? .ok : .missing
    }

    static func state(_ item: ChecklistItem, from answer: String) -> ItemState {
        switch (item, answer) {
        case (.microphone, "authorized"), (.systemAudio, "nonZero"), (.diaAutomation, "granted"): .ok
        case (.microphone, "notDetermined"), (.diaAutomation, "wouldPrompt"): .missing
        case (.systemAudio, "notTested"): .unknown
        case (.systemAudio, "allZero"): .denied("Le son n'est pas capté")
        case (.diaAutomation, "notRunning"): .notRunning
        // macOS's answer in words, never its code on screen (« denied », « restricted », « error:-1708 »), lot 10, 20/11.
        case (_, "denied"): .denied("Refusé dans Réglages Système")
        case (_, "restricted"): .denied("Bloqué par un profil installé sur le Mac")
        default: .denied("macOS ne répond pas comme prévu")
        }
    }
}

/// The Diagnostic page: each permission, its state, and how to fix it. A line of Réglages › Général since lot 7 (19/11):
/// the grouped form and the one width of Réglages, no title of its own (the window says it).
public struct DiagnosticView: View {
    @ObservedObject var model: DiagnosticModel
    let colin: ColinProbeControl?
    /// What every installed tool needs (21/11): the add-ons' control; nil in a capture that does not ask for it.
    let connections: AddOnControl?
    let notifications: NotificationHub?
    let openProbes: () -> Void
    /// Général's switch of the relaunch, given by Réglages (lot 7, 19/11): the line of the relaunch goes through it, its
    /// questions and its wait for the end of a meeting, never round them.
    @Environment(\.startupControl) private var startup

    /// `colin`: the probe of Colin, shown under the checks when the app gives it.
    public init(model: DiagnosticModel, colin: ColinProbeControl? = nil, connections: AddOnControl? = nil, notifications: NotificationHub? = nil,
                openProbes: @escaping () -> Void) {
        self.model = model
        self.colin = colin
        self.connections = connections
        self.notifications = notifications
        self.openProbes = openProbes
    }

    /// Réunions' own checks: always without the add-ons' control, else when Réunions is installed.
    private var showsMeetings: Bool { connections?.installed.contains(.meetings) ?? true }

    public var body: some View {
        Form {
            if let connections {
                ConnectionsSection(control: connections, notifications: notifications)
            }
            if showsMeetings { meetings }
            if let colin {
                Section { ColinProbeSection(control: colin) }
            }
        }
        .settingsForm()
        .task { if showsMeetings, model.states.isEmpty { await model.testAll(prompt: false) } }
    }

    /// Réunions' checks: the microphone, the others' sound, Dia, the models, the relaunch.
    @ViewBuilder private var meetings: some View {
            Section {
                // What is missing: a problem, said by `ErrorLine` (design system v2, 19/11).
                if model.allGood {
                    // « Visio », never « un Meet »; French typography, laid at display (lot 10, 20/11).
                    Text(Words.typeset("Tout est prêt : chaque visio rejointe dans Dia s'enregistre toute seule.")).foregroundStyle(.secondary)
                } else {
                    ErrorLine("Il manque quelque chose pour que les réunions s'enregistrent toutes seules.")
                }
            }
            Section {
                ForEach(model.items) { item in row(item) }
                HStack {
                    Button("Tout revérifier") { Task { await model.testAll(prompt: false) } }
                    Spacer()
                    // A link that acts: a word at the app's accent, the discreet role (design system v2, 19/11).
                    TextButton("Sondes de mesure…", action: openProbes)
                }
            } header: {
                Text(connections == nil ? "" : "Réunions : les vérifications")
            }
    }

    @ViewBuilder private func row(_ item: ChecklistItem) -> some View {
        let state = model.states[item] ?? .unknown
        HStack(alignment: .top, spacing: Space.m) {
            stateIcon(state, testing: model.testing.contains(item))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                // French typography, laid at display (lot 10, 20/11).
                Text(Words.typeset(item.explanation)).font(.meta).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if let reason = state.reason {
                    // In the text's color: the icon on the left carries the attention (design system v2, 19/11).
                    Text(Words.typeset(reason)).font(.meta).foregroundStyle(.primary)
                }
                if item == .relaunch, let startup { RelaunchProblem(startup: startup) }
            }
            Spacer()
            if item == .relaunch {
                if let startup { RelaunchSwitch(startup: startup, model: model, title: item.title) }
            } else {
                Button(state == .missing ? "Autoriser" : "Tester") {
                    Task { await model.test(item, prompt: state == .missing) }
                }
                .disabled(model.testing.contains(item))
                if state != .ok, let url = item.settingsURL {
                    // macOS's settings, named as in Réglages › Notifications: hub has its own Réglages.
                    Button("Ouvrir Réglages Système") { NSWorkspace.shared.open(url) }
                }
            }
        }
    }

    @ViewBuilder private func stateIcon(_ state: ItemState, testing: Bool) -> some View {
        if testing {
            ProgressView().controlSize(.small).frame(width: 22)
        } else {
            // Ready in the color of « done »; missing or refused, in the color of what is to check (design system v2,
            // 19/11): one color for « something is wrong », the symbol tells which.
            switch state {
            case .ok: Image(systemName: "checkmark.circle.fill").foregroundStyle(Tint.done).font(.title3)
            case .missing: Image(systemName: "circle.dashed").foregroundStyle(Tint.attention).font(.title3)
            case .denied, .notRunning: Image(systemName: "xmark.octagon.fill").foregroundStyle(Tint.attention).font(.title3)
            case .unknown: Image(systemName: "questionmark.circle").foregroundStyle(.secondary).font(.title3)
            }
        }
    }
}

/// The Diagnostic's switch of the relaunch (lot 7, 19/11): Général's own, with its questions and its wait for the end of a
/// meeting; the line's state is read again once it changed.
private struct RelaunchSwitch: View {
    @ObservedObject var startup: StartupControl
    @ObservedObject var model: DiagnosticModel
    let title: String

    var body: some View {
        StartupSwitch(startup: startup, title: title)
            .toggleStyle(.switch)
            .labelsHidden()
            .onChange(of: startup.isOn) { _, _ in Task { await model.test(.relaunch, prompt: false) } }
    }
}

/// What holds the relaunch back, as Général says it: a meeting under way, a refusal of macOS.
private struct RelaunchProblem: View {
    @ObservedObject var startup: StartupControl

    var body: some View {
        if let message = startup.message { ErrorLine(message).font(.meta) }
    }
}

/// « Autorisations et connexions » (21/11, Paul: « une page avec tout ce qu'il y a à accepter… pour quel outil c'est
/// nécessaire… voir tout ce qui est connecté ») : what the installed tools need from macOS and from the accounts, once
/// each, with the tools it serves and the button that settles it. Read again every two seconds: an authorization given
/// in Réglages Système shows at once.
struct ConnectionsSection: View {
    @ObservedObject var control: AddOnControl
    let notifications: NotificationHub?
    @State private var tick = 0

    var body: some View {
        let list = AddOnNeeds.connections(installed: control.installed, control.facts())
        Section {
            if list.isEmpty && notifications == nil {
                Text(Words.typeset("Tes outils ne demandent rien de plus.")).foregroundStyle(.secondary)
            }
            ForEach(list) { connection in
                ConnectionRow(connection: connection) { control.settle(connection.need) }
            }
            if let notifications { NotificationsPermissionRow(hub: notifications) }
        } header: {
            Text("Autorisations et connexions")
        } footer: {
            Text(Words.typeset("Ce que tes outils demandent à macOS et à tes comptes. Une autorisation se retire dans Réglages Système › Confidentialité."))
                .font(.meta).foregroundStyle(.secondary)
        }
        .id(tick)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                tick += 1
            }
        }
    }
}

/// One thing to allow or to connect: done or not, for whom, and its button.
struct ConnectionRow: View {
    let connection: AddOnConnection
    let settle: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.m) {
            Image(systemName: connection.need.done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(connection.need.done ? AnyShapeStyle(Tint.done) : AnyShapeStyle(Tint.attention))
                .accessibilityLabel(connection.need.done ? "Fait" : "À faire")
            VStack(alignment: .leading, spacing: 2) {
                Text(Words.typeset(connection.need.title))
                // The tools that ask for it, with their badges (21/11).
                HStack(spacing: Space.xs) {
                    ForEach(connection.tools, id: \.self) { AddOnBadge(addOn: $0, size: .mini) }
                    Text(connection.forWhom).font(.tag).foregroundStyle(.secondary)
                }
                if let note = connection.need.note {
                    Text(Words.typeset(note)).font(.meta).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: Space.s)
            if let button = connection.need.button {
                Button(button, action: settle).buttonStyle(.secondary).fixedSize()
            }
        }
    }
}

/// macOS's answer for hub's notifications, in the Diagnostic's list.
struct NotificationsPermissionRow: View {
    @ObservedObject var hub: NotificationHub

    var body: some View {
        let denied = hub.authorization == .denied
        HStack(alignment: .firstTextBaseline, spacing: Space.m) {
            Image(systemName: denied ? "circle" : "checkmark.circle.fill")
                .foregroundStyle(denied ? AnyShapeStyle(Tint.attention) : AnyShapeStyle(Tint.done))
                .accessibilityLabel(denied ? "À faire" : "Fait")
            VStack(alignment: .leading, spacing: 2) {
                Text("Les notifications")
                Text("Pour les rappels, les mails, les comptes rendus et Colin").font(.tag).foregroundStyle(.secondary)
            }
            Spacer(minLength: Space.s)
            if denied {
                Button("Ouvrir Réglages Système") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
                }
                .buttonStyle(.secondary).fixedSize()
            }
        }
        .task { await hub.readAuthorization() }
    }
}
