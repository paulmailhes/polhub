import Foundation
import HubDesign
import Testing
@testable import MeetingsUI

/// The pages of lot 8 (19/11): what they say and where they open, without a screen.
@MainActor @Suite struct PagesTests {
    /// A meeting whose audio does not play says why in French, in one line; the system's own text (in English, with a
    /// file's name) waits under « Détails ».
    @Test func aMeetingWhoseAudioDoesNotPlaySaysWhyInFrench() {
        let missing = AudioProblem(CocoaError(.fileReadNoSuchFile, userInfo: [NSFilePathErrorKey: "/tmp/reunion/meeting.json"]))
        #expect(missing.sentence == "L'audio de cette réunion est introuvable : son dossier est incomplet.")
        #expect(missing.details?.isEmpty == false)
        #expect(AudioProblem(NSError(domain: NSPOSIXErrorDomain, code: Int(ENOENT))).sentence == missing.sentence)
        let damaged = AudioProblem(DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Une ligne illisible")))
        #expect(damaged.sentence == "L'audio de cette réunion ne se lit pas : un de ses fichiers est abîmé.")
        #expect(AudioProblem(CocoaError(.fileReadCorruptFile)).sentence == damaged.sentence)
        let other = AudioProblem(NSError(domain: "AVFoundationErrorDomain", code: -11_800))
        #expect(other.sentence == "L'audio de cette réunion ne se lit pas.")
        for problem in [missing, damaged, other] {
            #expect(!problem.sentence.contains("meeting.json") && problem.details != problem.sentence)
        }
        // Nothing recorded at all: hub's sentence says it all, no « Détails ».
        #expect(AudioProblem.silent.sentence == "Aucun son enregistré pour cette réunion." && AudioProblem.silent.details == nil)
    }

    /// The week opens on the hour of Réglages › Calendrier with air above its label: « 08 h » is no longer cut by the top
    /// of the grid (the label rises over its line).
    @Test func theWeekOpensOnItsFirstHourReadWhole() {
        for hour in [1, 8, 12] {
            let line = CalendarView.gridTop + CGFloat(hour) * CalendarView.hourHeight
            let top = CalendarView.openingOffset(hour: hour)
            #expect(line - CalendarView.labelRise - top >= Space.s)
            #expect(line - top <= CalendarView.hourHeight / 2)
        }
        #expect(CalendarView.openingOffset(hour: 0) == 0)
    }

    /// Contacts with no one chosen says what to do, no longer the old vault (gone on 16/11).
    @Test func contactsWithNoOneChosenSaysWhatToDo() {
        #expect(ContactsView.noneChosen.title == "Aucun contact choisi")
        #expect(ContactsView.noneChosen.text == "Choisis un contact dans la liste.")
    }
}
