import HubDesign
import SwiftUI

/// The words of Réglages › Projets (lot 7, 19/11): one line under the logos' switch, the detail behind « ⓘ ».
enum ProjectsSettingsText {
    static let logosHelp = "Polhub demande son icône au site de chaque client ; coupé, les initiales."
    // Fifteen words at most a sentence (lot 10, 20/11).
    static let logosDetail = "Sans autre service : le site voit l'adresse IP du Mac, comme lors d'une visite. Une image déposée sur le logo d'un projet reste toujours."
}

/// Réglages › Projets: the size of the cards, the logos of the clients' sites (15/11).
public struct ProjectsSettingsPane: View {
    @AppStorage(Preferences.Key.cardSize) private var cardSize = CardSize.medium.rawValue
    @AppStorage(Preferences.Key.projectLogos) private var logosOnline = true
    @Environment(\.projectLogos) private var logos

    public init() {}

    public var body: some View {
        Form {
            Section("Kanban") {
                // An old « large » shows as « Normales » (CardSize(stored:)).
                Picker("Taille des cartes", selection: Binding(get: { CardSize(stored: cardSize) }, set: { cardSize = $0.rawValue })) {
                    ForEach(CardSize.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Section {
                SettingRow("Logos des sites des clients", help: ProjectsSettingsText.logosHelp, detail: ProjectsSettingsText.logosDetail) {
                    Toggle("Logos des sites des clients", isOn: $logosOnline)
                        // Off: the sites still waiting are not asked (correctifs, 15/11).
                        .onChange(of: logosOnline) { _, on in if !on { logos?.cancelPending() } }
                }
                if let logos {
                    // « Actualiser » reads again what comes from outside (lot 10, 20/11).
                    Button("Actualiser les logos") { logos.refreshAll() }
                        .disabled(!logosOnline)
                }
            }
        }
        .settingsForm()
    }
}
