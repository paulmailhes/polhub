import AppKit
import Combine
import Mail
import MailFormat
import Persistence
import PolhubDesign
import SwiftUI

/// A draft being written, shared by its text and its bar: the editor, the addresses typed and not yet chips,
/// whether the keyboard is in its fields.
@MainActor
final class ComposeSession: ObservableObject {
    let editor = RichTextController()
    @Published var fieldsFocused = false { didSet { if fieldsFocused, !oldValue { onFocus?() } } }
    @Published var pendingTo = ""
    @Published var pendingCc = ""
    @Published var pendingBcc = ""
    /// Its text or its fields just took the keyboard.
    var onFocus: (() -> Void)?
    private var watch: AnyCancellable?

    init() {
        watch = editor.$isFocused.removeDuplicates().sink { [weak self] on in
            if on { self?.onFocus?() }
        }
    }
}

/// The sessions of the drafts on one page, kept while it is open, and the one that last had the keyboard.
@MainActor
final class ComposeSessions: ObservableObject {
    private var sessions: [String: ComposeSession] = [:]
    @Published private(set) var active: String?

    func callAsFunction(_ draftID: String) -> ComposeSession {
        if let session = sessions[draftID] { return session }
        let session = ComposeSession()
        session.onFocus = { [weak self] in
            if self?.active != draftID { self?.active = draftID }
        }
        sessions[draftID] = session
        return session
    }
}

/// Which reply of a thread has the bar fixed at the bottom (review of 17/11): the one Paul writes, never another,
/// so « Envoyer » sends the mail he sees.
enum ComposePinning {
    /// Oldest first, the one just begun at the bottom: the replies keep their place as Paul types.
    static func ordered(_ drafts: [MailDraftRow]) -> [MailDraftRow] {
        drafts.sorted { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }
    }

    /// The reply that had the keyboard last; before any, the one just begun.
    static func pinned(_ ordered: [MailDraftRow], active: String?) -> MailDraftRow? {
        ordered.first { $0.id == active } ?? ordered.last
    }
}

/// The bar of a draft, fixed at the bottom of the page and in reach wherever the text is scrolled (Paul, 17/11:
/// « une barre fixe »): « Envoyer » and its schedule, « Joindre », the formatting, where the draft is kept, the trash.
struct ComposeBar: View {
    let draftID: String
    @ObservedObject var mails: MailLibrary
    @ObservedObject var session: ComposeSession
    @ObservedObject private var editor: RichTextController
    /// « Choisir une date et une heure… » is open (wave B).
    @State private var choosingDate = false
    @State private var confirmingDiscard = false

    init(draftID: String, mails: MailLibrary, session: ComposeSession) {
        self.draftID = draftID
        self.mails = mails
        self.session = session
        _editor = ObservedObject(wrappedValue: session.editor)
    }

    /// ⌘↩ belongs to the draft being written, never to another on the same screen.
    private var isActive: Bool { session.fieldsFocused || editor.isFocused }

    var body: some View {
        if let draft = mails.drafts.first(where: { $0.id == draftID }) {
            let leaving = mails.sending?.draftID == draftID
            // Programmed, it is locked until Paul calls the send off (wave B).
            let planned = mails.scheduled[draftID]
            HStack(spacing: Space.s) {
                send(draft, planned: planned)
                IconButton("paperclip", help: "Joindre des fichiers (ou les glisser sur le mail)", action: attach)
                    .disabled(planned != nil)
                Divider().frame(height: 18)
                formatting
                    .disabled(planned != nil)
                Spacer(minLength: Space.m)
                ComposeStatus(draft: draft, leaving: leaving, planned: planned)
                IconButton("trash", help: "Supprimer le brouillon") { confirmingDiscard = true }
                    .disabled(planned?.state == .leaving)
            }
            .disabled(leaving)
            .confirmationDialog("Supprimer ce brouillon ?", isPresented: $confirmingDiscard) {
                Button("Supprimer", role: .destructive) { mails.discard(draftID) }
            } message: {
                Text("Il disparaît aussi des brouillons de Gmail.")
            }
        }
    }

    /// « Envoyer » and, next to it, the arrow of « Programmer l'envoi » (wave B): one prominent glass control.
    private func send(_ draft: MailDraftRow, planned: ScheduledSend?) -> some View {
        let problem = mails.sendProblem(draft)
        let blocked = problem != nil || mails.sending != nil || planned != nil
        let delay = Preferences(defaults: .standard).mailUndoSeconds
        return GlassEffectContainer(spacing: 2) {
            HStack(spacing: 2) {
                Button(action: sendNow) { Label("Envoyer", systemImage: "paperplane.fill") }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(isActive && planned == nil ? KeyboardShortcut(.return, modifiers: .command) : nil)
                    .disabled(blocked)
                    .help(problem ?? (planned != nil ? "Programmé : annule l'envoi programmé pour le modifier ou l'envoyer"
                                                     : "Envoyer (⌘↩) : tu as \(delay) secondes pour l'annuler"))
                ScheduleMenu(pick: { scheduleNow(at: $0) }) { choosingDate = true }
                    .disabled(blocked)
                    .popover(isPresented: $choosingDate, arrowEdge: .top) {
                        SchedulePicker { date in
                            choosingDate = false
                            if let date { scheduleNow(at: date) }
                        }
                    }
            }
        }
        .controlSize(.large)
    }

    /// The commands Gmail has, with their shortcuts; they act on the text selected, or where the caret was.
    private var formatting: some View {
        HStack(spacing: 0) {
            IconButton("bold", help: "Gras (⌘B)", size: 13) { editor.bold() }
            IconButton("italic", help: "Italique (⌘I)", size: 13) { editor.italic() }
            IconButton("underline", help: "Souligné (⌘U)", size: 13) { editor.underline() }
            IconButton("list.bullet", help: "Liste à puces", size: 13) { editor.bulletList() }
            IconButton("list.number", help: "Liste numérotée", size: 13) { editor.numberedList() }
            IconButton("link", help: "Lien (⌘K)", size: 13) { editor.askingLink = true }
                .popover(isPresented: $editor.askingLink, arrowEdge: .top) {
                    LinkPrompt { address in
                        editor.askingLink = false
                        if let address { editor.link(address) }
                    }
                }
            IconButton("textformat", help: "Effacer la mise en forme", size: 13) { editor.removeFormat() }
        }
    }

    private func attach() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.prompt = "Joindre"
        if panel.runModal() == .OK { mails.attach(panel.urls, to: draftID) }
    }

    /// The addresses typed and not yet chips go with the mail; an incomplete one stops it.
    private func commitPending() -> Bool {
        let pending = [(RecipientField.parse(session.pendingTo), \MailDraftRow.to), (RecipientField.parse(session.pendingCc), \MailDraftRow.cc),
                       (RecipientField.parse(session.pendingBcc), \MailDraftRow.bcc)]
        if let bad = pending.flatMap(\.0).first(where: { !MIMEBuilder.isValid($0.email) }) {
            mails.message = "L'adresse « \(bad.email) » n'est pas complète : corrige-la avant d'envoyer."
            return false
        }
        if pending.contains(where: { !$0.0.isEmpty }) {
            mails.edit(draftID) { draft in
                for (addresses, path) in pending {
                    for address in addresses where !draft[keyPath: path].contains(where: { $0.email == address.email }) { draft[keyPath: path].append(address) }
                }
            }
            session.pendingTo = ""
            session.pendingCc = ""
            session.pendingBcc = ""
        }
        return true
    }

    private func sendNow() {
        guard commitPending() else { return }
        mails.send(draftID)
    }

    private func scheduleNow(at date: Date) {
        guard commitPending() else { return }
        mails.schedule(draftID, at: date)
    }
}

/// Where the draft is: programmed, leaving, waiting for Paul's choice, refused, kept in Gmail or on the Mac.
struct ComposeStatus: View {
    let draft: MailDraftRow
    let leaving: Bool
    let planned: ScheduledSend?

    var body: some View {
        Group {
            if let planned {
                Label(planned.state == .held ? "En retard" : "Programmé · \(MailText.scheduledShort(planned.sendAt))", systemImage: "clock")
                    .foregroundStyle(planned.state == .held ? Color.red : Color.secondary)
            } else if leaving {
                Text("Envoi en cours…")
            } else if draft.conflict != nil {
                Text("En attente de ton choix")
            } else if let error = draft.lastError {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).help(error)
            } else if draft.gmailDraftID != nil, !draft.needsPush {
                Text("Enregistré dans Gmail")
            } else {
                Text("Enregistré sur le Mac")
            }
        }
        .font(.meta)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .truncationMode(.tail)
    }
}
