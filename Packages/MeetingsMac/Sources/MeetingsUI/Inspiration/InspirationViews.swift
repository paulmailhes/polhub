import AppKit
import Persistence
import PolhubDesign
import SwiftUI
import UniformTypeIdentifiers

/// « Inspiration » (16/11): the page chosen in its toolbar (lot 4, 19/11: no longer three rows of the sidebar), or one of
/// its items open over the page, with a way back, as a project's page; « Annuler » and the collection's answers at the
/// bottom.
struct InspirationSectionView: View {
    @ObservedObject var library: InspirationLibrary
    @ObservedObject var router: WindowRouter

    var body: some View {
        Group {
            if let item = library.item(router.inspirationItem) {
                InspirationItemPage(item: item, library: library, router: router).id(item.id)
            } else {
                InspirationPageView(kind: router.inspirationPage, library: library, router: router).id(router.inspirationPage)
            }
        }
        .overlay(alignment: .bottom) { InspirationMessageBar(library: library) }
        // Another section, or the window closed: the thumbnails do not stay in memory all day.
        .onDisappear { InspirationThumbnails.shared.purge() }
    }
}

/// A page: its toolbar (title, search, « + »), a row of chips per family, then the grid of cards, newest first.
struct InspirationPageView: View {
    let kind: InspirationKind
    @ObservedObject var library: InspirationLibrary
    @ObservedObject var router: WindowRouter
    @State private var addingSite = false
    @State private var addingPage = false
    @State private var choosingFolder = false

    /// The narrowest card: three across a 1 080-point page.
    static let cardMinimumWidth: CGFloat = 240

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // The sidebar's word; the page and its count below (lot 4, 19/11).
            .windowTitle("Inspiration", subtitle: Self.subtitle(kind, shown: library.shown(kind).count, total: library.items(kind).count))
            .toolbar {
                // Its three pages, as « Kanban | Liste » in Projets (lot 4, 19/11): a choice of view, not three places.
                ToolbarItem(placement: .principal) {
                    Picker("Page", selection: Binding(get: { router.inspirationPage }, set: { router.openInspiration($0) })) {
                        ForEach(InspirationKind.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    // No bubble: it only said the three visible names again (lot 10, 20/11).
                }
                ToolbarItem(placement: .primaryAction) {
                    // ⌘N does the same, the window's « + » (`WindowKeys`) (lot 10, 20/11).
                    Button(action: add) { Label(kind.addTitle, systemImage: "plus") }
                        .help(Words.help(kind.addTitle, .command("n")))
                        .disabled(library.adding)
                }
            }
            // One field (Paul, 16/11: « une barre de recherche avec détection automatique avec les filtres »): the
            // words search, a category typed in full becomes a filter, the suggestions offer the others.
            .searchable(text: Binding(get: { library.query(kind) }, set: { library.setQuery($0, for: kind) }),
                        tokens: Binding(get: { library.tokens(kind) }, set: { library.setTokens($0, for: kind) }),
                        placement: .toolbar, prompt: kind.searchPrompt) { token in
                Text(token.label)
            }
            .searchSuggestions {
                ForEach(library.suggestions(kind)) { token in
                    InspirationSuggestionRow(token: token).searchCompletion(token)
                }
            }
            // ⌘N, as the « + » (lot 4, 19/11): once the page is on screen, then cleared.
            .task(id: router.addRequest) {
                guard router.addRequest != nil else { return }
                router.addRequest = nil
                add()
            }
            .sheet(isPresented: $addingSite) {
                InspirationAddSiteSheet(library: library) { id in router.openInspiration(.website, item: id) }
            }
            // A LinkedIn page, from the page itself (review of 16/11); Réglages keeps the list to change or remove one.
            .sheet(isPresented: $addingPage) { InspirationSourceSheet(library: library, source: nil) }
            .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
                guard case .success(let folder) = result else { return }
                Task {
                    do {
                        let id = try await library.addMockup(folder: folder)
                        router.openInspiration(.mockup, item: id)
                    } catch {
                        // Said in French, the system's text to the journal (lot 10, 20/11).
                        library.message = library.text(error, failed: "Le mock-up n'a pas pu être ajouté")
                    }
                }
            }
    }

    /// « Websites · 12 sites », « Websites · 4 sites sur 212 »: where Paul is, then what the page shows.
    static func subtitle(_ kind: InspirationKind, shown: Int, total: Int) -> String {
        let count = InspirationBrowse.subtitle(kind, shown: shown, total: total)
        return count.isEmpty ? kind.title : "\(kind.title) · \(count)"
    }

    @ViewBuilder
    private var content: some View {
        if !library.loaded.contains(kind) {
            ProgressView()
        } else if library.items(kind).isEmpty {
            InspirationEmptyState(kind: kind, add: add)
        } else {
            grid
        }
    }

    /// Websites: an address; Branding: a LinkedIn page; Mock-ups: a folder.
    private func add() {
        switch kind {
        case .website: addingSite = true
        case .branding: addingPage = true
        case .mockup: choosingFolder = true
        }
    }

    private var grid: some View {
        let shown = library.shown(kind)
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: Space.l) {
                if shown.isEmpty {
                    InspirationNoMatch { library.clearFilters(kind) }
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: Self.cardMinimumWidth), spacing: Space.l, alignment: .top)],
                              alignment: .leading, spacing: Space.l) {
                        ForEach(shown) { item in
                            InspirationCard(item: item, imageURL: library.imageURL(item), sourceColor: library.sourceColor(item)) {
                                router.openInspiration(kind, item: item.id)
                            } delete: {
                                library.moveToTrash(item)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, PageMetrics.horizontal)
            .padding(.top, PageMetrics.top)
            .padding(.bottom, PageMetrics.bottom + Space.xxl)
        }
    }
}

/// One card: the cover, cropped to 4:3, the title, one line of detail (the page's color dot on Branding).
struct InspirationCard: View {
    let item: InspirationItemRow
    let imageURL: URL?
    let sourceColor: String?
    let open: () -> Void
    let delete: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        Button(action: open) {
            VStack(alignment: .leading, spacing: 0) {
                InspirationImage(url: imageURL, mode: .fill, icon: item.kind.appIcon)
                    .aspectRatio(4 / 3, contentMode: .fit)
                VStack(alignment: .leading, spacing: 2) {
                    Text(InspirationBrowse.displayTitle(item)).font(.rowTitle.weight(.medium)).lineLimit(1)
                    HStack(spacing: 6) {
                        if let sourceColor { ColorDot(Color(hex: sourceColor), size: 8) }
                        Text(InspirationBrowse.meta(item)).font(.meta).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .padding(.horizontal, Space.m)
                .padding(.top, Space.s + 2)
                .padding(.bottom, Space.m)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Surface.fill)
            .clipShape(shape)
            .contentShape(shape)
        }
        .buttonStyle(InspirationCardButtonStyle())
        .cardHover()
        .help(item.title)
        .contextMenu {
            Button("Ouvrir", action: open)
            ForEach(InspirationBrowse.links(item)) { link in
                Button(link.title) { InspirationActions.open(link.target) }
            }
            Divider()
            Button("Supprimer", role: .destructive, action: delete)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// A card pressed sinks a little; `cardHover` does the rest.
struct InspirationCardButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(Motion.quick, value: configuration.isPressed)
    }
}

/// A suggestion of the search field: the value, its family (or the page's color), and how many items it shows.
struct InspirationSuggestionRow: View {
    let token: InspirationBrowse.InspirationToken

    var body: some View {
        HStack(spacing: Space.s) {
            if let color = token.color { ColorDot(Color(hex: color), size: 8) }
            Text(token.label)
            Text(token.familyTitle).foregroundStyle(.secondary)
            Spacer(minLength: Space.m)
            Text(Words.number(token.count)).foregroundStyle(.secondary).monospacedDigit()
        }
    }
}

/// A page without an item: one line, and the page's « + » (16/11: the vault's import is gone with the vault).
struct InspirationEmptyState: View {
    let kind: InspirationKind
    let add: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label {
                Text(kind.emptyTitle)
            } icon: {
                AppIconImage(kind.appIcon, size: 44).foregroundStyle(.secondary)
            }
        } description: {
            Text(kind.emptyText)
        } actions: {
            // The screen's one action: the principal button, no glass in the content (design system v2, 19/11).
            Button(kind.addTitle, action: add)
                .buttonStyle(.primary)
                .controlSize(.large)
        }
    }
}

/// The search and the filters leave nothing.
struct InspirationNoMatch: View {
    let showAll: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Aucune fiche", systemImage: "magnifyingglass")
        } description: {
            Text("Rien ne répond à cette recherche et à ces filtres.")
        } actions: {
            // No glass in the content: a secondary action (design system v2, 19/11). « Effacer » empties the search and the
            // filters, « Afficher » is for what is hidden (lot 10, 20/11).
            Button("Effacer les filtres", action: showAll).buttonStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Space.xxl)
    }
}

/// « Annuler » after « Supprimer », or what an addition answered: the small pill at the bottom, as in Mails; the message
/// goes by itself (Paul, 20/11).
struct InspirationMessageBar: View {
    @ObservedObject var library: InspirationLibrary

    private var visible: Bool { library.undoable != nil || library.message != nil }

    var body: some View {
        Group {
            if let undo = library.undoable {
                HStack(spacing: Space.s) {
                    Text(undo.text).help(undo.text)
                    Button { library.undo() } label: {
                        Text("Annuler").fontWeight(.semibold).padding(.horizontal, Space.xs).padding(.vertical, Space.xs / 2)
                    }
                    .buttonStyle(.hover(.capsule))
                    // A gesture to make: the accent, ink (design system v2, 19/11).
                    .foregroundStyle(Tint.accent)
                    .keyboardShortcut("z", modifiers: .command)
                    // The shortcut that works here, said (lot 10, 20/11).
                    .help(Words.help("Annuler", .command("z")))
                }
            } else if let message = library.message {
                HStack(spacing: Space.s) {
                    Text(message).help(message)
                    IconButton("xmark", help: "Fermer", size: 11) { library.message = nil }
                }
            }
        }
        // The small pill of Mails, one line (Paul, 20/11).
        .bottomPill()
        .padding(.bottom, Space.l)
        .opacity(visible ? 1 : 0)
        .allowsHitTesting(visible)
        .animation(.snappy, value: library.undoable)
        .animation(.snappy, value: library.message)
    }
}

/// « Ajouter un site »: its address; Polhub reads the rest.
struct InspirationAddSiteSheet: View {
    @ObservedObject var library: InspirationLibrary
    let added: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @State private var problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            Text("Ajouter un site").font(.title2.weight(.bold))
            VStack(alignment: .leading, spacing: Space.s) {
                TextField("Adresse du site", text: $address, prompt: Text("exemple.fr"))
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(add)
                // A problem in one line: the icon of attention in its color, the sentence in the text's own, never an
                // orange sentence (design system v2, 19/11).
                Group {
                    if let problem {
                        ErrorLine(problem)
                    } else {
                        Text("Polhub lit son titre, sa description et son image.").foregroundStyle(.secondary)
                    }
                }
                .font(.meta)
                .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if library.adding { ProgressView().controlSize(.small) }
                Spacer()
                Button("Annuler", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Ajouter", action: add)
                    .keyboardShortcut(.defaultAction)
                    // The window's principal action: full and matte, at the accent (design system v2, 19/11).
                    .buttonStyle(.primary)
                    .disabled(InspirationLibrary.siteURL(address) == nil || library.adding)
            }
        }
        .padding(Space.xl)
        .frame(width: 440)
    }

    private func add() {
        guard InspirationLibrary.siteURL(address) != nil, !library.adding else { return }
        problem = nil
        Task {
            do {
                let id = try await library.addSite(address)
                dismiss()
                added(id)
            } catch {
                // Said in French, the system's text to the journal (lot 10, 20/11).
                problem = library.text(error, failed: "Le site n'a pas pu être ajouté")
            }
        }
    }
}

/// What a link of an item does.
@MainActor
enum InspirationActions {
    static func open(_ target: InspirationBrowse.Link.Target) {
        switch target {
        case .web(let url): NSWorkspace.shared.open(url)
        case .finder(let folder): NSWorkspace.shared.activateFileViewerSelecting([folder])
        }
    }
}
