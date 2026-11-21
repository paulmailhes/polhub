import Foundation
import Notifications
import Testing
import VigieKit
@testable import MeetingsUI

/// 21/11, the migration (Paul : « complètement désactiver mon Vigie, utiliser celui de Hub ») : hub notifie comme l'app
/// Vigie. Rien au premier relevé, une seule fois par élément, trois bannières au plus, la plus importante d'abord ; une
/// attente finie retire sa notification ; rien tant que l'app Vigie tourne. Données inventées.
@Suite struct VigieNotificationsTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func overview(_ toReview: [VigieReview] = [], conversations: [VigieConversation] = [], accounts: [VigieAccount] = [],
                  reports: [VigieReport] = []) -> VigieOverview {
        VigieOverview(toReview: toReview, conversations: conversations, accounts: accounts, reports: reports)
    }

    func action(_ id: String, expires minutes: Double = 8) -> VigieReview {
        VigieReview(id: id, kind: .blocked, conversationID: "b1b9", conversationTitle: "Atelier", title: "Écrase l'historique", state: "waiting",
                    pendingID: "1", expiresAt: now.addingTimeInterval(minutes * 60), rule: "Envoi forcé")
    }

    @Test func theFirstReadingNotifiesNothing() {
        var state = VigieNotifications.State()
        let outcome = VigieNotifications.plan(overview([action("g:b1b9:1")]), state: &state, now: now)
        #expect(outcome.post.isEmpty && state.seeded && state.seen["r:g:b1b9:1"] != nil)
        // The same element afterwards: still nothing.
        #expect(VigieNotifications.plan(overview([action("g:b1b9:1")]), state: &state, now: now).post.isEmpty)
    }

    @Test func whatIsNewIsNotifiedOnceTheMostImportantFirst() {
        var state = VigieNotifications.State()
        _ = VigieNotifications.plan(overview(), state: &state, now: now)
        let question = VigieReview(id: "q:7f3a", kind: .question, conversationID: "b1b9", title: "Quel fond ?",
                                   question: VigieQuestion(id: "7f3a", items: [.init(question: "Quel fond ?", chosen: ["Fond B"])]))
        let waiting = VigieReview(id: "w:b1b9:2", kind: .waiting, conversationID: "b1b9", title: "Plan à approuver", detail: "Réponds dans VS Code.")
        let items = [question, waiting, action("g:b1b9:1"), action("g:b1b9:3"), action("g:b1b9:4"),
                     VigieReview(id: "b:b1b9:5", kind: .blocked, conversationID: "b1b9", title: "Installe", state: "blocked", reason: "echec")]
        let conversations = [VigieConversation(id: "b1b9", title: "Atelier", status: .blocked)]
        let outcome = VigieNotifications.plan(overview(items, conversations: conversations), state: &state, now: now)
        #expect(outcome.post.map(\.kind) == [.sensitive, .sensitive, .sensitive, .waiting, .failed, .question])
        // Three banners at most; the answer chosen for Paul never makes one.
        #expect(outcome.banners.count == 3 && !outcome.banners.contains("r:q:7f3a"))
        let sensitive = outcome.post[0]
        #expect(sensitive.title == "À autoriser · Atelier" && sensitive.subtitle == "Écrase l'historique")
        #expect(sensitive.body.hasPrefix("Refusée à ") && sensitive.body.hasSuffix("sans réponse. Clique pour décider."))
        #expect(outcome.post[3].title == "Atelier te propose un plan")
        #expect(outcome.post[5].title == "Réponse choisie pour toi · Atelier" && outcome.post[5].body == "« Quel fond ? » : Fond B" && outcome.post[5].quiet)
        // Read again: nothing new.
        #expect(VigieNotifications.plan(overview(items, conversations: conversations), state: &state, now: now).post.isEmpty)
    }

    @Test func aWaitThatEndedTakesItsNotificationAway() {
        var state = VigieNotifications.State()
        _ = VigieNotifications.plan(overview(), state: &state, now: now)
        _ = VigieNotifications.plan(overview([action("g:b1b9:1"), action("g:b1b9:2")]), state: &state, now: now)
        let outcome = VigieNotifications.plan(overview([action("g:b1b9:2")]), state: &state, now: now)
        #expect(outcome.post.isEmpty && outcome.remove == ["r:g:b1b9:1"])
    }

    @Test func aKindTurnedOffIsNotShownButNotForgotten() {
        var state = VigieNotifications.State()
        _ = VigieNotifications.plan(overview(), state: &state, now: now)
        let outcome = VigieNotifications.plan(overview([action("g:b1b9:1")]), state: &state, now: now, enabled: { $0 != .sensitive })
        #expect(outcome.post.isEmpty && state.seen["r:g:b1b9:1"] != nil)
    }

    /// While the app Vigie runs, it notifies: hub marks everything seen, so that nothing bursts out when it stops.
    @Test func whileTheAppVigieRunsHubStaysSilent() {
        var state = VigieNotifications.State()
        _ = VigieNotifications.plan(overview(), state: &state, now: now)
        #expect(VigieNotifications.plan(overview([action("g:b1b9:1")]), state: &state, now: now, silent: true).post.isEmpty)
        #expect(VigieNotifications.plan(overview([action("g:b1b9:1")]), state: &state, now: now).post.isEmpty)
    }

    @Test func aConversationWaitsTwentySecondsBeforeItIsSaid() {
        var state = VigieNotifications.State()
        _ = VigieNotifications.plan(overview(), state: &state, now: now)
        let fresh = VigieReview(id: "c:b1b9", kind: .waiting, conversationID: "b1b9", title: "Attend ton accord dans VS Code", at: now.addingTimeInterval(-5))
        #expect(VigieNotifications.plan(overview([fresh]), state: &state, now: now).post.isEmpty)
        let outcome = VigieNotifications.plan(overview([fresh]), state: &state, now: now.addingTimeInterval(30))
        #expect(outcome.post.first?.title == "Une conversation attend ton accord" && outcome.post.first?.body.hasPrefix("En attente depuis ") == true)
    }

    @Test func aWeekIsSaidOncePerThresholdAndASessionWhileAConversationWorks() {
        var state = VigieNotifications.State()
        _ = VigieNotifications.plan(overview(), state: &state, now: now)
        let resets = now.addingTimeInterval(3 * 86_400)
        let working = [VigieConversation(id: "b1b9", title: "Atelier", status: .working, accountID: "travail1")]
        let at85 = [VigieAccount(id: "travail1", label: "Travail 1", session: .init(percent: 92, resetsAt: now.addingTimeInterval(3_600)),
                                 week: .init(percent: 85, resetsAt: resets))]
        let first = VigieNotifications.plan(overview(conversations: working, accounts: at85), state: &state, now: now)
        #expect(first.post.map(\.title) == ["Travail 1 à 92 % de sa session", "Travail 1 passe 80 % de sa semaine"])
        #expect(first.post[0].body.hasPrefix("Atelier va bientôt s'arrêter"))
        let at86 = [VigieAccount(id: "travail1", label: "Travail 1", week: .init(percent: 86, resetsAt: resets))]
        #expect(VigieNotifications.plan(overview(accounts: at86), state: &state, now: now).post.isEmpty)
        let at91 = [VigieAccount(id: "travail1", label: "Travail 1", week: .init(percent: 91, resetsAt: resets))]
        #expect(VigieNotifications.plan(overview(accounts: at91), state: &state, now: now).post.map(\.title) == ["Travail 1 passe 90 % de sa semaine"])
    }

    /// The notifier remembers what it said from one launch to the next, stays silent while the app Vigie runs, and
    /// hands macOS hub's notices: Vigie's kind, the conversation a click opens, quiet when no banner.
    @MainActor @Test func theNotifierRemembersAndStaysSilentWhileTheAppRuns() async throws {
        let defaults = try #require(UserDefaults(suiteName: "vigie-notifier-\(UUID().uuidString)"))
        var posted: [PlannedNotice] = []
        var removed: [String] = []
        var appRuns = false
        func notifier() -> VigieNotifier {
            VigieNotifier(defaults: defaults, post: { posted.append($0) }, remove: { removed += $0 }, appRunning: { appRuns })
        }
        let first = notifier()
        await first.process(overview(), now: now)
        await first.process(overview([action("g:b1b9:1")]), now: now)
        let notice = try #require(posted.first)
        #expect(posted.count == 1 && notice.kind == .vigie && notice.vigie == "b1b9" && notice.id == "r:g:b1b9:1" && !notice.quiet)
        // A new launch: what was said is not said again.
        let second = notifier()
        await second.process(overview([action("g:b1b9:1")]), now: now)
        #expect(posted.count == 1)
        // The app Vigie runs: nothing from hub, and nothing bursts out when it stops.
        appRuns = true
        await second.process(overview([action("g:b1b9:1"), action("g:b1b9:2")]), now: now)
        appRuns = false
        await second.process(overview([action("g:b1b9:1"), action("g:b1b9:2")]), now: now)
        #expect(posted.count == 1)
        // Turned off in Réglages › Vigie: not shown.
        defaults.set(false, forKey: VigieNotifier.key(.sensitive))
        await second.process(overview([action("g:b1b9:1"), action("g:b1b9:2"), action("g:b1b9:3")]), now: now)
        #expect(posted.count == 1 && removed.isEmpty)
    }

    /// A request that finished is said with its length and « À toi »; it goes when the conversation works again.
    @Test func anEndIsSaidAndTakenAwayWhenTheConversationGoesOn() {
        var state = VigieNotifications.State()
        _ = VigieNotifications.plan(overview(), state: &state, now: now)
        let done = VigieReport(id: "fin:b1b9:1", kind: "missionDone", conversationID: "b1b9", title: "Les 29 étapes sont faites.",
                               prompt: "Applique la charte", toYou: "relire la planche", duration: 34 * 60, at: now)
        let idle = [VigieConversation(id: "b1b9", title: "Atelier", status: .idle)]
        let outcome = VigieNotifications.plan(overview(conversations: idle, reports: [done]), state: &state, now: now)
        #expect(outcome.post.first?.title == "Atelier a fini · 34 min" && outcome.post.first?.body == "Les 29 étapes sont faites.\nÀ toi : relire la planche")
        let working = [VigieConversation(id: "b1b9", title: "Atelier", status: .working)]
        #expect(VigieNotifications.plan(overview(conversations: working, reports: [done]), state: &state, now: now).remove == ["fin:b1b9:1"])
    }
}
