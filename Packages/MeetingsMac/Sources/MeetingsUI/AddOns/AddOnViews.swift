import Domain
import HubDesign
import SwiftUI

// The add-ons on Réglages' home (21/11, Paul: « les logos d'add-on, ce n'est même pas les mêmes logos qu'il y a dans la
// barre sur la gauche… les icônes un peu plus gros… avec une petite description, les outils qui sont nécessaires…
// rendre le truc utilisable pour des utilisateurs un peu lambda »). One line each, as Notion's: its badge — the same as
// in the sidebar —, its name, what it does, what it needs on soft tags, and its gesture. The tiles of 0.65.0 said the
// same things a second time on another page: they are gone. Every installation or removal asks first: it relaunches
// hub, and says who comes with it or goes with it.

extension AddOn {
    /// Its own page of Réglages.
    var settings: SettingsPane? {
        switch self {
        case .projects: .projects
        case .meetings: .meetings
        case .dictation: .dictation
        case .calendar: .calendar
        case .mails: .mails
        case .inspiration: .inspiration
        case .colin: .colin
        case .vigie: .vigie
        case .iphone: .iphone
        }
    }

    /// Its glyph: the sidebar's, for the tools that have a section there.
    var appIcon: AppIcon {
        switch self {
        case .projects: .projects
        case .meetings: .meetings
        case .dictation: .dictation
        case .calendar: .calendar
        case .mails: .mails
        case .inspiration: .inspiration
        case .colin: .colin
        case .vigie: .vigie
        case .iphone: .iphone
        }
    }

    /// Its place in the sidebar, where the window opens once it is installed; Colin lives on the Accueil.
    public var section: SidebarItem? {
        switch self {
        case .projects: .projects
        case .meetings: .meetings
        case .dictation: .dictation
        case .calendar: .calendar
        case .mails: .mails
        case .inspiration: .inspiration
        case .vigie: .vigie
        case .colin: .home
        case .iphone: nil
        }
    }

    /// Its color, as its section in the sidebar and its family in Réglages.
    var tint: String { settings?.tint ?? SidebarItem.vigie.tint }
}

/// An add-on's mark: its badge, as everywhere.
struct AddOnBadge: View {
    let addOn: AddOn
    var size: ToolBadge.Size = .row
    var muted = false

    var body: some View {
        ToolBadge(addOn.appIcon, color: addOn.tint, size: size, muted: muted)
    }
}

extension AddOnNeed {
    /// Its words on a tag: short, the same for every tool that needs it (Paul: « connexion Google »).
    var tag: String {
        switch id {
        case "modele": "Modèle de transcription"
        case "micro": "Micro"
        case "reunions": "Son des autres et Dia"
        case "accessibilite": "Accessibilité"
        case "google": "Connexion Google"
        case "boite": "Accès aux mails"
        case "claude": "Claude Code"
        case "marche": "Colin en marche"
        case "moteur": "Moteur de Vigie"
        case "moteur-marche": "Moteur en marche"
        case "icloud": "iCloud"
        case "relie": "iPhone relié"
        default: title
        }
    }

    var appIcon: AppIcon {
        switch id {
        case "modele": .download
        case "micro": .meetings
        case "reunions": .dictation
        case "accessibilite": .accessibility
        case "google": .google
        case "boite": .mails
        case "claude": .terminal
        case "marche": .colin
        case "moteur", "moteur-marche": .vigie
        case "icloud": .cloud
        case "relie": .iphone
        default: .checked
        }
    }
}

/// What an add-on needs, on its tags: done or missing once it is installed, with the button that settles what is
/// missing; before, what installing it will ask.
struct AddOnTags: View {
    let needs: [AddOnNeed]
    let installed: Bool
    let settle: (AddOnNeed) -> Void

    var body: some View {
        FlowLayout(spacing: Space.s) {
            ForEach(needs) { need in
                HStack(spacing: Space.xs) {
                    NeedTag(need.tag, icon: need.appIcon, kind: Self.kind(need, installed: installed))
                        .help(Words.typeset(need.note ?? need.title))
                    if installed, let button = need.button {
                        Button(button) { settle(need) }
                            .buttonStyle(.secondary)
                            .controlSize(.small)
                            .fixedSize()
                    }
                }
            }
        }
    }
}

extension AddOnTags {
    /// What is there already shows its check, installed or not; what is missing is said in the color of attention once
    /// the tool is installed — or before, when it keeps it from being installed (Colin without Claude Code).
    static func kind(_ need: AddOnNeed, installed: Bool) -> NeedTag.Kind {
        if need.done { return .done }
        return installed || need.id == "claude" ? .missing : .planned
    }
}

/// Installing or removing an add-on: the question asked first.
struct AddOnQuestion: Identifiable {
    let addOn: AddOn
    let installing: Bool
    let message: String
    var id: String { addOn.rawValue + (installing ? "+" : "-") }
    var title: String { "\(installing ? "Installer" : "Désinstaller") \(addOn.title) ?" }
}

extension AddOnControl {
    /// What installing or removing `addOn` brings or takes with it, and that hub relaunches.
    func question(_ addOn: AddOn, installing: Bool) -> AddOnQuestion {
        let parts: [String?] = installing
            ? [confirmation(installing: addOn), AddOnTexts.installing]
            : [confirmation(uninstalling: addOn), AddOnTexts.takingModel(addOn, installed: installed), AddOnTexts.keepsData, AddOnTexts.removing]
        return AddOnQuestion(addOn: addOn, installing: installing, message: parts.compactMap { $0 }.joined(separator: " "))
    }
}

/// One add-on on Réglages' home. Installed: a click opens its settings (when it has some); « … » removes it. Not
/// installed: greyed, with « Installer ».
struct AddOnLine: View {
    let addOn: AddOn
    @ObservedObject var control: AddOnControl
    /// Its page of Réglages, when it opens here.
    let page: SettingsPane?
    let open: (SettingsPane) -> Void
    let ask: (AddOnQuestion) -> Void

    var body: some View {
        let installed = control.installed.contains(addOn)
        AddOnLineLayout(addOn: addOn, installed: installed, opens: page != nil && installed, needs: control.needs(addOn),
                        settle: control.settle, open: { if let page { open(page) } }) {
            trailing(installed: installed)
        }
    }

    @ViewBuilder private func trailing(installed: Bool) -> some View {
        if control.working == addOn {
            if let progress = control.progress {
                ProgressView(value: progress).frame(width: 120)
            } else {
                ProgressView().controlSize(.small)
            }
        } else if !installed {
            // Colin without Claude Code: its tag says why.
            Button("Installer") { ask(control.question(addOn, installing: true)) }
                .buttonStyle(.secondary)
                .disabled((addOn == .colin && !control.claudeFound) || control.working != nil)
        } else {
            Menu {
                Button("Désinstaller \(addOn.title)…", role: .destructive) { ask(control.question(addOn, installing: false)) }
            } label: {
                Label("Plus", systemImage: "ellipsis").labelStyle(.iconOnly)
            }
            .menuStyle(.button).menuIndicator(.hidden).buttonStyle(.borderless).fixedSize()
            .disabled(control.working != nil)
            .help("Désinstaller \(addOn.title)")
        }
    }
}

/// The line itself, drawn the same with or without the control (a capture of Réglages without add-ons to install).
struct AddOnLineLayout<Trailing: View>: View {
    let addOn: AddOn
    let installed: Bool
    let opens: Bool
    let needs: [AddOnNeed]
    let settle: (AddOnNeed) -> Void
    let open: () -> Void
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(alignment: .center, spacing: Space.s) {
                if opens {
                    Button(action: open) { main }
                        .buttonStyle(.row(radius: Radius.control, inset: Space.s))
                        .help("Ouvrir les réglages de \(addOn.title)")
                } else {
                    main
                }
                trailing()
            }
            if !needs.isEmpty {
                AddOnTags(needs: needs, installed: installed, settle: settle)
                    .padding(.leading, ToolBadge.Size.line.rawValue + Space.m)
            }
        }
        .padding(.vertical, Space.m)
        .overlay(alignment: .bottom) { Rectangle().fill(Surface.stroke).frame(height: 1) }
    }

    private var main: some View {
        HStack(spacing: Space.m) {
            AddOnBadge(addOn: addOn, size: .line, muted: !installed)
            VStack(alignment: .leading, spacing: 2) {
                Text(addOn.title).font(.rowTitle.weight(.semibold)).foregroundStyle(installed ? .primary : .secondary)
                Text(Words.typeset(AddOnTexts.pitch(addOn)))
                    .font(.meta)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Space.s)
            if opens {
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
    }
}

/// The Bienvenue and the guide, over Réglages: presented here so that the home, which observes nothing, opens them.
struct AddOnSheets: View {
    @ObservedObject var control: AddOnControl

    var body: some View {
        Color.clear
            .sheet(isPresented: $control.showsWelcome) { WelcomeSheet(control: control) }
            .sheet(isPresented: $control.showsGuide) { AddOnGuideSheet(control: control) }
    }
}

/// One need: done or not, and what to know when hub cannot do it.
struct AddOnNeedLine: View {
    let need: AddOnNeed

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s) {
            Image(systemName: need.done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(need.done ? AnyShapeStyle(Tint.done) : AnyShapeStyle(.secondary))
                .accessibilityLabel(need.done ? "Fait" : "À faire")
            VStack(alignment: .leading, spacing: 2) {
                Text(Words.typeset(need.title)).font(.meta)
                if let note = need.note {
                    Text(Words.typeset(note)).font(.tag).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// The guide « ce qu'il leur faut » (21/11): after an installation, what the new add-ons need, one line each with its
/// button; the Bienvenue's last step too.
struct AddOnGuideSheet: View {
    @ObservedObject var control: AddOnControl

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            VStack(alignment: .leading, spacing: Space.xs) {
                if control.guideIsWelcome { WelcomeStep(step: 3) }
                Text(AddOnTexts.guideTitle).font(.title2.weight(.bold))
            }
            TimelineView(.periodic(from: .now, by: 1.5)) { _ in
                let waiting = control.guide.filter { addOn in control.needs(addOn).contains { !$0.done } }
                if waiting.isEmpty {
                    Label(AddOnTexts.guideAllSet, systemImage: "checkmark.circle.fill").foregroundStyle(Tint.done)
                } else {
                    VStack(alignment: .leading, spacing: Space.l) {
                        ForEach(waiting, id: \.self) { addOn in
                            VStack(alignment: .leading, spacing: Space.s) {
                                HStack(spacing: Space.s) {
                                    AddOnBadge(addOn: addOn, size: .sidebar)
                                    Text(addOn.title).font(.headline)
                                }
                                ForEach(control.needs(addOn)) { need in
                                    HStack(alignment: .firstTextBaseline, spacing: Space.m) {
                                        AddOnNeedLine(need: need)
                                        Spacer(minLength: Space.s)
                                        if let button = need.button {
                                            Button(button) { control.settle(need) }.buttonStyle(.secondary).fixedSize()
                                        }
                                    }
                                }
                            }
                        }
                        Text(Words.typeset(AddOnTexts.guideLater)).font(.meta).foregroundStyle(.secondary)
                    }
                }
            }
            HStack {
                Spacer()
                Button(control.guideIsWelcome ? "C'est parti" : "Terminé") { control.showsGuide = false }
                    .buttonStyle(.primary)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Space.xl)
        .frame(width: 540)
    }
}

/// « 2 sur 3 », above a step of the Bienvenue.
struct WelcomeStep: View {
    let step: Int

    var body: some View {
        Text("\(step) sur 3").font(.tag.weight(.semibold)).foregroundStyle(.secondary)
    }
}

/// The Bienvenue (21/11, Paul: « que je puisse relancer l'onboarding pour voir à quoi il ressemble ») : hub in one
/// sentence, then the tools to choose, then — after the installation's relaunch — the guide of what they need. Seen
/// again from Réglages, it only adds: nothing installed is removed here.
struct WelcomeSheet: View {
    @ObservedObject var control: AddOnControl
    @State private var step: Int
    @State private var chosen: Set<AddOn>

    /// The add-ons two by two, as the grid shows them.
    static let rows: [[AddOn]] = stride(from: 0, to: AddOn.allCases.count, by: 2).map { Array(AddOn.allCases[$0..<min($0 + 2, AddOn.allCases.count)]) }

    /// `step`, `chosen`: where it opens, for the captures.
    init(control: AddOnControl, step: Int = 1, chosen: Set<AddOn> = []) {
        self.control = control
        _step = State(initialValue: step)
        _chosen = State(initialValue: chosen)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            WelcomeStep(step: step)
            if step == 1 { hello } else { choose }
        }
        .padding(Space.xl)
        .frame(width: 680)
    }

    private var hello: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
                .accessibilityHidden(true)
            Text(AddOnTexts.welcomeTitle).font(.largeTitle.weight(.bold))
            Text(Words.typeset(AddOnTexts.welcomeText)).font(.title3).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Plus tard") { control.showsWelcome = false }.buttonStyle(.secondary)
                Spacer()
                Button("Continuer") { step = 2 }.buttonStyle(.primary).keyboardShortcut(.defaultAction)
            }
        }
    }

    private var choose: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(AddOnTexts.welcomeChoose).font(.title2.weight(.bold))
                Text(Words.typeset(AddOnTexts.welcomeChooseHelp)).font(.meta).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Grid(horizontalSpacing: Space.m, verticalSpacing: Space.m) {
                ForEach(Self.rows, id: \.self) { row in
                    GridRow {
                        ForEach(row, id: \.self) { addOn in
                            WelcomeChoice(addOn: addOn, needs: control.needs(addOn), installed: control.installed.contains(addOn),
                                          chosen: chosen.contains(addOn), blocked: addOn == .colin && !control.claudeFound) { toggle(addOn) }
                        }
                    }
                }
            }
            if let problem = control.problem { ErrorLine(problem) }
            HStack(spacing: Space.m) {
                Button("Retour") { step = 1 }.buttonStyle(.secondary).disabled(control.working != nil)
                Spacer()
                if control.working != nil {
                    if let progress = control.progress {
                        ProgressView(value: progress).frame(width: 120)
                    } else {
                        ProgressView().controlSize(.small)
                    }
                }
                if chosen.isEmpty {
                    Button("Continuer") { finish() }.buttonStyle(.primary).keyboardShortcut(.defaultAction)
                } else {
                    Button("Installer et continuer") {
                        Task { await control.install(AddOn.allCases.filter(chosen.contains), welcome: true) }
                    }
                    .buttonStyle(.primary)
                    .keyboardShortcut(.defaultAction)
                    .disabled(control.working != nil)
                }
            }
        }
    }

    /// Choosing one brings what it needs; leaving one out leaves out what needs it. What is installed stays.
    private func toggle(_ addOn: AddOn) {
        if chosen.contains(addOn) {
            chosen = AddOns.uninstalling(addOn, from: chosen)
        } else {
            chosen = AddOns.installing(addOn, into: chosen.union(control.installed)).subtracting(control.installed)
        }
    }

    /// Nothing new to install: straight to what the installed ones need.
    private func finish() {
        control.showsWelcome = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { control.openGuideForInstalled() }
    }
}

/// One tool to choose in the Bienvenue: its badge, what it does, what it will ask for.
struct WelcomeChoice: View {
    let addOn: AddOn
    let needs: [AddOnNeed]
    let installed: Bool
    let chosen: Bool
    let blocked: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(alignment: .top, spacing: Space.m) {
                AddOnBadge(addOn: addOn, size: .line)
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(addOn.title).font(.rowTitle.weight(.semibold))
                    Text(Words.typeset(blocked ? AddOnTexts.needsClaude : AddOnTexts.summary(addOn)))
                        .font(.meta).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if !needs.isEmpty, !installed {
                        AddOnTags(needs: needs, installed: false) { _ in }
                    }
                }
                Spacer(minLength: Space.s)
                if installed {
                    Text("Installé").font(.tag).foregroundStyle(.secondary)
                } else {
                    Image(systemName: chosen ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(chosen ? AnyShapeStyle(Tint.accent) : AnyShapeStyle(.tertiary))
                        .accessibilityLabel(chosen ? "Choisi" : "Pas choisi")
                }
            }
            .padding(Space.m)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .cardSurface(radius: Radius.inner)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(installed || blocked)
    }
}
