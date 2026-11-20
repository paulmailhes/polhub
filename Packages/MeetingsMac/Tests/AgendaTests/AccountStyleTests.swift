import Foundation
import Persistence
import Testing
@testable import Agenda

/// Each account's color (Paul, 14/11): a personal mailbox is orange, the others take violet, green, blue…
/// in the order they were connected; a color Paul chose wins.
@Suite struct AccountStyleTests {
    let start = Date(timeIntervalSince1970: 1_794_562_920)

    func account(_ email: String, _ minutes: Double, color: String? = nil) -> GoogleAccountRow {
        var row = GoogleAccountRow(email: email, addedAt: start.addingTimeInterval(minutes * 60))
        row.color = color
        return row
    }

    @Test func aPersonalMailboxIsOrangeAndTheOthersFollowThePalette() {
        let colors = AccountStyle.colors(for: [
            account("studio@atelier-nord.fr", 2), account("moi@gmail.com", 0), account("paul@exemple.fr", 1),
        ])
        #expect(colors["moi@gmail.com"] == AccountStyle.orange)
        #expect(colors["paul@exemple.fr"] == AccountStyle.palette[0])
        #expect(colors["studio@atelier-nord.fr"] == AccountStyle.palette[1])
        #expect(!AccountStyle.palette.prefix(2).contains(AccountStyle.orange))
    }

    @Test func aChosenColorWinsWithoutMovingTheOthers() {
        let colors = AccountStyle.colors(for: [
            account("moi@gmail.com", 0, color: "#3B82F6"), account("paul@exemple.fr", 1), account("studio@atelier-nord.fr", 2),
        ])
        #expect(colors["moi@gmail.com"] == "#3B82F6")
        #expect(colors["paul@exemple.fr"] == AccountStyle.palette[0])
        #expect(colors["studio@atelier-nord.fr"] == AccountStyle.palette[1])
    }

    @Test func aNewAccountDoesNotChangeTheOlderOnes() {
        let before = AccountStyle.colors(for: [account("paul@exemple.fr", 1), account("studio@atelier-nord.fr", 2)])
        let after = AccountStyle.colors(for: [account("paul@exemple.fr", 1), account("studio@atelier-nord.fr", 2), account("nouveau@autre.fr", 3)])
        #expect(after["paul@exemple.fr"] == before["paul@exemple.fr"])
        #expect(after["studio@atelier-nord.fr"] == before["studio@atelier-nord.fr"])
        #expect(after["nouveau@autre.fr"] == AccountStyle.palette[2])
    }

    @Test func labels() {
        #expect(AccountStyle.label(for: "paul@exemple.fr") == "Exemple")
        #expect(AccountStyle.label(for: "studio@atelier-nord.fr") == "Atelier Nord")
        #expect(AccountStyle.label(for: "moi@gmail.com") == "Perso")
        // Lot 10 (20/11): the personal account is a state, not the word of its label; a company may be called « Perso ».
        #expect(AccountStyle.isPersonal("moi@gmail.com") && !AccountStyle.isPersonal("paul@exemple.fr"))
        #expect(AccountStyle.label(for: "contact@perso.exemple") == "Perso" && !AccountStyle.isPersonal("contact@perso.exemple"))
    }
}
