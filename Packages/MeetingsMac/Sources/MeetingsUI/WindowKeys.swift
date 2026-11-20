import AppKit
import ProjectsUI

/// The window's keys (lot 4, 19/11): hub is an agent, without a menu bar of its own, so its key monitor reads them
/// (`NavigationInput`) and they act here. The same as in « Coup d'œil »: ⌘1 to ⌘7 for the sidebar's rows, ⌘, for
/// Réglages, ⌘N for the page's « + »; and ⌘F for the page's search, the back and forth of the history.
@MainActor
public struct WindowKeys {
    let router: WindowRouter
    let mails: MailLibrary?
    let projects: ProjectLibrary?
    /// The sidebar's rows, in its order (`SidebarItem.numbered`): ⌘1 is the first.
    let sections: [SidebarItem]

    public init(router: WindowRouter, mails: MailLibrary?, projects: ProjectLibrary?, sections: [SidebarItem]) {
        self.router = router
        self.mails = mails
        self.projects = projects
        self.sections = sections
    }

    /// Does what the key asks; false when it has nothing to do here, and the key goes on its way.
    @discardableResult
    public func run(_ command: NavigationInput.Command, in window: NSWindow?) -> Bool {
        switch command {
        case .back:
            router.goBack()
            return true
        case .forward:
            router.goForward()
            return true
        case .section(let number):
            guard sections.indices.contains(number - 1) else { return false }
            router.show(sections[number - 1], mails: mails)
            return true
        case .settings:
            router.openSettings(nil)
            return true
        case .new:
            return new()
        case .search:
            return window.map(Self.focusSearch(in:)) ?? false
        }
    }

    /// The « + » of the page: a new event, project or item. Where the page has none, a new mail, as ⌘N does in « Coup
    /// d'œil ».
    private func new() -> Bool {
        switch router.section {
        case .calendar:
            router.newEvent()
        case .projects:
            guard let projects else { return false }
            projects.newRequest = UUID()
        case .inspiration:
            // From an item open, its page's grid, where the « + » is.
            if router.inspirationItem != nil { router.openInspiration(router.inspirationPage) }
            router.addRequest = UUID()
        case .home, .meetings, .mails, .contacts, .settings:
            guard let mails, !mails.accounts.isEmpty else { return false }
            mails.writeNewMail(router: router)
        }
        return true
    }

    /// The caret in the page's search field, in the window's toolbar; false on a page without one.
    static func focusSearch(in window: NSWindow) -> Bool {
        guard let field = window.toolbar?.items.lazy.compactMap({ $0 as? NSSearchToolbarItem }).first else { return false }
        field.beginSearchInteraction()
        return true
    }
}

extension WindowRouter {
    /// A section, from its row in the sidebar or its key (lot 4, 19/11): Mails from the top of its inbox, Inspiration on
    /// its page's grid, Réglages on its families; the others as they were left.
    func show(_ item: SidebarItem, mails: MailLibrary?) {
        switch item {
        case .mails:
            if let mails { mails.show(.inbox, router: self) } else { section = .mails }
        case .inspiration:
            openInspiration(inspirationPage)
        case .settings:
            openSettings(nil)
        case .home, .projects, .meetings, .calendar, .contacts:
            section = item
        }
    }
}
