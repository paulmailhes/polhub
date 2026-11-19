import Domain
import Foundation
import Persistence
import Testing
@testable import ProjectsUI

/// Revue finale du module Projets : ce que la première version faisait mal.
@MainActor @Suite struct ProjectReviewTests {
    let now = Date(timeIntervalSince1970: 1_794_562_920)

    func ids(_ count: Int) -> [UUID] { (0..<count).map { _ in UUID() } }

    // Mineur 7 : descendre une carte d'une place se fait en la déposant sur la suivante.
    @Test func droppingOnTheNextCardMovesItDownOnePlace() {
        let column = ids(4)
        #expect(ProjectViews.dropBefore(dragged: column[0], onto: column[1], column: column) == column[2])
        #expect(ProjectViews.dropBefore(dragged: column[0], onto: column[3], column: column) == nil)
        #expect(ProjectViews.dropBefore(dragged: column[3], onto: column[1], column: column) == column[1])
        let other = UUID()
        #expect(ProjectViews.dropBefore(dragged: other, onto: column[1], column: column) == column[1])
    }

    // Mineur 9 : la date de réunion la plus récente, qu'elle vienne du coffre ou de l'app.
    @Test func theLastMeetingIsTheMostRecentOfBoth() {
        var project = ProjectRow(name: "A", status: .priorite1, createdAt: now)
        project.lastMeetingImported = now
        #expect(ProjectViews.lastMeeting(project, appMeeting: now.addingTimeInterval(-86_400)) == now)
        #expect(ProjectViews.lastMeeting(project, appMeeting: now.addingTimeInterval(60)) == now.addingTimeInterval(60))
    }

    func library() throws -> (ProjectLibrary, ProjectStore, MeetingStore) {
        let database = try AppDatabase.inMemory()
        let store = ProjectStore(database), meetings = MeetingStore(database)
        return (ProjectLibrary(store: store, meetings: meetings), store, meetings)
    }

    func eventually(_ condition: () throws -> Bool) async rethrows -> Bool {
        for _ in 0..<100 {
            if try condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }

    // Mineur 8, puis Paul le 19/11 : changer le statut depuis la page met la carte en haut de sa nouvelle colonne.
    @Test func aStatusChangedOnThePageGoesOnTopOfItsColumn() async throws {
        let (projects, store, _) = try library()
        _ = try store.addProject(name: "Déjà là", status: .priorite1, at: now)
        var moving = try store.addProject(name: "Arrive", status: .enPause, at: now)
        moving.status = .priorite1
        moving.todo = "Nouvelle chose"
        projects.save(moving)
        let column = try store.projects().filter { $0.status == .priorite1 }.sorted { $0.kanbanOrder < $1.kanbanOrder }
        #expect(column.map(\.name) == ["Arrive", "Déjà là"])
        #expect(column.first?.todo == "Nouvelle chose" && column.first?.lastEditedAt != nil)
    }

    // Mineur 9 : ranger une réunion met à jour « À surveiller » sans attendre.
    @Test func filingAMeetingRefreshesTheLastMeetings() async throws {
        let (projects, store, meetings) = try library()
        let project = try store.addProject(name: "Atelier client", status: .priorite2, at: now)
        let meeting = MeetingRow(createdAt: now, status: .ended, source: .dia, candidateKey: "t/a", title: "Cadrage", startedAt: now)
        try meetings.save(meeting)
        #expect(await eventually { projects.loaded })
        try store.setProject(meetingID: meeting.id, projectID: project.id)
        #expect(await eventually { projects.lastAppMeetings[project.id] != nil })
    }
}

// Mineur 12 : les notes comme dans le mode lecture d'Obsidian.
@Suite struct MarkdownReviewTests {
    @Test func aSingleLineBreakStaysALineBreak() {
        #expect(MarkdownBlocks.parse("Ligne un\nLigne deux") == [.paragraph("Ligne un\nLigne deux")])
    }

    @Test func numberedListsAndCodeKeepTheirShape() {
        #expect(MarkdownBlocks.parse("1. un\n2. deux\n```\nlet a = 1\n```") == [
            .numbered(number: 1, depth: 0, text: "un"), .numbered(number: 2, depth: 0, text: "deux"), .code("let a = 1"),
        ])
    }

    @Test func aTabIsOneLevel() {
        #expect(MarkdownBlocks.parse("- un\n\t- deux") == [.bullet(depth: 0, text: "un"), .bullet(depth: 1, text: "deux")])
    }
}
