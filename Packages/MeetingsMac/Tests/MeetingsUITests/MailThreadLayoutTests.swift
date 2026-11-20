import Foundation
import Mail
import Persistence
import Testing
@testable import MeetingsUI

/// Lot 6 (19/11): an open thread on one column, one principal button at a time, a short date, « Envoyé · Annuler » in
/// the draft's own bar, a meaning never said by a color alone.
@MainActor @Suite struct MailThreadLayoutTests {
    var paris: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        calendar.locale = Locale(identifier: "fr_FR")
        return calendar
    }

    func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        paris.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    /// An open message says when in short: today and yesterday with their hour, this year's day, another year's.
    @Test func anOpenMessageSaysWhenInShort() {
        let now = date(2026, 11, 19, 18, 30)
        #expect(MailText.shortDate(date(2026, 11, 19, 17, 55), now: now, calendar: paris) == "Aujourd'hui 17:55")
        #expect(MailText.shortDate(date(2026, 11, 18, 9, 12), now: now, calendar: paris) == "Hier 9:12")
        #expect(MailText.shortDate(date(2026, 11, 14, 9, 12), now: now, calendar: paris) == "14 nov.")
        #expect(MailText.shortDate(date(2025, 12, 3, 9, 12), now: now, calendar: paris) == "3 déc. 2025")
        // Just after midnight, the evening before is « Hier ».
        #expect(MailText.shortDate(date(2026, 11, 18, 23, 50), now: date(2026, 11, 19, 0, 5), calendar: paris) == "Hier 23:50")
    }

    /// « Répondre » is the screen's principal button until a reply is open under the thread: then its « Envoyer » is.
    @Test func replyIsThePrincipalUntilAReplyIsOpen() {
        #expect(MailThreadView.replyIsPrincipal(openReplies: 0))
        #expect(!MailThreadView.replyIsPrincipal(openReplies: 1))
        #expect(!MailThreadView.replyIsPrincipal(openReplies: 2))
    }

    /// While its delay runs, the draft's bar says « Envoyé » with « Annuler »; on its way, « Envoyé » alone. Another
    /// draft leaving changes nothing to this one.
    @Test func theDraftsBarSaysSentAndCallsItBack() {
        let created = Date(timeIntervalSince1970: 1_794_562_920)
        let draft = MailDraftRow(account: "moi@exemple.fr", mode: .reply, threadKey: "moi@exemple.fr|a", createdAt: created)
        #expect(ComposeStatus.kind(draft: draft, sending: (draft.id, false), planned: nil) == .sent(undoable: true))
        #expect(ComposeStatus.kind(draft: draft, sending: (draft.id, true), planned: nil) == .sent(undoable: false))
        #expect(ComposeStatus.kind(draft: draft, sending: ("autre", false), planned: nil) == .keptOnMac)
        #expect(ComposeStatus.kind(draft: draft, sending: nil, planned: nil) == .keptOnMac)
        // « Envoyer maintenant » on a programmed one: it is leaving, whatever its time.
        let planned = ScheduledSend(draftID: draft.id, account: "moi@exemple.fr", sendAt: created, fingerprint: "", subject: "x", threadKey: nil,
                                    state: .held, createdAt: created)
        #expect(ComposeStatus.kind(draft: draft, sending: (draft.id, false), planned: planned) == .sent(undoable: true))
        #expect(ComposeStatus.kind(draft: draft, sending: nil, planned: planned) == .late)
        var waiting = planned
        waiting.state = .waiting
        #expect(ComposeStatus.kind(draft: draft, sending: nil, planned: waiting) == .planned(at: created))
        var kept = draft
        kept.gmailDraftID = "g1"
        kept.pushedAt = created.addingTimeInterval(1)
        #expect(ComposeStatus.kind(draft: kept, sending: nil, planned: nil) == .keptInGmail)
        kept.lastError = "Gmail ne répond pas"
        #expect(ComposeStatus.kind(draft: kept, sending: nil, planned: nil) == .failed("Gmail ne répond pas"))
        kept.conflict = .modifie
        #expect(ComposeStatus.kind(draft: kept, sending: nil, planned: nil) == .waitingChoice)
    }

    /// The bar at the bottom of the page leaves « … part dans 8 s » to the draft's own bar when that bar is on screen:
    /// a reply under the open thread. A new mail closes as it leaves: the bar at the bottom says it.
    @Test func theBottomBarLeavesTheSendingToTheDraftsBar() {
        let created = Date(timeIntervalSince1970: 1_794_562_920)
        let reply = MailDraftRow(account: "moi@exemple.fr", mode: .reply, threadKey: "moi@exemple.fr|a", createdAt: created)
        let new = MailDraftRow(account: "moi@exemple.fr", mode: .new, createdAt: created)
        #expect(MailPanels.sendingInBar(reply.id, drafts: [reply, new], thread: "moi@exemple.fr|a"))
        #expect(!MailPanels.sendingInBar(reply.id, drafts: [reply, new], thread: "moi@exemple.fr|b"))
        #expect(!MailPanels.sendingInBar(reply.id, drafts: [reply, new], thread: nil))
        #expect(!MailPanels.sendingInBar(new.id, drafts: [reply, new], thread: "moi@exemple.fr|a"))
        #expect(!MailPanels.sendingInBar(nil, drafts: [reply, new], thread: "moi@exemple.fr|a"))
    }

    /// Over an open thread or a draft, « Nouveau mail » steps down from principal: « Répondre », « Envoyer » or « Pas un
    /// spam » is the screen's one.
    @Test func newMailStepsDownOverAPanel() {
        #expect(MailListView.newMailIsPrincipal(composing: nil, thread: nil))
        #expect(!MailListView.newMailIsPrincipal(composing: "d1", thread: nil))
        #expect(!MailListView.newMailIsPrincipal(composing: nil, thread: "moi@exemple.fr|a"))
    }

    /// An address to check never says so by its color alone: a stranger carries « ? », an invalid one the triangle.
    @Test func anAddressToCheckCarriesASymbol() {
        #expect(RecipientMark.of(valid: true, known: true) == .known && RecipientMark.known.symbol == nil)
        #expect(RecipientMark.of(valid: true, known: false) == .stranger && RecipientMark.stranger.symbol == "questionmark.circle")
        #expect(RecipientMark.of(valid: false, known: true) == .invalid && RecipientMark.invalid.symbol == "exclamationmark.triangle.fill")
        #expect(RecipientMark.of(valid: false, known: false) == .invalid)
    }

    /// The agent's banner: what to do in its title; the rule of the addresses names their mark, never a color.
    @Test func theAgentsBannerNamesTheMarkNotAColor() {
        #expect(ComposeView.agentNotice.title == "Préparé par un agent : relis-le avant d'envoyer.")
        #expect(ComposeView.agentNotice.detail.contains("?") && !ComposeView.agentNotice.detail.contains("orange"))
    }
}

/// Lot 10 (20/11): the details of a message find their rows of people by their field, never by their title.
@Suite struct MessageDetailTests {
    @Test func thePeopleAreInTheirFieldsRows() {
        #expect(MessageDetail.allCases.filter(\.listsPeople) == [.to, .cc])
        #expect(MessageDetail.allCases.map(\.title) == ["De", "À", "Cc", "Date", "Boîte", "Expéditeur"])
    }
}
