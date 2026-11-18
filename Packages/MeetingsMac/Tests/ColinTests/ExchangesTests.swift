import Foundation
import Persistence
import Testing
@testable import Colin

/// Who wrote to whom, and when (18/11): the exchange with a person, across the threads and the mailboxes. Every name
/// and address here is invented.
@Suite struct ExchangesTests {
    static let me = "moi@exemple.fr", claire = "claire@cabinet.exemple", marc = "marc@exemple.net", anne = "anne@maison.exemple"
    /// Wednesday 18/11/2026, 10:00 in Paris.
    let now = Date(timeIntervalSince1970: 1_794_992_400)
    let site = UUID(), house = UUID()

    func ago(_ days: Double) -> Date { now.addingTimeInterval(-days * 86_400) }

    func received(_ thread: String, from: String, _ daysAgo: Double, to: [String] = [me], calendar: Bool = false) -> MailExchange {
        MailExchange(threadKey: thread, date: ago(daysAgo), mine: false, sender: from, recipients: to, calendar: calendar)
    }

    func sent(_ thread: String, to: [String], _ daysAgo: Double) -> MailExchange {
        MailExchange(threadKey: thread, date: ago(daysAgo), mine: true, sender: Self.me, recipients: to, calendar: false)
    }

    /// Claire wrote in thread « a » five days ago; Paul answered her two days ago in a new thread, « b ».
    var answeredElsewhere: Exchanges {
        Exchanges([received("a", from: Self.claire, 5), sent("b", to: [Self.claire, Self.marc], 2)])
    }

    @Test func paulWroteToAPersonInWhateverThread() {
        let exchanges = answeredElsewhere
        #expect(exchanges.wrote(to: Self.claire, after: ago(5)))
        // In copy too.
        #expect(exchanges.wrote(to: Self.marc, after: ago(5)))
        #expect(exchanges.wrote(to: "CLAIRE@Cabinet.Exemple", after: ago(5)))
        #expect(!exchanges.wrote(to: Self.anne, after: ago(5)))
        // What he wrote before her message is no answer to it.
        #expect(!exchanges.wrote(to: Self.claire, after: ago(1)))
    }

    @Test func aPersonWroteInWhateverThread() {
        // Paul wrote to Anne nine days ago in « a »; she sent her files four days ago in a new thread.
        let exchanges = Exchanges([sent("a", to: [Self.anne], 9), received("b", from: Self.anne, 4)])
        #expect(exchanges.heard(from: Self.anne, after: ago(9)))
        #expect(!exchanges.heard(from: Self.anne, after: ago(3)))
        #expect(!exchanges.heard(from: Self.claire, after: ago(9)))
        // What Paul wrote himself is never « heard ».
        #expect(!exchanges.heard(from: Self.me, after: ago(30)))
    }

    /// As the rule stood on a past day: only what had happened by then.
    @Test func theWindowOpensAfterItsStartAndClosesAtItsEnd() {
        let exchanges = answeredElsewhere
        // Exactly at the start: not after it.
        #expect(!exchanges.wrote(to: Self.claire, after: ago(2)))
        // Exactly at the end: in.
        #expect(exchanges.wrote(to: Self.claire, after: ago(5), until: ago(2)))
        #expect(!exchanges.wrote(to: Self.claire, after: ago(5), until: ago(3)))
        #expect(exchanges.heard(from: Self.claire, after: ago(6), until: ago(5)))
        #expect(!exchanges.heard(from: Self.claire, after: ago(6), until: ago(5.5)))
    }

    @Test func theMessagesMayComeInAnyOrder() {
        let exchanges = Exchanges([sent("b", to: [Self.claire], 2), received("a", from: Self.claire, 5), sent("c", to: [Self.claire], 8)])
        #expect(exchanges.wrote(to: Self.claire, after: ago(5)))
        #expect(exchanges.wrote(to: Self.claire, after: ago(9), until: ago(7)))
        #expect(!exchanges.wrote(to: Self.claire, after: ago(7), until: ago(3)))
    }

    /// By project: a mail gone, or come, in any thread of the same project.
    @Test func aProjectHearsAndIsWrittenToThroughAllItsThreads() {
        let exchanges = Exchanges([received("a", from: Self.claire, 5), sent("b", to: [Self.marc], 2), received("c", from: Self.anne, 1)],
                                  projects: ["a": site, "b": site, "c": house])
        #expect(exchanges.wrote(in: site, after: ago(5)))
        #expect(!exchanges.wrote(in: house, after: ago(5)))
        #expect(exchanges.heard(in: house, after: ago(3)))
        #expect(exchanges.heard(in: site, after: ago(6)))
        #expect(!exchanges.heard(in: site, after: ago(4)))
        // A thread without a project counts for none.
        #expect(!Exchanges([sent("z", to: [Self.claire], 2)]).wrote(in: site, after: ago(5)))
    }

    @Test func theLastMessageOfAThreadOnADay() {
        let exchanges = Exchanges([received("a", from: Self.claire, 9), sent("a", to: [Self.claire], 8), received("a", from: Self.marc, 3, to: [Self.me, Self.claire], calendar: true)])
        #expect(exchanges.lastReceived(in: "a")?.sender == Self.marc)
        #expect(exchanges.lastReceived(in: "a")?.calendar == true)
        #expect(exchanges.lastReceived(in: "a")?.recipients == [Self.me, Self.claire])
        // A week ago, Claire's was the last.
        #expect(exchanges.lastReceived(in: "a", asOf: ago(7))?.sender == Self.claire)
        #expect(exchanges.lastReceived(in: "a", asOf: ago(10)) == nil)
        #expect(exchanges.lastSent(in: "a")?.recipients == [Self.claire])
        #expect(exchanges.lastSent(in: "a", asOf: ago(8.5)) == nil)
        #expect(exchanges.lastReceived(in: "ailleurs") == nil)
    }

    @Test func nothingIsKnownOfNoMessage() {
        let exchanges = Exchanges([])
        #expect(!exchanges.wrote(to: Self.claire, after: .distantPast))
        #expect(!exchanges.heard(from: Self.claire, after: .distantPast))
        #expect(exchanges.lastReceived(in: "a") == nil)
    }
}
