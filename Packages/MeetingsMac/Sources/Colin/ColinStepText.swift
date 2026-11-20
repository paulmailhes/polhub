import Foundation
import Persistence
import PolhubDesign

/// What a step is about, as the screen can say it: a thread by its subject and person, a meeting by its title, and the
/// project — found in Polhub's own base by the screen, never copied from what the tool gave back.
public struct StepSubject: Equatable, Sendable {
    public var title: String?
    public var project: String?

    public init(title: String?, project: String?) {
        self.title = title
        self.project = project
    }
}

/// Steps said together: several reads of the same tool in a row; a write, always alone.
public struct StepGroup: Equatable, Identifiable, Sendable {
    public var steps: [ColinStep]

    public init(steps: [ColinStep]) {
        self.steps = steps
    }

    public var id: String { steps.first?.id ?? "" }
    /// Where it comes in the answer.
    public var position: Int { steps.first?.position ?? 0 }
    public var tool: String { steps.first?.tool ?? "" }
    public var running: Bool { steps.contains { $0.state == .running } }
    public var failed: Bool { steps.contains { $0.state == .failed } }
}

/// The words of Colin's actions (the Accueil's pass, 18/11): what he is doing in the present, what he did in the past,
/// in words Paul reads — never a tool's name, never what a tool gave back.
public enum ColinStepText {
    static let writes: Set<String> = ["brouillon", "projet", "action", "fait", "journal"]

    public static func isWrite(_ tool: String) -> Bool { writes.contains(tool) }

    /// Reads of the same tool in a row, at the same place, fold into one; a write stands alone.
    public static func groups(_ steps: [ColinStep]) -> [StepGroup] {
        var groups: [StepGroup] = []
        for step in steps {
            if let last = groups.indices.last, groups[last].tool == step.tool, groups[last].position == step.position, !isWrite(step.tool) {
                groups[last].steps.append(step)
            } else {
                groups.append(StepGroup(steps: [step]))
            }
        }
        return groups
    }

    public static func present(_ group: StepGroup, subject: (ColinStep) -> StepSubject) -> String {
        words(group, subject: subject).present + "…"
    }

    public static func past(_ group: StepGroup, subject: (ColinStep) -> StepSubject) -> String {
        words(group, subject: subject).past + (group.failed ? " (raté)" : "")
    }

    public static func symbol(_ tool: String) -> String {
        switch tool {
        case "mails", "mail": "envelope"
        case "contexte", "projets", "actions": "folder"
        case "reunions", "reunion": "waveform"
        case "chercher", "contacts": "magnifyingglass"
        case "agenda": "calendar"
        case "brouillon": "square.and.pencil"
        case "projet", "action", "fait", "journal": "checklist"
        default: "sparkle"
        }
    }

    private static func words(_ group: StepGroup, subject: (ColinStep) -> StepSubject) -> (present: String, past: String) {
        let subjects = group.steps.map(subject)
        let count = group.steps.count
        // The project they share, if they share one.
        let projects = Set(subjects.map(\.project))
        let project = projects.count == 1 ? projects.first.flatMap { $0 }.map(clip) : nil
        let at = project.map { " · \($0)" } ?? ""
        let title = subjects.first?.title.map(clip)
        let text = group.steps.first?.arguments["texte"].map(clip)
        switch group.tool {
        case "mails":
            return ("Cherche dans tes mails\(at)", "A cherché dans tes mails\(at)")
        case "mail":
            if count > 1 { return ("Lit \(count) fils\(at)", "A lu \(count) fils\(at)") }
            return title.map { ("Lit le fil « \($0) »", "A lu le fil « \($0) »") } ?? ("Lit un fil", "A lu un fil")
        case "contexte":
            if count > 1 { return ("Lit \(count) projets", "A lu \(count) projets") }
            return project.map { ("Lit le projet \($0)", "A lu le projet \($0)") } ?? ("Lit un projet", "A lu un projet")
        case "projets":
            return ("Regarde tes projets", "A regardé tes projets")
        case "actions":
            return project.map { ("Lit les actions \(Words.of($0))", "A lu les actions \(Words.of($0))") } ?? ("Lit les actions", "A lu les actions")
        case "reunions":
            return ("Cherche tes réunions\(at)", "A cherché tes réunions\(at)")
        case "reunion":
            if count > 1 { return ("Lit \(count) réunions", "A lu \(count) réunions") }
            return title.map { ("Lit la réunion « \($0) »", "A lu la réunion « \($0) »") } ?? ("Lit une réunion", "A lu une réunion")
        case "chercher", "contacts":
            return text.map { ("Cherche « \($0) »", "A cherché « \($0) »") } ?? ("Cherche", "A cherché")
        case "agenda":
            return ("Regarde ton agenda", "A regardé ton agenda")
        case "brouillon":
            return ("Écrit un brouillon", "A écrit un brouillon")
        case "projet", "action", "fait", "journal":
            return project.map { ("Met à jour \($0)", "A mis à jour \($0)") } ?? ("Met à jour un projet", "A mis à jour un projet")
        default:
            return ("Travaille", "A travaillé")
        }
    }

    /// 60 characters at most: what the model wrote, or what a third party wrote.
    static func clip(_ text: String) -> String {
        let flat = text.replacingOccurrences(of: "\n", with: " ")
        return flat.count > 60 ? String(flat.prefix(59)) + "…" : flat
    }
}
