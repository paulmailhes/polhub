import Foundation
import Testing
@testable import Updates

@Suite struct VerifierTests {
    func signature(team: String = "CQ43U6XX4Z", identifier: String = "fr.paulmailhes.transcriptor") -> String {
        """
        Executable=/tmp/x/Transcriptor.app/Contents/MacOS/Transcriptor
        Identifier=\(identifier)
        Format=app bundle with Mach-O thin (arm64)
        CodeDirectory v=20500 size=11224 flags=0x10000(runtime) hashes=340+7 location=embedded
        Authority=Developer ID Application: Exemple (\(team))
        Authority=Developer ID Certification Authority
        Authority=Apple Root CA
        TeamIdentifier=\(team)
        """
    }

    let info: [String: Any] = ["CFBundleIdentifier": "fr.paulmailhes.transcriptor", "CFBundleShortVersionString": "0.3.1"]
    let expected = SemanticVersion("0.3.1")!

    @Test func theRightAppPasses() {
        #expect(Verifier.check(signature: signature(), info: info, expected: expected) == nil)
    }

    @Test func anAppOfAnotherTeamIsRefused() {
        #expect(Verifier.check(signature: signature(team: "ABCDE12345"), info: info, expected: expected) == .wrongTeam)
        #expect(Verifier.check(signature: "code object is not signed at all", info: info, expected: expected) == .wrongTeam)
    }

    @Test func anOlderOrDifferentVersionIsRefused() {
        var older = info
        older["CFBundleShortVersionString"] = "0.3.0"
        #expect(Verifier.check(signature: signature(), info: older, expected: expected) == .wrongVersion)
        var other = info
        other["CFBundleIdentifier"] = "fr.paulmailhes.autre"
        #expect(Verifier.check(signature: signature(identifier: "fr.paulmailhes.autre"), info: other, expected: expected) == .wrongIdentifier)
    }

    @Test func theScriptRestoresTheOldAppIfTheNewOneDoesNotStart() {
        let script = SwapScript.make(
            newApp: URL(fileURLWithPath: "/tmp/maj 1/Transcriptor.app"),
            installed: URL(fileURLWithPath: "/Applications/Transcriptor.app"),
            keepOld: URL(fileURLWithPath: "/Users/x/Library/Application Support/Transcriptor/Ancienne version"),
            agent: "fr.paulmailhes.transcriptor.relance", log: URL(fileURLWithPath: "/Users/x/Library/Logs/Transcriptor/mise à jour.log"),
            pid: 4242, uid: 501
        )
        #expect(script.hasPrefix("#!/bin/bash"))
        #expect(script.contains("kill -0 4242"))
        #expect(script.contains("'/Users/x/Library/Application Support/Transcriptor/Ancienne version'"))
        #expect(script.contains("ditto '/tmp/maj 1/Transcriptor.app' '/Applications/Transcriptor.app'"))
        #expect(script.contains("launchctl kickstart gui/501/fr.paulmailhes.transcriptor.relance"))
        #expect(script.contains("pgrep -x Transcriptor"))
        #expect(script.contains("retour à l'ancienne version"))
        #expect(SwapScript.quote("l'app") == #"'l'\''app'"#)
    }
}
