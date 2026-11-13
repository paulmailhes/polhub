import AppKit
import Recording
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
        case .relaunch: "Relancer Polhub s'il plante, et l'ouvrir à chaque session"
        }
    }

    var explanation: String {
        switch self {
        case .microphone: "Pour enregistrer ta voix."
        case .systemAudio: "Pour enregistrer le son des autres, dans Dia. Vérifié par un son inaudible."
        case .diaAutomation: "Pour voir qu'un onglet Google Meet s'ouvre."
        case .models: "Pour transcrire sur ton Mac, hors ligne : WhisperKit et le détecteur de voix, téléchargés une fois."
        case .relaunch: "Sans cela, une réunion n'est enregistrée que si tu as ouvert Polhub toi-même."
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
}

/// The checks of the first launch, run again from the Diagnostic page or when macOS or Dia changes.
@MainActor
public final class DiagnosticModel: ObservableObject {
    @Published public private(set) var states: [ChecklistItem: ItemState] = [:]
    @Published public private(set) var testing: Set<ChecklistItem> = []
    @Published public var relaunchMessage: String?
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
            && (states[.diaAutomation] == .ok || states[.diaAutomation] == .denied("Dia n'est pas ouvert"))
    }

    func set(_ item: ChecklistItem, _ state: ItemState) {
        states[item] = state
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
        case .microphone: states[item] = Self.state(item, from: status.microphone)
        case .systemAudio: states[item] = Self.state(item, from: status.systemAudio)
        case .diaAutomation: states[item] = Self.state(item, from: status.appleEventsDia)
        case .models, .relaunch: break
        }
    }

    public func testAll(prompt: Bool) async {
        states[.relaunch] = relaunchEnabled() ? .ok : .missing
        checkModels()
        testing = Set(items).subtracting([.models, .relaunch])
        let status = await PermissionCheck.run(prompt: prompt, testSystemAudio: true, amplitude: amplitude)
        states[.microphone] = Self.state(.microphone, from: status.microphone)
        states[.systemAudio] = Self.state(.systemAudio, from: status.systemAudio)
        states[.diaAutomation] = Self.state(.diaAutomation, from: status.appleEventsDia)
        testing = []
    }

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
        case (.diaAutomation, "notRunning"): .denied("Dia n'est pas ouvert")
        default: .denied(answer)
        }
    }
}

/// The Diagnostic page: each permission, its state, and how to fix it.
public struct DiagnosticView: View {
    @ObservedObject var model: DiagnosticModel
    let openProbes: () -> Void

    public init(model: DiagnosticModel, openProbes: @escaping () -> Void) {
        self.model = model
        self.openProbes = openProbes
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Diagnostic").font(.title2.bold())
                Text(model.allGood
                     ? "Tout est prêt : chaque Meet ouvert dans Dia s'enregistre tout seul."
                     : "Il manque quelque chose pour que les réunions s'enregistrent toutes seules.")
                    .foregroundStyle(model.allGood ? Color.secondary : Color.orange)

                ForEach(model.items) { item in
                    row(item)
                    Divider()
                }

                HStack {
                    Button("Tout revérifier") { Task { await model.testAll(prompt: false) } }
                    Spacer()
                    Button("Sondes de mesure…", action: openProbes).buttonStyle(.link)
                }
            }
            .padding(24)
            .frame(maxWidth: 720, alignment: .leading)
        }
        .task { if model.states.isEmpty { await model.testAll(prompt: false) } }
    }

    @ViewBuilder private func row(_ item: ChecklistItem) -> some View {
        let state = model.states[item] ?? .unknown
        HStack(alignment: .top, spacing: 12) {
            stateIcon(state, testing: model.testing.contains(item))
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).font(.headline)
                Text(item.explanation).font(.callout).foregroundStyle(.secondary)
                if case .denied(let reason) = state {
                    Text(reason).font(.callout).foregroundStyle(.red)
                }
                if item == .relaunch, let message = model.relaunchMessage {
                    Text(message).font(.callout).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if item == .relaunch {
                Toggle("", isOn: Binding(get: { state == .ok }, set: { model.toggleRelaunch($0) }))
                    .toggleStyle(.switch)
                    .labelsHidden()
            } else {
                Button(state == .missing ? "Autoriser" : "Tester") {
                    Task { await model.test(item, prompt: state == .missing) }
                }
                .disabled(model.testing.contains(item))
                if state != .ok, let url = item.settingsURL {
                    Button("Ouvrir les réglages") { NSWorkspace.shared.open(url) }
                }
            }
        }
    }

    @ViewBuilder private func stateIcon(_ state: ItemState, testing: Bool) -> some View {
        if testing {
            ProgressView().controlSize(.small).frame(width: 22)
        } else {
            switch state {
            case .ok: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.title3)
            case .missing: Image(systemName: "circle.dashed").foregroundStyle(.orange).font(.title3)
            case .denied: Image(systemName: "xmark.octagon.fill").foregroundStyle(.red).font(.title3)
            case .unknown: Image(systemName: "questionmark.circle").foregroundStyle(.secondary).font(.title3)
            }
        }
    }
}
