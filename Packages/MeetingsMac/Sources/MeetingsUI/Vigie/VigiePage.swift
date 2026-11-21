import HubDesign
import SwiftUI
import VigieKit

/// « Vigie » in the sidebar (21/11), its « Vue d'ensemble », as a Notion page: what waits for Paul's decision (a sensitive
/// action to allow or refuse, a question or a plan, a conversation that waits in VS Code), the questions Vigie answered
/// for him, what is only to see, then his conversations of Claude Code. Since the migration (21/11, Paul: « complètement
/// désactiver mon Vigie, utiliser celui de Hub »), everything the app Vigie did on this page is here: answer, change an
/// answer, Terminal, restart the engine, and Auto-accept in the toolbar.
struct VigiePage: View {
    @ObservedObject var library: VigieLibrary
    /// The window's router, for the pages of Vigie in the toolbar; none in a capture.
    var router: WindowRouter? = nil
    /// Opens a conversation's page (21/11); none in a capture.
    var openConversation: ((String) -> Void)? = nil
    @State private var answering: VigieReview?
    @State private var changing: VigieReview?

    var body: some View {
        Page(maxWidth: PageMetrics.readingWidth, spacing: Space.xxl) {
            ToolHeader("Vigie", icon: .vigie, color: SidebarItem.vigie.tint, subtitle: VigieWords.pageSubtitle)
            link
            messages
            if library.link == .running || !library.overview.conversations.isEmpty {
                decisions
                if !library.toRead.isEmpty { toRead }
                if !library.toSee.isEmpty { toSee }
                conversations
            }
        }
        .belowToolbar()
        .toolbar {
            if let router {
                ToolbarItem(placement: .principal) { VigiePagePicker(router: router) }
            }
            if let settings = library.settings {
                ToolbarItem(placement: .primaryAction) {
                    // Its name beside it: a switch alone in a toolbar says nothing.
                    HStack(spacing: Space.s) {
                        Text("Auto-accept").font(.meta)
                        Toggle("Auto-accept", isOn: Binding(get: { settings.autoAccept }, set: { on in Task { await library.setAutoAccept(on) } }))
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .controlSize(.small)
                    }
                    .padding(.horizontal, Space.s)
                    .help(VigieWords.autoAcceptHelp)
                }
            }
        }
        .sheet(item: $answering) { review in
            VigieChoicesSheet(review: review, items: review.questions, mode: .answer, library: library)
        }
        .sheet(item: $changing) { review in
            VigieChoicesSheet(review: review, items: review.question?.items ?? [], mode: .change, library: library)
        }
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
            Banner(.attention, "Le moteur de Vigie n'est pas sur ce Mac",
                   detail: "Il vient avec l'app Vigie : installe-la et ouvre-la une fois, puis cette page se remplit.")
        case .stopped:
            Banner(.attention, "Le moteur de Vigie ne répond pas",
                   detail: "Ce que tu vois date de sa dernière réponse. Les garde-fous continuent de tenir les actions sensibles.") {
                Button("Relancer") { Task { await library.restartEngine() } }
                    .disabled(library.sending.contains("moteur"))
            }
        case .trouble(let why):
            Banner(.attention, why) {
                Button("Relancer le moteur") { Task { await library.restartEngine() } }
                    .disabled(library.sending.contains("moteur"))
            }
        }
    }

    /// What a gesture said, and the engine's own sentences.
    @ViewBuilder private var messages: some View {
        if let problem = library.problem {
            Banner(.attention, problem) { Button("OK") { library.problem = nil } }
        }
        if let info = library.info {
            Banner(.information, info) { Button("OK") { library.info = nil } }
        }
        ForEach(library.overview.notices, id: \.self) { notice in
            Label(Words.typeset(notice), systemImage: "info.circle").font(.meta).foregroundStyle(.secondary)
        }
    }

    private var decisions: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            PartTitle(library.decisions.isEmpty ? "À décider" : "À décider · \(library.decisions.count)")
            if library.decisions.isEmpty {
                Label("Rien ne t'attend.", systemImage: "checkmark.circle").foregroundStyle(.secondary)
            } else {
                ForEach(library.decisions) { review in
                    VigieDecisionCard(review: review, library: library) { answering = review }
                }
            }
        }
    }

    /// The questions Vigie answered for Paul: « Ça me va », or « Changer ».
    private var toRead: some View {
        VStack(alignment: .leading, spacing: 0) {
            PartTitle("À relire · \(library.toRead.count)")
            ForEach(library.toRead) { review in
                VigieLine {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Words.typeset(review.title.isEmpty ? "Une question" : review.title)).font(.rowTitle)
                        Text(Words.typeset(VigieWords.chosen(review))).font(.meta).foregroundStyle(.secondary)
                        if let conversation = review.conversationTitle { Text(Words.typeset(conversation)).font(.tag).foregroundStyle(.tertiary) }
                    }
                } trailing: {
                    let busy = library.sending.contains(review.id)
                    if review.question?.items.contains(where: { !$0.options.isEmpty }) == true {
                        Button("Changer…") { changing = review }.buttonStyle(.secondary).disabled(busy)
                    }
                    Button("Ça me va") { Task { await library.approve(review) } }.buttonStyle(.secondary).disabled(busy)
                }
            }
        }
    }

    /// What is only to see: a refusal to do oneself, a limit, an account to connect again, a notice.
    private var toSee: some View {
        VStack(alignment: .leading, spacing: 0) {
            PartTitle("À regarder · \(library.toSee.count)")
            ForEach(library.toSee) { review in
                VigieLine {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Words.typeset(review.title)).font(.rowTitle).fixedSize(horizontal: false, vertical: true)
                        let detail = VigieWords.detail(review)
                        if !detail.isEmpty { Text(Words.typeset(detail)).font(.meta).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                    }
                } trailing: {
                    let busy = library.sending.contains(review.id)
                    // A limit fell: the conversation goes on with another account, at the end of its turn.
                    if review.kind == .limit, let conversation = review.conversationID {
                        let free = library.freeAccounts(excluding: review.accountID)
                        if !free.isEmpty {
                            Menu("Passer sur…") {
                                ForEach(free) { account in
                                    Button(account.label) { Task { await library.switchAccount(conversation, to: account.id, now: false) } }
                                }
                            }
                            .fixedSize()
                            .disabled(library.sending.contains("compte:" + conversation))
                        }
                    }
                    if review.command != nil, review.id.hasPrefix("b:") {
                        Button("Lancer dans Terminal") { Task { await library.runInTerminal(review) } }
                            .buttonStyle(.secondary).disabled(library.sending.contains("terminal:" + review.id))
                    }
                    if VigieWords.canDismiss(review) {
                        Button("Retirer") { Task { await library.dismiss(review) } }.buttonStyle(.secondary).disabled(busy)
                    }
                }
            }
        }
    }

    private var conversations: some View {
        VStack(alignment: .leading, spacing: 0) {
            PartTitle("Conversations · \(library.openConversations.count)")
            if library.openConversations.isEmpty {
                Text(Words.typeset("Aucune conversation ouverte dans Claude Code.")).foregroundStyle(.secondary).padding(.vertical, Space.m)
            } else {
                ForEach(library.openConversations) { conversation in
                    Button {
                        if let openConversation { openConversation(conversation.id) } else { Task { await library.open(conversation: conversation.id) } }
                    } label: {
                        VigieConversationRow(conversation: conversation, account: library.overview.accountLabel(conversation.accountID))
                    }
                    .buttonStyle(.row(radius: Radius.control, inset: Space.s))
                    .help(openConversation == nil ? "Ouvrir cette conversation dans VS Code" : "Voir où en est cette conversation")
                    .overlay(alignment: .bottom) { Rectangle().fill(Surface.stroke).frame(height: 1) }
                }
            }
            if library.closedCount > 0 {
                Text(Words.typeset(Words.count(library.closedCount, "conversation fermée", "conversations fermées") + " depuis deux jours."))
                    .font(.meta).foregroundStyle(.secondary).padding(.top, Space.s)
            }
        }
    }
}

/// A line of a part, as Notion's: what it is on the left, its gestures on the right, a line under it.
struct VigieLine<Content: View, Trailing: View>: View {
    @ViewBuilder var content: () -> Content
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.m) {
            content()
            Spacer(minLength: Space.m)
            HStack(spacing: Space.s) { trailing() }.fixedSize()
        }
        .padding(.vertical, Space.m)
        .overlay(alignment: .bottom) { Rectangle().fill(Surface.stroke).frame(height: 1) }
    }
}

/// The words of the « Vue d'ensemble » (pure, tested).
enum VigieWords {
    static let pageSubtitle = "Ce qui attend ta décision dans Claude Code, et où en est chaque conversation."
    static let autoAcceptHelp = "Vigie accepte seul les demandes sans risque de Claude Code ; les garde-fous retiennent les autres."

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

    /// The line under a card's title: the conversation, the rule that held the action, the agent that asked for it.
    static func context(_ review: VigieReview) -> String {
        [review.conversationTitle, review.rule, review.byAgent.map { "agent " + $0 }].compactMap { $0 }.filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    /// What Paul can take away once seen, as in the app Vigie: a refusal or a failure to do oneself, a limit, an account
    /// switched, a conversation started on another account. An account to connect again stays while the problem lasts.
    static func canDismiss(_ review: VigieReview) -> Bool {
        ["s:", "cf:", "b:", "l:"].contains { review.id.hasPrefix($0) }
    }

    /// What Claude chose for Paul, in his words.
    static func chosen(_ review: VigieReview) -> String {
        let chosen = review.question?.items.compactMap(\.chosenText) ?? []
        guard !chosen.isEmpty else { return review.detail ?? "" }
        return "Claude a pris « " + chosen.joined(separator: " » et « ") + " »"
    }

    /// The detail of what is only to see: the engine's, and for a limit, when it starts again.
    static func detail(_ review: VigieReview) -> String {
        [review.conversationTitle, review.detail].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// The button that answers what waits, by its kind.
    enum Gesture: Equatable {
        /// A sensitive action: « Autoriser » or « Refuser »; a sudo one goes to Terminal first.
        case decide(sudo: Bool)
        /// A question with its choices: « Répondre… ».
        case answer
        /// A plan, or a conversation that waits in VS Code: only VS Code answers it.
        case vsCode
    }

    static func gesture(_ review: VigieReview) -> Gesture {
        if review.isPendingDecision { return .decide(sudo: review.needsPassword) }
        if review.canAnswer { return .answer }
        return .vsCode
    }
}

/// One thing that waits for Paul's decision: what it is, where it comes from, and its gestures.
struct VigieDecisionCard: View {
    let review: VigieReview
    @ObservedObject var library: VigieLibrary
    let answer: () -> Void

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
                    TimelineView(.periodic(from: .now, by: 10)) { context in
                        Text(Words.typeset("refusée " + Words.until(expires, now: context.date))).font(.meta).foregroundStyle(Tint.attention)
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
                Text(Words.typeset("Une commande sudo demande ton mot de passe : le plus sûr est de la lancer toi-même dans Terminal."))
                    .font(.meta).foregroundStyle(.secondary)
            }
            HStack(spacing: Space.s) {
                if busy { ProgressView().controlSize(.small) }
                if review.command != nil, !review.commandIsMasked {
                    Button("Copier") { library.copy(review) }.buttonStyle(.secondary)
                }
                Spacer(minLength: 0)
                if let conversation = review.conversationID {
                    Button("Ouvrir dans VS Code") { Task { await library.open(conversation: conversation) } }
                        .buttonStyle(.secondary)
                        .disabled(library.sending.contains("ouvrir:" + conversation))
                }
                switch VigieWords.gesture(review) {
                case .decide(let sudo):
                    Button("Refuser") { Task { await library.decide(review, allow: false) } }.buttonStyle(.secondary).disabled(busy)
                    if sudo {
                        Button("Lancer dans Terminal") { Task { await library.runInTerminal(review) } }
                            .buttonStyle(.secondary).disabled(library.sending.contains("terminal:" + review.id))
                    }
                    Button("Autoriser") { Task { await library.decide(review, allow: true) } }.buttonStyle(.primary).disabled(busy)
                case .answer:
                    Button("Répondre…", action: answer).buttonStyle(.primary).disabled(busy)
                case .vsCode:
                    EmptyView()
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

/// « Répondre » to a question that waits, or « Changer » what Claude chose for Paul: each question with its options,
/// as Claude Code asks them.
struct VigieChoicesSheet: View {
    enum Mode {
        case answer, change
    }

    let review: VigieReview
    let items: [VigieQuestion.Item]
    let mode: Mode
    @ObservedObject var library: VigieLibrary
    @Environment(\.dismiss) private var dismiss
    @State private var picked: [Int: Set<String>] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            Text(mode == .answer ? "Répondre à Claude" : "Changer la réponse").font(.title2.weight(.bold))
            if let conversation = review.conversationTitle {
                Text(Words.typeset(conversation)).font(.meta).foregroundStyle(.secondary)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                        VStack(alignment: .leading, spacing: Space.s) {
                            if let header = item.header, !header.isEmpty {
                                Text(header).font(.tag.weight(.semibold)).foregroundStyle(.secondary)
                            }
                            Text(Words.typeset(item.question)).font(.headline).fixedSize(horizontal: false, vertical: true)
                            ForEach(item.options, id: \.self) { option in
                                choice(option, of: item, at: index)
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 420)
            if mode == .change {
                Text(Words.typeset("La correction est copiée et la conversation s'ouvre : colle-la, Claude reprend avec ton choix."))
                    .font(.meta).foregroundStyle(.secondary)
            }
            HStack {
                Button("Annuler") { dismiss() }.keyboardShortcut(.cancelAction).buttonStyle(.secondary)
                Spacer()
                Button(mode == .answer ? "Envoyer" : "Copier la correction") { send() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.primary)
                    .disabled(!complete || library.sending.contains(review.id))
            }
        }
        .padding(Space.xl)
        .frame(width: 560)
        .onAppear {
            // « Changer » starts from what Claude chose.
            guard mode == .change else { return }
            for (index, item) in items.enumerated() { picked[index] = Set(item.chosen) }
        }
    }

    private func choice(_ option: VigieQuestion.Option, of item: VigieQuestion.Item, at index: Int) -> some View {
        let on = picked[index]?.contains(option.label) ?? false
        return Button {
            var set = picked[index] ?? []
            if item.multiSelect {
                if on { set.remove(option.label) } else { set.insert(option.label) }
            } else {
                set = [option.label]
            }
            picked[index] = set
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                Image(systemName: item.multiSelect ? (on ? "checkmark.square.fill" : "square") : (on ? "largecircle.fill.circle" : "circle"))
                    .foregroundStyle(on ? AnyShapeStyle(Tint.accent) : AnyShapeStyle(.secondary))
                VStack(alignment: .leading, spacing: 2) {
                    Text(Words.typeset(option.label)).font(.rowBody)
                    if let description = option.description, !description.isEmpty {
                        Text(Words.typeset(description)).font(.meta).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(Space.s)
            .background(on ? Surface.selected : Color.clear, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Every question has its answer.
    private var complete: Bool {
        items.indices.allSatisfy { !(picked[$0] ?? []).isEmpty }
    }

    /// One answer per question, several joined as Claude Code writes them.
    private var answers: [String: String] {
        var answers: [String: String] = [:]
        for (index, item) in items.enumerated() {
            let labels = item.options.map(\.label).filter { picked[index]?.contains($0) ?? false }
            answers[item.question] = labels.joined(separator: ", ")
        }
        return answers
    }

    private func send() {
        let answers = answers
        Task {
            let done = mode == .answer ? await library.answer(review, answers: answers) : await library.change(review, answers: answers)
            if done { dismiss() }
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
        .padding(.vertical, Space.s)
        .contentShape(Rectangle())
    }
}
