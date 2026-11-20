import PolhubLink
import SwiftUI

/// Colin, the Accueil's thread (lot 3, 20/11): the same conversation as on the Mac, his answer as it is written, what he
/// changed with « Annuler ». He answers on the Mac, with the Mac's tools and their lock.
struct ColinScreen: View {
    @Environment(PhoneSession.self) private var session
    @State private var thread: LinkColin?
    @State private var keptAt: Date?
    @State private var problem: String?
    @State private var question = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(thread?.messages ?? []) { message in
                            ColinBubble(message: message)
                        }
                        if let thread, thread.answering {
                            Text(thread.streaming.isEmpty ? "Colin réfléchit…" : thread.streaming)
                                .foregroundStyle(thread.streaming.isEmpty ? .secondary : .primary)
                        }
                        ForEach(recentChanges) { change in
                            ChangeCard(change: change) { Task { await undo(change) } }
                        }
                        Color.clear.frame(height: 1).id("fin")
                    }
                    .padding()
                }
                .onChange(of: thread?.messages.count) { proxy.scrollTo("fin", anchor: .bottom) }
                .onChange(of: thread?.streaming) { proxy.scrollTo("fin", anchor: .bottom) }
            }
            .safeAreaInset(edge: .top, spacing: 0) { StateLine(keptAt: keptAt, problem: problem ?? thread?.problem) }
            .safeAreaInset(edge: .bottom) { bar }
            .navigationTitle("Colin")
            .toolbar {
                SettingsButton()
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles").foregroundStyle(PhoneStyle.colin)
                        Text("Colin").font(.headline)
                        if let state = thread?.state {
                            Circle().fill(state == "en panne" ? PhoneStyle.red : (state == "prêt" || state == "répond…" ? PhoneStyle.colin : .gray))
                                .frame(width: 7, height: 7)
                            Text(state).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .task { await follow() }
        }
    }

    /// The changes of his last answer, newest last.
    private var recentChanges: [LinkChange] {
        guard let last = thread?.messages.last(where: { !$0.fromPaul })?.date else { return [] }
        return (thread?.changes ?? []).filter { $0.at >= last.addingTimeInterval(-600) }
    }

    private var bar: some View {
        HStack(spacing: 8) {
            TextField("Écris à Colin…", text: $question, axis: .vertical)
                .lineLimit(1...5)
                .focused($focused)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20))
            Button { Task { await ask() } } label: {
                Image(systemName: "arrow.up").fontWeight(.semibold).frame(width: 36, height: 36)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.circle)
            .disabled(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || thread?.answering == true || keptAt != nil)
        }
        .padding(.horizontal).padding(.bottom, 6)
    }

    /// The thread, read again every second while Colin answers, every ten otherwise.
    private func follow() async {
        while !Task.isCancelled {
            await load()
            try? await Task.sleep(for: .seconds(thread?.answering == true ? 1 : 10))
        }
    }

    private func load() async {
        do throws(LinkFailure) {
            let fetched = try await session.fetch(LinkColin.self, LinkAPI.Path.colin)
            thread = fetched.value
            keptAt = fetched.keptAt
            problem = nil
        } catch {
            problem = error.message
        }
    }

    private func ask() async {
        let text = question.trimmingCharacters(in: .whitespacesAndNewlines)
        do throws(LinkFailure) {
            thread = try await session.post(LinkColin.self, LinkAPI.Path.colin, body: LinkQuestion(text: text))
            question = ""
            problem = nil
        } catch {
            problem = error.message
        }
    }

    private func undo(_ change: LinkChange) async {
        do throws(LinkFailure) {
            thread = try await session.post(LinkColin.self, LinkAPI.Path.colinUndo, body: LinkUndo(id: change.id))
        } catch {
            problem = error.message
        }
    }
}

/// Paul's question on the right, in a bubble; Colin's answer on the left, in markdown.
struct ColinBubble: View {
    let message: LinkColinMessage

    var body: some View {
        if message.fromPaul {
            HStack {
                Spacer(minLength: 48)
                Text(message.text)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(PhoneStyle.colin.opacity(0.14), in: RoundedRectangle(cornerRadius: 18))
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                MarkdownBlock(text: message.text)
                if message.state == "interrupted" || message.state == "failed" {
                    Text(message.state == "failed" ? "Colin n'a pas pu finir." : "Réponse arrêtée.").font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// « Projet modifié · Site vitrine », its fields, « Annuler ».
struct ChangeCard: View {
    let change: LinkChange
    let undo: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(change.created ? "Nouveau projet" : "Projet modifié").font(.caption.weight(.semibold)).foregroundStyle(PhoneStyle.colin)
            Text(change.project).font(.headline)
            if let note = change.note { Text(note).font(.footnote).foregroundStyle(.secondary) }
            ForEach(Array(change.fields.enumerated()), id: \.offset) { _, field in
                HStack(alignment: .firstTextBaseline) {
                    Text(field.label).font(.subheadline).foregroundStyle(.secondary).frame(width: 110, alignment: .leading)
                    Text([field.before, field.after].compactMap { $0 }.joined(separator: " → ")).font(.subheadline)
                }
            }
            if change.undone {
                Text("Annulé").font(.footnote).foregroundStyle(.secondary)
            } else {
                Button("Annuler", action: undo).font(.subheadline.weight(.semibold))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PhoneStyle.colin.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(PhoneStyle.colin.opacity(0.25), lineWidth: 1))
    }
}
