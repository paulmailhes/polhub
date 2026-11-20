import SwiftUI

/// The colors of Polhub on the iPhone (Paul, 20/11: « trop monotone, il faut de la couleur pour hiérarchiser »): each
/// tab has the color of its family on the Mac, a person their color, a project its own, a status its dot.
enum PhoneStyle {
    // The Mac's palette (PolhubDesign `Palette`).
    static let violet = Color(hex: "#8B5CF6")
    static let green = Color(hex: "#22A06B")
    static let orange = Color(hex: "#F97316")
    static let blue = Color(hex: "#3B82F6")
    static let pink = Color(hex: "#EC4899")
    static let teal = Color(hex: "#14B8A6")
    static let red = Color(hex: "#EF4444")
    static let yellow = Color(hex: "#EAB308")

    /// Each tab, the color of its family in the Mac's Réglages.
    static let mails = pink
    static let calendar = orange
    static let colin = green
    static let projects = blue
    static let meetings = violet

    /// The unread mark.
    static let unread = blue

    /// The same color for a person everywhere, from their address.
    static func person(_ address: String?) -> Color {
        let colors = [violet, green, orange, blue, pink, teal, red, yellow]
        let sum = (address ?? "").lowercased().unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0x7FFF_FFFF }
        return colors[sum % colors.count]
    }

    /// A project's status: its dot, as on the Kanban.
    static func status(_ status: String) -> Color {
        switch status {
        case "priorité 2": red
        case "priorité 1": orange
        case "terminé": green
        default: .gray
        }
    }
}

/// The initial of a person, on their color.
struct Initial: View {
    let name: String
    let address: String?
    var size: CGFloat = 36

    var body: some View {
        let color = PhoneStyle.person(address ?? name)
        Text(String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased())
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.16), in: Circle())
    }
}

/// A project's name on its color, lightly.
struct ProjectChip: View {
    let name: String
    let color: String?

    var body: some View {
        let tint = color.map { Color(hex: $0) } ?? .gray
        Text(name).font(.caption.weight(.semibold)).foregroundStyle(tint)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(tint.opacity(0.14), in: Capsule())
            .lineLimit(1)
    }
}
