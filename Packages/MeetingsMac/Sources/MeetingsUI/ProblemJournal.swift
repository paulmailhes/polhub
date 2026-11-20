import Domain
import Foundation
import Persistence
import HubDesign

extension AppDatabase {
    /// What the system said of a problem, in the journal of Réglages (lot 10, 20/11), never on the screen: `Words.problem`
    /// keeps it in `journal`. Nothing for hub's own errors, already said in French.
    func journal(_ problem: Words.Problem, at date: Date = Date()) {
        guard let text = problem.journal else { return }
        try? MeetingStore(self).addJournal(JournalEntry(createdAt: date, kind: .alert, message: text))
    }
}
