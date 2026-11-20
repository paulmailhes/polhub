import Persistence
import PolhubDesign
import SwiftUI

/// An item open (16/11): its images large (a post's side by side), its links, its text, its fonts and client, its
/// categories as chips Paul changes with a click (his from then on), « Supprimer » in « … ».
struct InspirationItemPage: View {
    let item: InspirationItemRow
    @ObservedObject var library: InspirationLibrary
    @ObservedObject var router: WindowRouter
    @AppStorage(Preferences.Key.inspirationAICategories) private var aiCategories = true

    /// The height of a post's strip of images.
    static let stripHeight: CGFloat = 420
    /// The tallest a single image gets.
    static let imageMaxHeight: CGFloat = 560

    var body: some View {
        Page(spacing: Space.xl) {
            header
            images
            links
            if !item.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(verbatim: item.text)
                    .font(.body)
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .frame(maxWidth: PageMetrics.readingWidth, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            details
            categories
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                // Back where the item was opened from, without a step of its own (lot 4, 19/11).
                Button { close() } label: { Label(item.kind.title, systemImage: "chevron.left") }
                    .help(router.returnHelp)
            }
        }
        .onExitCommand(perform: close)
        // The sidebar's word and the page; never the item's title, written large below (lot 4, 19/11).
        .windowTitle("Inspiration", subtitle: item.kind.title)
    }

    private func close() {
        if !router.close() { router.inspirationItem = nil }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: Space.l) {
            VStack(alignment: .leading, spacing: Space.xs) {
                // The large title of an object open, 26 points, as a project's (lot 8, 19/11).
                Text(InspirationBrowse.displayTitle(item))
                    .font(.largeTitle.weight(.bold))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    if let color = library.sourceColor(item) { ColorDot(Color(hex: color), size: 9) }
                    Text(metaLine).font(.meta).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            IconMenu("ellipsis", help: "Plus") {
                // Only for an item still without categories: it never replaces the vault's without a word (review
                // of 16/11); the background pass would tag it within minutes anyway.
                if aiCategories, !item.categoriesByPaul, item.kind != .mockup, item.categories.values.allSatisfy(\.isEmpty) {
                    Button("Proposer des catégories") { Task { await library.tag(item) } }
                    Divider()
                }
                Button("Supprimer", role: .destructive) {
                    close()
                    library.moveToTrash(item)
                }
            }
        }
    }

    /// The card's line, plus the post's pages when they are not already said.
    private var metaLine: String {
        var parts = [InspirationBrowse.meta(item)]
        if item.kind == .branding {
            let others = item.sources.filter { $0 != item.studio && !parts[0].hasSuffix($0) }
            if !others.isEmpty { parts.append("via \(others.joined(separator: ", "))") }
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Images

    @ViewBuilder
    private var images: some View {
        let urls = library.imageURLs(item)
        if urls.count == 1, let url = urls.first {
            InspirationLargeImage(url: url, icon: item.kind.appIcon, maxHeight: Self.imageMaxHeight)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if urls.count > 1 {
            ScrollView(.horizontal) {
                HStack(spacing: Space.m) {
                    ForEach(urls, id: \.self) { url in
                        InspirationLargeImage(url: url, icon: item.kind.appIcon).frame(height: Self.stripHeight)
                    }
                }
                .padding(.bottom, Space.s)
            }
            .scrollIndicators(.automatic)
        }
    }

    // MARK: - Links

    @ViewBuilder
    private var links: some View {
        let main = InspirationBrowse.links(item)
        let others = InspirationBrowse.otherLinks(item)
        if !main.isEmpty || !others.isEmpty {
            VStack(alignment: .leading, spacing: Space.m) {
                if !main.isEmpty {
                    HStack(spacing: Space.s) {
                        ForEach(main) { link in
                            Button { InspirationActions.open(link.target) } label: {
                                Label(link.title, systemImage: link.isFinder ? "folder" : "arrow.up.right")
                            }
                            // No glass in the content: secondary actions (design system v2, 19/11).
                            .buttonStyle(.secondary)
                            .help(link.help)
                        }
                    }
                }
                if !others.isEmpty {
                    FlowLayout(spacing: Space.xs) {
                        ForEach(others.prefix(8), id: \.self) { url in
                            Button { NSWorkspace.shared.open(url) } label: {
                                HStack(spacing: Space.xs) {
                                    Image(systemName: "link").font(.system(size: 11, weight: .semibold))
                                    Text(InspirationBrowse.host(url.absoluteString) ?? url.absoluteString).lineLimit(1)
                                }
                                .font(.meta.weight(.medium))
                                .padding(.horizontal, Space.s)
                                .padding(.vertical, 3)
                            }
                            .buttonStyle(.hover(.capsule))
                            // A link, its icon says so: the accent, ink (design system v2, 19/11).
                            .foregroundStyle(Tint.accent)
                            .help(url.absoluteString)
                        }
                    }
                    .padding(.horizontal, -Space.s)
                }
            }
        }
    }

    // MARK: - Fonts, client

    /// The width of the labels on the left (« Polices », « Secteur »).
    static let labelWidth: CGFloat = 64

    @ViewBuilder
    private var details: some View {
        let rows: [(String, String)] = [
            item.fonts.isEmpty ? nil : ("Polices", item.fonts.joined(separator: ", ")),
            item.client.flatMap { $0.isEmpty ? nil : ("Client", $0) },
        ].compactMap { $0 }
        if !rows.isEmpty {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Space.m, verticalSpacing: Space.s) {
                ForEach(rows, id: \.0) { title, value in
                    GridRow {
                        Text(title).font(.meta.weight(.semibold)).foregroundStyle(.secondary)
                            .frame(width: InspirationItemPage.labelWidth, alignment: .leading)
                        Text(value).font(.rowBody).textSelection(.enabled)
                    }
                }
            }
        }
    }

    // MARK: - Categories

    private var categories: some View {
        let rows = InspirationBrowse.categoryRows(item, vocabulary: library.vocabulary(item.kind))
        return VStack(alignment: .leading, spacing: Space.m) {
            SectionTitle("Catégories")
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Space.m, verticalSpacing: Space.s) {
                ForEach(rows) { row in
                    GridRow {
                        Text(row.title).font(.meta.weight(.semibold)).foregroundStyle(.secondary)
                            .frame(width: InspirationItemPage.labelWidth, alignment: .leading)
                        InspirationCategoryMenu(row: row) { value in library.toggleCategory(item, family: row.family, value: value) }
                    }
                }
            }
            if item.categoriesByPaul {
                Text("Choisies par toi : l'IA n'y touche plus.").font(.meta).foregroundStyle(.secondary)
            }
        }
    }
}

extension InspirationBrowse.Link {
    var isFinder: Bool {
        if case .finder = target { return true }
        return false
    }

    var help: String {
        switch target {
        case .web(let url): url.absoluteString
        case .finder(let folder): "Afficher \(folder.lastPathComponent) dans le Finder"
        }
    }
}

/// A family of an item: its values as chips; a click opens the vocabulary, each value ticked or not.
struct InspirationCategoryMenu: View {
    let row: InspirationBrowse.CategoryRow
    let toggle: (String) -> Void

    var body: some View {
        Menu {
            ForEach(row.options, id: \.self) { option in
                let on = row.values.contains { InspirationBrowse.fold($0) == InspirationBrowse.fold(option) }
                Toggle(InspirationBrowse.label(option), isOn: Binding(get: { on }, set: { _ in toggle(option) }))
            }
        } label: {
            Group {
                if row.values.isEmpty {
                    // Grey to be read (lot 8, 19/11): in `.tertiary`, 1.9:1.
                    Text("Choisir…").font(.meta).foregroundStyle(.secondary)
                        .padding(.vertical, 3)
                } else {
                    FlowLayout(spacing: Space.xs) {
                        ForEach(row.values, id: \.self) { value in Chip(InspirationBrowse.label(value)) }
                    }
                }
            }
            .padding(.horizontal, Space.s)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.hover(.rounded))
        .menuIndicator(.hidden)
        .padding(.horizontal, -Space.s)
        .help("Changer « \(row.title) »")
    }
}

/// An image whole, at its own proportions (read from its header first, 4:3 until then), never taller than
/// `maxHeight`.
struct InspirationLargeImage: View {
    let url: URL
    var icon: AppIcon = .inspiration
    var maxHeight: CGFloat? = nil
    @State private var aspect: CGFloat = 4 / 3

    var body: some View {
        InspirationImage(url: url, mode: .fill, icon: icon)
            .aspectRatio(aspect, contentMode: .fit)
            .frame(maxWidth: maxHeight.map { $0 * aspect } ?? .infinity)
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Surface.stroke))
            .task(id: url) {
                if let ratio = await InspirationThumbnails.aspectRatio(url), ratio > 0 { aspect = ratio }
            }
    }
}
