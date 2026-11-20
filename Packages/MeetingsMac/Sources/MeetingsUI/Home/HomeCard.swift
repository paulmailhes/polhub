import HubDesign
import SwiftUI

/// A card of « ta journée » (0.37.0, Paul: « mets-le dans des cartes, ça va rendre le truc beaucoup plus digeste et
/// lisible »): calm, as Polhub's other cards — no glass under text —, its title in 17 points with its count in a pill,
/// twenty points of air inside. One radius for every card (design system v2, 19/11): « Aujourd'hui » is no longer
/// rounder than the others.
struct HomeCard<Content: View>: View {
    let title: String
    var count: Int?
    let content: Content

    init(_ title: String, count: Int? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.count = count
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
        .cardSurface(radius: Radius.card)
    }
}

/// A group inside a card: a grey label of 12 points, in its own case — « En retard » (lot 5, 19/11: no more capitals of
/// 11 points, under the smallest text of the app).
struct HomeGroupLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.tag.weight(.semibold))
            .foregroundStyle(.secondary)
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
