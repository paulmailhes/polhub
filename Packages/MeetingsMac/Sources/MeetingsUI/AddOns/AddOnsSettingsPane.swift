import Domain
import HubDesign
import SwiftUI

/// Réglages › Add-ons (20/11; in tiles on 21/11, Paul: « faire des tuiles où on les explique ») : what hub can do, one
/// tile each — what it does, what it needs (done or not, with the button that settles it), and « Installer ». Every
/// installation or removal asks first: it relaunches hub, and says who comes with it or goes with it. The guide « ce
/// qu'il leur faut » and the Bienvenue open over this page.
struct AddOnsSettingsPane: View {
    @ObservedObject var control: AddOnControl
    @State private var asking: Question?

    struct Question: Identifiable {
        let addOn: AddOn
        let installing: Bool
        let message: String
        var id: String { addOn.rawValue + (installing ? "+" : "-") }
        var title: String { "\(installing ? "Installer" : "Désinstaller") \(addOn.title) ?" }
    }

    /// The add-ons two by two, as the grid shows them.
    static let rows: [[AddOn]] = stride(from: 0, to: AddOn.allCases.count, by: 2).map { Array(AddOn.allCases[$0..<min($0 + 2, AddOn.allCases.count)]) }

    var body: some View {
        Page(maxWidth: PageMetrics.readingWidth, spacing: PageMetrics.cardGap) {
            HStack(alignment: .firstTextBaseline, spacing: Space.l) {
                Text(Words.typeset(AddOnTexts.choose)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Space.m)
                Button(AddOnTexts.welcomeAgain) { control.showsWelcome = true }
                    .buttonStyle(.secondary)
                    .fixedSize()
            }
            // What an add-on needs changes outside hub (an authorization given in Réglages Système): read again.
            TimelineView(.periodic(from: .now, by: 1.5)) { _ in
                Grid(horizontalSpacing: PageMetrics.cardGap, verticalSpacing: PageMetrics.cardGap) {
                    ForEach(Self.rows, id: \.self) { row in
                        GridRow {
                            ForEach(row, id: \.self) { addOn in
                                AddOnTile(addOn: addOn, control: control) { ask(addOn, installing: $0) }
                            }
                        }
                    }
                }
            }
            if let problem = control.problem { ErrorLine(problem) }
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(Words.typeset(AddOnTexts.keepsData))
                Text(Words.typeset(AddOnTexts.permissions))
            }
            .font(.meta)
            .foregroundStyle(.secondary)
        }
        .confirmationDialog(asking?.title ?? "", isPresented: Binding(get: { asking != nil }, set: { if !$0 { asking = nil } }),
                            titleVisibility: .visible, presenting: asking) { question in
            Button(question.installing ? "Installer" : "Désinstaller", role: question.installing ? nil : .destructive) {
                Task { question.installing ? await control.install(question.addOn) : await control.uninstall(question.addOn) }
            }
            Button("Annuler", role: .cancel) {}
        } message: { question in
            Text(Words.typeset(question.message))
        }
        .sheet(isPresented: $control.showsWelcome) { WelcomeSheet(control: control) }
        .sheet(isPresented: $control.showsGuide) { AddOnGuideSheet(control: control) }
    }

    private func ask(_ addOn: AddOn, installing: Bool) {
        var parts: [String?]
        if installing {
            parts = [control.confirmation(installing: addOn), AddOnTexts.installing]
        } else {
            parts = [control.confirmation(uninstalling: addOn), AddOnTexts.takingModel(addOn, installed: control.installed),
                     AddOnTexts.keepsData, AddOnTexts.removing]
        }
        asking = Question(addOn: addOn, installing: installing, message: parts.compactMap { $0 }.joined(separator: " "))
    }
}

extension AddOn {
    /// Its family in Réglages: its icon, its color, its own settings.
    var pane: SettingsPane {
        switch self {
        case .projects: .projects
        case .meetings: .meetings
        case .dictation: .dictation
        case .calendar: .calendar
        case .mails: .mails
        case .inspiration: .inspiration
        case .colin: .colin
        case .iphone: .iphone
        }
    }
}

/// An add-on's icon in its colored square, as its family in Réglages.
struct AddOnBadge: View {
    let addOn: AddOn
    var side: CGFloat = 32

    var body: some View {
        Image(systemName: addOn.pane.icon)
            .font(.rowTitle.weight(.semibold))
            .foregroundStyle(.white)
            .frame(width: side, height: side)
            .background(Color(hex: addOn.pane.tint), in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            .accessibilityHidden(true)
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

/// Where an add-on is, beside its name.
struct AddOnStateLabel: View {
    let state: AddOnState

    var body: some View {
        switch state {
        case .notInstalled:
            EmptyView()
        case .ready:
            Label(state.text, systemImage: "checkmark.circle.fill").font(.meta).foregroundStyle(Tint.done)
        case .missing:
            Label(state.text, systemImage: "exclamationmark.circle.fill").font(.meta).foregroundStyle(Tint.attention)
        }
    }
}

/// One add-on: its name, what it does, what it needs, and its gesture.
struct AddOnTile: View {
    let addOn: AddOn
    @ObservedObject var control: AddOnControl
    /// Installs (true) or removes (false), after the question.
    let ask: (Bool) -> Void

    var body: some View {
        let installed = control.installed.contains(addOn)
        let needs = control.needs(addOn)
        let state = AddOnNeeds.state(installed: installed, needs: needs)
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(spacing: Space.m) {
                AddOnBadge(addOn: addOn)
                Text(addOn.title).font(.headline)
                Spacer(minLength: Space.s)
                AddOnStateLabel(state: state)
            }
            Text(Words.typeset(AddOnTexts.pitch(addOn)))
                .font(.rowBody)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            // What it needs, done or not — before it is installed too: Paul sees what installing will ask.
            if needs.isEmpty {
                Text(Words.typeset(AddOnTexts.nothingNeeded)).font(.meta).foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: Space.xs) {
                    ForEach(needs) { AddOnNeedLine(need: $0) }
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: Space.s) {
                gesture(installed: installed, needs: needs)
                Spacer(minLength: 0)
                if installed, control.working != addOn {
                    Menu {
                        Button("Ses réglages") { control.openSettings(addOn) }
                        Button("Désinstaller", role: .destructive) { ask(false) }
                    } label: {
                        Label("Plus", systemImage: "ellipsis").labelStyle(.iconOnly)
                    }
                    .menuStyle(.button).menuIndicator(.hidden).buttonStyle(.borderless).fixedSize()
                    .help("Ses réglages, ou le désinstaller")
                }
            }
        }
        .padding(PageMetrics.cardPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .cardSurface()
    }

    @ViewBuilder private func gesture(installed: Bool, needs: [AddOnNeed]) -> some View {
        let blocked = addOn == .colin && !control.claudeFound && !installed
        if control.working == addOn {
            if let progress = control.progress {
                ProgressView(value: progress).frame(width: 120)
            } else {
                ProgressView().controlSize(.small)
            }
        } else if !installed {
            // Colin without Claude Code: its first line says why.
            Button("Installer") { ask(true) }
                .buttonStyle(.secondary)
                .disabled(blocked || control.working != nil)
        } else if let next = AddOnNeeds.next(needs), let button = next.button {
            Button(button) { control.settle(next) }.buttonStyle(.secondary)
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
                                    AddOnBadge(addOn: addOn, side: 24)
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
/// again from Réglages › Add-ons, it only adds: nothing installed is removed here.
struct WelcomeSheet: View {
    @ObservedObject var control: AddOnControl
    @State private var step: Int
    @State private var chosen: Set<AddOn>

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
        .frame(width: 620)
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
                ForEach(AddOnsSettingsPane.rows, id: \.self) { row in
                    GridRow {
                        ForEach(row, id: \.self) { addOn in
                            WelcomeChoice(addOn: addOn, installed: control.installed.contains(addOn), chosen: chosen.contains(addOn),
                                          blocked: addOn == .colin && !control.claudeFound) { toggle(addOn) }
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

/// One tool to choose in the Bienvenue.
struct WelcomeChoice: View {
    let addOn: AddOn
    let installed: Bool
    let chosen: Bool
    let blocked: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(alignment: .top, spacing: Space.m) {
                AddOnBadge(addOn: addOn)
                VStack(alignment: .leading, spacing: 2) {
                    Text(addOn.title).font(.rowTitle.weight(.medium))
                    Text(Words.typeset(blocked ? AddOnTexts.needsClaude : AddOnTexts.summary(addOn)))
                        .font(.meta).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
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
