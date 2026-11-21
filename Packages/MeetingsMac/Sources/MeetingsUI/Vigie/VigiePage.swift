import HubDesign
import SwiftUI
import VigieKit

/// « Vigie » in the sidebar (21/11), first step: its « Vue d'ensemble » — what waits for Paul (a sensitive action to allow
/// or refuse, a question answered for him, a plan), then his conversations of Claude Code. The engine is Vigie's own;
/// the app Vigie stays beside hub, and keeps sending the notifications.
struct VigiePage: View {
    @ObservedObject var library: VigieLibrary

    var body: some View {
        Page(maxWidth: PageMetrics.readingWidth, spacing: PageMetrics.cardGap) {
            link
            if let problem = library.problem {
                Banner(.attention, problem) {
                    Button("OK") { library.problem = nil }
                }
            }
            if library.link == .running || !library.overview.conversations.isEmpty {
                waiting
                if !library.notices.isEmpty { notices }
                conversations
            }
        }
        .belowToolbar()
        .windowTitle("Vigie", subtitle: "Vue d'ensemble")
        .onAppear { library.isVisible = true }
        .onDisappear { library.isVisible = false }
    }

    /// Where the engine is, when it is not simply running.
    @ViewBuilder private var link: some View {
        switch library.link {
        case .running:
            EmptyView()
        case .unknown:
            HStack(spacing: Space.s) {
                ProgressView().controlSize(.small)
                Text("hub demande à Vigie…").foregroundStyle(.secondary)
            }
        case .absent:
            Card {
                SectionTitle("Le moteur de Vigie n'est pas sur ce Mac", systemImage: "binoculars")
                Text(Words.typeset("Il vient avec l'app Vigie : installe-la, ouvre-la une fois, et cette page se remplit. hub posera lui-même le moteur à une prochaine étape."))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .stopped:
            Banner(.attention, "Le moteur de Vigie ne répond pas", detail: "Ouvre l'app Vigie : elle le relance. Ce que tu vois ici date de sa dernière réponse.")
        case .trouble(let why):
            Banner(.attention, why)
        }
    }

    private var waiting: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            SectionTitle("T'attendent", count: library.waiting.count)
            if library.waiting.isEmpty {
                Card {
                    Label("Rien ne t'attend.", systemImage: "checkmark.circle").foregroundStyle(.secondary)
                }
            } else {
                ForEach(library.waiting) { review in
                    VigieReviewCard(review: review, library: library)
                }
            }
        }
    }

    private var notices: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            SectionTitle("À regarder", count: library.notices.count)
            Card {
                ForEach(library.notices) { review in
                    HStack(alignment: .firstTextBaseline, spacing: Space.m) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Words.typeset(review.title)).font(.rowBody)
                            if let detail = review.detail, !detail.isEmpty {
                                Text(Words.typeset(detail)).font(.meta).foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: Space.s)
                        if VigieWords.canDismiss(review) {
                            Button("Retirer") { Task { await library.dismiss(review) } }
                                .buttonStyle(.borderless)
                                .disabled(library.sending.contains(review.id))
                        }
                    }
                    if review.id != library.notices.last?.id { Divider() }
                }
            }
        }
    }

    private var conversations: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            SectionTitle("Conversations", count: library.openConversations.count)
            if library.openConversations.isEmpty {
                Card {
                    Text(Words.typeset("Aucune conversation ouverte dans Claude Code.")).foregroundStyle(.secondary)
                }
            } else {
                Card(padding: Space.s) {
                    VStack(spacing: 0) {
                        ForEach(library.openConversations) { conversation in
                            Button {
                                Task { await library.open(conversation: conversation.id) }
                            } label: {
                                VigieConversationRow(conversation: conversation, account: library.overview.accountLabel(conversation.accountID))
                            }
                            .buttonStyle(.row(radius: Radius.control, inset: Space.s))
                            .help("Ouvrir cette conversation dans VS Code")
                        }
                    }
                }
            }
            if library.closedCount > 0 {
                Text(Words.typeset(Words.count(library.closedCount, "conversation fermée", "conversations fermées") + " depuis deux jours."))
                    .font(.meta).foregroundStyle(.secondary)
            }
        }
    }
}

/// The words of the « Vue d'ensemble » (pure, tested).
enum VigieWords {
    /// What a conversation is doing, in two or three words.
    static func status(_ conversation: VigieConversation) -> String {
        switch conversation.status {
        case .working: conversation.agentsRunning > 0 ? "travaille · " + Words.count(conversation.agentsRunning, "agent") : "travaille"
        case .waiting: "t'attend"
        case .blocked: "attend ta décision"
        case .idle: "au repos"
        case .closed: "fermée"
        case .other: ""
        }
    }

    /// Whether the conversation needs Paul now: its line says so in the color of attention.
    static func needsPaul(_ conversation: VigieConversation) -> Bool {
        conversation.status == .waiting || conversation.status == .blocked || conversation.needsYou > 0
    }

    /// The line under a card's title: the conversation, and the rule that held the action.
    static func context(_ review: VigieReview) -> String {
        [review.conversationTitle, review.rule].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// A notice that goes when Paul has seen it; an account to connect again stays while the problem lasts.
    static func canDismiss(_ review: VigieReview) -> Bool {
        review.id.hasPrefix("s:") || review.id.hasPrefix("cf:")
    }
}

/// One thing that waits: what it is, where it comes from, and its gestures.
struct VigieReviewCard: View {
    let review: VigieReview
    @ObservedObject var library: VigieLibrary

    var body: some View {
        let busy = library.sending.contains(review.id)
        Card {
            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                Image(systemName: symbol).foregroundStyle(Tint.attention).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(Words.typeset(review.title.isEmpty ? "Une demande attend" : review.title)).font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    let context = VigieWords.context(review)
                    if !context.isEmpty { Text(Words.typeset(context)).font(.meta).foregroundStyle(.secondary) }
                }
                Spacer(minLength: Space.s)
                if let expires = review.expiresAt, review.isPendingDecision {
                    TimelineView(.periodic(from: .now, by: 20)) { context in
                        Text(Words.typeset("refus " + Words.until(expires, now: context.date))).font(.meta).foregroundStyle(.secondary)
                    }
                }
            }
            if let command = review.command, !command.isEmpty {
                Text(command)
                    .font(.meta.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Space.m)
                    .cardSurface(radius: Radius.inner)
            }
            if let detail = review.detail, !detail.isEmpty {
                Text(Words.typeset(detail)).font(.rowBody).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if review.needsPassword {
                Text(Words.typeset("Une commande sudo demande ton mot de passe : lance-la toi-même dans Terminal."))
                    .font(.meta).foregroundStyle(.secondary)
            }
            HStack(spacing: Space.s) {
                if busy { ProgressView().controlSize(.small) }
                Spacer(minLength: 0)
                if let conversation = review.conversationID {
                    Button("Ouvrir dans VS Code") { Task { await library.open(conversation: conversation) } }
                        .buttonStyle(.secondary)
                }
                if review.isPendingDecision {
                    Button("Refuser") { Task { await library.decide(review, allow: false) } }
                        .buttonStyle(.secondary).disabled(busy)
                    if !review.needsPassword {
                        Button("Autoriser") { Task { await library.decide(review, allow: true) } }
                            .buttonStyle(.primary).disabled(busy)
                    }
                } else if review.kind == .question, review.question != nil {
                    Button("Ça me va") { Task { await library.approve(review) } }
                        .buttonStyle(.primary).disabled(busy)
                }
            }
        }
    }

    private var symbol: String {
        switch review.kind {
        case .blocked: "hand.raised.fill"
        case .question, .waiting: "questionmark.bubble.fill"
        case .limit, .notice, .other: "info.circle.fill"
        }
    }
}

/// A conversation of Claude Code, on one line and a half.
struct VigieConversationRow: View {
    let conversation: VigieConversation
    let account: String?

    var body: some View {
        let needsPaul = VigieWords.needsPaul(conversation)
        HStack(alignment: .firstTextBaseline, spacing: Space.m) {
            Image(systemName: needsPaul ? "exclamationmark.circle.fill" : conversation.status == .working ? "circle.dotted.circle" : "circle")
                .foregroundStyle(needsPaul ? AnyShapeStyle(Tint.attention) : AnyShapeStyle(.secondary))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(Words.typeset(conversation.title.isEmpty ? "Sans titre" : conversation.title)).font(.rowTitle).lineLimit(1)
                if let headline = conversation.headline, !headline.isEmpty {
                    Text(Words.typeset(headline)).font(.meta).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: Space.m)
            VStack(alignment: .trailing, spacing: 2) {
                Text(VigieWords.status(conversation)).font(.meta)
                    .foregroundStyle(needsPaul ? AnyShapeStyle(Tint.attention) : AnyShapeStyle(.secondary))
                Text([conversation.project, account].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.tag).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.vertical, Space.xs)
        .contentShape(Rectangle())
    }
}
