import Domain
import Foundation

/// Réglages › Add-ons (20/11): installs and removes an add-on with those it brings or takes, never during a meeting, then
/// relaunches hub, which makes only what is installed. `prepare` gets an add-on ready before it is installed (the model of
/// Réunions, downloaded) and says why it could not; `cleanUp` takes away what an add-on downloaded once it is removed.
@MainActor public final class AddOnControl: ObservableObject {
    @Published public private(set) var installed: Set<AddOn>
    /// Why the last gesture did nothing; nil when it went through.
    @Published public private(set) var problem: String?
    /// The add-on being installed or removed, while hub gets it ready.
    @Published public private(set) var working: AddOn?
    /// How far its download went, 0 to 1, while it downloads (the model of Réunions).
    @Published public var progress: Double?
    /// Whether this Mac has Claude Code, which Colin needs: set by the app at launch.
    @Published public var claudeFound = true
    /// The guide « ce qu'il leur faut » (21/11): open, and for which add-ons — those just installed, after the relaunch.
    @Published public var showsGuide = false
    @Published public private(set) var guide: [AddOn] = []
    /// The guide is the Bienvenue's last step.
    @Published public private(set) var guideIsWelcome = false
    /// The Bienvenue: at the first launch, and when Paul asks to see it again.
    @Published public var showsWelcome = false

    /// What the Mac has, read by the app each time a tile asks.
    public var facts: () -> AddOnFacts = { AddOnFacts() }
    /// A need's button: the app does it.
    public var perform: (AddOnAction) -> Void = { _ in }
    /// « Ses réglages » on a tile.
    public var openSettings: (AddOn) -> Void = { _ in }

    let store: AddOnStore
    let isBusy: () async -> Bool
    let relaunch: () -> Void
    let prepare: (AddOn) async -> String?
    let cleanUp: (AddOn) -> Void

    public init(store: AddOnStore, isBusy: @escaping () async -> Bool, relaunch: @escaping () -> Void,
                prepare: @escaping (AddOn) async -> String? = { _ in nil }, cleanUp: @escaping (AddOn) -> Void = { _ in }) {
        self.store = store
        self.isBusy = isBusy
        self.relaunch = relaunch
        self.prepare = prepare
        self.cleanUp = cleanUp
        installed = store.installed
    }

    /// The sentence that asks first, when others come with it; nil when it comes alone.
    public func confirmation(installing addOn: AddOn) -> String? {
        // In the order of what it needs: « Colin a besoin de Mails et de Calendrier ».
        let coming = Set(AddOns.added(by: addOn, to: installed))
        var order: [AddOn] = []
        var waiting = addOn.requires
        while !waiting.isEmpty {
            let next = waiting.removeFirst()
            if !order.contains(next) { order.append(next); waiting += next.requires }
        }
        let others = order.filter(coming.contains)
        return others.isEmpty ? nil : AddOnTexts.bringing(addOn, others)
    }

    /// The sentence that asks first, when others go with it; nil when it goes alone.
    public func confirmation(uninstalling addOn: AddOn) -> String? {
        let others = AddOns.removed(by: addOn, from: installed)
        return others.isEmpty ? nil : AddOnTexts.taking(addOn, others)
    }

    public func install(_ addOn: AddOn) async {
        await install([addOn])
    }

    /// Several at once, with what they need (the Bienvenue): one relaunch. After it, the guide opens on what was
    /// installed and still needs something.
    public func install(_ chosen: [AddOn], welcome: Bool = false) async {
        guard working == nil else { return }
        guard !(await isBusy()) else { problem = AddOnTexts.busy; return }
        var after = installed
        for addOn in chosen { after = AddOns.installing(addOn, into: after) }
        let added = AddOn.allCases.filter { after.contains($0) && !installed.contains($0) }
        guard let first = chosen.first, !added.isEmpty else { return }
        problem = nil
        working = first
        defer { working = nil; progress = nil }
        for next in added {
            if let reason = await prepare(next) {
                problem = reason
                return
            }
        }
        store.save(after)
        store.setPendingGuide(added, welcome: welcome)
        installed = after
        relaunch()
    }

    // MARK: - Ce qu'il leur faut

    public func needs(_ addOn: AddOn) -> [AddOnNeed] {
        AddOnNeeds.list(addOn, facts())
    }

    public func state(_ addOn: AddOn) -> AddOnState {
        AddOnNeeds.state(installed: installed.contains(addOn), needs: needs(addOn))
    }

    /// A need's button. One that leads to another page closes the guide and the Bienvenue first.
    public func settle(_ need: AddOnNeed) {
        guard let action = need.action else { return }
        if action.leavesThePage {
            showsGuide = false
            showsWelcome = false
        }
        perform(action)
    }

    /// After a relaunch: the guide for what was just installed and still needs something; always after the Bienvenue,
    /// whose last step it is.
    public func openPendingGuide() {
        let pending = store.takePendingGuide()
        let waiting = pending.addOns.filter { installed.contains($0) && needs($0).contains { !$0.done } }
        guard pending.welcome || !waiting.isEmpty else { return }
        guide = waiting
        guideIsWelcome = pending.welcome
        showsGuide = true
    }

    /// The Bienvenue's last step without a relaunch (nothing new was installed): what is installed and needs something.
    public func openGuideForInstalled() {
        guide = AddOn.allCases.filter { installed.contains($0) && needs($0).contains { !$0.done } }
        guideIsWelcome = true
        showsWelcome = false
        showsGuide = true
    }

    public func uninstall(_ addOn: AddOn) async {
        guard working == nil else { return }
        guard !(await isBusy()) else { problem = AddOnTexts.busy; return }
        problem = nil
        let gone = [addOn] + AddOns.removed(by: addOn, from: installed)
        let after = AddOns.uninstalling(addOn, from: installed)
        store.save(after)
        installed = after
        for next in gone { cleanUp(next) }
        relaunch()
    }
}
