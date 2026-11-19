import Testing
@testable import MeetingDetection

@Suite struct AppOwnershipTests {
    @Test func findsTheOutermostApp() {
        #expect(AppOwnership.outermostAppPath(forExecutablePath:
            "/Applications/Dia.app/Contents/Frameworks/ArcCore.framework/Versions/A/Helpers/Browser Helper (Aperitif).app/Contents/MacOS/Browser Helper (Aperitif)")
            == "/Applications/Dia.app")
        #expect(AppOwnership.outermostAppPath(forExecutablePath:
            "/Applications/Arc.app/Contents/Frameworks/ArcCore.framework/Versions/A/Helpers/Browser Helper.app/Contents/MacOS/Browser Helper")
            == "/Applications/Arc.app")
        #expect(AppOwnership.outermostAppPath(forExecutablePath: "/Applications/VoiceInk.app/Contents/MacOS/VoiceInk") == "/Applications/VoiceInk.app")
        #expect(AppOwnership.outermostAppPath(forExecutablePath: "/usr/sbin/corespeechd") == nil)
    }
}

@Suite struct AudioProcessMonitorTests {
    // Lit le vrai Core Audio : la liste des processus se lit sans autorisation et sans produire de son.
    @Test func snapshotReadsWithoutPermission() throws {
        let procs = try AudioProcessMonitor().snapshot()
        #expect(procs.allSatisfy { $0.pid > 0 })
    }

    /// 19/11: the watcher asks only what one app does with sound, every second, without the device lists.
    @Test func activityOfOneAppReadsLightly() throws {
        let monitor = AudioProcessMonitor()
        let absent = try monitor.activity(ofAppAt: "/Applications/Une app qui n'existe pas.app")
        #expect(absent == AudioProcessMonitor.Activity(input: false, output: false))
        // Every app Core Audio knows can be asked, whatever it does.
        for path in Set(try monitor.snapshot().compactMap(\.owningAppPath)) {
            _ = try monitor.activity(ofAppAt: path)
        }
    }
}
