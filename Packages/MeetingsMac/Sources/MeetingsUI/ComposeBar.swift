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
            let sending = mails.sending.map { (draftID: $0.draftID, leaving: $0.leaving) }
            let leaving = sending?.draftID == draftID
            // Programmed, it is locked until Paul calls the send off (wave B).
            let planned = mails.scheduled[draftID]
            HStack(spacing: Space.s) {
                Group {
                    send(draft, planned: planned)
                    IconButton("paperclip", help: "Joindre des fichiers (ou les glisser sur le mail)", action: attach)
                        .disabled(planned != nil)
                    Divider().frame(height: 18)
                    formatting
                        .disabled(planned != nil)
                }
                .disabled(leaving)
                Spacer(minLength: Space.m)
                // « Envoyé · Annuler » here, in the bar of the mail leaving (lot 6, 19/11): its « Annuler » stays in reach
                // while the rest of the bar waits, and the draft is right there, nothing to say at the bottom of the page.
                ComposeStatus(draft: draft, sending: sending, planned: planned) { mails.cancelSend(quietly: true) }
                IconButton("trash", help: "Supprimer le brouillon") { confirmingDiscard = true }
                    .disabled(planned?.state == .leaving || leaving)
            }
            .confirmationDialog("Supprimer ce brouillon ?", isPresented: $confirmingDiscard) {
                Button("Supprimer", role: .destructive) { mails.discard(draftID) }
            } message: {
                Text("Il disparaît aussi des brouillons de Gmail.")
            }
        }
    }

    /// « Envoyer » and, next to it, the arrow of « Programmer l'envoi » (wave B): one prominent glass control. Glass
    /// stays in the floating bar, untinted: it takes the root's ink (design system v2, 19/11).
    private func send(_ draft: MailDraftRow, planned: ScheduledSend?) -> some View {
        let problem = mails.sendProblem(draft)
        let blocked = problem != nil || mails.sending != nil || planned != nil
        let delay = Preferences(defaults: .standard).mailUndoSeconds
        return GlassEffectContainer(spacing: 2) {
            HStack(spacing: 2) {
                Button(action: sendNow) { Label("Envoyer", systemImage: "paperplane.fill") }
                    .buttonStyle(.primary)
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

/// Where the draft is: sent and still called back, programmed, waiting for Paul's choice, refused, kept in Gmail or on
/// the Mac.
struct ComposeStatus: View {
    let draft: MailDraftRow
    /// The mail leaving, any: this draft's, or another's.
    let sending: (draftID: String, leaving: Bool)?
    let planned: ScheduledSend?
    /// « Annuler » while this draft's delay runs.
    var callBack: () -> Void = {}

    enum Kind: Equatable {
        /// « Envoyé · Annuler » while the delay runs, as Gmail's « Message envoyé · Annuler »; « Envoyé » once on its way.
        case sent(undoable: Bool)
        case planned(at: Date)
        case late
        case waitingChoice
        case failed(String)
        case keptInGmail
        case keptOnMac
    }

    /// The draft leaving says so first, a programmed one sent now included (lot 6, 19/11).
    static func kind(draft: MailDraftRow, sending: (draftID: String, leaving: Bool)?, planned: ScheduledSend?) -> Kind {
        if let sending, sending.draftID == draft.id { return .sent(undoable: !sending.leaving) }
        if let planned { return planned.state == .held ? .late : .planned(at: planned.sendAt) }
        if draft.conflict != nil { return .waitingChoice }
        if let error = draft.lastError { return .failed(error) }
        if draft.gmailDraftID != nil, !draft.needsPush { return .keptInGmail }
        return .keptOnMac
    }

    var body: some View {
        Group {
            switch Self.kind(draft: draft, sending: sending, planned: planned) {
            case .sent(let undoable):
                HStack(spacing: Space.xs) {
                    Text("Envoyé")
                    if undoable {
                        Text("·")
                        // The app's accent, ink, a fill under the pointer, as the « Annuler » of the bar at the bottom.
                        Button(action: callBack) {
                            Text("Annuler").fontWeight(.semibold).padding(.horizontal, Space.s).padding(.vertical, 2)
                        }
                        .buttonStyle(.hover(.capsule))
                        .foregroundStyle(Tint.accent)
                        .padding(.horizontal, -Space.s)
                        .keyboardShortcut("z", modifiers: .command)
                        .help("Il n'est pas encore parti : « Annuler » le garde en brouillon (⌘Z)")
                    }
                }
            case .planned(let at):
                Label("Programmé · \(MailText.scheduledShort(at))", systemImage: "clock")
            case .late:
                // Late: the late's red, as in « Programmés »; a failure is said by `ErrorLine` (design system v2, 19/11).
                Label("En retard", systemImage: "clock").foregroundStyle(Tint.late)
            case .waitingChoice:
                Text("En attente de ton choix")
            case .failed(let error):
                ErrorLine(error).help(error)
            case .keptInGmail:
                Text("Enregistré dans Gmail")
            case .keptOnMac:
                Text("Enregistré sur le Mac")
            }
        }
        .font(.meta)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .truncationMode(.tail)
    }
}
