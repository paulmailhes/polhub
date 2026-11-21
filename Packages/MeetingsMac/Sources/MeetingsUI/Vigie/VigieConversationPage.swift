import AppKit
import HubDesign
import SwiftUI
import VigieKit

/// A conversation of Claude Code, in Vigie (21/11, the migration's « page d'une conversation »), as a Notion page: what
/// it does now and its plan, what waits for Paul's decision in it, his request, its last messages, its agents at work,
/// its tests, its files, the decisions Vigie took for it, its pages published. In the toolbar: back to the « Vue
/// d'ensemble », VS Code, its account (another one when a limit falls), its own auto-accept.
struct VigieConversationPage: View {
    @ObservedObject var library: VigieLibrary
    @ObservedObject var router: WindowRouter
    let id: String
    @State private var switching: VigieAccount?

    var body: some View {
        let summary = library.detail?.summary ?? library.overview.conversations.first { $0.id == id }
        Page(maxWidth: PageMetrics.readingWidth, spacing: Space.xxl) {
            header(summary)
            messages
            if library.detailGone {
                Banner(.information, "Vigie n'en garde plus le détail", detail: "Une conversation fermée depuis plus de deux jours : ouvre-la dans VS Code.")
            }
            let decisions = library.decisions.filter { $0.conversationID == id }
            if !decisions.isEmpty {
                VStack(alignment: .leading, spacing: Space.m) {
                    PartTitle("À décider · \(decisions.count)")
                    ForEach(decisions) { review in
                        VigieDecisionCard(review: review, library: library) {}
                    }
                }
            }
            if let detail = library.detail {
                now(detail)
                request(detail)
                lastMessages(detail)
                work(detail)
                tests(detail)
                files(detail)
                published(detail)
                journal(detail)
            } else if !library.detailGone {
                HStack(spacing: Space.s) {
                    ProgressView().controlSize(.small)
                    Text("hub lit la conversation…").foregroundStyle(.secondary)
                }
            }
        }
        .belowToolbar()
        .toolbar { toolbar(summary) }
        .confirmationDialog(switching.map { "Passer sur \($0.label) ?" } ?? "", isPresented: Binding(get: { switching != nil }, set: { if !$0 { switching = nil } }),
                            titleVisibility: .visible, presenting: switching) { account in
            Button("À la fin de son tour") { Task { await library.switchAccount(id, to: account.id, now: false) } }
            Button("Tout de suite") { Task { await library.switchAccount(id, to: account.id, now: true) } }
            Button("Annuler", role: .cancel) {}
        } message: { _ in
            Text(Words.typeset(VigieWords.switchHelp))
        }
        .windowTitle("Vigie", subtitle: summary?.title ?? "Conversation")
        .onAppear {
            library.isVisible = true
            library.watch(conversation: id)
        }
        .onChange(of: id) { _, new in library.watch(conversation: new) }
        .onDisappear {
            library.isVisible = false
            library.stopWatching()
        }
        .onExitCommand { router.close() }
    }

    // MARK: - Parts

    private func header(_ summary: VigieConversation?) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(Words.typeset(summary?.title.isEmpty == false ? summary!.title : "Conversation"))
                .font(.pageTitle)
                .fixedSize(horizontal: false, vertical: true)
            let line = [summary.map(VigieWords.status), summary?.project, library.detail?.branch,
                        library.overview.accountLabel(summary?.accountID)].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
            if !line.isEmpty {
                Text(Words.typeset(line)).font(.pageSubtitle)
                    .foregroundStyle(summary.map(VigieWords.needsPaul) == true ? AnyShapeStyle(Tint.attention) : AnyShapeStyle(.secondary))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var messages: some View {
        if let problem = library.problem {
            Banner(.attention, problem) { Button("OK") { library.problem = nil } }
        }
        if let info = library.info {
            Banner(.information, info) { Button("OK") { library.info = nil } }
        }
    }

    /// Where it is: Claude's last report, the plan and its step, the tasks.
    @ViewBuilder private func now(_ detail: VigieConversationDetail) -> some View {
        let text = detail.current?.brief ?? detail.now?.text
        let plan = detail.now?.plan
        let tasks = detail.now?.tasks ?? []
        if text != nil || plan != nil || !tasks.isEmpty {
            VStack(alignment: .leading, spacing: Space.m) {
                PartTitle("Où elle en est")
                if let text, !text.isEmpty {
                    Text(Words.typeset(text)).font(.rowBody).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                }
                if let plan, plan.total > 0 {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        HStack {
                            Text(Words.typeset(plan.title ?? "Plan")).font(.meta.weight(.semibold))
                            Spacer()
                            Text("\(plan.done) sur \(plan.total)").font(.meta.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        ProgressView(value: Double(plan.done), total: Double(plan.total)).tint(Color(hex: Palette.cyan))
                        if let step = VigieWords.currentStep(plan) {
                            Text(Words.typeset("En cours : " + step)).font(.meta).foregroundStyle(.secondary)
                        }
                    }
                } else if !tasks.isEmpty {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        ForEach(Array(tasks.prefix(8).enumerated()), id: \.offset) { _, task in
                            Label(Words.typeset(task.text), systemImage: VigieWords.stepSymbol(task.status))
                                .font(.rowBody)
                                .foregroundStyle(task.status == "done" ? .secondary : .primary)
                        }
                    }
                }
            }
        }
    }

    /// Paul's request, and what it gave.
    @ViewBuilder private func request(_ detail: VigieConversationDetail) -> some View {
        if let request = detail.request, !request.isEmpty {
            VStack(alignment: .leading, spacing: Space.m) {
                PartTitle("Ta demande")
                Text(Words.typeset(request))
                    .font(.rowBody)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .padding(Space.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardSurface(radius: Radius.inner)
                if let outcome = detail.chapters.first?.outcome, !outcome.isEmpty, detail.current == nil {
                    Text(Words.typeset(outcome)).font(.rowBody).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// Claude's three last messages, the newest first: what it asks Paul, and what it leaves him.
    @ViewBuilder private func lastMessages(_ detail: VigieConversationDetail) -> some View {
        let last = Array(detail.messages.suffix(3).reversed())
        if !last.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                PartTitle("Ses derniers messages")
                ForEach(Array(last.enumerated()), id: \.offset) { _, message in
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text(Words.typeset(message.brief ?? message.text)).font(.rowBody).lineLimit(8).textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        if let ask = message.ask, !ask.isEmpty {
                            Text(Words.typeset("Elle te demande : " + ask)).font(.meta.weight(.medium)).foregroundStyle(Tint.attention)
                        }
                        if let toYou = message.toYou, !toYou.isEmpty {
                            Text(Words.typeset("À toi : " + toYou)).font(.meta.weight(.medium))
                        }
                        if let at = message.at {
                            Text(Words.moment(at, now: Date())).font(.tag).foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.vertical, Space.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .bottom) { Rectangle().fill(Surface.stroke).frame(height: 1) }
                }
            }
        }
    }

    /// The agents and workflows at work now.
    @ViewBuilder private func work(_ detail: VigieConversationDetail) -> some View {
        let running = detail.running
        let workflows = detail.workflows.filter { $0.status == "running" }
        if !running.isEmpty || !workflows.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                PartTitle("Au travail · \(running.count + workflows.count)")
                ForEach(Array(workflows.enumerated()), id: \.offset) { _, workflow in
                    VigieLine {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Words.typeset("Workflow " + workflow.name)).font(.rowTitle)
                            Text(Words.typeset([workflow.summary, Words.count(workflow.agents, "agent")].compactMap { $0 }.joined(separator: " · ")))
                                .font(.meta).foregroundStyle(.secondary).lineLimit(2)
                        }
                    } trailing: {
                        EmptyView()
                    }
                }
                ForEach(running) { agent in
                    VigieLine {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Words.typeset(agent.title)).font(.rowTitle).lineLimit(1)
                            let line = [agent.workflow, agent.phase, agent.lastAction].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
                            if !line.isEmpty { Text(Words.typeset(line)).font(.meta).foregroundStyle(.secondary).lineLimit(1) }
                        }
                    } trailing: {
                        if let duration = agent.duration { Text(Words.duration(Int(duration))).font(.meta).foregroundStyle(.secondary) }
                    }
                }
            }
        }
    }

    /// Its tests: those that failed lately first, then the last result.
    @ViewBuilder private func tests(_ detail: VigieConversationDetail) -> some View {
        let shown = Array((detail.failing + detail.tests.filter { $0.ok != false || $0.expectedFail }).prefix(5))
        if !shown.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                PartTitle(detail.failing.isEmpty ? "Tests" : "Tests · \(detail.failing.count) en échec")
                ForEach(Array(shown.enumerated()), id: \.offset) { _, test in
                    VigieLine {
                        Label {
                            Text(Words.typeset(test.title)).font(.rowBody).lineLimit(1)
                        } icon: {
                            Image(systemName: VigieWords.testSymbol(test)).foregroundStyle(VigieWords.testColor(test))
                        }
                    } trailing: {
                        Text(VigieWords.testCounts(test)).font(.meta).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    /// The files it wrote, the latest first.
    @ViewBuilder private func files(_ detail: VigieConversationDetail) -> some View {
        if !detail.files.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                PartTitle("Fichiers · \(detail.files.count)")
                ForEach(Array(detail.files.prefix(10).enumerated()), id: \.offset) { _, file in
                    VigieLine {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(file.name).font(.rowBody).lineLimit(1)
                            Text(Words.typeset([file.created ? "créé" : "modifié", file.by.map { "par " + $0 }].compactMap { $0 }.joined(separator: " · ")))
                                .font(.tag).foregroundStyle(.secondary)
                        }
                    } trailing: {
                        Button("Montrer") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: file.path)]) }
                            .buttonStyle(.secondary)
                            .help("Montrer le fichier dans le Finder")
                    }
                }
            }
        }
    }

    /// Its pages published: only an address of the web opens.
    @ViewBuilder private func published(_ detail: VigieConversationDetail) -> some View {
        let pages = detail.artifacts.filter { VigieWords.webAddress($0.url) != nil }
        if !pages.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                PartTitle("Pages publiées")
                ForEach(Array(pages.enumerated()), id: \.offset) { _, page in
                    VigieLine {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Words.typeset(page.title)).font(.rowBody)
                            if let description = page.description, !description.isEmpty {
                                Text(Words.typeset(description)).font(.meta).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                    } trailing: {
                        if let url = VigieWords.webAddress(page.url) {
                            Button("Ouvrir") { NSWorkspace.shared.open(url) }.buttonStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    /// What Vigie decided for it, the latest first.
    @ViewBuilder private func journal(_ detail: VigieConversationDetail) -> some View {
        if !detail.accepted.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                PartTitle("Ce que Vigie a décidé")
                ForEach(Array(detail.accepted.prefix(15).enumerated()), id: \.offset) { _, decision in
                    VigieLine {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Words.typeset(decision.title)).font(.rowBody).lineLimit(1)
                            if let detail = decision.detail, !detail.isEmpty {
                                Text(detail).font(.meta.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                    } trailing: {
                        Text(VigieWords.decision(decision.decision)).font(.meta).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private func toolbar(_ summary: VigieConversation?) -> some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button { router.close() } label: { Label("Vigie", systemImage: "chevron.left") }
                .help(router.returnHelp)
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Menu {
                ForEach(library.freeAccounts(excluding: summary?.accountID)) { account in
                    Button(account.label) { switching = account }
                }
            } label: {
                Text("Compte : " + (library.overview.accountLabel(summary?.accountID) ?? "—"))
            }
            .disabled(library.freeAccounts(excluding: summary?.accountID).isEmpty)
            .help("Passer cette conversation sur un autre compte")
            Menu {
                Button("Comme le réglage général") { Task { await library.setAutoAccept(id, to: nil) } }
                Button("Toujours") { Task { await library.setAutoAccept(id, to: true) } }
                Button("Jamais") { Task { await library.setAutoAccept(id, to: false) } }
            } label: {
                Text(VigieWords.autoAccept(library.detail))
            }
            .help("L'auto-accept de cette conversation seule")
            Button("Ouvrir dans VS Code") { Task { await library.open(conversation: id) } }
                .disabled(library.sending.contains("ouvrir:" + id))
        }
    }
}

extension VigieWords {
    static let switchHelp = "À la fin de son tour, rien ne s'interrompt. Tout de suite, elle s'arrête : écris-lui un message dans VS Code pour qu'elle reprenne sur ce compte."

    /// The step under way, by its id or its words.
    static func currentStep(_ plan: VigieConversationDetail.Now.Plan) -> String? {
        if let current = plan.current, let step = plan.steps.first(where: { $0.id == current }) {
            return [step.id, step.text].compactMap { $0 }.joined(separator: " ")
        }
        return plan.current ?? plan.steps.first { $0.status == "doing" }?.text
    }

    static func stepSymbol(_ status: String) -> String {
        switch status {
        case "done": "checkmark.circle.fill"
        case "doing": "circle.dotted.circle"
        default: "circle"
        }
    }

    static func testSymbol(_ test: VigieConversationDetail.TestRun) -> String {
        if test.expectedFail { return "circle.slash" }
        return switch test.ok {
        case true?: "checkmark.circle.fill"
        case false?: "xmark.circle.fill"
        case nil: "circle.dotted"
        }
    }

    static func testColor(_ test: VigieConversationDetail.TestRun) -> AnyShapeStyle {
        if test.expectedFail || test.ok == nil { return AnyShapeStyle(.secondary) }
        return test.ok == true ? AnyShapeStyle(Tint.done) : AnyShapeStyle(Tint.late)
    }

    /// « 245 réussis · 3 en échec ».
    static func testCounts(_ test: VigieConversationDetail.TestRun) -> String {
        guard test.ok != nil else { return "en cours" }
        var parts: [String] = []
        if let passed = test.passed { parts.append(Words.count(passed, "réussi")) }
        if let failed = test.failed, failed > 0 { parts.append("\(failed) en échec") }
        return parts.joined(separator: " · ")
    }

    /// Who decided: Vigie alone, Paul, a safeguard.
    static func decision(_ decision: String) -> String {
        switch decision {
        case "auto": "accepté seul"
        case "you": "par toi"
        case "blocked": "retenu"
        case "waiting": "attend"
        case "denied": "refusé"
        default: decision
        }
    }

    static func autoAccept(_ detail: VigieConversationDetail?) -> String {
        guard let detail else { return "Auto-accept" }
        switch detail.autoAcceptOverride {
        case true?: return "Auto-accept : toujours"
        case false?: return "Auto-accept : jamais"
        case nil: return "Auto-accept : " + (detail.autoAccept ? "oui" : "non")
        }
    }

    /// An address an agent wrote, opened only when it is of the web.
    static func webAddress(_ text: String?) -> URL? {
        guard let text, let url = URL(string: text), let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else { return nil }
        return url
    }
}
