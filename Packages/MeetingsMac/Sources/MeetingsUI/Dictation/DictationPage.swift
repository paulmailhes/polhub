import AudioCapture
import Dictation
import HubDesign
import Persistence
import SwiftUI
import UniformTypeIdentifiers

/// « Dictée » in the sidebar (20/11; in cards the same evening, Paul: « elle est pas très belle, tu peux mettre des
/// cartes »). Two pages chosen in the toolbar: « Historique », each dictation a card by day, to copy, hear or write again,
/// and the files to transcribe, dropped or chosen; « Mémoire », his words, his corrections, and the names hub knows.
struct DictationPage: View {
    @ObservedObject var library: DictationLibrary
    var service: DictationService?
    @State private var part = Part.history
    @State private var query = ""

    enum Part: String, CaseIterable {
        case history = "Historique"
        case memory = "Mémoire"
    }

    var body: some View {
        Group {
            switch part {
            case .history: DictationHistory(library: library, service: service, query: query)
            case .memory: DictationMemory(library: library)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .windowTitle("Dictée", subtitle: part.rawValue)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Page", selection: $part) {
                    ForEach(Part.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            if let service {
                ToolbarItem(placement: .primaryAction) {
                    Button { DictationHistory.chooseFiles(service) } label: { Label("Transcrire un fichier", systemImage: "waveform.badge.plus") }
                        .help("Transcrire un son ou une vidéo : son texte rejoint l'historique")
                }
            }
        }
        .searchable(text: $query, placement: .toolbar, prompt: "Chercher une dictée")
        .onChange(of: query) { _, value in
            if !value.isEmpty { part = .history }
        }
    }
}

// MARK: - Historique

struct DictationHistory: View {
    @ObservedObject var library: DictationLibrary
    var service: DictationService?
    let query: String
    @State private var dropping = false

    var body: some View {
        Page(maxWidth: PageMetrics.readingWidth, spacing: PageMetrics.cardGap) {
            if let service { DictationWork(service: service) }
            if rows.isEmpty {
                empty
            } else {
                ForEach(days, id: \.title) { day in
                    Text(Words.capitalizedFirst(day.title)).font(.tag.weight(.semibold)).foregroundStyle(.secondary)
                        .padding(.top, Space.s)
                    ForEach(day.rows) { row in
                        DictationCard(row: row, library: library, service: service)
                    }
                }
            }
        }
        .belowToolbar()
        .overlay {
            if dropping {
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                    .foregroundStyle(Tint.accent.opacity(0.5))
                    .padding(Space.m)
                    .allowsHitTesting(false)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let service else { return false }
            for url in urls { service.transcribe(url) }
            return !urls.isEmpty
        } isTargeted: { dropping = $0 }
    }

    private var rows: [DictationRow] {
        query.trimmingCharacters(in: .whitespaces).isEmpty ? library.history : library.search(query)
    }

    /// The dictations by day, the newest first: « Aujourd'hui », « Hier », « Mercredi », « Le 2 novembre ».
    private var days: [(title: String, rows: [DictationRow])] {
        let now = Date()
        var result: [(title: String, rows: [DictationRow])] = []
        for row in rows {
            let title = Words.day(row.createdAt, now: now)
            if result.last?.title == title { result[result.count - 1].rows.append(row) } else { result.append((title, [row])) }
        }
        return result
    }

    @ViewBuilder private var empty: some View {
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            Card {
                SectionTitle("Aucune dictée", systemImage: "waveform")
                Text(Words.typeset("Appuie sur \(DictationKey.current.title), parle, appuie de nouveau : tes mots s'écrivent là où est ton curseur, et chaque dictée se range ici."))
                    .foregroundStyle(.secondary)
                Text(Words.typeset("Glisse un son ou une vidéo sur cette page pour le transcrire."))
                    .font(.meta).foregroundStyle(.secondary)
            }
        } else {
            Card {
                Text(Words.typeset("Aucune dictée ne contient « \(query) »."))
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// « Transcrire un fichier » in the toolbar: sounds and videos, several at once.
    @MainActor static func chooseFiles(_ service: DictationService) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio, .movie]
        panel.allowsMultipleSelection = true
        panel.message = "Choisis un son ou une vidéo : son texte rejoindra l'historique."
        panel.prompt = "Transcrire"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls { service.transcribe(url) }
    }
}

/// The files being written, and what went wrong with the last one.
struct DictationWork: View {
    @ObservedObject var service: DictationService

    var body: some View {
        if let problem = service.fileProblem {
            Banner(.attention, problem) {
                Button("OK") { service.fileProblem = nil }
            }
        }
        ForEach(service.working.filter { $0.key.hasPrefix("fichier-") }.sorted(by: { $0.key < $1.key }), id: \.key) { _, name in
            Card {
                HStack(spacing: Space.m) {
                    ProgressView().controlSize(.small)
                    Text(Words.typeset("Transcription de « \(name) »…")).foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// One dictation: its words, then when, where, how long, and its gestures.
struct DictationCard: View {
    let row: DictationRow
    @ObservedObject var library: DictationLibrary
    var service: DictationService?
    @State private var copied = false

    var body: some View {
        Card {
            Text(row.text)
                .font(.body)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: Space.m) {
                Label(meta, systemImage: row.file == nil ? "waveform" : "doc.text")
                    .font(.meta).foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: Space.s)
                if rewriting {
                    ProgressView().controlSize(.small)
                    Text("Retranscription…").font(.meta).foregroundStyle(.secondary)
                }
                if library.hasSound(row) {
                    Button { library.play(row) } label: {
                        Label(library.playing == row.id ? "Arrêter" : "Écouter", systemImage: library.playing == row.id ? "stop.fill" : "play.fill")
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                }
                Button(copied ? "Copiée" : "Copier") {
                    library.copy(row)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                }
                .buttonStyle(.bordered).controlSize(.small)
                Menu {
                    if library.hasSound(row), let service {
                        Button("Retranscrire avec ta mémoire") { service.rewrite(row) }.disabled(rewriting)
                    }
                    Button("Supprimer", role: .destructive) { library.delete(row) }
                } label: {
                    Label("Plus", systemImage: "ellipsis").labelStyle(.iconOnly)
                }
                .menuStyle(.button).menuIndicator(.hidden).buttonStyle(.borderless).fixedSize()
                .help("Plus")
            }
        }
    }

    private var rewriting: Bool { service?.isRewriting(row) ?? false }

    /// « 21:40 · Claude · 8 s », « 21:12 · memo.m4a · 1 min 02 ».
    private var meta: String {
        [Words.time(row.createdAt), row.file ?? row.app, Words.preciseDuration(Int(row.seconds.rounded()))].compactMap { $0 }
            .joined(separator: " · ")
    }
}

// MARK: - Mémoire

struct DictationMemory: View {
    @ObservedObject var library: DictationLibrary
    @State private var newWord = ""
    @State private var heard = ""
    @State private var written = ""
    @State private var allKnown = false

    var body: some View {
        Page(maxWidth: PageMetrics.readingWidth, spacing: PageMetrics.cardGap) {
            words
            corrections
            if !library.known.isEmpty { known }
        }
        .belowToolbar()
    }

    private var words: some View {
        Card {
            SectionTitle("Tes mots", systemImage: "character.book.closed", count: library.words.count)
            Text(Words.typeset("Des noms, des marques, des mots rares : Whisper les connaît d'avance et les écrit bien."))
                .font(.meta).foregroundStyle(.secondary)
            HStack {
                TextField("Un mot, un nom", text: $newWord)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addWord)
                Button("Ajouter", action: addWord).disabled(newWord.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if !library.words.isEmpty {
                FlowLayout(spacing: Space.s) {
                    ForEach(library.words) { row in
                        MemoryChip(text: row.word) { library.removeWord(row.word) }
                    }
                }
            }
        }
    }

    private var corrections: some View {
        Card {
            SectionTitle("Corrections", systemImage: "arrow.left.arrow.right", count: library.replacements.count)
            Text(Words.typeset("Ce que Whisper entend de travers, remplacé par ce que tu veux dire : le mot entier, majuscules ou non."))
                .font(.meta).foregroundStyle(.secondary)
            HStack {
                TextField("Entendu", text: $heard).textFieldStyle(.roundedBorder)
                Image(systemName: "arrow.right").foregroundStyle(.secondary)
                TextField("Écrit", text: $written).textFieldStyle(.roundedBorder)
                    .onSubmit(addCorrection)
                Button("Ajouter", action: addCorrection).disabled(heard.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            VStack(spacing: 0) {
                ForEach(library.replacements) { row in
                    HStack(spacing: Space.m) {
                        Text(row.heard).foregroundStyle(.secondary)
                        Image(systemName: "arrow.right").foregroundStyle(.tertiary)
                        Text(row.written)
                        Spacer()
                        Button("Retirer") { library.removeReplacement(row.heard) }.buttonStyle(.borderless)
                    }
                    .padding(.vertical, Space.s)
                    if row.id != library.replacements.last?.id { Divider() }
                }
            }
        }
    }

    private var known: some View {
        let names = Self.unique(library.known)
        let shown = allKnown ? names : Array(names.prefix(24))
        return Card {
            SectionTitle("Déjà connus", systemImage: "person.2", count: names.count)
            Text(Words.typeset("Tes projets, leurs clients et tes contacts : hub les donne à Whisper, rien à faire."))
                .font(.meta).foregroundStyle(.secondary)
            FlowLayout(spacing: Space.s) {
                ForEach(shown, id: \.self) { Chip($0) }
            }
            if names.count > shown.count {
                Button("Voir les \(names.count)") { allKnown = true }.buttonStyle(.link)
            }
        }
    }

    static func unique(_ names: [String]) -> [String] {
        var seen: Set<String> = []
        return names.filter { seen.insert($0.lowercased()).inserted }
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

/// A word of the memory, and its ✕.
struct MemoryChip: View {
    let text: String
    let remove: () -> Void

    var body: some View {
        HStack(spacing: Space.xs) {
            Text(text).font(.callout)
            Button(action: remove) { Image(systemName: "xmark").font(.caption.weight(.semibold)) }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Retirer « \(text) »")
                .accessibilityLabel("Retirer \(text)")
        }
        .padding(.horizontal, Space.m)
        .padding(.vertical, Space.xs)
        .background(Surface.fill, in: Capsule())
        .overlay(Capsule().strokeBorder(Surface.stroke))
        .fixedSize()
    }
}

// MARK: - Réglages › Dictée

/// Réglages › Dictée (20/11; the evening's choices of Paul): the key, the window, the text, the sound, the history, and
/// the Accessibility hub needs to paste.
struct DictationSettingsPane: View {
    @ObservedObject var service: DictationService
    @AppStorage(Preferences.Key.dictationKey) private var key = DictationKey.rightOption.rawValue
    @AppStorage(Preferences.Key.dictationLanguage) private var language = "fr"
    @AppStorage(Preferences.Key.dictationMode) private var mode = KeyGesture.Mode.toggle.rawValue
    @AppStorage(Preferences.Key.dictationAutoStop) private var autoStop = DictationSettings.autoStopDefault
    @AppStorage(Preferences.Key.dictationWindowPlace) private var place = "bas"
    @AppStorage(Preferences.Key.dictationLiveText) private var liveText = true
    @AppStorage(Preferences.Key.dictationFillers) private var fillers = true
    @AppStorage(Preferences.Key.dictationSpokenPunctuation) private var spoken = true
    @AppStorage(Preferences.Key.dictationDigits) private var digits = true
    @AppStorage(Preferences.Key.dictationDropFinalPeriod) private var dropPeriod = true
    @AppStorage(Preferences.Key.dictationParagraphPause) private var paragraphs = DictationSettings.paragraphDefault
    @AppStorage(Preferences.Key.dictationTrailingSpace) private var space = true
    @AppStorage(Preferences.Key.dictationSounds) private var sounds = true
    @AppStorage(Preferences.Key.dictationMuteMac) private var mute = true
    @AppStorage(Preferences.Key.dictationPauseMedia) private var pauseMedia = true
    @AppStorage(Preferences.Key.dictationKeepSound) private var keepSound = true
    @AppStorage(Preferences.Key.dictationKeepDays) private var keepDays = 0
    @AppStorage(Preferences.Key.dictationRestoreClipboard) private var restoreClipboard = true

    var body: some View {
        Form {
            Section("La touche") {
                SettingRow("Touche", help: "Celle qui commence et finit une dictée ; Échap annule") {
                    Picker("Touche", selection: $key) {
                        ForEach(DictationKey.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
                    }
                    .fixedSize()
                }
                SettingRow("Façon", help: Self.help(KeyGesture.Mode(rawValue: mode) ?? .toggle)) {
                    Picker("Façon", selection: $mode) {
                        Text("Appuyer, parler, appuyer").tag(KeyGesture.Mode.toggle.rawValue)
                        Text("Tenir pour parler").tag(KeyGesture.Mode.hold.rawValue)
                        Text("Les deux").tag(KeyGesture.Mode.hybrid.rawValue)
                    }
                    .fixedSize()
                }
                SettingRow("Arrêt seul", help: "Si tu oublies d'appuyer : la dictée finit après un long silence") {
                    Picker("Arrêt seul", selection: $autoStop) {
                        Text("Jamais").tag(0.0)
                        Text("Après 5 s de silence").tag(5.0)
                        Text("Après 10 s de silence").tag(10.0)
                        Text("Après 20 s de silence").tag(20.0)
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
            Section("La fenêtre") {
                SettingRow("Place", help: "Où elle apparaît quand tu dictes, sur l'écran de ta souris") {
                    Picker("Place", selection: $place) {
                        Text("En bas").tag("bas")
                        Text("En haut").tag("haut")
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
                SettingRow("Mots en direct", help: "Tes mots s'écrivent dans la fenêtre pendant que tu parles") {
                    Toggle("Mots en direct", isOn: $liveText)
                }
            }
            Section("Le texte") {
                SettingRow("Sans les « euh »", help: "Les « euh », « hum », « bah » sont retirés") {
                    Toggle("Sans les euh", isOn: $fillers)
                }
                SettingRow("Ponctuation dite", help: "« à la ligne », « nouveau paragraphe », « virgule », « point d'interrogation »… deviennent des signes") {
                    Toggle("Ponctuation dite", isOn: $spoken)
                }
                SettingRow("Nombres en chiffres", help: "« dix heures trente » donne « 10 h 30 », « vingt-cinq euros » « 25 € »") {
                    Toggle("Nombres en chiffres", isOn: $digits)
                }
                SettingRow("Sans point final", help: "Une phrase seule finit sans point, comme dans un message") {
                    Toggle("Sans point final", isOn: $dropPeriod)
                }
                SettingRow("Paragraphes", help: "Une longue pause, quand tu changes de sujet, commence un paragraphe") {
                    Picker("Paragraphes", selection: $paragraphs) {
                        Text("Jamais").tag(0.0)
                        Text("Après 2 s de pause").tag(2.0)
                        Text("Après 3 s de pause").tag(3.0)
                        Text("Après 5 s de pause").tag(5.0)
                    }
                    .fixedSize()
                }
                SettingRow("Espace après", help: "Une espace après le texte collé, pour enchaîner la dictée suivante") {
                    Toggle("Espace après", isOn: $space)
                }
            }
            Section("Le son") {
                DictationMicrophones()
                SettingRow("Petits sons", help: "Un son discret quand la dictée commence et quand elle finit") {
                    Toggle("Petits sons", isOn: $sounds)
                }
                SettingRow("Couper le son du Mac", help: "Pendant que tu dictes, puis il revient ; jamais pendant une réunion que hub enregistre") {
                    Toggle("Couper le son du Mac", isOn: $mute)
                }
                SettingRow("Pause musique et vidéo", help: "Ce qui joue se met en pause, puis reprend ; hub ne relance que ce qu'il a arrêté") {
                    Toggle("Pause musique et vidéo", isOn: $pauseMedia)
                }
            }
            Section("L'historique") {
                SettingRow("Garder le son", help: "Pour réécouter une dictée, ou la retranscrire ; il reste sur ce Mac") {
                    Toggle("Garder le son", isOn: $keepSound)
                }
                SettingRow("Garder l'historique", help: "Au-delà, les dictées et leur son s'effacent seuls") {
                    Picker("Garder l'historique", selection: $keepDays) {
                        Text("Toujours").tag(0)
                        Text("90 jours").tag(90)
                        Text("30 jours").tag(30)
                        Text("7 jours").tag(7)
                    }
                    .fixedSize()
                }
                SettingRow("Presse-papiers", help: restoreClipboard ? "Rendu comme avant après le collage ; ta dictée reste dans l'historique"
                    : "Ta dictée y reste après le collage") {
                    Toggle("Rendre le presse-papiers", isOn: $restoreClipboard)
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

    static func help(_ mode: KeyGesture.Mode) -> String {
        switch mode {
        case .toggle: "Un appui commence, un appui finit : tu ne restes pas appuyé"
        case .hold: "Tiens la touche le temps de parler ; deux appuis brefs pour parler mains libres"
        case .hybrid: "Un appui bref commence, un appui finit ; tenue longtemps, elle finit quand tu la lâches"
        }
    }

    private var state: String {
        switch service.phase {
        case .starting: "La Dictée démarre"
        case .ready: service.whisperLoaded ? "Prête" : "Prête ; Whisper finit de se charger, ta dictée sera écrite dès qu'il est là"
        case .listening: "À l'écoute"
        case .writing: "J'écris"
        case .failed(let reason): reason
        }
    }
}

/// « Micros »: the microphones in Paul's order; the first connected is used, else the system's (20/11 in the evening).
struct DictationMicrophones: View {
    @AppStorage(Preferences.Key.dictationMicrophones) private var stored = ""
    @State private var connected: [Microphone] = []
    @State private var systemUID: String?
    /// The microphone that records talks by Bluetooth.
    @State private var bluetooth = false
    /// The names of the microphones seen, for those not connected now.
    @AppStorage(Preferences.Key.dictationMicrophoneNames) private var names = ""

    var body: some View {
        SettingRow("Micros", help: "Le premier branché sert ; sinon celui du système. Range-les avec les flèches",
                   problem: bluetooth ? "Ton micro est en Bluetooth : il met jusqu'à une seconde à s'ouvrir, et tes premiers mots peuvent manquer. Mets le micro du Mac en premier pour parler dès l'appui." : nil) {
            EmptyView()
        }
        // On the row always there: an empty list never appears.
        .onAppear(perform: refresh)
        ForEach(Array(list.enumerated()), id: \.element.uid) { index, microphone in
            HStack(spacing: Space.m) {
                Image(systemName: isConnected(microphone) ? "mic.fill" : "mic.slash").foregroundStyle(.secondary).frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(microphone.name)
                    Text(status(microphone)).font(.meta).foregroundStyle(.secondary)
                }
                Spacer()
                Button { move(index, by: -1) } label: { Image(systemName: "chevron.up") }
                    .buttonStyle(.borderless).disabled(index == 0)
                    .help("Monter").accessibilityLabel("Monter \(microphone.name)")
                Button { move(index, by: 1) } label: { Image(systemName: "chevron.down") }
                    .buttonStyle(.borderless).disabled(index == list.count - 1)
                    .help("Descendre").accessibilityLabel("Descendre \(microphone.name)")
            }
            .padding(.leading, Space.l)
        }
    }

    private var order: [String] { stored.split(separator: "\n").map(String.init) }

    private var known: [String: String] {
        Dictionary(names.split(separator: "\n").compactMap { line -> (String, String)? in
            let parts = line.split(separator: "\t", maxSplits: 1).map(String.init)
            return parts.count == 2 ? (parts[0], parts[1]) : nil
        }, uniquingKeysWith: { _, last in last })
    }

    private var list: [Microphone] {
        DictationSettings.ordered(order, connected: connected, known: known)
    }

    private func isConnected(_ microphone: Microphone) -> Bool { connected.contains { $0.uid == microphone.uid } }

    /// The one that records: the first connected of Paul's order, else the system's.
    private var used: String? {
        DictationSettings(defaults: .standard).microphone(connected: connected) ?? systemUID
    }

    private func status(_ microphone: Microphone) -> String {
        guard isConnected(microphone) else { return "Absent" }
        guard used == microphone.uid else { return "Branché" }
        return order.contains(microphone.uid) ? "Branché · c'est lui qui sert" : "Branché · c'est lui qui sert, celui du système"
    }

    /// The order is written only when Paul moves one: until then, the system's microphone records.
    private func refresh() {
        connected = Devices.microphones()
        systemUID = Devices.defaultInput().flatMap(Devices.uid)
        var all = known
        for microphone in connected { all[microphone.uid] = microphone.name }
        names = all.map { "\($0.key)\t\($0.value)" }.sorted().joined(separator: "\n")
        bluetooth = used.flatMap(Devices.device(uid:)).map(Devices.isBluetooth) ?? false
    }

    private func move(_ index: Int, by offset: Int) {
        var uids = list.map(\.uid)
        let target = index + offset
        guard uids.indices.contains(index), uids.indices.contains(target) else { return }
        uids.swapAt(index, target)
        stored = uids.joined(separator: "\n")
        bluetooth = used.flatMap(Devices.device(uid:)).map(Devices.isBluetooth) ?? false
    }
}
