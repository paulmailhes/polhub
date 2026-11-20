import HubDesign
import SwiftUI

/// A note shown as in Obsidian's reading mode: titles, lists, check boxes, quotes and callouts, with bold,
/// italics and links inside the lines.
public struct MarkdownView: View {
    let text: String

    public init(text: String) {
        self.text = text
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(MarkdownBlocks.parse(text).enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        // The links in the accent's ink, underlined by `inline` (design system v2, 19/11).
        .tint(Tint.accent)
    }

    @ViewBuilder private func view(for block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            inline(text).font(level <= 1 ? .title3.bold() : level == 2 ? .headline : .body.weight(.semibold))
                .padding(.top, 4)
        case .bullet(let depth, let text):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("•").foregroundStyle(.secondary)
                inline(text)
            }
            .padding(.leading, CGFloat(depth) * 16)
        case .task(let done, let text):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                // A box ticked, as what is chosen: the accent, ink (design system v2, 19/11).
                Image(systemName: done ? "checkmark.square.fill" : "square").foregroundStyle(done ? Tint.accent : .secondary)
                inline(text).strikethrough(done).foregroundStyle(done ? .secondary : .primary)
            }
        case .quote(let text):
            inline(text)
                .foregroundStyle(.secondary)
                .padding(.leading, 10)
                .overlay(alignment: .leading) { Rectangle().fill(.quaternary).frame(width: 3) }
        case .callout(let kind, let title, let body):
            VStack(alignment: .leading, spacing: 4) {
                Label(title.isEmpty ? kind.capitalized : title, systemImage: "info.circle").font(.callout.weight(.semibold))
                if !body.isEmpty { inline(body).font(.callout) }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Information, not a gesture: a raised surface, no accent; inside a card, its radius (design system v2, 19/11).
            .background(Surface.raised, in: RoundedRectangle(cornerRadius: Radius.inner, style: .continuous))
        case .numbered(let number, let depth, let text):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(number).").foregroundStyle(.secondary).monospacedDigit()
                inline(text)
            }
            .padding(.leading, CGFloat(depth) * 16)
        case .code(let text):
            Text(text)
                .font(.callout.monospaced())
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: Radius.inner, style: .continuous))
        case .paragraph(let text):
            inline(text).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func inline(_ text: String) -> Text {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        var line = (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
        // With an ink accent, a link reads by its underline, no longer by its color (design system v2, 19/11). The key
        // is SwiftUI's: AppKit has an `underlineStyle` of its own.
        for range in line.runs.filter({ $0.link != nil }).map(\.range) {
            line[range][AttributeScopes.SwiftUIAttributes.UnderlineStyleAttribute.self] = .single
        }
        return Text(line)
    }
}
