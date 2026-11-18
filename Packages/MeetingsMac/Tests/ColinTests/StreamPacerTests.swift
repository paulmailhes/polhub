import Foundation
import Testing
@testable import Colin

/// The text that writes itself (the Accueil's pass, 18/11): what Claude Code sends in bursts comes out word by word,
/// faster when it is behind, all of it at the end.
@Suite struct StreamPacerTests {
    @Test func wordsComeWhole() {
        var pacer = StreamPacer()
        pacer.push("Bonjour Cla")
        #expect(pacer.tick() == "Bonjour ")
        #expect(pacer.tick() == "Bonjour ")
        pacer.push("ire, ça va ?")
        var shown = ""
        for _ in 0..<10 { shown = pacer.tick() }
        #expect(shown == "Bonjour Claire, ça va ")
    }

    @Test func anUnfinishedWordWaits() {
        var pacer = StreamPacer()
        pacer.push("Maquette")
        #expect(pacer.tick() == "")
        #expect(pacer.backlog == 8)
    }

    @Test func flushShowsEverything() {
        var pacer = StreamPacer()
        pacer.push("Trois projets en cours")
        _ = pacer.tick()
        #expect(pacer.flush() == "Trois projets en cours")
        #expect(pacer.backlog == 0 && pacer.shown == "Trois projets en cours")
    }

    /// Review Focus 2: a long answer never leaves the screen further and further behind.
    @Test func aLongBacklogGoesFaster() {
        var pacer = StreamPacer()
        pacer.push(String(repeating: "mot ", count: 2_500))
        var ticks = 0
        while pacer.backlog > 0, ticks < 1_000 {
            _ = pacer.tick()
            ticks += 1
        }
        #expect(ticks < 120)
        #expect(pacer.shown.count == 10_000)
    }

    /// Lines and paragraphs count as the end of a word.
    @Test func aLineEndsAWord() {
        var pacer = StreamPacer()
        pacer.push("Fini.\n\nSuite")
        #expect(pacer.tick() == "Fini.\n\n")
    }
}
