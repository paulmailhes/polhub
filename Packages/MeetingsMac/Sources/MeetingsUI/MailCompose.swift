import Agenda
import AppKit
import Mail
import MailFormat
import Persistence
import PolhubDesign
import SwiftUI
import UniformTypeIdentifiers

/// « À », « Cc », « Cci »: the people as chips, a field to type more, the contacts that match below it.
struct RecipientField: View {
    let label: String
    @Binding var addresses: [MailAddress]
    let suggest: (String) -> [MailAddress]
    var trailing: AnyView? = nil
    @State private var text = ""
    @FocusState private var focused: Bool

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

    var body: some View {
        let matches = focused ? suggest(text).filter { match in !addresses.contains { $0.email == match.email } } : []
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                Text(label).foregroundStyle(.secondary).frame(width: 34, alignment: .leading)
                FlowLayout(spacing: 6) {
                    ForEach(addresses, id: \.email) { address in
                        let valid = MIMEBuilder.isValid(address.email)
                        HStack(spacing: 3) {
                            Text(address.name ?? address.email).lineLimit(1)
                            Button { addresses.removeAll { $0.email == address.email } } label: { Image(systemName: "xmark").font(.caption2.bold()) }
                                .buttonStyle(.plain)
                                .help("Retirer \(address.email)")
                        }
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(valid ? Surface.raised : Color.red.opacity(0.18), in: Capsule())
                        .foregroundStyle(valid ? Color.primary : Color.red)
                        .help(valid ? address.email : "« \(address.email) » n'est pas une adresse valide")
                    }
                    TextField("", text: $text)
                        .textFieldStyle(.plain)
                        .focused($focused)
                        .frame(minWidth: 160)
                        .onSubmit { commit(matches.first.flatMap { text.contains("@") ? nil : $0 }) }
                        .onChange(of: text) { _, typed in if typed.contains(",") || typed.contains(";") { commit() } }
                        .onChange(of: focused) { _, on in if !on, !text.isEmpty { commit() } }
                        .onKeyPress(.delete) {
                            guard text.isEmpty, !addresses.isEmpty else { return .ignored }
                            addresses.removeLast()
                            return .handled
                        }
                }
                if let trailing { trailing }
            }
            if !matches.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(matches, id: \.email) { match in
                        Button { commit(match) } label: {
                            HStack(spacing: Space.s) {
                                Avatar(String((match.name ?? match.email).prefix(1)).uppercased(), size: 20, tint: MailText.tint(for: match.email))
                                Text(match.name ?? match.email)
                                if match.name != nil { Text(match.email).foregroundStyle(.secondary) }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, Space.s).padding(.vertical, 4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .font(.callout)
                .padding(.vertical, 4)
                .background(Surface.raised, in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
                .padding(.leading, 42)
            }
        }
    }
}

/// A draft being written: who from, who to, the subject, the text, the files, the signature, the quote; then
/// « Envoyer ». Every change is kept at once and reaches Gmail's drafts three seconds later.
struct ComposeView: View {
    let draftID: String
    @ObservedObject var mails: MailLibrary
    @State private var showCc = false
    @State private var showBcc = false
    @State private var showQuote = false
    @State private var dropping = false
    @State private var confirmingDiscard = false
    @FocusState private var bodyFocused: Bool

    private var draft: MailDraftRow? { mails.drafts.first { $0.id == draftID } }

    private func binding<Value>(_ path: WritableKeyPath<MailDraftRow, Value>, default fallback: Value) -> Binding<Value> {
        Binding(get: { draft?[keyPath: path] ?? fallback }, set: { value in mails.edit(draftID) { $0[keyPath: path] = value } })
    }

    var body: some View {
        if let draft {
            let leaving = mails.sending?.draftID == draftID
            VStack(alignment: .leading, spacing: Space.m) {
                fields(draft)
                Divider()
                TextEditor(text: binding(\.body, default: ""))
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .focused($bodyFocused)
                    .frame(minHeight: 160)
                    .overlay(alignment: .topLeading) {
                        if draft.body.isEmpty {
                            Text(draft.mode == .new ? "Écris ton mail…" : "Écris ta réponse…").foregroundStyle(.tertiary).padding(.leading, 5).allowsHitTesting(false)
                        }
                    }
                if !draft.files.isEmpty { files(draft) }
                if let signature = mails.signature(of: draft.account) {
                    Toggle(isOn: binding(\.signature, default: true)) {
                        Text(signature).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                    }
                    .toggleStyle(.checkbox)
                    .help("Ta signature Gmail, ajoutée sous ton texte")
                }
                if let quote = draft.quoteText {
                    DisclosureGroup(isExpanded: $showQuote) {
                        Text(quote).font(.caption).foregroundStyle(.secondary).textSelection(.enabled).lineLimit(30)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } label: {
                        Text(draft.mode == .forward ? "Message transféré" : "Message cité").font(.caption).foregroundStyle(.secondary)
                    }
                }
                footer(draft, leaving: leaving)
            }
            .padding(Space.l)
            .background(Surface.fill, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay {
                if dropping {
                    RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6]))
                }
            }
            .disabled(leaving)
            .onDrop(of: [.fileURL], isTargeted: $dropping) { providers in
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
                showCc = !draft.cc.isEmpty
                showBcc = !draft.bcc.isEmpty
                if draft.mode != .new { bodyFocused = true }
            }
            .confirmationDialog("Supprimer ce brouillon ?", isPresented: $confirmingDiscard) {
                Button("Supprimer", role: .destructive) { mails.discard(draftID) }
            } message: {
                Text("Il disparaît aussi des brouillons de Gmail.")
            }
        }
    }

    @ViewBuilder
    private func fields(_ draft: MailDraftRow) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: Space.s) {
                Text("De").foregroundStyle(.secondary).frame(width: 34, alignment: .leading)
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
            RecipientField(label: "À", addresses: binding(\.to, default: []), suggest: mails.suggestions(for:), trailing: AnyView(
                HStack(spacing: Space.s) {
                    if !showCc { Button("Cc") { showCc = true }.buttonStyle(.borderless) }
                    if !showBcc { Button("Cci") { showBcc = true }.buttonStyle(.borderless) }
                }
                .font(.callout)
            ))
            if showCc { RecipientField(label: "Cc", addresses: binding(\.cc, default: []), suggest: mails.suggestions(for:)) }
            if showBcc { RecipientField(label: "Cci", addresses: binding(\.bcc, default: []), suggest: mails.suggestions(for:)) }
            HStack(spacing: Space.s) {
                Text("Objet").foregroundStyle(.secondary).frame(width: 34, alignment: .leading)
                TextField("", text: binding(\.subject, default: "")).textFieldStyle(.plain).font(.body.weight(.medium))
            }
        }
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
                    Image(nsImage: NSWorkspace.shared.icon(for: type)).resizable().frame(width: 18, height: 18)
                    Text(file.filename).lineLimit(1).truncationMode(.middle)
                    Text(MailText.size(file.size)).foregroundStyle(.secondary)
                    Button { mails.removeFile(file, from: draftID) } label: { Image(systemName: "xmark").font(.caption2.bold()) }
                        .buttonStyle(.plain)
                        .help("Retirer")
                }
                .font(.callout)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Surface.raised, in: Capsule())
            }
        }
    }

    private func footer(_ draft: MailDraftRow, leaving: Bool) -> some View {
        HStack(spacing: Space.m) {
            Button { mails.send(draftID) } label: { Label("Envoyer", systemImage: "paperplane.fill") }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(mails.sendProblem(draft) != nil || mails.sending != nil)
                .help(mails.sendProblem(draft) ?? "Envoyer (⌘↩) : tu as dix secondes pour l'annuler")
            Button {
                let panel = NSOpenPanel()
                panel.allowsMultipleSelection = true
                panel.canChooseDirectories = false
                panel.prompt = "Joindre"
                if panel.runModal() == .OK { mails.attach(panel.urls, to: draftID) }
            } label: { Label("Joindre", systemImage: "paperclip") }
                .buttonStyle(.glass)
                .help("Joindre des fichiers (ou les glisser ici)")
            status(draft, leaving: leaving)
            Spacer()
            Button(role: .destructive) { confirmingDiscard = true } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .help("Supprimer le brouillon")
        }
    }

    @ViewBuilder
    private func status(_ draft: MailDraftRow, leaving: Bool) -> some View {
        Group {
            if leaving {
                Text("Envoi en cours…")
            } else if let error = draft.lastError {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).lineLimit(2)
            } else if draft.gmailDraftID != nil, !draft.needsPush {
                Text("Enregistré dans Gmail")
            } else {
                Text("Enregistré sur le Mac")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

/// A new mail, over the list: the composer in a floating panel.
struct NewMailPanel: View {
    let draftID: String
    @ObservedObject var mails: MailLibrary

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Space.m) {
                PanelCloseButton { mails.closeComposer() }
                Text(mails.drafts.first { $0.id == draftID }?.subject.isEmpty == false
                     ? mails.drafts.first { $0.id == draftID }!.subject : "Nouveau mail")
                    .font(.title2.bold()).lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, Space.xl).padding(.vertical, Space.m)
            Divider()
            ScrollView {
                ComposeView(draftID: draftID, mails: mails)
                    .padding(Space.xl)
                    .frame(maxWidth: PageMetrics.readingWidth)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

/// The drafts: Polhub's, then those Gmail holds from elsewhere. A click takes one up.
struct MailDraftListView: View {
    @ObservedObject var mails: MailLibrary
    @ObservedObject var router: WindowRouter

    var body: some View {
        let mine = mails.drafts.filter { !mails.hidden.contains($0.account) }
        if mine.isEmpty && mails.gmailDrafts.isEmpty {
            ContentUnavailableView("Aucun brouillon", systemImage: "doc", description: Text("Un mail commencé et pas encore envoyé t'attend ici."))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(mine) { draft in
                        row(account: draft.account, people: draft.to.map { $0.name ?? $0.email }, subject: draft.subject,
                            extract: draft.body, date: draft.updatedAt, error: draft.lastError) { mails.open(draft, router: router) }
                            .contextMenu { Button("Supprimer le brouillon", role: .destructive) { mails.discard(draft.id) } }
                        Divider().padding(.leading, 64)
                    }
                    if !mails.gmailDrafts.isEmpty {
                        Text("Commencés dans Gmail")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, Space.l).padding(.top, Space.l).padding(.bottom, 6)
                        ForEach(mails.gmailDrafts) { message in
                            row(account: message.account, people: message.to.map { $0.name ?? $0.email }, subject: message.subject,
                                extract: message.snippet, date: message.date, error: nil) { mails.resume(message, router: router) }
                                .help("Reprendre ce brouillon dans Polhub")
                            Divider().padding(.leading, 64)
                        }
                    }
                }
            }
        }
    }

    private func row(account: String, people: [String], subject: String, extract: String, date: Date, error: String?,
                     open: @escaping () -> Void) -> some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 1.5).fill(mails.color(for: account)).frame(width: 3, height: 22).padding(.leading, Space.m)
            Text("Brouillon").font(.caption.weight(.semibold)).foregroundStyle(.red).frame(width: 70)
            Text(people.isEmpty ? "(sans destinataire)" : people.joined(separator: ", ")).lineLimit(1).frame(width: 180, alignment: .leading)
            (Text(subject.isEmpty ? "(sans objet)" : subject).fontWeight(.medium)
                + Text(extract.isEmpty ? "" : "  —  \(extract.replacingOccurrences(of: "\n", with: " "))").foregroundStyle(.secondary))
                .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading).padding(.leading, Space.s)
            if error != nil { Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange).help(error ?? "") }
            Text(MailText.date(date)).font(.callout).foregroundStyle(.secondary).frame(width: 92, alignment: .trailing).padding(.trailing, Space.l)
        }
        .font(.callout)
        .frame(height: 40)
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
    }
}
