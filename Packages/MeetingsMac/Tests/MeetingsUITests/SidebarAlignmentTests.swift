import AppKit
import Agenda
import Persistence
import SwiftUI
import Testing
@testable import MeetingsUI

/// Correctifs du 15/11 : la ligne Réglages, en bas de la barre latérale, s'aligne sur les lignes du dessus, avec ou
/// sans le groupe « Mails ».
@MainActor @Suite struct SidebarAlignmentTests {
    /// Where the rows' contents start, list by list, in the window.
    static func rowStarts(in view: NSView) -> [[CGFloat]] {
        var tables: [NSTableView] = []
        func walk(_ view: NSView) {
            if let table = view as? NSTableView { tables.append(table) }
            view.subviews.forEach(walk)
        }
        walk(view)
        return tables.sorted { $0.convert($0.bounds, to: nil).maxY > $1.convert($1.bounds, to: nil).maxY }.map { table in
            (0..<table.numberOfRows).compactMap { row in
                guard let cell = table.view(atColumn: 0, row: row, makeIfNecessary: false) else { return nil }
                return cell.convert(cell.bounds, to: nil).minX
            }
        }
    }

    /// The rows of the work start `SidebarFooter.outlineIndent` further right than Réglages' list once « Mails » is
    /// there (its disclosure arrow), level otherwise: the footer's row is moved by as much.
    @Test func reglagesLinesUpWithTheRowsAbove() async throws {
        let database = try AppDatabase.inMemory()
        let calendar = CalendarStore(database)
        try calendar.addAccount(email: "moi@exemple.fr", at: Date())
        try calendar.setGrantedScopes(email: "moi@exemple.fr",
                                      scopes: "openid https://www.googleapis.com/auth/calendar.events https://www.googleapis.com/auth/gmail.modify")
        let root = FileManager.default.temporaryDirectory.appending(path: "alignement-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let agenda = AgendaLibrary(database: database)
        let mails = MailLibrary(agenda: agenda, root: root, defaults: try #require(UserDefaults(suiteName: "alignement-\(UUID().uuidString)")), flavor: .dev)
        for _ in 0..<100 where mails.accounts.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        let library = MeetingLibrary(store: MeetingStore(database))
        for withMails in [false, true] {
            let host = NSHostingView(rootView: MainWindowView(library: library, agenda: agenda, mails: withMails ? mails : nil, router: WindowRouter(),
                                                             paths: AppPaths(root: root, logs: root)) { EmptyView() })
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1_100, height: 800), styleMask: [.titled, .resizable],
                                  backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            window.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(400))
            window.layoutIfNeeded()
            let starts = Self.rowStarts(in: host)
            print("MESURE mails=\(withMails) : \(starts)")
            let work = try #require(starts.first?.first), footer = try #require(starts.last?.first)
            #expect(starts.count == 2)
            #expect(work - footer == (withMails ? SidebarFooter.outlineIndent : 0))
        }
    }
}
