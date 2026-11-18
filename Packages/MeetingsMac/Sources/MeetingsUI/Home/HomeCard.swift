import PolhubDesign
import SwiftUI

/// A card of « ta journée » (0.37.0, Paul: « mets-le dans des cartes, ça va rendre le truc beaucoup plus digeste et
/// lisible »): calm, as Polhub's other cards — no glass under text —, its title in 17 points with its count in a pill,
/// twenty points of air inside. « Aujourd'hui » is the one put forward: rounder.
struct HomeCard<Content: View>: View {
    let title: String
    var count: Int?
    var hero = false
    let content: Content

    init(_ title: String, count: Int? = nil, hero: Bool = false, @ViewBuilder content: () -> Content) {
        self.title = title
        self.count = count
        self.hero = hero
        self.content = content()
    }

    static var padding: CGFloat { 20 }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HomeSectionHeader(title: title, count: count)
            content
        }
        .padding(Self.padding)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .cardSurface(radius: hero ? Radius.hero : Radius.card)
    }
}

/// A group inside a card, in small grey capitals: « EN RETARD ».
struct HomeGroupLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(.secondary)
            .accessibilityLabel(text)
    }
}

extension View {
    /// A row of a card with air above and under it, and a thin line over it unless it is the first.
    func homeRow(first: Bool) -> some View {
        padding(.vertical, 6)
            .overlay(alignment: .top) {
                if !first { Divider().offset(y: -2) }
            }
    }
}
