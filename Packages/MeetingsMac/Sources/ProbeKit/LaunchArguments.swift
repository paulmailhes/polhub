public enum LaunchArguments {
    /// `--probe <id> [--seconds <n>] [--variant <v>] [--quit]`. Returns nil when no known probe is requested.
    public static func parse(_ args: [String]) -> ProbeRequest? {
        func value(after flag: String) -> String? {
            guard let i = args.firstIndex(of: flag), args.indices.contains(i + 1) else { return nil }
            return args[i + 1]
        }
        guard let raw = value(after: "--probe"), let probe = ProbeID(rawValue: raw) else { return nil }
        return ProbeRequest(
            probe: probe,
            seconds: value(after: "--seconds").flatMap(Int.init) ?? 60,
            variant: value(after: "--variant"),
            quitWhenDone: args.contains("--quit")
        )
    }
}
