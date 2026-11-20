import Foundation
import Testing

/// The public pages (18/11), behind Google's consent screen: once Colin can be turned on, they say what he sends to
/// Anthropic, and that he is off until the user turns him on.
@Suite struct PublicPagesTests {
    /// The repository, from this file: Tests/ColinTests/<file>.
    func read(_ path: String) throws -> String {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let text = try String(contentsOf: root.appending(path: path), encoding: .utf8)
        return text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    @Test func thePublicPagesSayWhatColinSends() throws {
        let readme = try read("README.md")
        #expect(!readme.contains("Rien ne quitte la machine"))
        #expect(readme.contains("Colin") && readme.contains("Anthropic"))
        for page in ["docs/index.html", "docs/confidentialite.html", "docs/conditions.html"] {
            let text = try read(page)
            #expect(text.contains("Colin"), "\(page)")
            #expect(text.contains("Anthropic"), "\(page)")
            #expect(text.contains("à l'arrêt"), "\(page)")
        }
        for page in ["docs/index.html", "docs/confidentialite.html"] {
            let text = try read(page)
            #expect(text.contains("assistant") && text.contains("sans aucun invité"), "\(page)")
        }
        #expect(!(try read("docs/index.html")).contains("Tout reste sur le Mac"))
        // « Never by itself » holds, Colin apart.
        #expect(!(try read("docs/confidentialite.html")).contains("selon les conditions de cet assistant. hub ne le fait jamais de lui-même."))
    }
}
