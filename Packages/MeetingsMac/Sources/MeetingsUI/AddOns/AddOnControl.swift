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
        guard working == nil else { return }
        guard !(await isBusy()) else { problem = AddOnTexts.busy; return }
        problem = nil
        working = addOn
        defer { working = nil; progress = nil }
        for next in AddOns.added(by: addOn, to: installed) + [addOn] {
            if let reason = await prepare(next) {
                problem = reason
                return
            }
        }
        let after = AddOns.installing(addOn, into: installed)
        store.save(after)
        installed = after
        relaunch()
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
