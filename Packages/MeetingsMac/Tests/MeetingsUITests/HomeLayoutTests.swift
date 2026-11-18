import Colin
import Foundation
import Persistence
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
