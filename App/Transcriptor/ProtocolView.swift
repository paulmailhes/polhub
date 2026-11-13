import ProbeKit
import SwiftUI

/// Guides the person through the test call, one instruction at a time.
///
/// A wrong click must not cost the session: no keyboard shortcut moves a step, a double-click counts
/// once, a step passed too early can be redone, and stopping asks for confirmation.
struct ProtocolView: View {
    @ObservedObject var board: ProtocolBoard
    let stop: () -> Void
    @State private var confirmingStop = false

    var body: some View {
        if let step = board.currentStep, let index = board.stepIndex {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Appel d'essai · étape \(index + 1) sur \(board.steps.count)")
                        .font(.headline)
                    Spacer()
                    Text(step.id).font(.caption).foregroundStyle(.secondary)
                }

                Text(step.instruction)
                    .font(.title3)
                    .fixedSize(horizontal: false, vertical: true)

                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let elapsed = Int(context.date.timeIntervalSince(board.stepStartedAt ?? context.date))
                    let remaining = max(0, step.minSeconds - elapsed)
                    HStack {
                        Button("Étape précédente") { board.previous() }
                            .disabled(board.isFirstStep)
                        if board.isLastStep {
                            Text("Les mesures s'arrêtent.").foregroundStyle(.secondary)
                        } else {
                            Button(remaining > 0 ? "Étape suivante (encore \(remaining) s)" : "Étape suivante") {
                                board.next()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        Spacer()
                        Button("Arrêter l'essai", role: .destructive) { confirmingStop = true }
                    }
                }
            }
            .padding(20)
            .frame(width: 560)
            .confirmationDialog("Arrêter l'appel d'essai ?", isPresented: $confirmingStop) {
                Button("Arrêter, les mesures faites sont gardées", role: .destructive, action: stop)
                Button("Continuer l'essai", role: .cancel) {}
            } message: {
                Text("Les étapes restantes ne seront pas mesurées.")
            }
        }
    }
}
