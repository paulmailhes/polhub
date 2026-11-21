import HubDesign
import SwiftUI
import VigieKit

/// Réglages › Vigie (21/11, the migration: Paul turns the app Vigie off, its settings come here): what the engine does
/// for Claude Code — Auto-accept, the questions when Paul is away, the safeguards —, and the engine itself.
struct VigieSettingsPane: View {
    @ObservedObject var library: VigieLibrary

    var body: some View {
        Form {
            if let settings = library.settings {
                Section("Claude Code") {
                    SettingRow("Auto-accept", help: VigieWords.autoAcceptHelp) {
                        Toggle("Auto-accept", isOn: bind(settings.autoAccept) { await library.setAutoAccept($0) })
                    }
                    SettingRow("Quand je ne suis pas là, Claude choisit l'option recommandée", help: VigieSettingsText.questionsHelp) {
                        Toggle("Réponse automatique", isOn: bind(settings.questionsAuto) { await library.setQuestionsAuto($0) })
                    }
                    if settings.questionsAuto {
                        Picker("Après", selection: bind(settings.questionWaitMinutes) { await library.setQuestionWait($0) }) {
                            ForEach(VigieSettingsText.questionWaits(settings.questionWaitMinutes), id: \.self) { Text(Words.duration($0 * 60)).tag($0) }
                        }
                    }
                }
                Section("Garde-fous") {
                    SettingRow("Garde-fous", help: VigieSettingsText.safeguardsHelp) {
                        Toggle("Garde-fous", isOn: bind(settings.safeguards.enabled) { await library.setSafeguards($0) })
                    }
                    if settings.safeguards.enabled {
                        Picker("Refusée d'office après", selection: bind(settings.safeguards.waitMinutes) { await library.setSafeguardWait($0) }) {
                            ForEach(VigieSettingsText.safeguardWaits(settings.safeguards.waitMinutes), id: \.self) { minutes in
                                Text(minutes == 0 ? "Tout de suite" : Words.duration(minutes * 60)).tag(minutes)
                            }
                        }
                        ForEach(settings.safeguards.rules) { rule in
                            Toggle(Words.typeset(rule.label), isOn: bind(!rule.disabled) { await library.setRule(rule.id, on: $0) })
                        }
                    }
                }
                Section("Moteur") {
                    if let autoUpdate = settings.autoUpdate {
                        SettingRow("Mises à jour automatiques", help: VigieSettingsText.autoUpdateHelp) {
                            Toggle("Mises à jour automatiques", isOn: bind(autoUpdate) { await library.setAutoUpdate($0) })
                        }
                    }
                    if let stopForgotten = settings.stopForgotten {
                        SettingRow("Arrêter les Chrome oubliés", help: VigieSettingsText.stopForgottenHelp) {
                            Toggle("Arrêter les Chrome oubliés", isOn: bind(stopForgotten) { await library.setStopForgotten($0) })
                        }
                    }
                    if let connectors = settings.connectorsDefault {
                        SettingRow("MCP du compte dans les nouvelles conversations", help: VigieSettingsText.connectorsHelp) {
                            Toggle("MCP du compte", isOn: bind(connectors == "on") { await library.setConnectorsDefault($0) })
                        }
                    }
                    SettingRow("Relancer le moteur", help: VigieSettingsText.restartHelp) {
                        Button("Relancer") { Task { await library.restartEngine() } }
                            .disabled(library.sending.contains("moteur"))
                    }
                }
            } else {
                Section {
                    Text(Words.typeset(VigieSettingsText.unavailable(library.link))).foregroundStyle(.secondary)
                    Button("Relancer le moteur") { Task { await library.restartEngine() } }
                        .disabled(library.sending.contains("moteur") || library.link == .absent)
                }
            }
            // The notifications of Vigie, kind by kind, as the app Vigie's (21/11: « les notifications dans chaque outil »).
            Section {
                ForEach(VigieNotifications.Kind.allCases, id: \.self) { kind in VigieNotifyToggle(kind: kind) }
            } header: {
                Text("Notifications")
            } footer: {
                Text(Words.typeset(VigieNotifier.isAppRunning() ? VigieSettingsText.appNotifies : VigieSettingsText.hubNotifies))
                    .font(.meta).foregroundStyle(.secondary)
            }
            if let problem = library.problem {
                Section { ErrorLine(problem) }
            }
        }
        .settingsForm()
        .onAppear { library.isVisible = true }
        .onDisappear { library.isVisible = false }
    }

    /// A setting shown as the engine holds it, sent when it changes.
    private func bind<Value: Sendable>(_ value: Value, _ set: @escaping @MainActor (Value) async -> Void) -> Binding<Value> {
        Binding(get: { value }, set: { new in Task { @MainActor in await set(new) } })
    }
}

/// The words of Réglages › Vigie.
enum VigieSettingsText {
    static let questionsHelp = "Passé le délai, Vigie répond pour toi ; tu relis ses choix dans la Vue d'ensemble."
    static let safeguardsHelp = "Les actions sensibles (sudo, suppression, envoi forcé…) attendent ta décision."
    static let autoUpdateHelp = "Chaque nouvelle version de Vigie réinstalle et relance l'app Vigie : coupe-les pour t'en passer."
    static let stopForgottenHelp = "Les fenêtres de Chrome laissées par les agents s'arrêtent seules quand leur conversation est finie."
    static let connectorsHelp = "Gmail, Drive… branchés d'office dans chaque nouvelle conversation de Claude Code."
    static let restartHelp = "Quand il ne répond plus : macOS le relance, rien n'est perdu."
    static let appNotifies = "L'app Vigie tourne : c'est elle qui notifie. hub prend le relais dès qu'elle est fermée."
    static let hubNotifies = "hub notifie à la place de l'app Vigie ; une attente finie retire sa notification."

    /// The waits the engine takes for the questions (1 to 120 min), the current one kept.
    static func questionWaits(_ current: Int) -> [Int] {
        Array(Set([5, 10, 20, 30, 60, current])).sorted()
    }

    /// The waits before an action is refused (0 to 120 min), the current one kept.
    static func safeguardWaits(_ current: Int) -> [Int] {
        Array(Set([0, 2, 5, 10, 20, 30, current])).sorted()
    }

    static func unavailable(_ link: VigieLibrary.Link) -> String {
        switch link {
        case .absent: "Le moteur de Vigie n'est pas sur ce Mac : ses réglages viendront avec lui."
        case .stopped: "Le moteur de Vigie ne répond pas : relance-le pour régler Vigie."
        case .unknown: "hub demande ses réglages à Vigie…"
        case .trouble(let why): why
        case .running: "Vigie n'a pas encore donné ses réglages."
        }
    }
}

/// A kind of Vigie's notifications, on or off.
struct VigieNotifyToggle: View {
    let kind: VigieNotifications.Kind
    @AppStorage private var on: Bool

    init(kind: VigieNotifications.Kind) {
        self.kind = kind
        _on = AppStorage(wrappedValue: true, VigieNotifier.key(kind))
    }

    var body: some View {
        Toggle(Words.typeset(kind.title), isOn: $on)
    }
}
