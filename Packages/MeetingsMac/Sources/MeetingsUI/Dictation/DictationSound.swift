import AppKit
import AudioCapture
import Dictation
import Foundation
import HubDesign

/// What Réglages › Dictée says (20/11 in the evening), read at each dictation: a change counts at the next one.
struct DictationSettings {
    var defaults: UserDefaults = .standard

    func on(_ key: String) -> Bool { defaults.object(forKey: key) as? Bool ?? true }

    var rules: DictationRules {
        DictationRules(fillers: on(Preferences.Key.dictationFillers), spokenPunctuation: on(Preferences.Key.dictationSpokenPunctuation),
                       digits: on(Preferences.Key.dictationDigits), dropFinalPeriod: on(Preferences.Key.dictationDropFinalPeriod))
    }

    /// Seconds of silence before the dictation finishes alone; nil: never.
    var autoStop: Double? { seconds(Preferences.Key.dictationAutoStop, or: Self.autoStopDefault) }
    /// Seconds of pause before a paragraph; nil: never.
    var paragraphPause: Double? { seconds(Preferences.Key.dictationParagraphPause, or: Self.paragraphDefault) }
    /// How the key works: a press starts and a press finishes, by default.
    var mode: KeyGesture.Mode {
        defaults.string(forKey: Preferences.Key.dictationMode).flatMap(KeyGesture.Mode.init(rawValue:)) ?? .toggle
    }
    var windowAtTop: Bool { defaults.string(forKey: Preferences.Key.dictationWindowPlace) == "haut" }
    /// Days the history is kept; 0: always.
    var keepDays: Int { defaults.integer(forKey: Preferences.Key.dictationKeepDays) }
    /// The microphones by Paul's order, as UIDs.
    var microphones: [String] {
        (defaults.string(forKey: Preferences.Key.dictationMicrophones) ?? "").split(separator: "\n").map(String.init)
    }

    static let autoStopDefault = 10.0
    static let paragraphDefault = 3.0

    private func seconds(_ key: String, or fallback: Double) -> Double? {
        let value = defaults.object(forKey: key) as? Double ?? fallback
        return value > 0 ? value : nil
    }

    /// The first of Paul's microphones that is connected; nil: the system's.
    func microphone(connected: [Microphone]) -> String? {
        let here = Set(connected.map(\.uid))
        return microphones.first(where: here.contains)
    }

    /// Paul's order, then the microphones connected that he never ordered: the list of Réglages.
    static func ordered(_ order: [String], connected: [Microphone], known: [String: String]) -> [Microphone] {
        var names = known
        for microphone in connected { names[microphone.uid] = microphone.name }
        var uids = order
        for microphone in connected where !uids.contains(microphone.uid) { uids.append(microphone.uid) }
        return uids.compactMap { uid in names[uid].map { Microphone(uid: uid, name: $0) } }
    }
}

/// The Mac's sound while Paul dictates (20/11 in the evening): a small sound to start and to finish, the output muted,
/// the music or the video paused; given back as it was. Never during a meeting hub records.
@MainActor final class DictationSound {
    let settings: () -> DictationSettings
    let media: MediaPause
    /// The muting that counts: a dictation that ends cancels the one asked before.
    private var muteToken = 0

    init(settings: @escaping () -> DictationSettings = { DictationSettings() }, media: MediaPause) {
        self.settings = settings
        self.media = media
    }

    /// The key is pressed: what plays is paused at once.
    func pressed(inMeeting: Bool) {
        guard !inMeeting, settings().on(Preferences.Key.dictationPauseMedia) else { return }
        media.pause()
    }

    /// The microphone gives sound: the small sound says « parle », then the Mac is muted.
    func listening(inMeeting: Bool) {
        let settings = settings()
        if settings.on(Preferences.Key.dictationSounds) { Self.play("Tink") }
        guard !inMeeting, settings.on(Preferences.Key.dictationMuteMac) else { return }
        muteToken += 1
        let token = muteToken
        // After the small sound: muted at once, it would be cut. Never once the dictation has ended meanwhile: a
        // dictation given up in its first quarter of a second left the Mac muted (found 21/11).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, self.muteToken == token else { return }
            OutputMute.mute()
        }
    }

    /// `finished`: the text is coming (a sound); else the dictation was given up (none).
    func stopped(finished: Bool) {
        muteToken += 1
        OutputMute.unmute()
        media.resume()
        if finished, settings().on(Preferences.Key.dictationSounds) { Self.play("Pop") }
    }

    static func play(_ name: String) {
        guard let sound = NSSound(named: NSSound.Name(name))?.copy() as? NSSound else { return }
        sound.volume = 0.35
        sound.play()
    }
}

/// The output muted by hub, noted until it is given back: a hub stopped mid-dictation gives it back at its next launch.
enum OutputMute {
    static var defaults: UserDefaults { .standard }

    static func mute() {
        guard defaults.string(forKey: Preferences.Key.dictationMutedOutput) == nil, let device = Devices.defaultOutput(),
              Devices.isMuted(device) == false, let uid = Devices.uid(device), Devices.setMuted(true, device) else { return }
        defaults.set(uid, forKey: Preferences.Key.dictationMutedOutput)
    }

    /// Gives back the output hub muted, the one it muted even if another has become the default.
    static func unmute() {
        guard let uid = defaults.string(forKey: Preferences.Key.dictationMutedOutput) else { return }
        if let device = Devices.device(uid: uid) { Devices.setMuted(false, device) }
        defaults.removeObject(forKey: Preferences.Key.dictationMutedOutput)
    }
}

/// The music or the video paused while Paul dictates, then played again — only what hub paused (20/11 in the evening).
/// macOS keeps « what is playing » to its own apps; Perl, one of them, reads it for hub through `hub-media.dylib`, as
/// VoiceInk does (mediaremote-adapter). Measured 20/11: the state reads through Perl, not directly.
@MainActor final class MediaPause {
    let bridge: MediaBridge?
    private var pausing: Task<Int32?, Never>?

    init(bridge: MediaBridge?) {
        self.bridge = bridge
    }

    func pause() {
        guard let bridge else { return }
        pausing = Task {
            guard let state = await bridge.state(), state.playing else { return nil }
            await bridge.send("pause")
            return state.pid
        }
    }

    func resume() {
        guard let bridge, let pausing else { return }
        self.pausing = nil
        Task {
            // The pause asked at the start is waited for: a short dictation must not leave the music paused.
            guard let pid = await pausing.value else { return }
            try? await Task.sleep(for: .milliseconds(150))
            guard let state = await bridge.state(), !state.playing, state.pid == pid else { return }
            await bridge.send("play")
        }
    }
}

/// `/usr/bin/perl` loads `hub-media.dylib` and calls one of its functions: `state` writes « 1 1234 » (playing, the
/// app's process), `pause` and `play` send the order.
struct MediaBridge: Sendable {
    let library: URL

    static let script = """
        use DynaLoader;
        my $lib = DynaLoader::dl_load_file($ARGV[0]) or exit 2;
        my $sym = DynaLoader::dl_find_symbol($lib, "hub_media_" . $ARGV[1]) or exit 3;
        DynaLoader::dl_install_xsub("main::order", $sym);
        main::order();
        """

    struct State: Equatable {
        var playing: Bool
        var pid: Int32
    }

    func state() async -> State? {
        guard let line = await run("state") else { return nil }
        let parts = line.split(separator: " ")
        guard parts.count == 2, let pid = Int32(parts[1]) else { return nil }
        return State(playing: parts[0] == "1", pid: pid)
    }

    func send(_ order: String) async {
        _ = await run(order)
    }

    /// Two seconds at most: a stuck Perl never holds a dictation.
    private func run(_ order: String) async -> String? {
        guard FileManager.default.fileExists(atPath: library.path(percentEncoded: false)) else { return nil }
        return await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
            process.arguments = ["-e", Self.script, library.path(percentEncoded: false), order]
            let output = Pipe()
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            let once = Once()
            process.terminationHandler = { _ in
                let data = output.fileHandleForReading.readDataToEndOfFile()
                once.run { continuation.resume(returning: String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)) }
            }
            do { try process.run() } catch {
                once.run { continuation.resume(returning: nil) }
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                if process.isRunning { process.terminate() }
                once.run { continuation.resume(returning: nil) }
            }
        }
    }
}

/// A continuation resumed once, whoever comes first.
final class Once: @unchecked Sendable {
    private var done = false
    private let lock = NSLock()

    func run(_ body: () -> Void) {
        lock.withLock {
            guard !done else { return }
            done = true
            body()
        }
    }
}
