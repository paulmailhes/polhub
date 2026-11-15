import PolhubDesign
import SwiftUI

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
                Toggle("Logos des sites des clients", isOn: $logosOnline)
                if let logos {
                    Button("Rafraîchir les logos") { logos.refreshAll() }
                        .disabled(!logosOnline)
                }
            } footer: {
                Text("Polhub demande son icône au site de chaque client, directement depuis le Mac, sans passer par un autre service : le site voit l'adresse IP du Mac, comme lors d'une visite. Coupé, les projets gardent leurs initiales. Une image déposée sur le logo d'un projet reste toujours.")
                    .font(.meta)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: 640)
    }
}
