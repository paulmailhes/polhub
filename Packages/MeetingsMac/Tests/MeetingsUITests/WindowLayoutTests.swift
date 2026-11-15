import AppKit
import Domain
import Foundation
import Persistence
import SwiftUI
import Testing
@testable import MeetingsUI
import ProjectsUI

/// 13/11 : « le truc réunion est trop large par rapport à la fenêtre, ça décale la barre latérale ».
@MainActor @Suite struct WindowLayoutTests {
    @Test func theWindowFitsItsMinimumWidthWithALongTranscript() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "largeur \(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let database = try AppDatabase.inMemory()
        let store = MeetingStore(database)
        let start = Date().addingTimeInterval(-3_600)
        let row = MeetingRow(createdAt: start, status: .ended, source: .dia, candidateKey: "t/a",
                             title: "RDV de Cadrage : un client avec un titre assez long pour la liste et la fiche", startedAt: start,
                             endedAt: start.addingTimeInterval(2_860), transcribedAt: start.addingTimeInterval(3_100))
        try store.save(row)
        try TranscriptStore(database).replaceUtterances(meetingID: row.id, (0..<6).map { index in
            UtteranceRow(meetingID: row.id, speaker: .autres, startMs: index * 20_000, endMs: index * 20_000 + 15_000,
                         text: String(repeating: "Une phrase de la réunion qui continue assez longtemps. ", count: 4), doubtful: true)
        })
        let library = MeetingLibrary(store: store)
        let router = WindowRouter()
        router.selection = row.id
        try await Task.sleep(for: .milliseconds(200))
        let width = MainWindowView<EmptyView>.minimumWidth
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 700), styleMask: [.titled, .resizable],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: MainWindowView(library: library, router: router, paths: AppPaths(root: root, logs: root)) { EmptyView() })
        window.contentView = host
        window.setContentSize(NSSize(width: width, height: 700))
        window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(300))
        window.layoutIfNeeded()
        #expect(host.fittingSize.width <= width + 1)
    }

    @Test func theProjectsSectionFitsTheMinimumWidth() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "largeur \(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let database = try AppDatabase.inMemory()
        let store = MeetingStore(database)
        let projectStore = ProjectStore(database)
        for (index, status) in ProjectStatus.allCases.enumerated() {
            for copy in 0..<2 {
                var project = try projectStore.addProject(name: "Projet au nom assez long \(index)-\(copy)", status: status, at: Date())
                project.todo = "Une chose à faire qui prend de la place sur la carte du kanban"
                project.client = "Atelier Nord"
                try projectStore.save(project, at: Date())
            }
        }
        let library = MeetingLibrary(store: store)
        let projects = ProjectLibrary(store: projectStore, meetings: store, defaults: UserDefaults(suiteName: "largeur-\(UUID().uuidString)")!)
        let router = WindowRouter()
        router.section = .projects
        try await Task.sleep(for: .milliseconds(200))
        let width = MainWindowView<EmptyView>.minimumWidth
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 700), styleMask: [.titled, .resizable],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: MainWindowView(library: library, projects: projects, router: router,
                                                         paths: AppPaths(root: root, logs: root)) { EmptyView() })
        window.contentView = host
        window.setContentSize(NSSize(width: width, height: 700))
        window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(300))
        window.layoutIfNeeded()
        #expect(projects.projects.count == ProjectStatus.allCases.count * 2)
        #expect(host.fittingSize.width <= width + 1)
    }
}
