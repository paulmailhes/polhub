public enum LaunchArguments {
    /// `--probe <id> [--seconds <n>] [--variant <v>] [--quit]`. Returns nil when no known probe is requested.
    /// Only the probes of the window: the one of Colin has its button, with its guards (no meeting, a real account),
    /// which a command line would skip.
    public static func parse(_ args: [String]) -> ProbeRequest? {
        func value(after flag: String) -> String? {
            guard let i = args.firstIndex(of: flag), args.indices.contains(i + 1) else { return nil }
            return args[i + 1]
        }
        guard let raw = value(after: "--probe"), let probe = ProbeID(rawValue: raw), ProbeID.listed.contains(probe) else { return nil }
        return ProbeRequest(
            probe: probe,
            seconds: value(after: "--seconds").flatMap(Int.init) ?? 60,
            variant: value(after: "--variant"),
            quitWhenDone: args.contains("--quit")
        )
    }
}
