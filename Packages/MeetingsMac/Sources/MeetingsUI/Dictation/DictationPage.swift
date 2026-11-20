import HubDesign
import Persistence
import SwiftUI

/// « Dictée » in the sidebar (20/11): « Historique », what Paul said, each line to copy; « Mémoire », his words and his
/// corrections, and the names hub already knows.
struct DictationPage: View {
    @ObservedObject var library: DictationLibrary
    @State private var part = Part.history
    @State private var newWord = ""
    @State private var heard = ""
    @State private var written = ""

    enum Part: String, CaseIterable {
        case history = "Historique"
        case memory = "Mémoire"
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $part) {
                ForEach(Part.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 280)
            .padding(.vertical, Space.m)
            switch part {
            case .history: history
            case .memory: memory
            }
        }
        .windowTitle("Dictée", subtitle: part.rawValue)
        .belowToolbar()
    }

    @ViewBuilder private var history: some View {
        if library.history.isEmpty {
            ContentUnavailableView("Aucune dictée", systemImage: "waveform",
                                   description: Text(Words.typeset("Tiens \(DictationKey.current.title) et parle : tes mots s'écrivent là où est ton curseur.")))
        } else {
            List(library.history) { row in
                HStack(alignment: .firstTextBaseline, spacing: Space.m) {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text(row.text).textSelection(.enabled)
                        Text([Words.shortMoment(row.createdAt, now: Date()), row.app].compactMap { $0 }.joined(separator: " · "))
                            .font(.meta).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: Space.m)
                    Button("Copier") { library.copy(row) }
                        .buttonStyle(.borderless)
                    Button(role: .destructive) { library.delete(row) } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless)
                        .help("Supprimer cette dictée")
                        .accessibilityLabel("Supprimer cette dictée")
                }
                .padding(.vertical, Space.xs)
            }
        }
    }

    private var memory: some View {
        Form {
            Section {
                HStack {
                    TextField("Un mot, un nom", text: $newWord)
                        .onSubmit(addWord)
                    Button("Ajouter", action: addWord).disabled(newWord.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                ForEach(library.words) { row in
                    HStack {
                        Text(row.word)
                        Spacer()
                        Button("Retirer", role: .destructive) { library.removeWord(row.word) }.buttonStyle(.borderless)
                    }
                }
            } header: {
                Text("Tes mots")
            } footer: {
                Text(Words.typeset("Whisper les connaît d'avance, avec tes projets, leurs clients et tes contacts (\(library.known.count))."))
                    .font(.meta).foregroundStyle(.secondary)
            }
            Section {
                HStack {
                    TextField("Entendu", text: $heard)
                    Image(systemName: "arrow.right").foregroundStyle(.secondary)
                    TextField("Écrit", text: $written)
                        .onSubmit(addCorrection)
                    Button("Ajouter", action: addCorrection).disabled(heard.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                ForEach(library.replacements) { row in
                    HStack {
                        Text(row.heard).foregroundStyle(.secondary)
                        Image(systemName: "arrow.right").foregroundStyle(.tertiary)
                        Text(row.written)
                        Spacer()
                        Button("Retirer", role: .destructive) { library.removeReplacement(row.heard) }.buttonStyle(.borderless)
                    }
                }
            } header: {
                Text("Corrections")
            } footer: {
                Text(Words.typeset("Ce que Whisper entend de travers, remplacé par ce que tu veux dire, mot entier, majuscules ou non."))
                    .font(.meta).foregroundStyle(.secondary)
            }
        }
        .settingsForm()
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private func addWord() {
        library.addWord(newWord)
        newWord = ""
    }

    private func addCorrection() {
        library.setReplacement(heard: heard, written: written)
        heard = ""
        written = ""
    }
}

/// Réglages › Dictée (20/11): the key, the language, and the Accessibility hub needs to paste.
struct DictationSettingsPane: View {
    @ObservedObject var service: DictationService
    @AppStorage(Preferences.Key.dictationKey) private var key = DictationKey.rightOption.rawValue
    @AppStorage(Preferences.Key.dictationLanguage) private var language = "fr"

    var body: some View {
        Form {
            Section {
                SettingRow("Touche", help: "Tiens-la pour parler ; deux appuis pour parler mains libres, Échap pour annuler") {
                    Picker("Touche", selection: $key) {
                        ForEach(DictationKey.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
                    }
                    .fixedSize()
                }
                SettingRow("Langue", help: "Automatique reconnaît la langue de chaque dictée, un peu plus lentement") {
                    Picker("Langue", selection: $language) {
                        Text("Français").tag("fr")
                        Text("Automatique").tag("auto")
                    }
                    .fixedSize()
                }
            }
            Section {
                SettingRow("Accessibilité", help: service.trusted ? "Accordée : hub colle tes mots là où tu écris"
                    : "À donner : sans elle, la touche ne marche que dans hub, et tes mots sont seulement copiés") {
                    if service.trusted {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Tint.done)
                    } else {
                        Button("Ouvrir les Réglages Système") { service.askAccessibility() }
                    }
                }
                SettingRow("État", help: state) { EmptyView() }
            }
        }
        .settingsForm()
    }

    private var state: String {
        switch service.phase {
        case .loading: "Whisper se charge (une vingtaine de secondes après le lancement)"
        case .ready: "Prête"
        case .listening: "À l'écoute"
        case .writing: "J'écris"
        case .failed(let reason): reason
        }
    }
}
