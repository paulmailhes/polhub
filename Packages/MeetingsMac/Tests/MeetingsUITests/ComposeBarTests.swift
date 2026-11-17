import Foundation
import Persistence
import Testing
@testable import MeetingsUI

/// The bar fixed at the bottom of a thread (17/11) belongs to the reply Paul is writing, never to another one of
/// the same thread: a click on « Envoyer » would send the wrong mail.
@MainActor @Suite struct ComposeBarTests {
    let date = Date(timeIntervalSince1970: 1_794_562_920)

    func draft(_ id: String, created: TimeInterval, updated: TimeInterval) -> MailDraftRow {
        MailDraftRow(id: id, account: "moi@exemple.fr", mode: .reply, threadKey: "moi@exemple.fr|a", subject: "Re: Maquette",
                     createdAt: date.addingTimeInterval(created), updatedAt: date.addingTimeInterval(updated))
    }

    /// The replies keep their place as Paul types: oldest first, the one just begun at the bottom.
    @Test func theRepliesKeepTheirPlace() {
        let older = draft("a", created: 0, updated: 60), newer = draft("b", created: 30, updated: 30)
        // The library lists the last changed first.
        #expect(ComposePinning.ordered([older, newer]).map(\.id) == ["a", "b"])
    }

    /// The bar goes to the reply that has the keyboard; before any, to the one just begun.
    @Test func theBarGoesToTheReplyBeingWritten() {
        let ordered = ComposePinning.ordered([draft("a", created: 0, updated: 60), draft("b", created: 30, updated: 30)])
        #expect(ComposePinning.pinned(ordered, active: nil)?.id == "b")
        #expect(ComposePinning.pinned(ordered, active: "a")?.id == "a")
        #expect(ComposePinning.pinned(ordered, active: "gone")?.id == "b")
        #expect(ComposePinning.pinned([], active: "a") == nil)
    }

    /// A reply takes the bar as soon as its text or its fields have the keyboard.
    @Test func aReplyTakesTheBarWhenItHasTheKeyboard() {
        let sessions = ComposeSessions()
        let first = sessions("a"), second = sessions("b")
        #expect(sessions.active == nil)
        second.fieldsFocused = true
        #expect(sessions.active == "b")
        first.editor.isFocused = true
        #expect(sessions.active == "a")
        #expect(sessions("a") === first)
    }
}
