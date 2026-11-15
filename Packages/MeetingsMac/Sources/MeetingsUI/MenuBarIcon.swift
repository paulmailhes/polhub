import PolhubDesign
import SwiftUI

/// The label of the menu bar's item: the logo, and the clock, the countdown, « fin ? » or « 8 min » beside it
/// (`MenuBarLabel`). The only view that reads `AppModel.now`.
public struct MenuBarIcon: View {
    let model: AppModel
    /// Réglages › Général: the minutes before a Meet (on by default).
    @AppStorage(Preferences.Key.menuBarMeetMinutes) private var meetMinutes = true

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        let label = model.menuBarLabel(meetMinutes: meetMinutes)
        Image(nsImage: label.image)
        if let text = label.text {
            Text(text).monospacedDigit()
        }
    }
}
