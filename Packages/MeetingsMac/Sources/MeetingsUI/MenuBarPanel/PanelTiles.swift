import PolhubDesign
import SwiftUI

/// The four fixed tiles of « Coup d'œil » (15/11), two by two, always in the same place: Calendrier, Mails, Réunions,
/// Projets. Their words change with the moment (`PanelModel.Tile`); a click opens the page and Polhub's window.
struct PanelTiles: View {
    let context: CoupDoeilContext
    let calendar: PanelModel.Tile
    let mails: PanelModel.Tile
    let meetings: PanelModel.Tile
    let projects: PanelModel.Tile
    let hasAgenda: Bool
    let hasMailboxes: Bool

    /// Two columns of 161 points in a panel of 360, margins 14 and a gap of 10.
    static let size = CGSize(width: (MenuBarPanel.width - 2 * MenuBarPanel.margin - MenuBarPanel.gap) / 2, height: 80)

    var body: some View {
        Grid(horizontalSpacing: MenuBarPanel.gap, verticalSpacing: MenuBarPanel.gap) {
            GridRow {
                PanelTile(item: .calendar, tile: calendar, shortcut: 4) {
                    context.open(hasAgenda ? .section(.calendar) : .settings(.accounts))
                }
                PanelTile(item: .mails, tile: mails, shortcut: 5) {
                    context.open(hasMailboxes ? .mail(nil) : .settings(.accounts))
                }
            }
            GridRow {
                PanelTile(item: .meetings, tile: meetings, shortcut: 3) { context.open(.section(.meetings)) }
                PanelTile(item: .projects, tile: projects, shortcut: 2) { context.open(.section(.projects)) }
            }
        }
    }
}

/// A tile: the section's icon in its color and its name, a count on the right; the value, then a detail line.
struct PanelTile: View {
    let item: SidebarItem
    let tile: PanelModel.Tile
    let shortcut: Int
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 6) {
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
                Spacer(minLength: 0)
                HStack(alignment: .center, spacing: 5) {
                    if tile.live {
                        Circle().fill(PanelTint.red).frame(width: 7, height: 7)
                    }
                    Text(tile.value)
                        .font(.rowTitle.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                Text(tile.detail ?? " ")
                    .font(.meta)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.top, 1)
            }
            .padding(.horizontal, Space.m)
            .padding(.top, 10)
            .padding(.bottom, 9)
            .frame(width: PanelTiles.size.width, height: PanelTiles.size.height, alignment: .topLeading)
            .background(PanelSurface.card, in: shape)
            .contentShape(shape)
        }
        .buttonStyle(PanelCardStyle(radius: Radius.card))
        .help("Ouvrir \(item.title) (⌘\(shortcut))")
        .accessibilityLabel([item.title, tile.value, tile.detail].compactMap { $0 }.joined(separator: ", "))
    }
}
