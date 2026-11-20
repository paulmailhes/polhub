import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import PolhubDesign
import SwiftUI

/// Réglages › iPhone (Paul, 20/11): the switch, the Mac's address on Tailscale, the QR code that pairs an iPhone, the
/// iPhones paired.
struct PhoneSettingsPane: View {
    @ObservedObject var access: PhoneAccess

    var body: some View {
        Form {
            Section {
                SettingRow("Accès depuis l'iPhone", help: PhoneSettingsText.accessHelp, detail: PhoneSettingsText.accessDetail,
                           problem: access.problem) {
                    Toggle("Accès depuis l'iPhone", isOn: Binding(get: { access.enabled }, set: { access.enabled = $0 }))
                }
            }
            if access.enabled {
                Section("Adresse du Mac") {
                    SettingRow("Adresse", help: PhoneSettingsText.addressHelp) {
                        TextField("Adresse", text: $access.address, prompt: Text("https://mac.exemple.ts.net:8443"))
                            .frame(maxWidth: 320)
                    }
                    if access.published == false {
                        SettingRow("Une fois, dans le Terminal", help: PhoneSettingsText.serveHelp) {
                            Button("Copier la commande") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(PhoneAccess.serveCommand, forType: .string)
                            }
                        }
                        Text(PhoneAccess.serveCommand)
                            .font(.meta.monospaced())
                            .textSelection(.enabled)
                            .foregroundStyle(.secondary)
                    }
                }
                Section {
                    SettingRow("Notifications sur l'iPhone", help: PhoneSettingsText.notificationsHelp,
                               problem: access.hasPushKey ? nil : PhoneSettingsText.noKey) {
                        Toggle("Notifications sur l'iPhone", isOn: Binding(get: { access.notifies }, set: { access.notifies = $0 }))
                    }
                }
                Section("iPhone reliés") {
                    ForEach(access.devices) { device in
                        HStack {
                            VStack(alignment: .leading, spacing: Space.xs / 2) {
                                Text(device.name)
                                Text(PhoneSettingsText.seen(device)).font(.meta).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Retirer") { access.remove(device) }
                        }
                    }
                    if let pairing = access.pairing {
                        PairingCode(link: pairing.link, until: pairing.until) { access.endPairing() }
                    } else {
                        Button("Relier un iPhone") { Task { await access.pair() } }
                    }
                }
            }
        }
        .settingsForm()
        .task { await access.readTailscale() }
        // The iPhone just scanned: its line says it.
        .task(id: access.pairing?.link) {
            while access.pairing != nil {
                try? await Task.sleep(for: .seconds(2))
                access.refresh()
            }
        }
    }
}

/// The QR code that pairs an iPhone, and how long it stays valid.
struct PairingCode: View {
    let link: URL
    let until: Date
    let done: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Space.l) {
            if let image = Self.image(link.absoluteString) {
                Image(nsImage: image).interpolation(.none).resizable().frame(width: 180, height: 180)
                    .accessibilityLabel("Code à scanner avec l'iPhone")
            }
            VStack(alignment: .leading, spacing: Space.s) {
                Text(PhoneSettingsText.scan)
                Text("Valable jusqu'à \(Words.time(until)).").font(.meta).foregroundStyle(.secondary)
                HStack {
                    // Universal Clipboard: copied here, pasted on the iPhone by « Coller le lien du code » (20/11).
                    Button("Copier le lien") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(link.absoluteString, forType: .string)
                    }
                    .help("Copier le lien, à coller dans Polhub sur l'iPhone")
                    Button("Fermer", action: done)
                }
                Text(PhoneSettingsText.paste).font(.meta).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, Space.s)
    }

    /// The link as a QR code, its modules sharp at any size.
    static func image(_ text: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
              let cgImage = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: output.extent.width / 2, height: output.extent.height / 2))
    }
}

/// Réglages › iPhone's words.
enum PhoneSettingsText {
    static let accessHelp = "Ton iPhone lit tes mails, ton agenda, tes projets et tes réunions quand le Mac est allumé."
    static let accessDetail = "Par ton réseau Tailscale seulement : Polhub n'écoute que sur ce Mac, et Tailscale le publie pour tes appareils. Un iPhone doit être relié par le code de cette page pour lire quoi que ce soit."
    static let addressHelp = "L'adresse de ce Mac sur Tailscale, que l'iPhone appelle."
    static let serveHelp = "Tailscale ne publie pas encore Polhub : colle cette commande dans le Terminal, une seule fois."
    static let notificationsHelp = "Les nouveaux mails, les rendez-vous qui arrivent, les rappels et les comptes rendus, sur l'iPhone aussi, quand le Mac est allumé."
    static let noKey = "La clé de notifications d'Apple manque : rien n'arrive sur l'iPhone."
    static let scan = "Scanne ce code avec l'appareil photo de ton iPhone : il ouvre Polhub et le relie à ce Mac."
    static let paste = "Ou « Copier le lien », puis sur l'iPhone, dans Polhub : « Coller le lien du code »."

    /// « Relié le 20 nov. · vu il y a 4 min », « En attente du code ».
    static func seen(_ device: PhoneDevice, now: Date = Date()) -> String {
        guard let seen = device.lastSeenAt else { return "En attente du code" }
        return "Relié le \(Words.shortDate(device.pairedAt, now: now)) · vu \(Words.ago(seen, now: now))"
    }
}
