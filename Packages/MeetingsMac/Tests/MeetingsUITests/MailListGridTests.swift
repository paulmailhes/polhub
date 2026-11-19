import Foundation
import Persistence
import Testing
@testable import MeetingsUI

/// Lot 6 (19/11): one grid for every folder of the list, the bar of gestures always there, an end column that holds the
/// date at rest and the gestures under the pointer, a mailbox's stripe only among several, empty lists that say what to do.
@Suite struct MailListGridTests {
    /// A thread of the inbox, made up.
    func thread(unread: Bool = true) -> MailThreadRow {
        let message = MailMessageRow(account: "moi@exemple.fr", messageID: "m1", threadID: "t1", date: Date(timeIntervalSince1970: 1_794_562_920),
                                     sender: MailAddress(name: "Camille Martin", email: "camille@exemple-studio.fr"), to: [MailAddress(email: "moi@exemple.fr")],
                                     subject: "Maquette", snippet: "Voici la maquette.", labels: unread ? ["INBOX", "UNREAD"] : ["INBOX"])
        return MailThreadRow.aggregate(account: "moi@exemple.fr", threadID: "t1", messages: [message], mine: ["moi@exemple.fr"])!
    }

    /// The columns follow each other: the stripe, the box, who, then the subject; the end column is apart.
    @Test func theColumnsFollowEachOther() {
        #expect(MailGrid.boxStart == MailGrid.stripeStart + MailGrid.stripeWidth)
        #expect(MailGrid.boxEnd == MailGrid.boxStart + MailGrid.boxWidth)
        #expect(MailGrid.subjectStart == MailGrid.boxEnd + MailGrid.sendersWidth + MailGrid.gap)
        // Where the box and the senders started before (0.39.0): the bar and the day titles stay lined up on them.
        #expect(MailGrid.boxStart == 15 && MailGrid.boxEnd == 59 && MailGrid.subjectStart == 285)
    }

    /// The gestures of a line, the case's menu with them, fit in the end column of every folder: they never cover the
    /// subject, and nothing needs a gradient under them.
    @Test func theGesturesFitTheEndColumnOfEveryFolder() {
        for folder in MailFolder.allCases {
            let count = folder.gestures(for: thread()).count + (folder.aside == nil ? 1 : 0)
            #expect(MailGrid.gesturesWidth(count) <= MailGrid.endWidth, "\(folder)")
        }
        #expect(MailGrid.gesturesWidth(1) == 32 && MailGrid.gesturesWidth(4) == 4 * 32 + 3 * 2)
    }

    /// The mailbox's stripe says which box a line comes from: only when the list shows two boxes or more.
    @Test func theStripeShowsOnlyAmongSeveralBoxes() {
        #expect(!MailGrid.showsStripes(accounts: [], hidden: []))
        #expect(!MailGrid.showsStripes(accounts: ["moi@exemple.fr"], hidden: []))
        #expect(MailGrid.showsStripes(accounts: ["moi@exemple.fr", "perso@exemple.org"], hidden: []))
        #expect(!MailGrid.showsStripes(accounts: ["moi@exemple.fr", "perso@exemple.org"], hidden: ["perso@exemple.org"]))
        #expect(MailGrid.showsStripes(accounts: ["moi@exemple.fr", "perso@exemple.org", "paul@atelier.exemple"], hidden: ["perso@exemple.org"]))
    }

    /// The bar is there in every folder; its box ticks only what can be ticked, and « Non lus » shows only where it filters.
    @Test func theBarOffersOnlyWhatTheFolderDoes() {
        let ticked: [MailFolder] = [.inbox, .sent, .notifications, .all, .spam, .trash]
        let unticked: [MailFolder] = [.drafts, .scheduled, .subscriptions]
        for folder in ticked { #expect(MailListBar.ticks(folder: folder, searching: false), "\(folder)") }
        for folder in unticked {
            #expect(!MailListBar.ticks(folder: folder, searching: false), "\(folder)")
            // A search shows threads, whatever the folder.
            #expect(MailListBar.ticks(folder: folder, searching: true), "\(folder)")
        }
        for folder in [MailFolder.inbox, .sent, .notifications, .all] { #expect(MailListBar.filtersUnread(folder: folder, searching: false), "\(folder)") }
        for folder in [MailFolder.spam, .trash, .drafts, .scheduled, .subscriptions] {
            #expect(!MailListBar.filtersUnread(folder: folder, searching: false), "\(folder)")
        }
        // A search's results come from every folder, read or not: « Non lus » would do nothing there.
        #expect(!MailListBar.filtersUnread(folder: .inbox, searching: true))
    }

    /// An empty folder says what arrives there and how to act; one emptied by a filter says so and offers to lift it.
    @Test func anEmptyListSaysWhatToDo() {
        func empty(_ folder: MailFolder, searching: Bool = false, reading: Bool = false, readingAside: Bool = false, unreadOnly: Bool = false,
                   hidden: Int = 0) -> MailEmptyState {
            MailEmptyState.of(folder: folder, searching: searching, reading: reading, readingAside: readingAside, unreadOnly: unreadOnly, hiddenBoxes: hidden)
        }
        // « Non lus » on and nothing left: everything is read, and the way back to all of them.
        #expect(empty(.inbox, unreadOnly: true) == MailEmptyState(title: "Tout est lu", systemImage: "envelope.open", detail: nil, action: .showRead))
        #expect(MailEmptyState.Action.showRead.title == "Afficher tous les mails")
        // A mailbox hidden: the list may be empty because of it.
        #expect(empty(.sent, hidden: 1).detail == "1 boîte est masquée." && empty(.sent, hidden: 1).action == .showEveryBox)
        #expect(empty(.drafts, hidden: 2).detail == "2 boîtes sont masquées." && empty(.drafts, hidden: 2).title == "Aucun brouillon")
        #expect(MailEmptyState.Action.showEveryBox.title == "Afficher toutes les boîtes")
        // Each folder, as it is: what arrives, and how to write.
        #expect(empty(.inbox) == MailEmptyState(title: "Boîte de réception vide", systemImage: "tray",
                                                detail: "Les mails des personnes arrivent ici. ⌘N pour écrire.", action: nil))
        #expect(empty(.notifications).title == "Aucune notification"
            && empty(.notifications).detail == "Les reçus, les alertes et les lettres d'information arrivent ici.")
        #expect(empty(.sent).title == "Aucun mail envoyé" && empty(.sent).detail == "⌘N pour écrire un mail.")
        #expect(empty(.drafts).detail == "Un mail commencé et pas encore envoyé t'attend ici. ⌘N pour écrire.")
        #expect(empty(.scheduled).detail == "La flèche à côté d'« Envoyer » programme un mail : il attend ici son heure.")
        #expect(empty(.trash).title == "Corbeille vide" && empty(.spam).title == "Aucun spam")
        // A search, a first reading, Gmail's list on its way: what is happening, never « Rien ici ».
        #expect(empty(.inbox, searching: true).title == "Aucun mail trouvé" && empty(.inbox, searching: true).systemImage == "magnifyingglass")
        #expect(empty(.inbox, searching: true, unreadOnly: true).title == "Aucun mail trouvé")
        #expect(empty(.inbox, reading: true).title == "Lecture de tes boîtes…" && empty(.inbox, reading: true).action == nil)
        #expect(empty(.trash, readingAside: true).title == "Lecture de Gmail…")
        // Nothing says « Rien ici » any more.
        for folder in MailFolder.allCases { #expect(empty(folder).title != "Rien ici", "\(folder)") }
    }
}
