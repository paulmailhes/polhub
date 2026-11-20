import AppKit
import Foundation
import Notifications
import Persistence
import HubDesign
import SwiftUI
import Testing
@testable import MeetingsUI

/// hub's notification center (15/11), with made-up notifications: `HUB_LIVE=1 HUB_SNAPSHOTS=<dossier> swift test
/// --filter NotificationCenterScreenTests`. Live, the bell's real popover is captured too, glass included.
@MainActor @Suite(.enabled(if: ProcessInfo.processInfo.environment["HUB_SNAPSHOTS"] != nil))
struct NotificationCenterScreenTests {
    let now = Date()

    /// Today, yesterday and earlier: a meeting not recorded, a summary, a burst of mails (one thread of three), a
    /// reminder, new events, a programmed mail late. The last hour is new.
    func sample() -> NotificationInbox {
        let inbox = NotificationInbox(file: nil)
        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now))!
        func record(_ notice: PlannedNotice, _ date: Date) { inbox.record(notice, at: date) }
        func mail(_ thread: String, _ sender: String, _ subject: String) -> PlannedNotice {
            PlannedNotice(id: thread, fireDate: now, title: sender, body: subject, eventID: nil, meetCode: nil, account: nil,
                          threadKey: "moi@exemple.fr|\(thread)", kind: .mail)
        }
        let event = "moi@exemple.fr|hebdo"
        record(PlannedNotice(id: "n1", fireDate: now, title: "Nouveaux rendez-vous", body: "4 rendez-vous sont arrivés dans tes agendas.",
                             eventID: nil, meetCode: nil, account: nil, kind: .newEvent), calendar.date(byAdding: .day, value: -3, to: now)!)
        record(NotificationPlan.summaryNotice(meetingID: UUID(), title: "Atelier contenus — Studio Sud", now: now),
               yesterday.addingTimeInterval(11 * 3_600 + 5 * 60))
        record(PlannedNotice(id: "p1", fireDate: now, title: "Mail programmé parti en retard",
                             body: "« Relance du devis » est parti à 9 h 12, le Mac était en veille à 9 h.", eventID: nil, meetCode: nil,
                             account: nil, threadKey: "moi@exemple.fr|devis", kind: .mail), yesterday.addingTimeInterval(17 * 3_600 + 40 * 60))
        record(NotificationPlan.newEventNotice(.init(account: "moi@exemple.fr", eventID: "revue", title: "Revue de maquette",
                                                     startAt: calendar.date(byAdding: .day, value: 4, to: now)!, endAt: now, updatedAt: now), now: now),
               now.addingTimeInterval(-3 * 3_600))
        record(PlannedNotice(id: "r1", fireDate: now, title: "Point hebdo — Atelier Nord", body: "Dans 10 min · Google Meet", eventID: event,
                             meetCode: "abc-defg-hij", account: "moi@exemple.fr", kind: .reminder), now.addingTimeInterval(-2 * 3_600 - 9 * 60))
        record(PlannedNotice(id: "r2", fireDate: now, title: "Point hebdo — Atelier Nord", body: "Dans 1 min · Google Meet", eventID: event,
                             meetCode: "abc-defg-hij", account: "moi@exemple.fr", kind: .reminder), now.addingTimeInterval(-2 * 3_600))
        inbox.markAllSeen()
        record(mail("photo", "Jules Durand", "Devis pour l'atelier photo : je t'envoie la version signée dans la journée."),
               now.addingTimeInterval(-31 * 60))
        record(mail("maquette", "Camille Martin", "Re: Maquette de l'accueil"), now.addingTimeInterval(-40 * 60))
        record(mail("maquette", "Léa Bernard", "Re: Maquette de l'accueil"), now.addingTimeInterval(-34 * 60))
        record(mail("maquette", "Camille Martin", "Re: Maquette de l'accueil — j'ai repris tes remarques sur le bandeau et les photos."),
               now.addingTimeInterval(-26 * 60))
        record(NotificationPlan.summaryNotice(meetingID: UUID(), title: "Cadrage de la refonte du site", now: now), now.addingTimeInterval(-12 * 60))
        record(PlannedNotice(id: "u1", fireDate: now, title: "Réunion non enregistrée",
                             body: "« Point hebdo — Atelier Nord » a commencé et hub ne l'enregistre pas. Rejoindre ?", eventID: event,
                             meetCode: "abc-defg-hij", account: "moi@exemple.fr", kind: .unrecorded), now.addingTimeInterval(-40))
        return inbox
    }

    @Test func thePanel() async throws {
        let output = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["HUB_SNAPSHOTS"]), isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for dark in [false, true] {
            let name = dark ? "sombre" : "clair"
            let inbox = sample()
            try await LiveWindow.capture(Panel(inbox: inbox, now: now), to: output.appending(path: "panneau-\(name).png"),
                                         size: NSSize(width: 440, height: 760), dark: dark)
            // The burst of mails, open.
            let open = sample()
            try await LiveWindow.capture(Panel(inbox: open, now: now, expanded: Set(open.notices.filter { $0.kind == .mail }.map(\.id))),
                                         to: output.appending(path: "panneau-pile-ouverte-\(name).png"), size: NSSize(width: 440, height: 760), dark: dark)
            try await LiveWindow.capture(Panel(inbox: NotificationInbox(file: nil), now: now), to: output.appending(path: "panneau-vide-\(name).png"),
                                         size: NSSize(width: 440, height: 300), dark: dark)
            // The bell and its count, closed.
            try await LiveWindow.capture(BellCorner(inbox: sample(), opensAlone: false), to: output.appending(path: "cloche-pastille-\(name).png"),
                                         size: NSSize(width: 360, height: 120), dark: dark)
            if ProcessInfo.processInfo.environment["HUB_LIVE"] != nil {
                try await PopoverCapture.capture(BellCorner(inbox: sample()), to: output.appending(path: "cloche-\(name).png"),
                                                 size: NSSize(width: 760, height: 820), dark: dark)
            }
        }
    }

    /// The panel as the popover holds it: in glass, over a window.
    struct Panel: View {
        let inbox: NotificationInbox
        let now: Date
        var expanded: Set<UUID> = []

        var body: some View {
            NotificationPanel(inbox: inbox, clock: now, expanded: expanded) { _ in }
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                .padding(Space.xl)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(Color(nsColor: .windowBackgroundColor))
        }
    }

    /// A sidebar's foot, with « Réglages » and the bell, whose popover opens on its own.
    struct BellCorner: View {
        let inbox: NotificationInbox
        var opensAlone = true

        var body: some View {
            HStack(spacing: 0) {
                VStack(alignment: .leading) {
                    Spacer()
                    HStack {
                        Label("Réglages", systemImage: "gearshape.fill").font(.rowTitle)
                        Spacer()
                        NotificationBell(inbox: inbox, arrowEdge: .top, opensAlone: opensAlone) { _ in }
                    }
                    .padding(.horizontal, Space.l)
                    .padding(.bottom, Space.l)
                }
                .frame(width: 252)
                .background(Surface.fill)
                Divider()
                Color(nsColor: .textBackgroundColor)
            }
        }
    }
}

/// A window on screen, captured with what floats over it (a popover is a window of its own).
@MainActor
enum PopoverCapture {
    static func capture(_ view: some View, to file: URL, size: NSSize, dark: Bool) async throws {
        _ = NSApplication.shared
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.setContentSize(size)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        defer { window.close() }
        // Under every window, never over Paul's work (19/11): the window's own image is taken, not the screen.
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) - 1)
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1_440, height: 900)
        window.setFrameTopLeftPoint(NSPoint(x: max(screen.minX + 40, screen.maxX - size.width - 40), y: screen.maxY - 20))
        window.orderBack(nil)
        try await Task.sleep(for: .milliseconds(2_200))
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-l", "\(window.windowNumber)", "-o", "-x", file.path]
        try process.run()
        process.waitUntilExit()
    }
}
