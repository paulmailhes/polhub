import PolhubDesign
import SwiftUI

/// The two tiles of « Coup d'œil », side by side, always in the same place: Calendrier and Mails. « Tuiles allégées »
/// (Paul, 16/11): Réunions said again what the hero says, Projets gave a count nobody acts on; they left. Their words
/// change with the moment (`PanelModel.Tile`); a click opens the page and Polhub's window.
struct PanelTiles: View {
    let context: CoupDoeilContext
    let calendar: PanelModel.Tile
    let mails: PanelModel.Tile
    let hasAgenda: Bool
    let hasMailboxes: Bool

    /// Two columns of 160 points in a panel of 360, margins 16 and a gap of 8 (lot 9, 20/11: 161, 14 and 10 before).
    static let size = CGSize(width: (MenuBarPanel.width - 2 * MenuBarPanel.margin - MenuBarPanel.gap) / 2, height: 80)
    /// The air inside a tile, on every side (lot 9, 20/11: 12 on the sides, 10 above and 9 under before).
    static let padding: CGFloat = Space.m

    var body: some View {
        HStack(spacing: MenuBarPanel.gap) {
            PanelTile(item: .calendar, tile: calendar) {
                context.open(hasAgenda ? .section(.calendar) : .settings(.accounts))
            }
            PanelTile(item: .mails, tile: mails) {
                context.open(hasMailboxes ? .mail(nil) : .settings(.accounts))
            }
        }
    }
}

/// A tile: the section's icon in its color and its name, a count on the right; the value, then a detail line.
struct PanelTile: View {
    let item: SidebarItem
    let tile: PanelModel.Tile
    let action: () -> Void

    /// The value's lines (lot 9, 20/11): two when no detail sits under it, so a title takes the room (« Revue de
    /// maquettes » under « Libre jusqu'à 16:30 », cut at « Revue de maque… » on one line).
    static func valueLines(_ tile: PanelModel.Tile) -> Int { tile.detail == nil ? 2 : 1 }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        Button(action: action) {
            // From the top (lot 9, 20/11): the two tiles' values start on the same line, one or two lines long.
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .center, spacing: Space.s) {
                    AppIconImage(item.appIcon, size: 17)
                        .foregroundStyle(Color(hex: item.tint))
                    Text(item.title)
                        .font(.meta.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if let count = tile.count {
                        Text("\(count)")
                            .font(.meta.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(tile.value)
                        .font(.rowTitle.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(Self.valueLines(tile))
                        .fixedSize(horizontal: false, vertical: true)
                    if let detail = tile.detail {
                        Text(detail)
                            .font(.meta)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(PanelTiles.padding)
            .frame(width: PanelTiles.size.width, height: PanelTiles.size.height, alignment: .topLeading)
            .background(PanelSurface.card, in: shape)
            .contentShape(shape)
        }
        .buttonStyle(PanelCardStyle(radius: Radius.card))
        // Its key, from the sidebar's order (lot 4, 19/11): never a number written by hand; « Ouvrir Calendrier (⌘4) » by
        // `Words.help` (lot 10, 20/11).
        .help(Words.help("Ouvrir \(item.title)", shortcuts: item.shortcut.map { [Words.Shortcut.command("\($0)")] } ?? []))
        .accessibilityLabel([item.title, tile.value, tile.detail].compactMap { $0 }.joined(separator: ", "))
    }
}
