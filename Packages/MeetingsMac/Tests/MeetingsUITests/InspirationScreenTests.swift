import AppKit
import Agenda
import Foundation
import Persistence
import HubDesign
import SwiftUI
import Testing
@testable import MeetingsUI

/// The pages of « Inspiration », to look at (16/11), with an invented world: images drawn by the tests, made-up
/// studios and sites. Not part of `make check`:
/// `HUB_LIVE=1 HUB_SNAPSHOTS=<dossier> swift test --filter InspirationScreenTests` (live: glass and toolbar).
@MainActor @Suite(.enabled(if: ProcessInfo.processInfo.environment["HUB_SNAPSHOTS"] != nil), .serialized)
struct InspirationScreenTests {
    static let size = NSSize(width: 1_320, height: 860)

    private func output() throws -> URL {
        let output = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["HUB_SNAPSHOTS"]), isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        return output
    }

    private func window(_ inspiration: InspirationLibrary, router: WindowRouter, paths: AppPaths) throws -> some View {
        let database = try AppDatabase.inMemory()
        let agenda = AgendaLibrary(database: database)
        let library = MeetingLibrary(store: MeetingStore(database))
        return MainWindowView(library: library, agenda: agenda, inspiration: inspiration, router: router, paths: paths) { EmptyView() }
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<300 where !condition() { try await Task.sleep(for: .milliseconds(10)) }
    }

    @Test func thePages() async throws {
        let output = try output()
        let world = try InspirationTestWorld(name: "captures")
        defer { world.clean() }
        try world.fill()
        let inspiration = world.library()
        try await waitUntil { inspiration.loaded.count == 3 && inspiration.sources.count == 3 }
        let router = WindowRouter()
        for dark in [false, true] {
            let suffix = dark ? "-sombre" : ""
            for kind in InspirationKind.allCases {
                router.openInspiration(kind)
                try await LiveWindow.capture(try window(inspiration, router: router, paths: world.paths),
                                             to: output.appending(path: "inspiration-\(kind.folderName)\(suffix).png"), size: Self.size, dark: dark,
                                             wait: .milliseconds(2_500))
            }
            // A filter chosen: one page, one style.
            inspiration.setFilter("Atelier Nord", family: "source", for: .branding)
            router.openInspiration(.branding)
            try await LiveWindow.capture(try window(inspiration, router: router, paths: world.paths),
                                         to: output.appending(path: "inspiration-branding-filtre\(suffix).png"), size: Self.size, dark: dark,
                                         wait: .milliseconds(2_500))
            inspiration.clearFilters(.branding)
            // A post open: its images side by side, its links, its categories.
            let post = try #require(inspiration.items(.branding).first { $0.title == "Fondation Exemple" })
            router.openInspiration(.branding, item: post.id)
            try await LiveWindow.capture(try window(inspiration, router: router, paths: world.paths),
                                         to: output.appending(path: "inspiration-fiche-branding\(suffix).png"), size: Self.size, dark: dark,
                                         wait: .milliseconds(2_500))
            let site = try #require(inspiration.items(.website).first)
            router.openInspiration(.website, item: site.id)
            try await LiveWindow.capture(try window(inspiration, router: router, paths: world.paths),
                                         to: output.appending(path: "inspiration-fiche-site\(suffix).png"), size: Self.size, dark: dark,
                                         wait: .milliseconds(2_500))
            let mockup = try #require(inspiration.items(.mockup).first)
            router.openInspiration(.mockup, item: mockup.id)
            try await LiveWindow.capture(try window(inspiration, router: router, paths: world.paths),
                                         to: output.appending(path: "inspiration-fiche-mockup\(suffix).png"), size: Self.size, dark: dark,
                                         wait: .milliseconds(2_500))
        }
    }

    @Test func theEmptyPageAndReglages() async throws {
        let output = try output()
        let world = try InspirationTestWorld(name: "captures-vide")
        defer { world.clean() }
        let empty = world.library()
        try await waitUntil { empty.loaded.count == 3 }
        let router = WindowRouter()
        for dark in [false, true] {
            router.openInspiration(.website)
            try await LiveWindow.capture(try window(empty, router: router, paths: world.paths),
                                         to: output.appending(path: "inspiration-vide\(dark ? "-sombre" : "").png"), size: Self.size, dark: dark,
                                         wait: .milliseconds(2_000))
        }

        let full = try InspirationTestWorld(name: "captures-reglages")
        defer { full.clean() }
        try full.fill()
        let lastRun = InspirationTestWorld.day(11, 16).addingTimeInterval(2 * 3_600)
        let services = InspirationServices(status: {
            [InspirationStatusLine(id: "awwwards", name: "Awwwards", lastRun: lastRun, added: 1),
             InspirationStatusLine(id: "https://www.linkedin.com/company/atelier-nord/", name: "Atelier Nord", lastRun: lastRun,
                                   problem: "LinkedIn demande une connexion : réessai au prochain tour")]
        })
        let inspiration = full.library(services: services)
        try await waitUntil { inspiration.loaded.count == 3 && inspiration.sources.count == 3 }
        for dark in [false, true] {
            router.openSettings(.inspiration)
            try await LiveWindow.capture(try window(inspiration, router: router, paths: full.paths),
                                         to: output.appending(path: "inspiration-reglages\(dark ? "-sombre" : "").png"),
                                         size: NSSize(width: 1_100, height: 1_000), dark: dark, wait: .milliseconds(2_000))
        }
        router.openSettings(nil)
        for dark in [false, true] {
            try await LiveWindow.capture(try window(inspiration, router: router, paths: full.paths),
                                         to: output.appending(path: "inspiration-reglages-familles\(dark ? "-sombre" : "").png"),
                                         size: NSSize(width: 1_100, height: 760), dark: dark, wait: .milliseconds(1_500))
        }
    }
}
