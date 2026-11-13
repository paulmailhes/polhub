import Testing
@testable import ProjectsUI

@Suite struct MarkdownBlocksTests {
    @Test func headingsBulletsTasksAndParagraphs() {
        let blocks = MarkdownBlocks.parse("""
        # Titre
        Un paragraphe
        sur deux lignes.

        - une puce **grasse**
        - [ ] à faire
        - [x] fait
        """)
        #expect(blocks == [
            .heading(level: 1, text: "Titre"),
            .paragraph("Un paragraphe\nsur deux lignes."),
            .bullet(depth: 0, text: "une puce **grasse**"),
            .task(done: false, text: "à faire"),
            .task(done: true, text: "fait"),
        ])
    }

    @Test func anObsidianCalloutIsOneBlock() {
        let blocks = MarkdownBlocks.parse("""
        > [!info]- Pour une IA
        > Première ligne.
        > Deuxième ligne.

        > Une simple citation.
        """)
        #expect(blocks == [
            .callout(kind: "info", title: "Pour une IA", body: "Première ligne.\nDeuxième ligne."),
            .quote("Une simple citation."),
        ])
    }

    @Test func nestedBulletsKeepTheirDepth() {
        let blocks = MarkdownBlocks.parse("- un\n  - deux\n    - trois\n* quatre")
        #expect(blocks == [.bullet(depth: 0, text: "un"), .bullet(depth: 1, text: "deux"), .bullet(depth: 2, text: "trois"),
                           .bullet(depth: 0, text: "quatre")])
    }
}
