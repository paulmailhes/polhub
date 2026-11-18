import Colin
import Foundation
import Persistence
import PolhubDesign
import Testing
@testable import MeetingsUI

/// The new Accueil (18/11): Colin's column on the left, the lists on the right; one under the other when the
/// window is narrow.
@Suite struct HomeLayoutTests {
    @Test func twoColumnsFromTheBreakpoint() {
        #expect(HomeLayout.breakpoint == 760 && HomeLayout.listsWidth == 360)
        #expect(HomeLayout.of(width: 760) == .columns)
        #expect(HomeLayout.of(width: 759) == .stacked)
        #expect(HomeLayout.of(width: 1_400) == .columns)
    }

    @Test func theNarrowestWindowStacks() {
        #expect(HomeLayout.of(width: 661) == .stacked)
        #expect(HomeLayout.of(width: 0) == .stacked)
    }
}

/// The words of the Accueil. Every name here is invented.
@Suite struct HomeTextTests {
    func line(_ kind: ReviewRules.Kind, _ person: String, detail: String? = nil, days: Int? = nil) -> ReviewRules.Line {
        ReviewRules.Line(id: "\(kind.rawValue):x", kind: kind, person: person, detail: detail, days: days)
    }

    @Test func eachLineSaysWhatWaits() {
        #expect(ReviewText.title(line(.draft, "Claire")) == "Brouillon prêt pour Claire")
        #expect(ReviewText.title(line(.reply, "Marc")) == "Marc attend ta réponse")
        #expect(ReviewText.title(line(.silent, "Anne")) == "Anne ne répond plus")
        #expect(ReviewText.title(line(.unfiled, "Point Cabinet Martin")) == "Réunion à ranger")
        // Without a name, the sentence still stands.
        #expect(ReviewText.title(line(.draft, "")) == "Brouillon prêt")
        #expect(ReviewText.title(line(.reply, "")) == "Un mail attend ta réponse")
        #expect(ReviewText.title(line(.silent, "")) == "Un client ne répond plus")
    }

    @Test func theSecondLineSaysTheProjectAndTheDays() {
        #expect(ReviewText.detail(line(.reply, "Marc", detail: "Studio Nord", days: 3)) == "Studio Nord · 3 jours")
        #expect(ReviewText.detail(line(.silent, "Anne", detail: "Maison Leroy", days: 9)) == "Maison Leroy · 9 jours")
        #expect(ReviewText.detail(line(.reply, "Marc", days: 1)) == "1 jour")
        #expect(ReviewText.detail(line(.reply, "Marc", days: 0)) == "aujourd'hui")
        #expect(ReviewText.detail(line(.draft, "Claire", detail: "Cabinet Martin")) == "Cabinet Martin")
        #expect(ReviewText.detail(line(.draft, "Claire")) == nil)
        // A meeting to file is named on its second line.
        #expect(ReviewText.detail(line(.unfiled, "Point Cabinet Martin")) == "Point Cabinet Martin")
    }

    @Test func eachLineHasItsButton() {
        #expect(ReviewText.action(.draft) == "Relire")
        #expect(ReviewText.action(.reply) == "Ouvrir")
        #expect(ReviewText.action(.silent) == "Ouvrir")
        #expect(ReviewText.action(.unfiled) == "Ranger")
    }

    /// « Pas besoin », « Plus tard », and for a silent client « Anne a répondu ailleurs »: said with the name, never
    /// with « elle » or « il ».
    @Test func theWaysToSetALineAside() {
        #expect(ReviewText.dismissals(line(.reply, "Marc")).map(\.title) == ["Pas besoin", "Plus tard"])
        #expect(ReviewText.dismissals(line(.reply, "Marc")).map(\.reason) == [.notNeeded, .later])
        #expect(ReviewText.dismissals(line(.silent, "Anne")).map(\.title) == ["Anne a répondu ailleurs", "Pas besoin", "Plus tard"])
        #expect(ReviewText.dismissals(line(.silent, "Anne")).map(\.reason) == [.answeredElsewhere, .notNeeded, .later])
        #expect(ReviewText.dismissals(line(.silent, "")).first?.title == "Réponse reçue ailleurs")
        // A draft leaves when it is sent or deleted; a meeting when it is filed, under « Aucun » too.
        #expect(ReviewText.dismissals(line(.draft, "Claire")).isEmpty)
        #expect(ReviewText.dismissals(line(.unfiled, "Point Cabinet Martin")).isEmpty)
    }

    @Test func aSentenceOfThePointIsItsLabelAndItsText() {
        #expect(BriefingText.parts("Cette semaine : 5 rendez-vous, le prochain demain 10:00.") == BriefingText.Part(label: "Cette semaine", text: "5 rendez-vous, le prochain demain 10:00."))
        // The hour of « depuis » has its own colon: only the one that ends the label counts.
        #expect(BriefingText.parts("Depuis hier 19:40 : 4 mails de clients.") == BriefingText.Part(label: "Depuis hier 19:40", text: "4 mails de clients."))
        // The text begins with a capital, as a sentence of its own.
        #expect(BriefingText.parts("Cette semaine : aucun rendez-vous.") == BriefingText.Part(label: "Cette semaine", text: "Aucun rendez-vous."))
        #expect(BriefingText.parts("Rien à dire.") == BriefingText.Part(label: nil, text: "Rien à dire."))
    }
}

/// Colin's thread and bar on the Accueil (18/11): the days of the thread, what the bar says, how wide it is.
@MainActor
@Suite struct ColinThreadTextTests {
    /// Wednesday 18/11/2026, 10:00 in Paris.
    let now = Date(timeIntervalSince1970: 1_794_992_400)
    var paris: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        calendar.locale = Locale(identifier: "fr_FR")
        return calendar
    }

    @Test func theDaySeparatorsSayTodayYesterdayThenTheDate() {
        #expect(ColinThreadText.day(now.addingTimeInterval(-3_600), now: now, calendar: paris) == "Aujourd'hui")
        #expect(ColinThreadText.day(now.addingTimeInterval(-86_400), now: now, calendar: paris) == "Hier")
        #expect(ColinThreadText.day(now.addingTimeInterval(-2 * 86_400), now: now, calendar: paris) == "lundi 16 novembre")
        let messages = [-2.0, -1.9, -1.0, 0].map { days in
            ColinMessageRow(author: .paul, text: "\(days)", createdAt: now.addingTimeInterval(days * 86_400 - 60))
        }
        #expect(ColinThreadText.sections(messages, now: now, calendar: paris).map(\.day) == ["lundi 16 novembre", "Hier", "Aujourd'hui"])
        #expect(ColinThreadText.sections(messages, now: now, calendar: paris).map { $0.messages.count } == [2, 1, 1])
    }

    @Test func theBarSaysWhatColinCanDo() {
        let ask = "Écris ou dicte à Colin…"
        #expect(ColinThreadText.bar(.off) == .turnOn)
        #expect(ColinThreadText.bar(.waitingCall) == .field(placeholder: "Colin attend la fin de ton call", enabled: false, note: nil))
        #expect(ColinThreadText.bar(.idle) == .field(placeholder: ask, enabled: true, note: nil))
        #expect(ColinThreadText.bar(.working("Colin lit tes mails…")) == .field(placeholder: ask, enabled: true, note: nil))
        #expect(ColinThreadText.bar(.settling) == .field(placeholder: ask, enabled: true, note: "Le Mac vient de se réveiller : Colin répond dans un instant."))
        #expect(ColinThreadText.bar(.broken("Limite atteinte.")) == .field(placeholder: ask, enabled: true, note: "Limite atteinte."))
    }

    @Test func theEndOfAnAnswerIsSaidApart() {
        func answer(_ text: String, _ state: ColinMessageRow.State) -> ColinMessageRow { ColinMessageRow(author: .colin, text: text, state: state, createdAt: now) }
        #expect(ColinThreadText.note(of: answer("Marc t'a écrit\n\nArrêté : ton call commence.", .interrupted)) == ("Marc t'a écrit", "Arrêté : ton call commence."))
        #expect(ColinThreadText.note(of: answer("Arrêté : le Mac s'endort.", .interrupted)) == ("", "Arrêté : le Mac s'endort."))
        #expect(ColinThreadText.note(of: answer("Marc t'a", .interrupted)) == ("Marc t'a", "Arrêté."))
        #expect(ColinThreadText.note(of: answer("Mar", .failed)) == ("Mar", "Colin n'a pas pu finir."))
        #expect(ColinThreadText.note(of: answer("Trois projets.", .done)) == ("Trois projets.", nil))
    }

    @Test func theBarIsAsWideAsColinsColumn() {
        #expect(HomeLayout.colinWidth(content: 1_000) == 1_000 - HomeLayout.listsWidth - Space.l)
    }
}
