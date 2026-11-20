import Foundation

/// What hub accepts of a launch of Colin (18/11), read in each `init` (Claude Code says it again at every turn):
/// his tools exactly, his one server connected, nothing of the user's, the mode that asks nothing, Opus, no key.
public enum ColinInitCheck {
    /// `nil` when the launch is what hub asked for; else a word that says what is wrong, for the trace.
    public static func problem(_ launch: ClaudeInit, tools: Set<String>) -> String? {
        if !launch.missing.isEmpty { return "incomplet" }
        if Set(launch.tools) != tools || launch.tools.count != tools.count { return "outils" }
        if launch.servers != ["hub": "connected"] { return "serveurs" }
        if launch.plugins > 0 { return "plugins" }
        if launch.skills > 0 { return "skills" }
        if launch.slashCommands > 0 { return "commandes" }
        if launch.memoryPaths > 0 { return "memoire" }
        if launch.directories > 0 { return "dossiers" }
        if launch.permissionMode != "dontAsk" { return "mode" }
        if !launch.model.lowercased().contains("opus") { return "modele" }
        if launch.apiKeySource != "none" { return "cle" }
        return nil
    }
}
