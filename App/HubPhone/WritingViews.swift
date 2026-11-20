import HubLink
import SwiftUI

/// A new mail, or a reply under a thread (lot 3, 20/11): written here, sent by the Mac after its delay.
struct ComposeSheet: View {
    /// The thread answered; nil for a new mail.
    let reply: (thread: LinkThread, all: Bool)?
    @Environment(PhoneSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var to = ""
    @State private var cc = ""
    @State private var subject = ""
    @State private var text = ""
    @State private var accounts: [String] = []
    @State private var account: String?
    @State private var problem: String?
    @State private var sending = false
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                if let reply {
                    Section {
                        LabeledContent(reply.all ? "Répondre à tous" : "Répondre", value: reply.thread.people)
                        Text(reply.thread.subject).foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        if accounts.count > 1 {
                            Picker("De", selection: $account) {
                                ForEach(accounts, id: \.self) { Text($0).tag(Optional($0)) }
                            }
                        }
                        TextField("À", text: $to).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                        TextField("Cc", text: $cc).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                        TextField("Objet", text: $subject)
                    }
                }
                Section {
                    TextField("Ton message", text: $text, axis: .vertical).lineLimit(8...30).focused($focused)
                } footer: {
                    Text("Le Mac l'envoie avec ta signature, après le délai de Réglages › Mails ; « Annuler » le rappelle.")
                }
                if let problem {
                    Section { Label(problem, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
                }
            }
            .navigationTitle(reply == nil ? "Nouveau mail" : "Réponse")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Envoyer") { Task { await send() } }
                        .disabled(sending || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .task {
                focused = reply != nil
                guard reply == nil else { return }
                accounts = (try? await session.fetch([String].self, LinkAPI.Path.accounts).value) ?? []
                account = account ?? accounts.first
            }
        }
    }

    private func send() async {
        sending = true
        defer { sending = false }
        func list(_ text: String) -> [String] {
            text.split(whereSeparator: { $0 == "," || $0 == ";" || $0 == " " }).map(String.init).filter { !$0.isEmpty }
        }
        problem = if let reply {
            await session.send(reply: LinkReply(thread: reply.thread.id, all: reply.all, text: text))
        } else {
            await session.send(mail: LinkNewMail(account: account, to: list(to), cc: list(cc), subject: subject, text: text))
        }
        if problem == nil { dismiss() }
    }
}

/// « Envoi dans 8 s · Annuler », above the tabs, as on the Mac.
struct SendingPill: View {
    @Environment(PhoneSession.self) private var session

    var body: some View {
        if let sending = session.sending {
            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                let left = max(0, Int(sending.at.timeIntervalSince(context.date).rounded(.up)))
                HStack(spacing: 12) {
                    Image(systemName: "paperplane.fill").foregroundStyle(.secondary)
                    Text(left > 0 && !sending.leaving ? "Envoi dans \(left) s" : "Envoi…").font(.subheadline)
                    if !sending.leaving, left > 0 {
                        Button("Annuler") { Task { await session.cancelSending() } }.fontWeight(.semibold)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                .glassEffect(.regular, in: Capsule())
            }
            .padding(.bottom, 64)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
