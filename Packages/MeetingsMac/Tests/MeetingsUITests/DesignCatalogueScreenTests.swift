import AppKit
import PolhubDesign
import SwiftUI
import Testing

/// Lot 3, before anything changes in the app (plan of 19/11): what the app draws today beside the design system v2,
/// the ink accent, the tints and the four roles of a button, in light and in dark. Shown to Paul before it spreads.
/// `POLHUB_LIVE=1 POLHUB_SNAPSHOTS=<dossier hors du dépôt> swift test --filter DesignCatalogueScreenTests`. Every text
/// is invented.
@MainActor @Suite(.enabled(if: ProcessInfo.processInfo.environment["POLHUB_SNAPSHOTS"] != nil))
struct DesignCatalogueScreenTests {
    @Test func theCatalogue() async throws {
        let output = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["POLHUB_SNAPSHOTS"]), isDirectory: true)
        for dark in [false, true] {
            try await LiveWindow.capture(DesignCatalogue().background(Color(nsColor: .windowBackgroundColor)),
                                         to: output.appending(path: "design-v2\(dark ? "-sombre" : "").png"), size: NSSize(width: 1_000, height: 640),
                                         dark: dark)
        }
    }
}

private struct DesignCatalogue: View {
    var body: some View {
        HStack(alignment: .top, spacing: 40) {
            column("Aujourd'hui") {
                section("Couleurs") {
                    Text("En retard · 2 jours").foregroundStyle(Color.accentColor)
                    Text("Dans 8 min").foregroundStyle(Color.accentColor)
                    Text("Un lien : exemple.fr").foregroundStyle(Color.accentColor)
                    Text("En retard (Kanban)").foregroundStyle(.red)
                }
                section("Boutons") {
                    HStack(spacing: 10) {
                        Button("Répondre") {}.buttonStyle(.borderedProminent)
                        Button("Transférer") {}.buttonStyle(.bordered)
                        Button("Archiver") {}.buttonStyle(.glass)
                    }
                    HStack(spacing: 10) {
                        TextButton("Modifier") {}
                        TextButton("Plus tard", quiet: true) {}
                    }
                }
            }
            Divider()
            column("Proposé : accent encre") {
                section("Couleurs : une couleur, un sens") {
                    swatch(.accent, "Encre", "le bouton principal, la sélection")
                    swatch(.late, "En retard · 2 jours", "une échéance passée")
                    swatch(.attention, "Dans 8 min · à vérifier", "maintenant, ou à relire")
                    swatch(.recording, "Enregistrement", "une réunion en cours")
                    swatch(.done, "Livré", "c'est fait")
                    swatch(.agent, "Préparé par Colin", "écrit par un agent")
                    Text("Dans un texte, \(Text("un lien").underline()) se reconnaît à son soulignement.")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                }
                section("Boutons : quatre rôles") {
                    HStack(spacing: 10) {
                        Button("Répondre") {}.buttonStyle(.primary)
                        Button("Transférer") {}.buttonStyle(.secondary)
                        TextButton("Archiver", quiet: true) {}
                        IconButton("trash", help: "Supprimer") {}
                        Button("Envoyer") {}.buttonStyle(.primary).disabled(true)
                    }
                    RowButton(action: {}) {
                        HStack {
                            Text("Une ligne entière").font(.rowTitle)
                            Spacer()
                            Text("hier").font(.meta).foregroundStyle(.secondary)
                        }
                    }
                }
                section("Bandeaux : seule l'icône porte la couleur") {
                    Banner(.attention, "Ce lien mène à piege.exemple", detail: "Le texte affiche banque.exemple.") {
                        Button("Voir") {}.buttonStyle(.secondary)
                    }
                    Banner(.agent, "Brouillon préparé par Colin", detail: "Relis-le avant de l'envoyer.") {
                        Button("Relire") {}.buttonStyle(.primary)
                    }
                }
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    func column(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(title).font(.system(size: 17, weight: .semibold))
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func section(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            content()
        }
    }

    func swatch(_ role: Tint.Role, _ example: String, _ meaning: String) -> some View {
        HStack(spacing: 10) {
            Circle().fill(role.color).frame(width: 10, height: 10)
            Text(example).font(.system(size: 15, weight: .medium)).foregroundStyle(role.color)
            Text(meaning).font(.system(size: 13)).foregroundStyle(.secondary)
        }
    }
}
