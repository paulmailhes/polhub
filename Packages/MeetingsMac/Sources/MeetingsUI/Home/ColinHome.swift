import Colin
import PolhubDesign
import SwiftUI

/// Colin's column on the Accueil (18/11): what is done, and where Paul stands. For now « Le point » alone; his
/// thread and his bar come with the next step.
struct ColinHome: View {
    @ObservedObject var colin: ColinLibrary

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            if let preparedAt = colin.briefingAt, !colin.briefing.isEmpty {
                BriefingCard(sentences: colin.briefing, preparedAt: preparedAt)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .animation(Motion.standard, value: colin.briefingAt)
    }
}
