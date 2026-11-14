import Foundation
import Persistence

/// The color and the short name of each Google account, to tell them apart at a glance (Paul, 14/11).
public enum AccountStyle {
    public static let violet = "#8B5CF6"
    public static let green = "#22A06B"
    public static let orange = "#F97316"
    public static let blue = "#3B82F6"
    public static let pink = "#EC4899"
    public static let teal = "#14B8A6"
    public static let red = "#EF4444"
    public static let gray = "#8E8E93"

    /// The colors of the work accounts, in the order they were connected. Orange is the personal one's.
    public static let palette = [violet, green, blue, pink, teal, red, gray]
    /// What Paul can choose from.
    public static let choices = [violet, green, orange, blue, pink, teal, red, gray]

    /// Address → `#RRGGBB`. Paul's choice wins; otherwise a personal mailbox is orange and the others take
    /// the palette by order of connection, whatever the others' choices.
    public static func colors(for accounts: [GoogleAccountRow]) -> [String: String] {
        var result: [String: String] = [:]
        var next = 0
        for account in accounts.sorted(by: { $0.addedAt < $1.addedAt }) {
            let personal = isPersonal(account.email)
            let fallback = personal ? orange : palette[next % palette.count]
            if !personal { next += 1 }
            result[account.email] = account.color ?? fallback
        }
        return result
    }

    /// « Exemple » for `…@exemple.fr`, « Perso » for a public mailbox.
    public static func label(for email: String) -> String {
        Linker.company(forEmail: email) ?? "Perso"
    }

    static func isPersonal(_ email: String) -> Bool {
        Linker.company(forEmail: email) == nil
    }
}
