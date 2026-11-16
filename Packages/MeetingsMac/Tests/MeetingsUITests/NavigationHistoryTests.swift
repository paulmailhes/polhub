import AppKit
import Foundation
import Persistence
import Testing
@testable import MeetingsUI

/// « Précédent » and « Suivant » across the whole window (Paul, 16/11: « je fais retour sur les pages internet, sur
/// n'importe quoi… avec mes raccourcis de base »): the mouse's side buttons, ⌘[ ⌘], the trackpad's swipe.
@MainActor @Suite struct NavigationHistoryTests {
    /// Each place visited is a step back; forward undoes a step back; a new place drops what was ahead.
    @Test func backAndForwardRetraceTheWay() {
        let router = WindowRouter()
        router.section = .home
        router.settle()
        // The window opens on Accueil: nothing behind it.
        router.clearHistory()
        #expect(!router.canGoBack)
        let meeting = UUID()
        router.open(meetingID: meeting, at: nil)
        router.settle()
        router.openInspiration(.branding)
        router.settle()
        #expect(router.canGoBack && !router.canGoForward)
        router.goBack()
        #expect(router.section == .meetings && router.selection == meeting)
        router.goBack()
        #expect(router.section == .home)
        #expect(!router.canGoBack)
        router.goForward()
        #expect(router.section == .meetings && router.selection == meeting)
        router.openMail(nil)
        router.settle()
        #expect(!router.canGoForward)
        router.goBack()
        #expect(router.section == .meetings)
    }

    /// One gesture that changes several things (a page of Inspiration and its item) is one step; going back and
    /// forward is never a step itself.
    @Test func oneGestureIsOneStep() {
        let router = WindowRouter()
        router.section = .home
        router.settle()
        let item = UUID()
        router.openInspiration(.mockup, item: item)
        router.openInspiration(.mockup, item: nil)
        router.openInspiration(.mockup, item: item)
        router.settle()
        router.goBack()
        router.settle()
        #expect(router.section == .home && router.canGoForward)
        router.goForward()
        router.settle()
        #expect(router.section == .inspiration && router.inspirationPage == .mockup && router.inspirationItem == item)
        #expect(!router.canGoForward)
    }

    /// A list that chooses its first row by itself (the meetings, the contacts) refines the place: no step, and what
    /// was ahead stays.
    @Test func aSelectionMadeByItselfIsNoStep() {
        let router = WindowRouter()
        router.section = .home
        router.settle()
        router.section = .contacts
        router.settle()
        router.goBack()
        router.settle()
        router.goForward()
        router.settle()
        router.contactSelection = UUID()
        router.settle()
        router.goBack()
        #expect(router.section == .home)
    }

    /// The open project and the mails' folder are kept by their libraries: the history asks them back.
    @Test func theProjectAndTheFolderComeBack() {
        let router = WindowRouter()
        var project: UUID?
        var folder: MailFolder = .inbox
        router.restoreProject = { project = $0 }
        router.restoreMailFolder = { folder = $0 }
        router.section = .mails
        router.settle()
        router.mailFolderChanged(.sent)
        folder = .sent
        router.settle()
        let opened = UUID()
        router.section = .projects
        router.projectChanged(opened)
        project = opened
        router.settle()
        router.projectChanged(nil)
        project = nil
        router.settle()
        router.goBack()
        #expect(project == opened)
        router.goBack()
        #expect(router.section == .mails && folder == .sent)
        router.goBack()
        #expect(folder == .inbox)
    }

    /// What goes back and what goes forward: the mouse's buttons 4 and 5, ⌘[ and ⌘] (where they are on the
    /// keyboard, whatever its layout), ⌘← and ⌘→ outside a text, the trackpad's swipe.
    @Test func theGesturesAreRead() {
        typealias Input = NavigationInput
        #expect(Input.direction(.mouse(button: 3)) == .back)
        #expect(Input.direction(.mouse(button: 4)) == .forward)
        #expect(Input.direction(.mouse(button: 2)) == nil)
        #expect(Input.direction(.key(code: 33, modifiers: .command, editingText: true)) == .back)
        #expect(Input.direction(.key(code: 30, modifiers: .command, editingText: false)) == .forward)
        #expect(Input.direction(.key(code: 33, modifiers: [.command, .option], editingText: false)) == nil)
        #expect(Input.direction(.key(code: 123, modifiers: .command, editingText: false)) == .back)
        #expect(Input.direction(.key(code: 124, modifiers: .command, editingText: false)) == .forward)
        #expect(Input.direction(.key(code: 123, modifiers: .command, editingText: true)) == nil)
        #expect(Input.direction(.key(code: 33, modifiers: [], editingText: false)) == nil)
        #expect(Input.direction(.swipe(deltaX: 1)) == .back)
        #expect(Input.direction(.swipe(deltaX: -1)) == .forward)
        #expect(Input.direction(.swipe(deltaX: 0)) == nil)
    }
}
