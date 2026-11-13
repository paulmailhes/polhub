import AppKit
import Domain
import Foundation
import Persistence
import SwiftUI
import Testing
@testable import MeetingsUI
import ProjectsUI

/// Draws the window off screen, at a few widths, into PNG files to look at. Not part of `make check`:
/// `POLHUB_SNAPSHOTS=<dossier> swift test --filter WindowSnapshotTests`.
@MainActor @Suite(.enabled(if: ProcessInfo.processInfo.environment["POLHUB_SNAPSHOTS"] != nil))
struct WindowSnapshotTests {
    @Test func theMeetingsSectionAtSeveralWidths() async throws {
        let output = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["POLHUB_SNAPSHOTS"]), isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let root = FileManager.default.temporaryDirectory.appending(path: "fenêtre \(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = AppPaths(root: root, logs: root.appending(path: "logs"))
        let database = try AppDatabase.inMemory()
        let store = MeetingStore(database)
        let start = Date().addingTimeInterval(-3_600)
        let row = MeetingRow(createdAt: start, status: .ended, source: .dia, candidateKey: "t/a",
                             title: "RDV de Cadrage : un client avec un titre assez long pour la liste", startedAt: start,
                             endedAt: start.addingTimeInterval(2_860), transcribedAt: start.addingTimeInterval(3_100))
        try store.save(row)
        try TranscriptStore(database).replaceUtterances(meetingID: row.id, (0..<12).map { index in
            UtteranceRow(meetingID: row.id, speaker: index % 2 == 0 ? .autres : .moi, startMs: index * 20_000, endMs: index * 20_000 + 15_000,
                         text: String(repeating: "Une phrase de la réunion qui continue assez longtemps. ", count: index % 3 + 1), doubtful: index == 5)
        })
        let library = MeetingLibrary(store: store)
        let router = WindowRouter()
        router.selection = row.id
        try await Task.sleep(for: .milliseconds(300))

        func measure(_ name: String, _ view: some View) {
            let host = NSHostingView(rootView: view)
            print("mesure \(name) : \(Int(host.fittingSize.width)) de large au moins")
        }
        measure("liste", MeetingListView(library: library, selection: .constant(row.id)))
        measure("fiche", MeetingDetailView(row: row, store: store, paths: paths, transcripts: library.transcripts, queue: nil,
                                           job: nil, meetingActive: false, router: router))
        measure("en-tête de transcription", TranscriptHeader(status: .done(doubtful: true), meetingID: row.id, queue: nil, canRetranscribe: true))
        measure("répliques", DialogueRows(lines: try TranscriptStore(database).utterances(meetingID: row.id), current: nil, seek: { _ in }))
        measure("ligne de liste", MeetingRowView(row: row, now: Date(), badge: "Transcription 50 %"))

        for width in [860.0, 1_000, 1_280] {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 700), styleMask: [.titled, .resizable, .closable],
                                  backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: MainWindowView(library: library, router: router, paths: paths) { EmptyView() })
            window.setContentSize(NSSize(width: width, height: 700))
            window.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(500))
            window.layoutIfNeeded()
            let view = try #require(window.contentView)
            let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: output.appending(path: "fenetre-\(Int(width)).png"))
            print("fenêtre \(Int(width)) : contenu \(Int(view.fittingSize.width)) × \(Int(view.fittingSize.height)), fenêtre \(Int(window.frame.width))")
            window.close()
        }
    }

    @Test func theProjectsBoard() async throws {
        let output = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["POLHUB_SNAPSHOTS"]), isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let root = FileManager.default.temporaryDirectory.appending(path: "kanban \(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let database = try AppDatabase.inMemory()
        let store = ProjectStore(database)
        let samples: [(String, ProjectStatus, String?, Int?, String?)] = [
            ("Site vitrine", .idee, "Freelance", nil, nil), ("Refonte site", .priorite1, "Ourama", -2, "Envoyer la maquette de l'accueil"),
            ("Identité", .priorite1, "Elias", 0, "Valider la typographie"), ("Studio photo", .priorite2, "Ourama", 6, "Relancer pour les contenus"),
            ("Landing", .priorite3, "Ourama", 12, "Préparer le cadrage"), ("Agence", .enAttente, "Ourama", nil, nil),
        ]
        for (name, status, client, due, todo) in samples {
            var project = try store.addProject(name: name, status: status, at: Date())
            project.client = client
            project.dueDate = due.map { Date().addingTimeInterval(Double($0) * 86_400) }
            project.todo = todo
            project.color = name == "Identité" ? "purple" : nil
            try store.save(project, at: Date())
        }
        let library = MeetingLibrary(store: MeetingStore(database))
        let projects = ProjectLibrary(store: store, meetings: MeetingStore(database), defaults: UserDefaults(suiteName: "kanban-\(UUID().uuidString)")!)
        let router = WindowRouter()
        router.section = .projects
        try await Task.sleep(for: .milliseconds(300))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1_400, height: 640), styleMask: [.titled, .resizable],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = NSHostingView(rootView: MainWindowView(library: library, projects: projects, router: router,
                                                                   paths: AppPaths(root: root, logs: root)) { EmptyView() })
        window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(500))
        window.layoutIfNeeded()
        let view = try #require(window.contentView)
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try #require(bitmap.representation(using: .png, properties: [:])).write(to: output.appending(path: "kanban.png"))
    }

    @Test func theProjectPage() async throws {
        let output = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["POLHUB_SNAPSHOTS"]), isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let database = try AppDatabase.inMemory()
        let store = ProjectStore(database)
        var project = try store.addProject(name: "Refonte site", status: .priorite1, at: Date())
        project.client = "Ourama"
        project.todo = "Envoyer la maquette de l'accueil"
        project.dueDate = Date().addingTimeInterval(3 * 86_400)
        project.contacts = ["Camille Exemple"]
        project.notes = "> [!info]- Contexte\n> Studio de création.\n\n## Rendez-vous\n- **6 nov.** — Premier échange, voir la [page](https://exemple.fr).\n  - budget à confirmer\n- [ ] Lire la fiche"
        project.lastMeetingImported = Date().addingTimeInterval(-8 * 86_400)
        try store.save(project, at: Date())
        try store.saveAction(ActionRow(projectID: project.id, text: "Lire la fiche du client", addedOn: Date(), position: 0, createdAt: Date()))
        try store.saveAction(ActionRow(projectID: project.id, text: "Envoyer le devis", done: true, addedOn: Date(), position: 1, createdAt: Date()))
        try store.addJournal(ProjectJournalRow(projectID: project.id, date: Date(), title: "Maquette envoyée", body: "- Deux pages.\n- Retour attendu lundi.", createdAt: Date()))
        let projects = ProjectLibrary(store: store, meetings: MeetingStore(database), defaults: UserDefaults(suiteName: "page-\(UUID().uuidString)")!)
        try await Task.sleep(for: .milliseconds(300))
        projects.selected = project.id
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 1_100), styleMask: [.titled, .resizable],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = NSHostingView(rootView: ProjectsView(library: projects))
        window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(500))
        window.layoutIfNeeded()
        let view = try #require(window.contentView)
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try #require(bitmap.representation(using: .png, properties: [:])).write(to: output.appending(path: "projet.png"))
    }
}
