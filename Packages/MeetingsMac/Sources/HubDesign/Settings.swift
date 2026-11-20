import SwiftUI

// The pages of Réglages (lot 7 of the plan of 19/11): one width, the system's grouped form, and a setting's help in one
// line under it, in its card; the long detail behind « ⓘ ». The rules are in docs/design-system.md, « Les réglages ».

/// The measures of Réglages' pages.
public enum SettingsMetrics {
    /// The one width of every page of Réglages, the list of the families included (lot 7, 19/11: 640, 680 and 720 before).
    public static let width: CGFloat = 640
}

extension View {
    /// A page of Réglages: the system's grouped form, at the one width of Réglages (lot 7, 19/11).
    public func settingsForm() -> some View {
        formStyle(.grouped).frame(maxWidth: SettingsMetrics.width)
    }
}

/// A setting in its card (lot 7, 19/11): its title, its help under it in one line, its control on the right, all in one
/// row; no help below the card any more. `problem`: why it cannot work now, said by `ErrorLine` in place of the help.
public struct SettingRow<Control: View>: View {
    let title: String
    let help: String?
    let detail: String?
    let problem: String?
    let control: Control

    public init(_ title: String, help: String? = nil, detail: String? = nil, problem: String? = nil, @ViewBuilder control: () -> Control) {
        self.title = title
        self.help = help
        self.detail = detail
        self.problem = problem
        self.control = control()
    }

    public var body: some View {
        LabeledContent {
            // A switch, as every switch of a form: inside a row of its own, the system would draw a box to tick.
            control.labelsHidden().toggleStyle(.switch)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                // French typography, laid at display (`Words.typeset`, lot 10, 20/11).
                Text(Words.typeset(title))
                if let problem {
                    ErrorLine(problem).font(.meta).fixedSize(horizontal: false, vertical: true)
                } else if let help {
                    SettingHelp(help, detail: detail)
                }
            }
        }
    }
}

/// The help of a setting (lot 7, 19/11): one line in the meta style, grey, under what it explains; the long detail behind
/// « ⓘ », in a bubble. Never more than two lines on screen.
public struct SettingHelp: View {
    /// The longest help, in characters: two lines of a card of Réglages beside its control, at most, in the narrowest
    /// window (measured on the captures of 20/11).
    public static let longest = 100

    let text: String
    let detail: String?

    public init(_ text: String, detail: String? = nil) {
        self.text = text
        self.detail = detail
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
            // French typography, laid at display (`Words.typeset`, lot 10, 20/11).
            Text(Words.typeset(text))
                .font(.meta)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let detail { InfoBubble(detail) }
        }
    }
}

/// « ⓘ » (lot 7, 19/11): a detail too long to stay on screen (what leaves the Mac, the exact rules), in a bubble that
/// opens on a click; the system draws it in glass.
public struct InfoBubble: View {
    let text: String
    @State private var shown = false

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Button { shown.toggle() } label: {
            Image(systemName: "info.circle").font(.meta).frame(width: 18, height: 18)
        }
        .buttonStyle(.hover(.circle))
        .foregroundStyle(.secondary)
        .help("En savoir plus")
        .accessibilityLabel("En savoir plus")
        .popover(isPresented: $shown) {
            // French typography, laid at display (`Words.typeset`, lot 10, 20/11).
            Text(Words.typeset(text))
                .font(.meta)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 320, alignment: .leading)
                .padding(Space.l)
        }
    }
}
