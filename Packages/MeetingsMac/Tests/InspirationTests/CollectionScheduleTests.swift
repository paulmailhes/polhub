import Foundation
import Persistence
import Testing
@testable import Inspiration

/// When each collection runs (16/11): the sites every two hours from 8:00 to 22:00, the branding at 9, 14 and
/// 20 h; a slot missed while the Mac slept is caught up once.
@Suite struct CollectionScheduleTests {
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }

    var schedule: CollectionSchedule { CollectionSchedule(calendar: calendar) }

    func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    @Test func theSlotsAreN8nsOnes() {
        #expect(schedule.slots(.websites, on: at(16, 12)) == [8, 10, 12, 14, 16, 18, 20, 22].map { at(16, $0) })
        #expect(schedule.slots(.branding, on: at(16, 12)) == [9, 14, 20].map { at(16, $0) })
    }

    @Test func aCollectionIsDueOncePerSlot() {
        // Never run: at once.
        #expect(schedule.isDue(.websites, lastRun: nil, now: at(16, 9, 30)))
        // Run at 10:01: not before 12:00.
        #expect(!schedule.isDue(.websites, lastRun: at(16, 10, 1), now: at(16, 11, 59)))
        #expect(schedule.isDue(.websites, lastRun: at(16, 10, 1), now: at(16, 12)))
        #expect(!schedule.isDue(.branding, lastRun: at(16, 9, 2), now: at(16, 13, 59)))
        #expect(schedule.isDue(.branding, lastRun: at(16, 9, 2), now: at(16, 14)))
    }

    /// The Mac slept from 9:30 to 19:10: one run of each at the wake, then the usual slots.
    @Test func missedSlotsAreCaughtUpOnce() {
        let wake = at(16, 19, 10)
        let lastRuns: [CollectionJob: Date] = [.websites: at(16, 8, 1), .branding: at(16, 9, 1)]
        #expect(schedule.due(lastRuns: lastRuns, now: wake) == [.websites, .branding])
        let after: [CollectionJob: Date] = [.websites: wake, .branding: wake]
        #expect(schedule.due(lastRuns: after, now: at(16, 19, 59)).isEmpty)
        #expect(schedule.due(lastRuns: after, now: at(16, 20)) == [.websites, .branding])
        // A night: nothing at 7:00 after the evening's runs; the morning's first slots run.
        let evening: [CollectionJob: Date] = [.websites: at(16, 22, 3), .branding: at(16, 20, 2)]
        #expect(schedule.due(lastRuns: evening, now: at(17, 7)).isEmpty)
        #expect(schedule.due(lastRuns: evening, now: at(17, 8)) == [.websites])
        #expect(schedule.due(lastRuns: evening, now: at(17, 9)) == [.websites, .branding])
        // Away for a week: still one run each.
        #expect(schedule.due(lastRuns: evening, now: at(24, 15)) == [.websites, .branding])
    }

    @Test func theNextCheckIsTheNextSlot() {
        #expect(schedule.nextCheck(after: at(16, 9, 30)) == at(16, 10))
        #expect(schedule.nextCheck(after: at(16, 13, 10)) == at(16, 14))
        #expect(schedule.nextCheck(after: at(16, 22)) == at(17, 8))
        #expect(schedule.nextSlot(.branding, after: at(16, 20, 30)) == at(17, 9))
        #expect(schedule.lastSlot(.websites, atOrBefore: at(17, 7)) == at(16, 22))
        #expect(CollectionSchedule(hours: [:], calendar: calendar).due(lastRuns: [:], now: at(16, 12)).isEmpty)
    }

    @Test func theRunLogKeepsTheLastRunsAndAwwwardsState() {
        let log = CollectWorld.runLog()
        #expect(log.lastRuns.isEmpty && log.awwwards == nil)
        log.setLastRun(.websites, at(16, 10))
        log.setAwwwards(CollectionStatus(source: .awwwards, name: "Awwwards", date: at(16, 10), outcome: .read(newItems: 1)))
        #expect(log.lastRuns == [.websites: at(16, 10)])
        #expect(log.awwwards == CollectionStatus(source: .awwwards, name: "Awwwards", date: at(16, 10), outcome: .read(newItems: 1)))
        log.setAwwwards(CollectionStatus(source: .awwwards, name: "Awwwards", date: at(16, 12), outcome: .offline))
        #expect(log.awwwards?.text(now: at(16, 13), calendar: calendar) == "Pas de connexion à Internet : réessai au prochain tour")
    }

    /// The lines of Réglages › Inspiration, in plain French.
    @Test func theStatusesSpeakPlainly() {
        let page = UUID()
        func line(_ outcome: CollectionStatus.Outcome, _ source: CollectionStatus.Source = .linkedIn(page), date: Date? = nil) -> String {
            CollectionStatus(source: source, name: "Studio Exemple", date: date ?? at(16, 14, 2), outcome: outcome).text(now: at(16, 15), calendar: calendar)
        }
        #expect(line(.read(newItems: 2)) == "Lu à 14:02, 2 nouveaux posts")
        #expect(line(.read(newItems: 1)) == "Lu à 14:02, 1 nouveau post")
        #expect(line(.read(newItems: 0)) == "Lu à 14:02, aucun nouveau post")
        #expect(line(.read(newItems: nil)) == "Lu à 14:02")
        #expect(line(.read(newItems: 1), .awwwards) == "Lu à 14:02, 1 nouveau site")
        #expect(line(.read(newItems: 0), .awwwards) == "Lu à 14:02, rien de nouveau")
        #expect(line(.read(newItems: 3), date: at(15, 20)) == "Lu hier à 20:00, 3 nouveaux posts")
        #expect(line(.read(newItems: nil), date: at(12, 9, 5)) == "Lu le 12/11 à 09:05")
        #expect(line(.loginWall) == "LinkedIn demande une connexion : réessai au prochain tour")
        #expect(line(.refused) == "LinkedIn refuse la lecture pour l'instant : réessai au prochain tour")
        #expect(line(.slowDown) == "LinkedIn demande de ralentir : réessai au prochain tour")
        #expect(line(.noPosts) == "Aucun post visible sur la page : réessai au prochain tour")
        // A page's last reading, as the base keeps it after a relaunch.
        let row = InspirationSourceRow(name: "Atelier Nord", link: "https://www.linkedin.com/company/atelier-nord/", lastReadAt: at(16, 9),
                                       lastError: "LinkedIn demande une connexion : réessai au prochain tour", createdAt: at(1, 9))
        #expect(CollectionStatus(page: row)?.isProblem == true)
        #expect(CollectionStatus(page: row)?.text(now: at(16, 10), calendar: calendar) == "LinkedIn demande une connexion : réessai au prochain tour")
        var fine = row
        fine.lastError = nil
        #expect(CollectionStatus(page: fine)?.text(now: at(16, 10), calendar: calendar) == "Lu à 09:00")
        fine.lastReadAt = nil
        #expect(CollectionStatus(page: fine) == nil)
    }
}
