/// Parses what the Dia script returns: records ended by U+001E, fields separated by U+001F.
///
/// - a tab: seven fields, `windowID, tabID, loading, isFocused, isPinned, URL, title` ;
/// - `+`: one window was read without trouble ;
/// - `!`, error number, error message: one window could not be read.
enum DiaTabParser {
    struct Output: Equatable {
        var tabs: [BrowserTab] = []
        var windowsRead = 0
        var windowFailures: [ScriptFailure] = []
    }

    static let fieldSeparator: Character = "\u{1F}"
    static let recordSeparator: Character = "\u{1E}"
    /// What the script returns instead of waking Dia up when it is not running.
    static let notRunningSentinel = "~notrunning"

    static func parse(_ raw: String) -> [BrowserTab] {
        parseDetailed(raw).tabs
    }

    static func parseDetailed(_ raw: String) -> Output {
        var output = Output()
        var seen = Set<String>()
        for record in raw.split(separator: recordSeparator, omittingEmptySubsequences: true) {
            // The title comes last and is kept whole, whatever it contains.
            let fields = record.split(separator: fieldSeparator, maxSplits: 6, omittingEmptySubsequences: false)
            if fields.count == 1, fields[0] == "+" {
                output.windowsRead += 1
            } else if fields.count >= 2, fields[0] == "!" {
                output.windowFailures.append(ScriptFailure(
                    code: Int(fields[1]) ?? 0,
                    message: fields.dropFirst(2).joined(separator: " ")
                ))
            } else if fields.count == 7 {
                let tabID = String(fields[1])
                guard seen.insert(tabID).inserted else { continue }
                output.tabs.append(BrowserTab(
                    windowID: String(fields[0]),
                    tabID: tabID,
                    url: String(fields[5]),
                    title: String(fields[6]),
                    isLoading: fields[2] == "true",
                    isFocused: fields[3] == "true",
                    isPinned: fields[4] == "true"
                ))
            }
        }
        return output
    }
}
