import AppKit
import Persistence
import PolhubDesign
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
                Toggle("Catégories par l'IA d'Apple", isOn: $aiCategories)
            } footer: {
                Text("Le modèle d'Apple, sur le Mac, range chaque nouvelle fiche dans tes catégories, d'après son texte. Il ne touche jamais une fiche dont tu as choisi les catégories.")
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: 640)
        .sheet(item: $editing) { draft in InspirationSourceSheet(library: library, source: draft.source) }
        .confirmationDialog("Ne plus suivre « \(removing?.name ?? "") » ?",
                            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), presenting: removing) { source in
            Button("Ne plus la suivre", role: .destructive) { library.deleteSource(source) }
        } message: { _ in
            Text("Ses publications restent dans Branding.")
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
        } header: {
            Text("Pages LinkedIn")
        } footer: {
            Text("Polhub lit la page publique de chaque studio, sans compte ni cookie : ses 10 derniers posts. La couleur marque ses publications dans Branding.")
        }
    }

    private func sourceRow(_ source: InspirationSourceRow) -> some View {
        let line = InspirationSettingsText.sourceLine(source, status: library.status(for: source.link))
        return HStack(spacing: Space.m) {
            ColorDot(Color(hex: InspirationBrowse.color(ofSource: source.name, in: library.sources)), size: 10)
            VStack(alignment: .leading, spacing: 1) {
                Text(source.name).font(.rowBody.weight(.medium))
                Text(line.text).font(.meta).foregroundStyle(line.problem ? Color.orange : .secondary).lineLimit(2)
            }
            Spacer(minLength: Space.s)
            IconButton("pencil", help: "Modifier", size: 13) { editing = SourceDraft(source: source) }
            IconButton("trash", help: "Ne plus suivre", size: 13) { removing = source }
        }
    }

    // MARK: - The collection

    private var collectionSection: some View {
        Section {
            Toggle("Collecte automatique", isOn: $autoCollect)
            let lines = library.status.filter { line in !library.sources.contains { $0.link == line.id } }
            if lines.isEmpty {
                Text(InspirationSettingsText.noRunYet).font(.meta).foregroundStyle(.secondary)
            }
            ForEach(lines) { line in
                let text = InspirationSettingsText.statusLine(line)
                Text(text.text).font(.meta).foregroundStyle(text.problem ? Color.orange : .secondary)
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
        } footer: {
            Text("Le site du jour d'Awwwards toutes les 2 heures de 8 h à 22 h, les pages LinkedIn à 9 h, 14 h et 20 h, et au réveil du Mac, quand Polhub est ouvert. Jamais dans la version de développement.")
        }
    }
}

/// The words of Réglages › Inspiration, pure.
enum InspirationSettingsText {
    static let noRunYet = "Pas encore de collecte."

    /// « linkedin.com/company/studio-exemple · lue aujourd'hui à 14:02, 2 nouveaux posts », or what went wrong. A
    /// reading restored from the base says no count: it is not known.
    static func sourceLine(_ source: InspirationSourceRow, status: InspirationStatusLine?, now: Date = Date()) -> (text: String, problem: Bool) {
        let link = source.link.replacingOccurrences(of: "https://www.", with: "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let problem = status?.problem ?? source.lastError
        let date = [status?.lastRun, source.lastReadAt].compactMap { $0 }.max()
        if let problem {
            return ("\(problem)" + (date.map { " (\(when($0, now: now)))" } ?? ""), true)
        }
        guard let date else { return (link, false) }
        let added = status?.added.map { count in
            ", " + (count == 0 ? "aucun nouveau post" : count == 1 ? "1 nouveau post" : "\(count) nouveaux posts")
        } ?? ""
        return ("\(link) · lue \(when(date, now: now))\(added)", false)
    }

    /// « Awwwards : lu aujourd'hui à 14:02, 1 nouveau site », or what went wrong; no count when it is not known.
    static func statusLine(_ line: InspirationStatusLine, now: Date = Date()) -> (text: String, problem: Bool) {
        if let problem = line.problem {
            return ("\(line.name) : \(problem)" + (line.lastRun.map { " (\(when($0, now: now)))" } ?? ""), true)
        }
        guard let date = line.lastRun else { return ("\(line.name) : pas encore lu", false) }
        let added = line.added.map { count in
            ", " + (count == 0 ? "rien de nouveau" : count == 1 ? "1 nouveau site" : "\(count) nouveaux sites")
        } ?? ""
        return ("\(line.name) : lu \(when(date, now: now))\(added)", false)
    }

    /// « aujourd'hui à 14:02 », « hier à 9:00 », « le 12 nov. à 20:00 ».
    static func when(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let time = date.formatted(Date.FormatStyle(locale: InspirationBrowse.locale, calendar: calendar, timeZone: calendar.timeZone).hour().minute())
        if calendar.isDate(date, inSameDayAs: now) { return "aujourd'hui à \(time)" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) { return "hier à \(time)" }
        return "le \(InspirationBrowse.dateText(date, now: now, calendar: calendar)) à \(time)"
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
            Text(problem ?? "La page publique d'un studio, celle de son entreprise sur LinkedIn.")
                .font(.meta)
                .foregroundStyle(problem == nil ? Color.secondary : .orange)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Annuler", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(source == nil ? "Ajouter" : "Enregistrer", action: save)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.glassProminent)
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
