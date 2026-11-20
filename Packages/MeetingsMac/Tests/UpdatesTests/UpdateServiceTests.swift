import Foundation
import Testing
@testable import Updates

final class FakeInstaller: UpdateInstalling, @unchecked Sendable {
    private let lock = NSLock()
    private var prepares = 0, launches = 0
    var fails = false
    var onPrepare: (@Sendable () -> Void)?
    var prepared: Int { lock.withLock { prepares } }
    var launched: Int { lock.withLock { launches } }

    func prepare(_ release: Release) async throws -> URL {
        lock.withLock { prepares += 1 }
        onPrepare?()
        if fails { throw Installer.InstallError.noApp }
        return URL(fileURLWithPath: "/tmp/Polhub.app")
    }

    func launch(newApp: URL, version: SemanticVersion) throws {
        lock.withLock { launches += 1 }
    }
}

final class Switch: @unchecked Sendable {
    private let lock = NSLock()
    private var on: Bool
    init(_ on: Bool) { self.on = on }
    var value: Bool {
        get { lock.withLock { on } }
        set { lock.withLock { on = newValue } }
    }
}

@MainActor @Suite struct UpdateServiceTests {
    let start = Date(timeIntervalSince1970: 1_794_600_000)
    nonisolated static let available = Data(ReleaseTests.json.utf8)

    func service(fetch: @escaping @Sendable () async throws -> Data = { UpdateServiceTests.available }, installer: FakeInstaller,
                 idle: Switch = Switch(true), auto: Bool = true, clock: TestNow, quits: QuitCounter = QuitCounter()) -> UpdateService {
        let defaults = UserDefaults(suiteName: "maj-\(UUID().uuidString)")!
        defaults.set(auto, forKey: UpdateService.autoKey)
        return UpdateService(current: SemanticVersion("0.3.0")!, fetch: fetch, installer: installer, isIdle: { idle.value },
                             defaults: defaults, now: { clock.date }, quit: { quits.count += 1 })
    }

    @Test func gitHubUnreachableIsSaidAndNothingElseChanges() async {
        let installer = FakeInstaller()
        let updates = service(fetch: { throw URLError(.notConnectedToInternet) }, installer: installer, clock: TestNow(start))
        await updates.tick()
        #expect(updates.newer.isEmpty && installer.prepared == 0)
        #expect(UpdateService.text(updates.state)?.contains("GitHub ne répond pas") == true)
    }

    @Test func aNewerVersionIsInstalledWhenAllIsQuiet() async {
        let installer = FakeInstaller(), quits = QuitCounter()
        let updates = service(installer: installer, clock: TestNow(start), quits: quits)
        await updates.tick()
        #expect(updates.latest?.version.description == "0.3.1")
        #expect(installer.prepared == 1 && installer.launched == 1 && quits.count == 1)
    }

    @Test func aNewerVersionWaitsWhileAMeetingIsOn() async {
        let installer = FakeInstaller(), idle = Switch(false), clock = TestNow(start)
        let updates = service(installer: installer, idle: idle, clock: clock)
        await updates.tick()
        #expect(installer.prepared == 0 && updates.state == .waitingForIdle)
        // A meeting starts while the archive downloads: nothing is installed.
        idle.value = true
        installer.onPrepare = { idle.value = false }
        await updates.tick()
        #expect(installer.prepared == 1 && installer.launched == 0 && updates.state == .waitingForIdle)
        installer.onPrepare = nil
        idle.value = true
        await updates.tick()
        #expect(installer.launched == 1)
    }

    @Test func autoInstallOffOnlyAnnounces() async {
        let installer = FakeInstaller()
        let updates = service(installer: installer, auto: false, clock: TestNow(start))
        await updates.tick()
        #expect(updates.latest?.version.description == "0.3.1" && installer.prepared == 0)
        await updates.installNow()
        #expect(installer.launched == 1)
    }

    @Test func aFailedInstallIsRetriedAnHourLater() async {
        let installer = FakeInstaller(), clock = TestNow(start)
        installer.fails = true
        let updates = service(installer: installer, clock: clock)
        await updates.tick()
        #expect(installer.prepared == 1 && UpdateService.text(updates.state)?.contains("hub.app") == true)
        clock.date = start.addingTimeInterval(600)
        await updates.tick()
        #expect(installer.prepared == 1)
        clock.date = start.addingTimeInterval(3_700)
        await updates.tick()
        #expect(installer.prepared == 2)
    }

    // Revue, important 2 : une version déjà ratée ne se réinstalle pas en boucle.
    @Test func aVersionThatFailedIsNotTriedAgainAutomatically() async {
        let installer = FakeInstaller(), clock = TestNow(start)
        let defaults = UserDefaults(suiteName: "maj-\(UUID().uuidString)")!
        defaults.set("0.3.1", forKey: UpdateService.failedVersionKey)
        let updates = UpdateService(current: SemanticVersion("0.3.0")!, fetch: { UpdateServiceTests.available }, installer: installer,
                                    isIdle: { true }, defaults: defaults, now: { clock.date }, quit: {})
        await updates.tick()
        #expect(updates.latest?.version.description == "0.3.1" && installer.prepared == 0)
        await updates.installNow()
        #expect(installer.prepared == 1)
    }

    // Revue, mineur 4 : une demande à la main attend la fin de la réunion, même après la vérification suivante.
    @Test func aManualRequestSurvivesTheNextCheck() async {
        let installer = FakeInstaller(), idle = Switch(false), clock = TestNow(start)
        let updates = service(installer: installer, idle: idle, auto: false, clock: clock)
        await updates.tick()
        await updates.installNow()
        #expect(updates.state == .waitingForIdle)
        clock.date = start.addingTimeInterval(3_700)
        idle.value = true
        await updates.tick()
        #expect(installer.launched == 1)
    }

    @Test func everyStateHasAFrenchText() {
        #expect(UpdateService.text(.idle) == nil)
        #expect(UpdateService.text(.waitingForIdle) == "La mise à jour s'installera à la fin de la réunion ou de la transcription en cours.")
        #expect(UpdateService.text(.installing) == "Installation : hub va se relancer.")
    }

    @Test func theJournalSaysWhichVersionCameIn() {
        #expect(UpdateService.upgradeNote(previous: "0.3.0", current: "0.3.1") == "hub est passé de 0.3.0 à 0.3.1.")
        #expect(UpdateService.upgradeNote(previous: "0.3.1", current: "0.3.1") == nil)
        #expect(UpdateService.upgradeNote(previous: nil, current: "0.3.1") == nil)
    }
}

final class TestNow: @unchecked Sendable {
    var date: Date
    init(_ date: Date) { self.date = date }
}

@MainActor final class QuitCounter {
    var count = 0
}
