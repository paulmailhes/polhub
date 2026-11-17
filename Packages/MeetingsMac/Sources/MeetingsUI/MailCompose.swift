import Agenda
import AppKit
import Mail
import MailFormat
import Persistence
import PolhubDesign
import SwiftUI
import UniformTypeIdentifiers

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
                        HStack(spacing: 3) {
                            if !known, valid { Image(systemName: "questionmark.circle").font(.meta) }
                            // A stranger's name never hides its address: « camille@client.exemple » could be anyone's.
                            Text(known ? (address.name ?? address.email) : [address.name, address.email].compactMap { $0 }.joined(separator: " · "))
                                .lineLimit(1)
                            Button { addresses.removeAll { $0.email == address.email } } label: {
                                Image(systemName: "xmark").font(.caption2.bold()).frame(width: 16, height: 16)
                            }
                            .buttonStyle(.hover(.circle))
                            .help("Retirer \(address.email)")
                            .accessibilityLabel("Retirer \(address.email)")
                        }
                        .padding(.leading, Space.s + 2).padding(.trailing, 4).padding(.vertical, 2)
                        .background(!valid ? Color.red.opacity(0.18) : (known ? Surface.raised : Color.orange.opacity(0.16)), in: Capsule())
                        .foregroundStyle(!valid ? Color.red : (known ? Color.primary : Color.orange))
                        .help(!valid ? "« \(address.email) » n'est pas une adresse valide"
                              : (known ? address.email : "\(address.email) : tu n'as jamais écrit à cette adresse, vérifie-la"))
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
                    Label("Préparé par un agent : relis-le avant d'envoyer. Une adresse en orange n'est ni un contact ni une personne à qui tu as écrit.",
                          systemImage: "sparkles")
                        .font(.meta)
                        .padding(Space.m)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
                }
                // The text, written with formatting as in Gmail (17/11); an agent's formatted draft opens as it leaves.
                // Its buttons are in the bar fixed at the bottom of the page, in reach wherever the text is scrolled.
                RichTextEditor(initialHTML: draft.editorHTML, placeholder: draft.mode == .new ? "Écris ton mail…" : "Écris ta réponse…",
                               isEditable: planned == nil, focusOnStart: draft.mode != .new, controller: editor, height: $editorHeight) { html in
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
            .background(Surface.fill, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .focusedValue(\.writingMail, true)
            .overlay {
                if dropping {
                    RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6]))
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
                    // Small words that answer under the pointer and when pressed (correctifs, 15/11).
                    if !showCc { TextButton("Cc") { showCc = true }.help("Ajouter des destinataires en copie") }
                    if !showBcc { TextButton("Cci") { showBcc = true }.help("Ajouter des destinataires en copie cachée") }
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
                Text("Choisir la boîte…").foregroundStyle(Color.accentColor)
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

    /// Gmail's copy went its own way: Paul chooses which version lives on.
    private func conflictBanner(_ conflict: MailDraftRow.Conflict) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.m) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            switch conflict {
            case .absent:
                Text("Ce brouillon n'est plus dans Gmail : il a peut-être été envoyé ou supprimé ailleurs. Regarde dans Envoyés avant de le renvoyer.")
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button("Le garder") { mails.keepDraft(draftID) }
                Button("Le supprimer") { mails.forgetDraft(draftID, gmailKept: false) }
            case .modifie:
                Text("Ce brouillon a été modifié dans Gmail, sur un autre appareil.").fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button("Garder celui-ci") { mails.keepDraft(draftID) }
                Button("Prendre celui de Gmail") { mails.forgetDraft(draftID, gmailKept: true) }
            }
        }
        .font(.meta)
        .padding(Space.m)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
    }

}

/// A new mail, over the list: the composer in a floating panel.
struct NewMailPanel: View {
    let draftID: String
    @ObservedObject var mails: MailLibrary
    @StateObject private var session = ComposeSession()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Space.m) {
                PanelCloseButton { mails.closeComposer() }
                Text(mails.drafts.first { $0.id == draftID }?.subject.isEmpty == false
                     ? mails.drafts.first { $0.id == draftID }!.subject : "Nouveau mail")
                    .font(.title.bold()).lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, Space.xl).padding(.vertical, Space.l)
            Divider()
            ScrollView {
                ComposeView(draftID: draftID, mails: mails, session: session)
                    .id(mails.agentRevisions[draftID] ?? 0)
                    .padding(Space.xl)
                    .frame(maxWidth: PageMetrics.readingWidth)
                    .frame(maxWidth: .infinity)
            }
            // The bar stays at the bottom of the panel, however long the mail (17/11).
            .safeAreaInset(edge: .bottom, spacing: 0) {
                FloatingBar { ComposeBar(draftID: draftID, mails: mails, session: session) }
                    .frame(maxWidth: PageMetrics.readingWidth)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

/// The drafts: Polhub's, then those Gmail holds from elsewhere, on the list's lines. A click takes one up.
struct MailDraftListView: View {
    @ObservedObject var mails: MailLibrary
    @ObservedObject var router: WindowRouter

    var body: some View {
        // A programmed mail is in « Programmés » only, as in Gmail (wave B).
        let mine = mails.drafts.filter { !mails.hidden.contains($0.account) && mails.scheduled[$0.id] == nil }
        if mine.isEmpty && mails.gmailDrafts.isEmpty {
            ContentUnavailableView("Aucun brouillon", systemImage: "doc", description: Text("Un mail commencé et pas encore envoyé t'attend ici."))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(mine) { draft in
                        MailDraftLine(account: draft.account, color: mails.color(for: draft.account), people: draft.to.map { $0.name ?? $0.email },
                                      subject: draft.subject, extract: draft.body, date: draft.updatedAt, error: draft.lastError,
                                      agent: draft.origin == .agent) { mails.open(draft, router: router) }
                            .contextMenu { Button("Supprimer le brouillon", role: .destructive) { mails.discard(draft.id) } }
                    }
                    if !mails.gmailDrafts.isEmpty {
                        Text("Commencés dans Gmail")
                            .font(.meta.weight(.semibold)).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, MailRow.boxEnd).padding(.top, Space.l + 4).padding(.bottom, Space.s)
                            .overlay(alignment: .bottom) { MailLine() }
                        ForEach(mails.gmailDrafts) { message in
                            MailDraftLine(account: message.account, color: mails.color(for: message.account), people: message.to.map { $0.name ?? $0.email },
                                          subject: message.subject, extract: message.snippet, date: message.date, error: nil) { mails.resume(message, router: router) }
                                .help("Reprendre ce brouillon dans Polhub")
                        }
                    }
                }
            }
        }
    }
}

/// A draft on one line, as Gmail's: « Brouillon » in red and to whom; the subject and the start of the text;
/// the date at the end.
struct MailDraftLine: View {
    let account: String
    let color: Color
    let people: [String]
    let subject: String
    let extract: String
    let date: Date
    let error: String?
    var agent = false
    let open: () -> Void

    var body: some View {
        // The line of the list, as Gmail's: a shadow under the pointer, a shade darker pressed (15/11).
        Button(action: open) { line }
            .buttonStyle(LineButtonStyle(ground: MailSurface.unread))
    }

    private var line: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 1.5).fill(color).frame(width: 3, height: 22).padding(.leading, Space.m).help(account)
            Color.clear.frame(width: 44, height: 1)
            (Text("Brouillon").foregroundStyle(.red) + Text(people.isEmpty ? "" : " · \(people.joined(separator: ", "))"))
                .font(.rowTitle)
                .lineLimit(1)
                .frame(width: MailRow.sendersWidth, alignment: .leading)
                .padding(.trailing, Space.l)
            (Text(subject.isEmpty ? "(sans objet)" : subject).font(.rowTitle)
                + Text(extract.isEmpty ? "" : " — \(extract.replacingOccurrences(of: "\n", with: " "))").font(.rowBody).foregroundStyle(.secondary))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if agent {
                Label("préparé par un agent", systemImage: "sparkles").font(.meta).foregroundStyle(Color.accentColor).fixedSize().padding(.horizontal, Space.s)
            }
            if error != nil { Image(systemName: "exclamationmark.triangle").font(.meta).foregroundStyle(.orange).help(error ?? "").padding(.horizontal, Space.s) }
            Text(MailText.date(date)).font(.meta).foregroundStyle(.secondary).monospacedDigit().lineLimit(1).frame(minWidth: 58, alignment: .trailing)
        }
        .foregroundStyle(.primary)
        .padding(.vertical, Space.m)
        .padding(.trailing, Space.l)
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
