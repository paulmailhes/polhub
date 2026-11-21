import HubDesign
import SwiftUI
import VigieKit

/// Vigie's pages, named as in the app Vigie (Paul, 21/11: « les mêmes que dans Vigie »), chosen in the toolbar.
public enum VigieSubpage: String, CaseIterable, Hashable, Sendable {
    case overview, accounts

    var title: String {
        switch self {
        case .overview: "Vue d'ensemble"
        case .accounts: "Comptes"
        }
    }
}

/// The pages of Vigie, in the toolbar's middle, as Inspiration's.
struct VigiePagePicker: View {
    @ObservedObject var router: WindowRouter

    var body: some View {
        Picker("Page", selection: $router.vigiePage) {
            ForEach(VigieSubpage.allCases, id: \.self) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        .fixedSize()
    }
}

/// « Comptes » (21/11, the migration's third step): each Claude account, its 5-hour session and its week (and the
/// week of a model) with when they start again and when the week would be full, its connection, the account of new
/// conversations; connect, read the usage again (a small real request: on a click only), add, remove. And VS Code's
/// launcher, without which a conversation's account is not kept.
struct VigieAccountsPage: View {
    @ObservedObject var library: VigieLibrary
    @ObservedObject var router: WindowRouter
    @State private var removing: VigieAccount?
    @State private var adding = false

    var body: some View {
        Page(maxWidth: PageMetrics.readingWidth, spacing: Space.xxl) {
            ToolHeader("Comptes", icon: .vigie, color: SidebarItem.vigie.tint, subtitle: VigieAccountsText.subtitle)
            if let problem = library.problem {
                Banner(.attention, problem) { Button("OK") { library.problem = nil } }
            }
            if let info = library.info {
                Banner(.information, info) { Button("OK") { library.info = nil } }
            }
            if let accounts = library.accounts {
                if !accounts.launcherActive {
                    Banner(.attention, "Le lanceur de comptes n'est pas actif dans VS Code", detail: VigieAccountsText.launcherHelp) {
                        Button("Activer") { Task { await library.setLauncher(true) } }
                            .disabled(library.sending.contains("lanceur"))
                    }
                }
                VStack(alignment: .leading, spacing: 0) {
                    PartTitle("Comptes Claude · \(accounts.accounts.count)") {
                        Button("Ajouter un compte…") { adding = true }.buttonStyle(.link).font(.meta)
                    }
                    ForEach(accounts.accounts) { account in
                        VigieAccountLine(account: account, isDefault: account.id == accounts.defaultForNew || account.isDefault,
                                         library: library) { removing = account }
                    }
                }
                Text(Words.typeset(VigieAccountsText.refreshNote)).font(.meta).foregroundStyle(.secondary)
            } else {
                HStack(spacing: Space.s) {
                    ProgressView().controlSize(.small)
                    Text("hub lit les comptes…").foregroundStyle(.secondary)
                }
            }
        }
        .belowToolbar()
        .toolbar {
            ToolbarItem(placement: .principal) { VigiePagePicker(router: router) }
        }
        .confirmationDialog(removing.map { "Retirer \($0.label) ?" } ?? "", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                            titleVisibility: .visible, presenting: removing) { account in
            Button("Retirer", role: .destructive) { Task { await library.removeAccount(account.id) } }
            Button("Annuler", role: .cancel) {}
        } message: { _ in
            Text(Words.typeset(VigieAccountsText.removeHelp))
        }
        .sheet(isPresented: $adding) { VigieNewAccountSheet(library: library) }
        .windowTitle("Vigie", subtitle: "Comptes")
        .onAppear {
            library.isVisible = true
            library.watchAccounts()
        }
        .onDisappear {
            library.isVisible = false
            library.stopWatchingAccounts()
        }
    }
}

/// One account: its name and address, its state, its gauges, its gestures.
struct VigieAccountLine: View {
    let account: VigieAccount
    let isDefault: Bool
    @ObservedObject var library: VigieLibrary
    let remove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                Text(Words.typeset(account.label)).font(.rowTitle.weight(.semibold))
                if isDefault { NeedTag("Nouvelles conversations", icon: nil, kind: .planned) }
                if account.needsConnecting {
                    NeedTag("À reconnecter", icon: nil, kind: .missing)
                } else if account.wrongAccount {
                    NeedTag("Mauvaise adresse", icon: nil, kind: .missing)
                } else if !account.sameAs.isEmpty {
                    NeedTag("En double", icon: nil, kind: .missing)
                }
                Spacer(minLength: Space.s)
                actions
            }
            if let email = account.email, !email.isEmpty {
                Text(email).font(.meta).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: Space.s) {
                VigieGauge(title: "Session de 5 h", window: account.session, now: Date(), fullAt: false)
                VigieGauge(title: "Semaine", window: account.week, now: Date(), fullAt: true)
                if let model = account.weekModel {
                    VigieGauge(title: "Semaine de " + (account.weekModelLabel ?? "son modèle"), window: model, now: Date(), fullAt: false)
                }
            }
            if let observed = account.observedAt {
                Text(Words.typeset("Relevé " + Words.ago(observed, now: Date()))).font(.tag).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, Space.l)
        .overlay(alignment: .bottom) { Rectangle().fill(Surface.stroke).frame(height: 1) }
    }

    @ViewBuilder private var actions: some View {
        HStack(spacing: Space.s) {
            Button(account.needsConnecting || !account.connected ? "Connecter" : "Reconnecter") {
                Task { await library.connectAccount(account.id) }
            }
            .buttonStyle(.secondary)
            .disabled(library.sending.contains("connexion:" + account.id))
            Button("Actualiser") { Task { await library.refreshUsage(account.id) } }
                .buttonStyle(.secondary)
                .disabled(library.sending.contains("relevé:" + account.id))
                .help("Relire sa consommation : une petite requête au modèle")
            Menu {
                if !isDefault {
                    Button("Pour les nouvelles conversations") { Task { await library.setDefaultAccount(account.id) } }
                }
                Button("Retirer…", role: .destructive, action: remove)
            } label: {
                Label("Plus", systemImage: "ellipsis").labelStyle(.iconOnly)
            }
            .menuStyle(.button).menuIndicator(.hidden).buttonStyle(.borderless).fixedSize()
        }
        .fixedSize()
    }
}

/// A gauge of an account: how much of a window is used, when it starts again, and when the week would be full.
struct VigieGauge: View {
    let title: String
    let window: VigieAccount.Window?
    let now: Date
    let fullAt: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack {
                Text(Words.typeset(title)).font(.meta)
                Spacer()
                Text(window.map { "\(Int($0.percent.rounded())) %" } ?? "—").font(.meta.monospacedDigit())
                    .foregroundStyle(VigieAccountsText.isTight(window) ? AnyShapeStyle(Tint.attention) : AnyShapeStyle(.secondary))
            }
            ProgressView(value: min(100, window?.percent ?? 0), total: 100)
                .tint(VigieAccountsText.isTight(window) ? Tint.attention : Color(hex: Palette.cyan))
            let line = VigieAccountsText.line(window, now: now, fullAt: fullAt)
            if !line.isEmpty { Text(Words.typeset(line)).font(.tag).foregroundStyle(.secondary) }
        }
    }
}

/// A new Claude account: its name, its address if known; then it is connected.
struct VigieNewAccountSheet: View {
    @ObservedObject var library: VigieLibrary
    @Environment(\.dismiss) private var dismiss
    @State private var label = ""
    @State private var email = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            Text("Ajouter un compte Claude").font(.title2.weight(.bold))
            TextField("Son nom (Travail 2, Perso…)", text: $label)
            TextField("Son adresse, si tu la connais", text: $email)
            Text(Words.typeset(VigieAccountsText.addHelp)).font(.meta).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Annuler") { dismiss() }.keyboardShortcut(.cancelAction).buttonStyle(.secondary)
                Spacer()
                Button("Ajouter et connecter") {
                    let label = label.trimmingCharacters(in: .whitespaces), email = email.trimmingCharacters(in: .whitespaces)
                    Task {
                        await library.createAccount(label: label, email: email)
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.primary)
                .disabled(label.trimmingCharacters(in: .whitespaces).isEmpty || library.sending.contains("nouveau-compte"))
            }
        }
        .textFieldStyle(.roundedBorder)
        .padding(Space.xl)
        .frame(width: 460)
    }
}

/// The words of « Comptes » (pure, tested).
enum VigieAccountsText {
    static let subtitle = "Tes comptes Claude, ce qu'ils ont consommé, et celui des nouvelles conversations."
    static let launcherHelp = "Sans lui, VS Code lance chaque conversation sur le compte du Mac, quel que soit celui choisi."
    static let refreshNote = "« Actualiser » envoie une petite requête au modèle sur ce compte, au plus une fois toutes les dix minutes ; Vigie relève seul les comptes qui ont travaillé."
    static let removeHelp = "Sa connexion est retirée de ce Mac et ses conversations passent sur le compte des nouvelles conversations. Le compte du Mac ne se retire pas."
    static let addHelp = "Le navigateur s'ouvre pour te connecter : connecte-toi avec ce compte-là, pas un autre."

    /// Past 90 %, the gauge takes the color of attention.
    static func isTight(_ window: VigieAccount.Window?) -> Bool {
        (window?.percent ?? 0) >= 90
    }

    /// « Remise à zéro demain à 20:00 · pleine vers jeudi à 14:00 »; nothing when the reading is too old (« — »).
    static func line(_ window: VigieAccount.Window?, now: Date, fullAt: Bool) -> String {
        guard let window else { return "Pas de relevé récent : « Actualiser » le relit." }
        var parts: [String] = []
        if let resets = window.resetsAt { parts.append("remise à zéro " + Words.day(resets, now: now) + " à " + Words.time(resets)) }
        if fullAt, let full = window.fullAt, full > now { parts.append("pleine vers " + Words.day(full, now: now) + " à " + Words.time(full)) }
        return Words.capitalizedFirst(parts.joined(separator: " · "))
    }
}
