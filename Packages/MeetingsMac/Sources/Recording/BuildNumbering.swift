import Foundation

/// Each build of a stream writes to its own folder, `bNN` or `bNN-<micro>`. After a crash, a meeting goes
/// on in the same folder: the next build takes the number after the highest one already there, so no
/// segment is ever overwritten.
public enum BuildNumbering {
    public static func next(existingFolders: [String]) -> Int {
        let numbers = existingFolders.compactMap { name -> Int? in
            guard let match = name.firstMatch(of: /^b(\d+)(?:-|$)/) else { return nil }
            return Int(match.output.1)
        }
        return (numbers.max() ?? 0) + 1
    }
}
