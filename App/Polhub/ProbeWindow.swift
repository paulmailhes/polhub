import AppKit
import Observability
import PolhubDesign
import ProbeKit
import SwiftUI

struct ProbeWindow: View {
    @ObservedObject var runner: ProbeRunner
    @ObservedObject private var permissions = PermissionBoard.shared
    @ObservedObject private var guide = ProtocolBoard.shared
    @State private var relaunchStatus = RelaunchAgent.statusText
    @State private var relaunchMessage: String?

    var body: some View {
        // During the guided call the window shows the current instruction and nothing else.
        if guide.stepIndex != nil {
            ProtocolView(board: guide, stop: runner.stop)
        } else {
            probeList
        }
    }

    private var probeList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sondes de la phase 0")
                .font(.title2.bold())
            Text("Les traces et le son enregistré restent sur ce Mac.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(ProbeID.listed, id: \.self) { id in
                HStack {
                    Text(id.title)
                    Spacer()
                    if runner.running == id {
                        ProgressView().controlSize(.small)
                        Button("Arrêter") { runner.stop() }
                    } else {
                        Button("Lancer") { runner.start(ProbeRequest(probe: id)) }
                            .disabled(runner.running != nil || ProbeRegistry.make(id) == nil)
                    }
                }
            }

            Divider()

            permissionsSection

            Divider()

            if let message = runner.message {
                // A problem in one line: the icon of attention, the sentence in the text's own color
                // (design system v2, 19/11).
                ErrorLine(message)
            }
            LabeledContent("Dossier des traces") {
                Text(TracePaths.root.path)
                    .font(.caption)
                    .textSelection(.enabled)
            }
            if let directory = runner.lastDirectory {
                Button("Montrer la dernière trace dans le Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([directory])
                }
            }
        }
        .padding(20)
        .frame(minWidth: 520)
    }

    @ViewBuilder
    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Autorisations").font(.headline)
            if let report = permissions.latest {
                Text("Micro : \(report.microphone) · Automatisation de Dia : \(report.appleEventsDia) · Audio du système : \(report.systemAudio)")
                    .font(.caption)
                    .textSelection(.enabled)
            }
            Button("Demander les autorisations") {
                runner.start(ProbeRequest(probe: .permissions, variant: "prompt"))
            }
            .disabled(runner.running != nil)

            Text("Relance après plantage : \(relaunchStatus)").font(.headline)
            HStack {
                Button("Activer la relance") {
                    relaunchMessage = RelaunchAgent.enable()
                    relaunchStatus = RelaunchAgent.statusText
                    if relaunchMessage == nil, LaunchContext.current == .user {
                        handOverToTheAgentCopy()
                    }
                }
                Button("Désactiver la relance") {
                    relaunchMessage = RelaunchAgent.disable()
                    relaunchStatus = RelaunchAgent.statusText
                    if relaunchMessage == nil, LaunchContext.current == .launchd {
                        relaunchMessage = "Relance désactivée : cette copie, lancée par l'agent, va se fermer."
                    }
                }
                Button("Planter l'app maintenant") {
                    Task { await PermissionsProbe.crashNow() }
                }
                .disabled(LaunchContext.current != .launchd)
                .help("Seule la copie lancée par l'agent de relance est relancée : active d'abord la relance.")
            }
            if let relaunchMessage {
                Text(relaunchMessage).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    /// launchd restarts only the copy it started. This copy steps aside, but only once the agent's copy
    /// is really there: never leave the person with no copy running.
    private func handOverToTheAgentCopy() {
        relaunchMessage = "Relance activée. J'attends la copie lancée par l'agent…"
        Task {
            for _ in 0..<25 {
                if AppDelegate.anotherCopyIsRunning() {
                    relaunchMessage = "Relance activée. Cette fenêtre se ferme : rouvre les sondes par l'icône de la barre des menus."
                    try? await Task.sleep(for: .seconds(1.5))
                    // A probe under way ends with this copy, and the Claude Code it launched with it.
                    runner.stopForExit()
                    exit(0)
                }
                try? await Task.sleep(for: .milliseconds(200))
            }
            // A path of System Settings, its levels apart by « › » (lot 10, 20/11).
            relaunchMessage = "La copie de l'agent n'a pas démarré en 5 s : cette fenêtre reste ouverte. Vérifie Réglages Système › Général › Ouverture."
        }
    }
}
