import PolhubDesign
import Testing
@testable import ProjectsUI

/// Réglages › Projets (lot 7, 19/11): one line of help under the logos' switch, the detail behind « ⓘ ».
@Suite struct ProjectsSettingsTests {
    @Test func theLogosHelpHoldsInOneLine() {
        #expect(ProjectsSettingsText.logosHelp.count <= SettingHelp.longest)
        #expect(!ProjectsSettingsText.logosHelp.contains("\n"))
        // The detail keeps what leaves the Mac: the site sees the Mac's address.
        #expect(ProjectsSettingsText.logosDetail.contains("adresse IP"))
    }
}
