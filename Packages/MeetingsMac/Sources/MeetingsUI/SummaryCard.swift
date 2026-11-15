import AppKit
import Domain
import Persistence
import PolhubDesign
import ProjectsUI
import Summarization
import SwiftUI

/// A meeting's summary (15/11): « Résumé », « Points clés », « Décisions », « Actions » (their boxes, « Ajouter au
/// projet » by hand), and « Copier le compte rendu », « Refaire ». A summary of another shape (the vault's) shows
/// as Markdown.
struct SummaryCard: View {
    /// For the copy: the meeting's title and date.
    let title: String
    let subtitle: String
    let summary: String?
    let job: SummaryJobRow?
    /// Where it is, under way, or what stops it.
    let status: String?
    let progress: SummaryProgress?
    let actions: [ActionRow]
    /// The meeting's project: its actions can go there.
    let project: ProjectRow?
    /// `nil` when « Refaire » cannot be asked now.
    let redo: (() -> Void)?
    let setDone: (ActionRow, Bool) -> Void
    let addToProject: (ActionRow, ProjectRow) -> Void
    @State private var copied = false

    private var hasSummary: Bool { summary?.isEmpty == false }
    private var sections: SummarySections? { summary.flatMap(SummaryText.sections) }
    /// Being written for the first time: grey lines stand for it.
    private var writing: Bool { job?.state == .running && !hasSummary }
    /// A failure offers « Réessayer » beside its reason, not « Refaire » above.
    private var redoAbove: (() -> Void)? { job?.state == .failed ? nil : redo }

    var body: some View {
        let sections = sections
        VStack(alignment: .leading, spacing: Space.l) {
            SectionTitle("Compte rendu", systemImage: "sparkles") { controls(missing: sections?.missing) }
            if let status { statusLine(status) }
            if let sections {
                parts(sections)
            } else if let summary, !summary.isEmpty {
                MarkdownView(text: summary).frame(maxWidth: .infinity, alignment: .leading)
            } else if writing {
                placeholder
            }
            if !actions.isEmpty { actionList }
        }
        .padding(Space.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
        .animation(Motion.gentle, value: summary)
        .animation(Motion.standard, value: job?.state)
    }

    // MARK: - The head

    @ViewBuilder
    private func controls(missing: String?) -> some View {
        HStack(spacing: Space.xs) {
            if let missing {
                Chip("Partiel", systemImage: "exclamationmark.triangle", tint: .orange)
                    .help(missing.prefix(1).uppercased() + missing.dropFirst() + ".")
            }
            // The words when there is room, the icons alone otherwise.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Space.xs) {
                    if hasSummary { textButton("Copier le compte rendu", systemImage: copied ? "checkmark" : "doc.on.doc", action: copy) }
                    if let redo = redoAbove { textButton("Refaire", systemImage: "arrow.clockwise", action: redo) }
                }
                HStack(spacing: 0) {
                    if hasSummary { IconButton(copied ? "checkmark" : "doc.on.doc", help: "Copier le compte rendu", action: copy) }
                    if let redo = redoAbove { IconButton("arrow.clockwise", help: "Refaire le compte rendu", action: redo) }
                }
            }
        }
    }

    private func textButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.meta.weight(.medium))
                .contentTransition(.symbolEffect(.replace))
                .padding(.horizontal, Space.s)
                .padding(.vertical, Space.xs)
        }
        .buttonStyle(.hover(.capsule))
        .foregroundStyle(.secondary)
        .fixedSize()
    }

    private func statusLine(_ status: String) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            if job?.state == .running {
                if let progress {
                    ProgressView(value: progress.fraction).frame(maxWidth: 260)
                } else {
                    ProgressView().progressViewStyle(.linear).frame(maxWidth: 260)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                Text(status)
                    .font(.rowBody)
                    .foregroundStyle(job?.state == .failed ? Color.orange : .secondary)
                    .contentTransition(.numericText())
                    .fixedSize(horizontal: false, vertical: true)
                if job?.state == .failed, let redo {
                    Button("Réessayer", action: redo).buttonStyle(.glass).controlSize(.small)
                }
            }
        }
    }

    /// Three grey lines while the summary is written.
    private var placeholder: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(String(repeating: "Le compte rendu de la réunion ", count: 3))
            Text(String(repeating: "Ce qui a été dit et décidé ", count: 3))
            Text("Les actions qui suivent")
        }
        .font(.rowBody)
        .lineLimit(1)
        .redacted(reason: .placeholder)
        .accessibilityHidden(true)
    }

    // MARK: - The four parts

    private func parts(_ sections: SummarySections) -> some View {
        VStack(alignment: .leading, spacing: Space.l) {
            if !sections.overview.isEmpty {
                part("Résumé") {
                    Text(sections.overview).font(.rowBody).lineSpacing(3).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }
            }
            if !sections.points.isEmpty {
                part("Points clés") {
                    ForEach(Array(sections.points.enumerated()), id: \.offset) { _, point in
                        HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                            Text("•").font(.rowBody.weight(.bold)).foregroundStyle(Color(hex: Palette.violet))
                            Text(point).font(.rowBody).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            if !sections.decisions.isEmpty {
                part("Décisions") {
                    ForEach(Array(sections.decisions.enumerated()), id: \.offset) { _, decision in
                        HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                            Image(systemName: "checkmark.seal.fill").font(.system(size: 12)).foregroundStyle(Color(hex: Palette.green))
                            Text(decision).font(.rowBody).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .transition(.opacity)
    }

    private func part<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(title).font(.meta.weight(.semibold)).foregroundStyle(.secondary)
            content()
        }
    }

    private var actionList: some View {
        part("Actions") {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(actions) { action in actionRow(action) }
            }
        }
    }

    private func actionRow(_ action: ActionRow) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s) {
            Toggle(isOn: Binding(get: { action.done }, set: { setDone(action, $0) })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(action.text).font(.rowBody).strikethrough(action.done).foregroundStyle(action.done ? .secondary : .primary)
                    if let owner = action.owner { Text(owner).font(.meta).foregroundStyle(.secondary) }
                }
            }
            .toggleStyle(.checkbox)
            Spacer(minLength: Space.s)
            if action.projectID != nil {
                Label("Dans le projet", systemImage: "checkmark.circle").font(.tag).foregroundStyle(.secondary).labelStyle(.titleAndIcon)
            } else if let project {
                Button { addToProject(action, project) } label: {
                    Label("Ajouter au projet", systemImage: "plus")
                        .font(.tag.weight(.medium))
                        .padding(.horizontal, Space.s)
                        .padding(.vertical, Space.xs)
                }
                .buttonStyle(.hover(.capsule))
                .foregroundStyle(.secondary)
                .fixedSize()
                .help("Ajoute cette action à celles de « \(project.name) »")
            }
        }
        .padding(.vertical, Space.xs)
        .hoverRow(inset: Space.s)
    }

    // MARK: - « Copier le compte rendu »

    private func copy() {
        guard let summary else { return }
        let text = SummaryText.export(title: title, subtitle: subtitle, markdown: summary, actions: actions)
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(text.plain, forType: .string)
        board.setString(text.html, forType: .html)
        withAnimation(Motion.quick) { copied = true }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation(Motion.quick) { copied = false }
        }
    }
}
