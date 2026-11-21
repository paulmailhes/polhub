import Domain
import HubDesign
import Testing
@testable import MeetingsUI

/// 21/11 (Paul : « dans les réglages, les logos d'add-on, ce n'est même pas les mêmes logos qu'il y a dans la barre sur
/// la gauche… Réunion et Dicté ont le même logo ») : un outil a une seule marque, partout la même.
@Suite struct BrandTests {
    @Test func everyToolHasItsOwnMarkTheSidebarsOne() {
        let icons = AddOn.allCases.map(\.appIcon)
        #expect(Set(icons).count == icons.count)
        #expect(AddOn.meetings.appIcon != AddOn.dictation.appIcon)
        let sections: [(AddOn, SidebarItem)] = [(.projects, .projects), (.meetings, .meetings), (.dictation, .dictation), (.calendar, .calendar),
                                                (.mails, .mails), (.inspiration, .inspiration), (.vigie, .vigie)]
        for (addOn, item) in sections {
            #expect(addOn.appIcon == item.appIcon && addOn.tint == item.tint, "\(addOn)")
        }
        // Réglages' pages of the tools wear the same badge.
        for addOn in AddOn.allCases {
            if let pane = addOn.settings { #expect(pane.appIcon == addOn.appIcon && pane.tint == addOn.tint, "\(addOn)") }
        }
    }

    /// « connexion Google, nécessaire pour chaque truc qui a besoin d'une connexion Google » : one short tag per need,
    /// the same for every tool.
    @Test func everyNeedHasItsShortTag() {
        var facts = AddOnFacts()
        facts.googleAccounts = 0
        facts.accessibility = false
        for addOn in AddOn.allCases {
            for need in AddOnNeeds.list(addOn, facts) {
                #expect(need.tag != need.title && need.tag.count <= 24, "\(need.id)")
            }
        }
        #expect(AddOnNeeds.list(.calendar, facts).first?.tag == "Connexion Google")
        #expect(AddOnNeeds.list(.mails, facts).first?.tag == "Connexion Google")
    }

    /// What is there shows its check, installed or not; what is missing is said once the tool is installed, or before
    /// when it blocks the installation.
    @Test func aTagSaysWhatIsThereAndWhatIsMissing() {
        let google = AddOnNeed("google", "Un compte Google", done: false)
        let claude = AddOnNeed("claude", "Claude Code sur ce Mac", done: false)
        let micro = AddOnNeed("micro", "Le micro", done: true)
        #expect(AddOnTags.kind(google, installed: true) == .missing)
        #expect(AddOnTags.kind(google, installed: false) == .planned)
        #expect(AddOnTags.kind(claude, installed: false) == .missing)
        #expect(AddOnTags.kind(micro, installed: false) == .done)
    }

    @Test func theBadgeKeepsAnAppIconsProportions() {
        #expect(ToolBadge.Size.sidebar.radius == 6 && ToolBadge.Size.header.radius == 15)
        for size in ToolBadge.Size.allCases { #expect(size.glyph < size.rawValue) }
    }
}
