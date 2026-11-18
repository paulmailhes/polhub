import Foundation
import Persistence
import Testing
@testable import Colin

/// The first message of a fresh context (18/11): the day, what Colin knows, the last exchanges, what waits on the
/// Accueil. Every text here is invented.
@Suite struct ColinPrimerTests {
    /// Wednesday 18/11/2026, 10:00 in Paris.
    let now = Date(timeIntervalSince1970: 1_794_992_400)
    var paris: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        calendar.locale = Locale(identifier: "fr_FR")
        return calendar
    }

    func message(_ text: String, _ author: ColinMessageRow.Author, minutesAgo: Double) -> ColinMessageRow {
        ColinMessageRow(author: author, text: text, createdAt: now.addingTimeInterval(-minutesAgo * 60))
    }

    @Test func thePrimerSaysTheDayKnowledgeExchangesAndWhatWaits() {
        let text = ColinPrimer.text(knowledge: "Écrire court, à mon ton.", exchanges: [message("Où on en est ?", .paul, minutesAgo: 90),
                                                                                      message("Trois projets t'attendent.", .colin, minutesAgo: 89)],
                                    review: ["Brouillon prêt pour Claire · Cabinet Martin", "Marc attend ta réponse · 4 jours"], now: now, calendar: paris)
        #expect(text.contains("mercredi 18 novembre 2026, 10:00"))
        #expect(text.contains("Écrire court, à mon ton."))
        let question = try? #require(text.range(of: "Moi (mercredi 18 novembre, 08:30) : Où on en est ?"))
        let answer = try? #require(text.range(of: "Toi (mercredi 18 novembre, 08:31) : Trois projets t'attendent."))
        #expect(question != nil && answer != nil && question!.lowerBound < answer!.lowerBound)
        #expect(text.contains("- Brouillon prêt pour Claire · Cabinet Martin\n- Marc attend ta réponse · 4 jours"))
    }

    @Test func anEmptyPartIsLeftOut() {
        let text = ColinPrimer.text(knowledge: "  \n", exchanges: [], review: [], now: now, calendar: paris)
        #expect(text.contains("mercredi 18 novembre 2026, 10:00"))
        #expect(!text.contains("Ce que tu sais"))
        #expect(!text.contains("Nos derniers échanges"))
        #expect(text.contains("À valider : rien."))
    }
}
