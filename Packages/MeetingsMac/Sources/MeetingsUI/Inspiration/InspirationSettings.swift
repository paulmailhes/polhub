import AppKit
import Persistence
import HubDesign
import SwiftUI

/// Réglages › Inspiration (16/11): the LinkedIn pages followed, the automatic collection and how its last runs went,
/// the categories by Apple's AI. The vault's import is gone with the vault (16/11).
struct InspirationSettingsPane: View {
    @ObservedObject var library: InspirationLibrary
    @ObservedObject var router: WindowRouter
    @AppStorage(Preferences.Key.inspirationAutoCollect) private var autoCollect = true
    @AppStorage(Preferences.Key.inspirationAICategories) private var aiCategories = true
    @State private var editing: SourceDraft?
    @State private var removing: InspirationSourceRow?

    struct SourceDraft: Identifiable {
        let id = UUID()
        let source: InspirationSourceRow?
    }

    var body: some View {
        Form {
            sourcesSection
            collectionSection
            Section {
                SettingRow("Catégories par l'IA d'Apple", help: InspirationSettingsText.aiHelp) {
                    Toggle("Catégories par l'IA d'Apple", isOn: $aiCategories)
                }
            }
        }
        .settingsForm()
        .sheet(item: $editing) { draft in InspirationSourceSheet(library: library, source: draft.source) }
        .confirmationDialog("Ne plus suivre « \(removing?.name ?? "") » ?",
                            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), presenting: removing) { source in
            Button("Ne plus la suivre", role: .destructive) { library.deleteSource(source) }
        } message: { _ in
            // « post », LinkedIn's word, everywhere (lot 10, 20/11).
            Text("Ses posts restent dans Branding.")
        }
        .task {
            while !Task.isCancelled {
                await library.refreshStatus()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    // MARK: - The LinkedIn pages

    private var sourcesSection: some View {
        Section {
            if library.sources.isEmpty {
                Text("Aucune page pour l'instant.").font(.meta).foregroundStyle(.secondary)
            }
            ForEach(library.sources) { source in sourceRow(source) }
            Button { editing = SourceDraft(source: nil) } label: { Label("Ajouter une page LinkedIn", systemImage: "plus") }
                .buttonStyle(.hover)
            // In the card, under the pages it explains (lot 7, 19/11).
            SettingHelp(InspirationSettingsText.sourcesHelp)
        } header: {
            Text("Pages LinkedIn")
        }
    }

    private func sourceRow(_ source: InspirationSourceRow) -> some View {
        let line = InspirationSettingsText.sourceLine(source, status: library.status(for: source.link))
        return HStack(spacing: Space.m) {
            ColorDot(Color(hex: InspirationBrowse.color(ofSource: source.name, in: library.sources)), size: 10)
            VStack(alignment: .leading, spacing: 1) {
                Text(source.name).font(.rowBody.weight(.medium))
                // A problem: the icon of attention in its color, the sentence in the text's own, never an orange
                // sentence (design system v2, 19/11).
                Group {
                    if line.problem {
                        ErrorLine(line.text)
                    } else {
                        Text(line.text).foregroundStyle(.secondary)
                    }
                }
                .font(.meta)
                .lineLimit(2)
            }
            Spacer(minLength: Space.s)
            // A verb and its object, as the sheet and the dialog name them (lot 10, 20/11).
            IconButton("pencil", help: "Modifier « \(source.name) »", size: 13) { editing = SourceDraft(source: source) }
            IconButton("trash", help: "Ne plus suivre « \(source.name) »", size: 13) { removing = source }
        }
    }

    // MARK: - The collection

    private var collectionSection: some View {
        Section {
            SettingRow("Collecte automatique", help: InspirationSettingsText.collectHelp, detail: InspirationSettingsText.collectDetail) {
                Toggle("Collecte automatique", isOn: $autoCollect)
            }
            let lines = library.status.filter { line in !library.sources.contains { $0.link == line.id } }
            if lines.isEmpty {
                Text(InspirationSettingsText.noRunYet).font(.meta).foregroundStyle(.secondary)
            }
            ForEach(lines) { line in
                let text = InspirationSettingsText.statusLine(line)
                // As a page's line: a problem in one line, never in orange (design system v2, 19/11). « Awwwards : … », the
                // French typography laid; never on a page's line, which shows its link (lot 10, 20/11).
                Group {
                    if text.problem {
                        ErrorLine(text.text)
                    } else {
                        Text(Words.typeset(text.text)).foregroundStyle(.secondary)
                    }
                }
                .font(.meta)
            }
            HStack(spacing: Space.s) {
                Button("Collecter maintenant") { Task { await library.collectNow() } }
                    .disabled(library.collecting)
                if library.collecting { ProgressView().controlSize(.small) }
                Spacer()
            }
            // Each place says its own problem on its line (review of 16/11: a shared message here only ever showed
            // other gestures' errors).
        } header: {
            Text("Collecte")
        }
    }
}

/// The words of Réglages › Inspiration, pure.
enum InspirationSettingsText {
    static let noRunYet = "Pas encore de collecte."

    // One line of help under each setting, the long detail behind « ⓘ » (lot 7, 19/11).
    static let sourcesHelp = "Leurs 10 derniers posts, lus sans compte ni cookie ; la couleur les marque dans Branding."
    static let collectHelp = "Awwwards et tes pages LinkedIn, plusieurs fois par jour, quand Polhub est ouvert."
    // Fifteen words at most a sentence (lot 10, 20/11).
    static let collectDetail = "Le site du jour d'Awwwards toutes les 2 heures, de 8 h à 22 h. Les pages LinkedIn à 9 h, 14 h et 20 h, et au réveil du Mac. Seulement quand Polhub est ouvert, jamais dans la version de développement."
    // « l'IA d'Apple », never « le modèle d'Apple » (lot 10, 20/11).
    static let aiHelp = "L'IA d'Apple, sur le Mac, range chaque nouvelle fiche ; jamais celles que tu as rangées."

    /// Every help of the page, for its test.
    static let helps = [sourcesHelp, collectHelp, aiHelp]

    /// « linkedin.com/company/studio-exemple · lue aujourd'hui 14:02, 2 nouveaux posts », or what went wrong. A
    /// reading restored from the base says no count: it is not known. The count accorded by `Words` (lot 10, 20/11).
    static func sourceLine(_ source: InspirationSourceRow, status: InspirationStatusLine?, now: Date = Date()) -> (text: String, problem: Bool) {
        let link = source.link.replacingOccurrences(of: "https://www.", with: "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let problem = status?.problem ?? source.lastError
        let date = [status?.lastRun, source.lastReadAt].compactMap { $0 }.max()
        if let problem {
            return ("\(problem)" + (date.map { " (\(when($0, now: now)))" } ?? ""), true)
        }
        guard let date else { return (link, false) }
        let added = status?.added.map { count in
            ", " + (count == 0 ? "aucun nouveau post" : Words.count(count, "nouveau post", "nouveaux posts"))
        } ?? ""
        return ("\(link) · lue \(when(date, now: now))\(added)", false)
    }

    /// « Awwwards : lu aujourd'hui 14:02, 1 nouveau site », or what went wrong; no count when it is not known. The count
    /// accorded by `Words` (lot 10, 20/11).
    static func statusLine(_ line: InspirationStatusLine, now: Date = Date()) -> (text: String, problem: Bool) {
        if let problem = line.problem {
            return ("\(line.name) : \(problem)" + (line.lastRun.map { " (\(when($0, now: now)))" } ?? ""), true)
        }
        guard let date = line.lastRun else { return ("\(line.name) : pas encore lu", false) }
        let added = line.added.map { count in
            ", " + (count == 0 ? "rien de nouveau" : Words.count(count, "nouveau site", "nouveaux sites"))
        } ?? ""
        return ("\(line.name) : lu \(when(date, now: now))\(added)", false)
    }

    /// « aujourd'hui 14:02 », « hier 9:04 », « lundi 20:00 »; a week back or more, the day alone, « le 12 novembre »:
    /// the day and the hour by `Words`, as everywhere (lot 10, 20/11).
    static func when(_ date: Date, now: Date = Date(), calendar: Calendar = Words.calendar) -> String {
        Words.moment(date, now: now, calendar: calendar)
    }
}

/// A LinkedIn page to follow, or to change: its name, its link, its color.
struct InspirationSourceSheet: View {
    @ObservedObject var library: InspirationLibrary
    let source: InspirationSourceRow?
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var link: String
    @State private var color: Color
    @State private var problem: String?

    init(library: InspirationLibrary, source: InspirationSourceRow?) {
        self.library = library
        self.source = source
        _name = State(initialValue: source?.name ?? "")
        _link = State(initialValue: source?.link ?? "")
        let hex = source.map { InspirationBrowse.color(ofSource: $0.name, in: [$0]) } ?? Palette.blue
        _color = State(initialValue: Color(hex: hex))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            Text(source == nil ? "Ajouter une page LinkedIn" : "Modifier « \(source?.name ?? "") »").font(.title2.weight(.bold))
            Form {
                TextField("Nom", text: $name, prompt: Text("Studio Exemple"))
                TextField("Lien", text: $link, prompt: Text("linkedin.com/company/…"))
                ColorPicker("Couleur", selection: $color, supportsOpacity: false)
            }
            .formStyle(.columns)
            // A problem in one line: the icon of attention in its color, the sentence in the text's own, never an orange
            // sentence (design system v2, 19/11).
            Group {
                if let problem {
                    ErrorLine(problem)
                } else {
                    Text("La page publique d'un studio, celle de son entreprise sur LinkedIn.").foregroundStyle(.secondary)
                }
            }
            .font(.meta)
            .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Annuler", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(source == nil ? "Ajouter" : "Enregistrer", action: save)
                    .keyboardShortcut(.defaultAction)
                    // The window's principal action: full and matte, at the accent (design system v2, 19/11).
                    .buttonStyle(.primary)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || link.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(Space.xl)
        .frame(width: 460)
    }

    private func save() {
        if let problem = library.saveSource(id: source?.id, name: name, link: link, color: Self.hex(color)) {
            self.problem = problem
        } else {
            dismiss()
        }
    }

    /// `#RRGGBB`, in sRGB.
    static func hex(_ color: Color) -> String? {
        guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        func byte(_ value: CGFloat) -> Int { Int((min(1, max(0, value)) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(rgb.redComponent), byte(rgb.greenComponent), byte(rgb.blueComponent))
    }
}
