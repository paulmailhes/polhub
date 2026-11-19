import Agenda
import AppKit
import Mail
import MailFormat
import Persistence
import PolhubDesign
import SwiftUI
import UniformTypeIdentifiers

/// What a recipient's chip says of its address (lot 6, 19/11): a contact or someone Paul wrote to, plain; a stranger,
/// « ? »; an invalid address, the triangle. The two to check share the attention's color: their symbol tells them apart,
/// a color never says a meaning alone.
enum RecipientMark: Equatable {
    case known, stranger, invalid

    var symbol: String? {
        switch self {
        case .known: nil
        case .stranger: "questionmark.circle"
        case .invalid: "exclamationmark.triangle.fill"
        }
    }

    static func of(valid: Bool, known: Bool) -> RecipientMark {
        !valid ? .invalid : (known ? .known : .stranger)
    }
}

extension ComposeView {
    /// The banner over a draft an agent prepared (lot 6, 19/11): what to do, then the rule of the addresses by their
    /// mark — the chip's color alone never says it.
    static let agentNotice = (title: "Préparé par un agent : relis-le avant d'envoyer.",
                              detail: "Une adresse marquée d'un ? n'est ni un contact ni une personne à qui tu as écrit.")
}

/// « À », « Cc », « Cci »: the people as chips, a field to type more, the people that match below it (15/11:
/// ranked, ↑ ↓ to move, ↩ or ⇥ to take, Échap to close, as Gmail).
struct RecipientField: View {
    let label: String
    @Binding var addresses: [MailAddress]
    /// What is typed and not yet a chip: the composer takes it before sending (review of 14/11).
    @Binding var text: String
    /// The people matching what is typed, those already chosen left out.
    let suggest: (String, Set<String>) -> [PersonSuggestion]
    /// A contact or someone Paul wrote to; any other address shows in full.
    let isKnown: (String) -> Bool
    /// The project shown on a suggestion's line.
    var project: (PersonSuggestion) -> ProjectRow? = { _ in nil }
    var trailing: AnyView? = nil
    var onFocus: (Bool) -> Void = { _ in }
    @FocusState private var focused: Bool
    @State private var highlighted = 0
    @State private var moved = false
    @State private var dismissed = false

    /// « Camille Martin <camille@exemple.fr> », « camille@exemple.fr », several separated by commas.
    static func parse(_ text: String) -> [MailAddress] {
        let pieces = text.split(whereSeparator: { $0 == "," || $0 == ";" || $0 == "\n" }).map { $0.trimmingCharacters(in: .whitespaces) }
        return pieces.compactMap { piece -> MailAddress? in
            guard !piece.isEmpty else { return nil }
            if let open = piece.lastIndex(of: "<"), let close = piece.lastIndex(of: ">"), open < close {
                let name = piece[..<open].trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
                return MailAddress(name: name.isEmpty ? nil : name, email: String(piece[piece.index(after: open)..<close]).trimmingCharacters(in: .whitespaces))
            }
            return MailAddress(email: piece)
        }
    }

    private func commit(_ chosen: MailAddress? = nil) {
        let added = chosen.map { [$0] } ?? Self.parse(text)
        for address in added where !addresses.contains(where: { $0.email == address.email }) { addresses.append(address) }
        text = ""
    }

    private func accept(_ matches: [PersonSuggestion]) {
        commit(SuggestionChoice.accepted(typed: text, matches: matches, highlighted: highlighted, moved: moved))
    }

    var body: some View {
        let matches = focused && !dismissed ? suggest(text, Set(addresses.map(\.email))) : []
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                Text(label).foregroundStyle(.secondary).frame(width: 48, alignment: .leading)
                FlowLayout(spacing: 6) {
                    ForEach(addresses, id: \.email) { address in
                        let valid = MIMEBuilder.isValid(address.email)
                        let known = isKnown(address.email)
                        let mark = RecipientMark.of(valid: valid, known: known)
                        HStack(spacing: 3) {
                            // « ? » for a stranger, the triangle for an invalid address (lot 6, 19/11).
                            if let symbol = mark.symbol { Image(systemName: symbol).font(.meta) }
                            // A stranger's name never hides its address: « camille@client.exemple » could be anyone's.
                            Text(mark == .known ? (address.name ?? address.email) : [address.name, address.email].compactMap { $0 }.joined(separator: " · "))
                                .lineLimit(1)
                            Button { addresses.removeAll { $0.email == address.email } } label: {
                                Image(systemName: "xmark").font(.caption2.bold()).frame(width: 16, height: 16)
                            }
                            .buttonStyle(.hover(.circle))
                            .help("Retirer \(address.email)")
                            .accessibilityLabel("Retirer \(address.email)")
                        }
                        .padding(.leading, Space.s + 2).padding(.trailing, 4).padding(.vertical, 2)
                        // Invalid, or never written to: the one color of « to check » (design system v2, 19/11); its
                        // symbol says which (lot 6, 19/11).
                        .background(mark == .known ? Surface.raised : Tint.attention.opacity(mark == .invalid ? 0.18 : 0.16), in: Capsule())
                        .foregroundStyle(mark == .known ? Color.primary : Tint.attention)
                        .help(mark == .invalid ? "« \(address.email) » n'est pas une adresse valide"
                              : (mark == .known ? address.email : "\(address.email) : tu n'as jamais écrit à cette adresse, vérifie-la"))
                    }
                    TextField("", text: $text)
                        .textFieldStyle(.plain)
                        .focused($focused)
                        .frame(minWidth: 160)
                        .onSubmit { accept(matches) }
                        .suggestionKeys(count: matches.count, highlighted: $highlighted, moved: $moved, dismissed: $dismissed) { accept(matches) }
                        .onChange(of: text) { _, typed in
                            highlighted = 0
                            moved = false
                            dismissed = false
                            if typed.contains(",") || typed.contains(";") { commit() }
                        }
                        .onChange(of: focused) { _, on in
                            if !on, !text.isEmpty { commit() }
                            onFocus(on)
                        }
                        .onKeyPress(.delete) {
                            guard text.isEmpty, !addresses.isEmpty else { return .ignored }
                            addresses.removeLast()
                            return .handled
                        }
                }
                if let trailing { trailing }
            }
            if !matches.isEmpty {
                PersonSuggestionList(matches: matches, highlighted: $highlighted, project: project) { commit($0.address) }
                    .padding(.leading, 48 + Space.s)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(Motion.quick, value: matches.isEmpty)
    }
}

/// A draft being written: who from, who to, the subject, the text, the files, the signature, the quote; then
/// « Envoyer ». Every change is kept at once and reaches Gmail's drafts three seconds later.
struct ComposeView: View {
    let draftID: String
    @ObservedObject var mails: MailLibrary
    /// Shared with the draft's bar, fixed at the bottom of the page (17/11): the editor, the addresses being typed.
    @ObservedObject var session: ComposeSession
    @State private var showCc = false
    @State private var showBcc = false
    @State private var showQuote = false
    @State private var dropping = false
    /// The subject as typed, kept here: a late reading of the base never takes a keystroke back (review of 14/11).
    /// The text lives in the editor, which reads the draft once.
    @State private var subject = ""
    @State private var editorHeight = RichTextEditor.minimumHeight
    @State private var loaded = false
    @State private var recipientsFocused = false
    /// The project of the thread a reply answers: its people come first among the suggestions (15/11).
    @State private var threadProject: UUID?
    @FocusState private var focus: Field?

    enum Field { case body, subject }

    private var editor: RichTextController { session.editor }

    private var draft: MailDraftRow? { mails.drafts.first { $0.id == draftID } }

    private func binding<Value>(_ path: WritableKeyPath<MailDraftRow, Value>, default fallback: Value) -> Binding<Value> {
        Binding(get: { draft?[keyPath: path] ?? fallback }, set: { value in mails.edit(draftID) { $0[keyPath: path] = value } })
    }

    var body: some View {
        if let draft {
            let leaving = mails.sending?.draftID == draftID
            // Programmed, it is locked until Paul calls the send off (wave B).
            let planned = mails.scheduled[draftID]
            VStack(alignment: .leading, spacing: Space.m) {
                if let planned {
                    ScheduledBanner(entry: planned, draftID: draftID, mails: mails)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                fields(draft)
                    .disabled(planned != nil)
                Divider()
                if let conflict = draft.conflict { conflictBanner(conflict) }
                if draft.origin == .agent {
                    // The mails' one band (lot 6, 19/11): only the icon says « an agent », in its color.
                    Banner(.agent, Self.agentNotice.title, detail: Self.agentNotice.detail)
                }
                // The text, written with formatting as in Gmail (17/11); an agent's formatted draft opens as it leaves.
                // Its buttons are in the bar fixed at the bottom of the page, in reach wherever the text is scrolled.
                RichTextEditor(initialHTML: draft.editorHTML, placeholder: draft.mode == .new ? "Écris ton mail…" : "Écris ta réponse…",
                               isEditable: planned == nil, focusOnStart: draft.mode != .new && mails.agentRevisions[draftID] == nil,
                               controller: editor, height: $editorHeight) { html in
                    mails.edit(draftID) { $0.write(html: html) }
                }
                .frame(height: max(RichTextEditor.minimumHeight, editorHeight))
                .opacity(planned != nil ? 0.75 : 1)
                if !draft.files.isEmpty { files(draft).disabled(planned != nil) }
                if let signature = mails.signature(of: draft.account) {
                    Toggle(isOn: binding(\.signature, default: true)) {
                        Text(signature).font(.meta).foregroundStyle(.secondary).lineLimit(3)
                    }
                    .toggleStyle(.checkbox)
                    .help("Ta signature Gmail, ajoutée sous ton texte")
                    .disabled(planned != nil)
                }
                if let quote = draft.quoteText, draft.isFormattedGmailDraft {
                    // A draft written in Gmail with formatting (bold, lists, links): its text is the draft itself, shown
                    // whole, never folded as a quote (Paul, 16/11: « je vois pas le texte de mon brouillon »).
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text("Écrit dans Gmail, avec sa mise en forme : il part tel quel, sous ce que tu ajoutes.")
                            .font(.meta).foregroundStyle(.secondary)
                        Text(quote).font(.system(size: TextSize.reading)).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else if let quote = draft.quoteText {
                    DisclosureGroup(isExpanded: $showQuote) {
                        Text(quote).font(.meta).foregroundStyle(.secondary).textSelection(.enabled).lineLimit(30)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } label: {
                        Text(draft.mode == .forward ? "Message transféré" : "Message cité").font(.meta).foregroundStyle(.secondary)
                    }
                }
            }
            .animation(Motion.standard, value: planned?.state)
            .padding(Space.xl)
            // The app's one card: its fill and its edge (lot 6, 19/11), on the reading column of the thread or the panel.
            .cardSurface()
            .focusedValue(\.writingMail, true)
            .overlay {
                // Where the files drop: the selection's ink (design system v2, 19/11).
                if dropping {
                    RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Tint.accent, style: StrokeStyle(lineWidth: 2, dash: [6]))
                }
            }
            .disabled(leaving)
            .onDrop(of: [.fileURL], isTargeted: $dropping) { providers in
                guard planned == nil else { return false }
                Task {
                    var urls: [URL] = []
                    for provider in providers {
                        if let url = try? await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) as? Data,
                           let file = URL(dataRepresentation: url, relativeTo: nil) { urls.append(file) }
                    }
                    mails.attach(urls, to: draftID)
                }
                return true
            }
            .onAppear {
                if !loaded {
                    subject = draft.subject
                    loaded = true
                }
                showCc = !draft.cc.isEmpty
                showBcc = !draft.bcc.isEmpty
                if let key = draft.threadKey, let thread = try? mails.store.thread(key) {
                    threadProject = mails.filing(of: thread)?.filing.projectID
                }
            }
            .onChange(of: focus) { _, field in session.fieldsFocused = field != nil || recipientsFocused }
            .onChange(of: recipientsFocused) { _, on in session.fieldsFocused = focus != nil || on }
        }
    }

    @ViewBuilder
    private func fields(_ draft: MailDraftRow) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(spacing: Space.s) {
                Text("De").foregroundStyle(.secondary).frame(width: 48, alignment: .leading)
                if draft.mode == .new {
                    Menu {
                        ForEach(mails.accounts) { account in
                            Button { mails.setAccount(account.email, for: draftID) } label: {
                                Text("\(AccountStyle.label(for: account.email)) · \(account.email)")
                            }
                        }
                    } label: {
                        fromLabel(draft, choose: mails.unconfirmed.contains(draftID))
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .fixedSize()
                } else {
                    fromLabel(draft, choose: false)
                }
                Spacer()
            }
            RecipientField(label: "À", addresses: binding(\.to, default: []), text: $session.pendingTo, suggest: suggest, isKnown: mails.isKnown,
                           project: suggestedProject, trailing: AnyView(
                HStack(spacing: Space.s) {
                    // Small words that answer under the pointer and when pressed (correctifs, 15/11); grey: there, not
                    // calling (lot 6, 19/11).
                    if !showCc { TextButton("Cc", quiet: true) { showCc = true }.help("Ajouter des destinataires en copie") }
                    if !showBcc { TextButton("Cci", quiet: true) { showBcc = true }.help("Ajouter des destinataires en copie cachée") }
                }
                .font(.meta)
            ), onFocus: { recipientsFocused = $0 })
            if showCc {
                RecipientField(label: "Cc", addresses: binding(\.cc, default: []), text: $session.pendingCc, suggest: suggest, isKnown: mails.isKnown,
                               project: suggestedProject, onFocus: { recipientsFocused = $0 })
            }
            if showBcc {
                RecipientField(label: "Cci", addresses: binding(\.bcc, default: []), text: $session.pendingBcc, suggest: suggest, isKnown: mails.isKnown,
                               project: suggestedProject, onFocus: { recipientsFocused = $0 })
            }
            HStack(spacing: Space.s) {
                Text("Objet").foregroundStyle(.secondary).frame(width: 48, alignment: .leading)
                TextField("", text: $subject).textFieldStyle(.plain).font(.rowTitle.weight(.medium))
                    .focused($focus, equals: .subject)
                    .onChange(of: subject) { _, typed in if loaded { mails.edit(draftID) { $0.subject = typed } } }
            }
        }
        .font(.rowBody)
    }

    private func suggest(_ text: String, _ chosen: Set<String>) -> [PersonSuggestion] {
        mails.suggestions(for: text, excluding: chosen, project: threadProject)
    }

    /// The project shown on a suggestion: the thread's when the person is in it, else their first under way.
    private func suggestedProject(_ person: PersonSuggestion) -> ProjectRow? {
        if let id = threadProject, person.projectIDs.contains(id) { return mails.project(id) }
        return mails.agenda.projects.filter { person.projectIDs.contains($0.id) && $0.status != .termine }
            .min { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func fromLabel(_ draft: MailDraftRow, choose: Bool) -> some View {
        HStack(spacing: 6) {
            ColorDot(mails.color(for: draft.account), size: 8)
            if choose {
                // A choice to make: the app's accent, ink (design system v2, 19/11).
                Text("Choisir la boîte…").foregroundStyle(Tint.accent)
            } else {
                Text(AccountStyle.label(for: draft.account)).fontWeight(.medium)
                Text(draft.account).foregroundStyle(.secondary)
            }
            if draft.mode == .new { Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(.secondary) }
        }
        .help(draft.mode == .new ? "La boîte d'envoi" : "Une réponse part de la boîte du fil")
    }

    private func files(_ draft: MailDraftRow) -> some View {
        FlowLayout(spacing: 6) {
            ForEach(draft.files, id: \.filename) { file in
                let type = UTType(filenameExtension: (file.filename as NSString).pathExtension) ?? .data
                HStack(spacing: 6) {
                    Image(nsImage: NSWorkspace.shared.icon(for: type)).resizable().frame(width: 20, height: 20)
                    Text(file.filename).lineLimit(1).truncationMode(.middle)
                    Text(MailText.size(file.size)).foregroundStyle(.secondary)
                    Button { mails.removeFile(file, from: draftID) } label: {
                        Image(systemName: "xmark").font(.caption2.bold()).frame(width: 16, height: 16)
                    }
                    .buttonStyle(.hover(.circle))
                    .help("Retirer")
                    .accessibilityLabel("Retirer \(file.filename)")
                }
                .font(.meta)
                .padding(.horizontal, Space.s + 2).padding(.vertical, 5)
                .background(Surface.raised, in: Capsule())
            }
        }
    }

    /// Gmail's copy went its own way: Paul chooses which version lives on. The mails' one band (lot 6, 19/11): the icon
    /// of attention, the two ways out as secondary buttons (« Envoyer » waits for the choice).
    @ViewBuilder
    private func conflictBanner(_ conflict: MailDraftRow.Conflict) -> some View {
        switch conflict {
        case .absent:
            Banner(.attention, "Ce brouillon n'est plus dans Gmail.",
                   detail: "Il a peut-être été envoyé ou supprimé ailleurs. Regarde dans Envoyés avant de le renvoyer.") {
                Button("Le garder") { mails.keepDraft(draftID) }.buttonStyle(.secondary)
                Button("Le supprimer") { mails.forgetDraft(draftID, gmailKept: false) }.buttonStyle(.secondary)
            }
        case .modifie:
            Banner(.attention, "Ce brouillon a été modifié dans Gmail, sur un autre appareil.") {
                Button("Garder celui-ci") { mails.keepDraft(draftID) }.buttonStyle(.secondary)
                Button("Prendre celui de Gmail") { mails.forgetDraft(draftID, gmailKept: true) }.buttonStyle(.secondary)
            }
        }
    }

}

/// A new mail, over the list: the composer in a floating panel.
struct NewMailPanel: View {
    let draftID: String
    @ObservedObject var mails: MailLibrary
    @StateObject private var session = ComposeSession()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ✕ at the top right, as on every panel and object open (lot 4, 19/11); the title on the reading column, the
            // draft's edge under it, as in a thread (lot 6, 19/11: one edge).
            HStack(spacing: Space.m) {
                Text(mails.drafts.first { $0.id == draftID }?.subject.isEmpty == false
                     ? mails.drafts.first { $0.id == draftID }!.subject : "Nouveau mail")
                    .font(.title.bold()).lineLimit(1)
                Spacer()
                PanelCloseButton { mails.closeComposer() }
            }
            .readingColumn()
            .padding(.vertical, Space.l)
            Divider()
            ScrollView {
                ComposeView(draftID: draftID, mails: mails, session: session)
                    .id(mails.agentRevisions[draftID] ?? 0)
                    .padding(.vertical, Space.xl)
                    .readingColumn()
            }
            // The bar stays at the bottom of the panel, however long the mail (17/11), its glass on the draft's edges.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                FloatingBar { ComposeBar(draftID: draftID, mails: mails, session: session) }
                    .padding(.horizontal, PageMetrics.horizontal - Space.xl)
                    .frame(maxWidth: PageMetrics.readingWidth)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

extension View {
    /// The reading column of a mail (lot 6, 19/11): 860 points at most with its margins, in the middle; a thread's header,
    /// its messages and its reply, a new mail's title and its draft, all start on its edge.
    func readingColumn() -> some View {
        padding(.horizontal, PageMetrics.horizontal)
            .frame(maxWidth: PageMetrics.readingWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
    }
}

/// The drafts: Polhub's, then those Gmail holds from elsewhere, on the list's lines and its grid (lot 6, 19/11). A click
/// takes one up.
struct MailDraftListView: View {
    @ObservedObject var mails: MailLibrary
    @ObservedObject var router: WindowRouter
    @AppStorage(Preferences.Key.mailDensity) private var density = MailDensity.defaut.rawValue

    var body: some View {
        // A programmed mail is in « Programmés » only, as in Gmail (wave B).
        let mine = mails.drafts.filter { !mails.hidden.contains($0.account) && mails.scheduled[$0.id] == nil }
        let density = MailDensity(rawValue: density) ?? .defaut
        let stripes = MailGrid.showsStripes(accounts: mails.accounts.map(\.email), hidden: mails.hidden)
        if mine.isEmpty && mails.gmailDrafts.isEmpty {
            MailEmptyView(state: mails.emptyState, mails: mails)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(mine) { draft in
                        MailDraftLine(account: draft.account, color: stripes ? mails.color(for: draft.account) : nil, people: draft.to.map { $0.name ?? $0.email },
                                      subject: draft.subject, extract: draft.body, date: draft.updatedAt, error: draft.lastError,
                                      agent: draft.origin == .agent, density: density) { mails.open(draft, router: router) }
                            .contextMenu { Button("Supprimer le brouillon", role: .destructive) { mails.discard(draft.id) } }
                    }
                    if !mails.gmailDrafts.isEmpty {
                        Text("Commencés dans Gmail")
                            .font(.meta.weight(.semibold)).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, MailGrid.boxEnd).padding(.top, Space.l + 4).padding(.bottom, Space.s)
                            .overlay(alignment: .bottom) { MailLine() }
                        ForEach(mails.gmailDrafts) { message in
                            MailDraftLine(account: message.account, color: stripes ? mails.color(for: message.account) : nil,
                                          people: message.to.map { $0.name ?? $0.email }, subject: message.subject, extract: message.snippet, date: message.date,
                                          error: nil, density: density) { mails.resume(message, router: router) }
                                .help("Reprendre ce brouillon dans Polhub")
                        }
                    }
                }
            }
        }
    }
}

/// A draft on one line, as Gmail's, on the list's grid (lot 6, 19/11): « Brouillon » and to whom; the subject and the
/// start of the text; the date in the end column. Gmail writes « Brouillon » in red; here it is grey, red says « late »
/// only (design system v2, 19/11). No box: a draft is never ticked.
struct MailDraftLine: View {
    let account: String
    /// The mailbox's stripe, when the list shows several.
    let color: Color?
    let people: [String]
    let subject: String
    let extract: String
    let date: Date
    let error: String?
    var agent = false
    var density = MailDensity.defaut
    let open: () -> Void

    var body: some View {
        // The line of the list, as Gmail's: a shadow under the pointer, a shade darker pressed (15/11).
        Button(action: open) { line }
            .buttonStyle(LineButtonStyle(ground: MailSurface.unread))
    }

    private var line: some View {
        MailGridLine(stripe: color, stripeHelp: account) {
            Color.clear
        } senders: {
            (Text("Brouillon").foregroundStyle(.secondary) + Text(people.isEmpty ? "" : " · \(people.joined(separator: ", "))"))
                .font(.rowTitle)
                .lineLimit(1)
        } subject: {
            HStack(spacing: Space.s) {
                (Text(subject.isEmpty ? "(sans objet)" : subject).font(.rowTitle)
                    + Text(extract.isEmpty ? "" : " — \(extract.replacingOccurrences(of: "\n", with: " "))").font(.rowBody).foregroundStyle(.secondary))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                // Written by an agent: its own color; a failure: the attention's (design system v2, 19/11).
                if agent {
                    Label("préparé par un agent", systemImage: "sparkles").font(.meta).foregroundStyle(Tint.agent).fixedSize()
                }
                if error != nil { Image(systemName: "exclamationmark.triangle").font(.meta).foregroundStyle(Tint.attention).help(error ?? "") }
            }
        } end: {
            Text(MailText.date(date)).font(.meta).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
        }
        .foregroundStyle(.primary)
        .padding(.vertical, density.padding)
        .padding(.trailing, MailGrid.trailing)
        .overlay(alignment: .bottom) { MailLine() }
        .contentShape(Rectangle())
    }
}

extension MailDraftRow {
    /// A draft written in Gmail with formatting, taken up whole: its HTML is the draft itself (`MailEngine.resume`
    /// keeps it below what Paul adds), not a message it quotes.
    var isFormattedGmailDraft: Bool { origin == .gmail && quoteHTML != nil && mode != .forward }

    /// What the editor opens with: the formatted text, else the plain one, a block a line.
    var editorHTML: String { bodyHTML ?? MailRichText.html(fromPlain: body) }

    /// What Paul wrote in the editor (17/11): its formatting kept simple, and the plain text the mail carries beside it.
    mutating func write(html: String) {
        let cleaned = MailRichText.clean(html)
        let words = MailRichText.plain(cleaned)
        bodyHTML = words.isEmpty ? nil : cleaned
        body = words
    }
}

/// « Lien » : the address, then « Ajouter ».
struct LinkPrompt: View {
    let done: (String?) -> Void
    @State private var address = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("Ajouter un lien").font(.headline)
            TextField("exemple.fr/page ou une adresse mail", text: $address)
                .textFieldStyle(.roundedBorder)
                .frame(width: 280)
                .onSubmit { done(address) }
            HStack {
                Spacer()
                Button("Annuler") { done(nil) }.keyboardShortcut(.cancelAction)
                Button("Ajouter") { done(address) }.keyboardShortcut(.defaultAction).disabled(RichTextController.address(address) == nil)
            }
        }
        .padding(Space.l)
    }
}
