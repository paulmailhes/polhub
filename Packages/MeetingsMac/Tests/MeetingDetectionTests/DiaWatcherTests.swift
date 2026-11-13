import Testing
@testable import MeetingDetection

@Suite struct DiaWatcherTests {
    func proc(_ pid: Int32, app: String?, input: Bool = false, output: Bool = false) -> AudioProcessInfo {
        AudioProcessInfo(objectID: UInt32(pid), pid: pid, bundleID: nil, executablePath: nil, owningAppPath: app,
                         isRunningInput: input, isRunningOutput: output, inputDeviceUIDs: [], outputDeviceUIDs: [])
    }

    // Mesure S07 de la phase 0 : VoiceInk tient le micro dans son propre processus.
    @Test func diaAudioIsReadFromDiaProcessesOnly() {
        let dia = "/Applications/Dia.app"
        let dictation = DiaAudio.from([proc(1, app: "/Applications/VoiceInk.app", input: true), proc(2, app: dia)], diaAppPath: dia)
        #expect(dictation == DiaAudio(holdsMic: false, playing: false))
        let call = DiaAudio.from([proc(2, app: dia), proc(3, app: dia, input: true, output: true)], diaAppPath: dia)
        #expect(call == DiaAudio(holdsMic: true, playing: true))
        let video = DiaAudio.from([proc(3, app: dia, output: true)], diaAppPath: dia)
        #expect(video == DiaAudio(holdsMic: false, playing: true))
    }

    // Mesure 4 de la phase 0 : une lecture coûte 0,3 s à Dia.
    @Test func tabsAreReadOftenOnlyAroundTheMicrophone() {
        #expect(TabCadence.interval(holdsMic: true, secondsSinceMicReleased: nil, meetingActive: false) == 2)
        #expect(TabCadence.interval(holdsMic: false, secondsSinceMicReleased: 12, meetingActive: false) == 2)
        #expect(TabCadence.interval(holdsMic: false, secondsSinceMicReleased: 31, meetingActive: false) == 30)
        #expect(TabCadence.interval(holdsMic: false, secondsSinceMicReleased: nil, meetingActive: true) == 2)
        #expect(TabCadence.interval(holdsMic: false, secondsSinceMicReleased: nil, meetingActive: false) == 30)
    }
}
