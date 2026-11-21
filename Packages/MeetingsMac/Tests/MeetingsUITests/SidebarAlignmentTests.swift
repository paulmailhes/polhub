import AppKit
import Agenda
import HubDesign
import Persistence
import SwiftUI
import Testing
@testable import MeetingsUI

/// 21/11 (Paul : « Boîte de réception, Brouillons… encore en orange quand je rentre dans Mail… il faut l'enlever ») : une
/// liste native allumait la rangée choisie à la couleur d'accent du Mac dès qu'elle avait le focus. La barre latérale
/// dessine ses rangées elle-même : aucune table du système n'y reste, avec ou sans le groupe « Mails ».
@MainActor @Suite struct SidebarAlignmentTests {
    /// The system's tables in the window, by where they start.
    static func tables(in view: NSView) -> [CGRect] {
        var frames: [CGRect] = []
        func walk(_ view: NSView) {
            if let table = view as? NSTableView { frames.append(table.convert(table.bounds, to: nil)) }
            view.subviews.forEach(walk)
        }
        walk(view)
        return frames
    }

    @Test func theSidebarHasNoSystemListToLightInTheAccentColor() async throws {
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
            // The sidebar is the window's first 224 points.
            let inSidebar = Self.tables(in: host).filter { $0.minX < 200 }
            #expect(inSidebar.isEmpty, "mails=\(withMails) : \(inSidebar)")
        }
    }

    /// A folder under « Mails » starts its glyph under « Mails »' name, as the list did: the hierarchy shows.
    @Test func aFolderSitsUnderTheNameOfMails() {
        let mailsName = SidebarFooterMetrics.rowPadding + ToolBadge.Size.sidebar.rawValue + SidebarFooterMetrics.iconGap
        let folderGlyph = SidebarFooterMetrics.rowPadding + SidebarFooterMetrics.folderIndent
        #expect(abs(folderGlyph - mailsName) <= 4)
    }
}
