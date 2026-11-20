import Domain
import HubDesign
import SwiftUI

/// Réglages › Add-ons (20/11): what hub can do, one row each, with « Installer », or « Installé » and its menu. Every
/// gesture asks first: it relaunches hub, and says who comes with it or goes with it.
struct AddOnsSettingsPane: View {
    @ObservedObject var control: AddOnControl
    @State private var asking: Question?

    struct Question: Identifiable {
        let addOn: AddOn
        let installing: Bool
        let message: String
        var id: String { addOn.rawValue + (installing ? "+" : "-") }
        var title: String { "\(installing ? "Installer" : "Désinstaller") \(addOn.title) ?" }
    }

    var body: some View {
        Form {
            if control.installed.isEmpty {
                Section { Text(Words.typeset(AddOnTexts.choose)) }
            }
            Section {
                ForEach(AddOn.allCases, id: \.self) { addOn in row(addOn) }
            } footer: {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(Words.typeset(AddOnTexts.keepsData))
                    Text(Words.typeset(AddOnTexts.permissions))
                }
                .font(.meta)
                .foregroundStyle(.secondary)
            }
            if let problem = control.problem {
                Section { ErrorLine(problem) }
            }
        }
        .settingsForm()
        .confirmationDialog(asking?.title ?? "", isPresented: Binding(get: { asking != nil }, set: { if !$0 { asking = nil } }),
                            titleVisibility: .visible, presenting: asking) { question in
            Button(question.installing ? "Installer" : "Désinstaller", role: question.installing ? nil : .destructive) {
                Task { question.installing ? await control.install(question.addOn) : await control.uninstall(question.addOn) }
            }
            Button("Annuler", role: .cancel) {}
        } message: { question in
            Text(Words.typeset(question.message))
        }
    }

    private func row(_ addOn: AddOn) -> some View {
        let installed = control.installed.contains(addOn)
        let blocked = addOn == .colin && !control.claudeFound && !installed
        // What it asks for, only while it is not installed.
        return SettingRow(addOn.title, help: installed ? AddOnTexts.summary(addOn) : AddOnTexts.help(addOn),
                          problem: blocked ? AddOnTexts.needsClaude : nil) {
            if control.working == addOn {
                if let progress = control.progress {
                    ProgressView(value: progress).frame(width: 96)
                } else {
                    ProgressView().controlSize(.small)
                }
            } else if installed {
                Menu("Installé") {
                    Button("Désinstaller", role: .destructive) { ask(addOn, installing: false) }
                }
                .fixedSize()
            } else {
                Button("Installer") { ask(addOn, installing: true) }
                    .disabled(blocked || control.working != nil)
            }
        }
    }

    private func ask(_ addOn: AddOn, installing: Bool) {
        var parts: [String?]
        if installing {
            parts = [control.confirmation(installing: addOn), AddOnTexts.installing]
        } else {
            parts = [control.confirmation(uninstalling: addOn), addOn == .meetings ? AddOnTexts.takingModel : nil,
                     AddOnTexts.keepsData, AddOnTexts.removing]
        }
        asking = Question(addOn: addOn, installing: installing, message: parts.compactMap { $0 }.joined(separator: " "))
    }
}
