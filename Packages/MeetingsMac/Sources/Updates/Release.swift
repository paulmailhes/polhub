import Foundation

/// `X.Y.Z`, compared number by number (0.10.0 comes after 0.9.9).
public struct SemanticVersion: Comparable, Hashable, Sendable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init?(_ text: String) {
        var text = text.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("v") { text.removeFirst() }
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, let major = Int(parts[0]), let minor = Int(parts[1]), let patch = Int(parts[2]),
              major >= 0, minor >= 0, patch >= 0 else { return nil }
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public static func < (a: SemanticVersion, b: SemanticVersion) -> Bool {
        (a.major, a.minor, a.patch) < (b.major, b.minor, b.patch)
    }

    public var description: String { "\(major).\(minor).\(patch)" }
}

/// A version published on GitHub, with its archive.
public struct Release: Equatable, Sendable {
    public let version: SemanticVersion
    /// What changed, as written in `CHANGELOG.md`.
    public let notes: String
    public let publishedAt: Date?
    public let archiveURL: URL

    public init(version: SemanticVersion, notes: String, publishedAt: Date?, archiveURL: URL) {
        self.version = version
        self.notes = notes
        self.publishedAt = publishedAt
        self.archiveURL = archiveURL
    }
}

public enum Releases {
    /// The archive every release carries: hub-board's, then the one of the versions published as Polhub, the name before
    /// 20/11 (the bridge 0.57.1 included).
    public static let archiveNames = ["hub-board.zip", "Polhub.zip"]
    /// The name of the archive this version publishes and downloads.
    public static var archiveName: String { archiveNames[0] }
    /// The public repository the versions are published on, then its name before 20/11.
    public static let repositories = ["paulmailhes/hub-board", "paulmailhes/polhub"]
    public static let listURLs: [URL] = repositories.map { URL(string: "https://api.github.com/repos/\($0)/releases?per_page=20")! }
    static let downloadPrefixes = repositories.map { "https://github.com/\($0)/releases/download/" }

    /// The first of `urls` that answers 200: before the repository is renamed, the new address does not answer yet.
    public static func fetchFirst(_ urls: [URL], get: @Sendable (URL) async throws -> (Data, Int)) async throws -> Data {
        for url in urls {
            if let (data, status) = try? await get(url), status == 200 { return data }
        }
        throw URLError(.badServerResponse)
    }

    private struct Payload: Decodable {
        struct Asset: Decodable {
            let name: String
            let browser_download_url: String
        }

        let tag_name: String
        let draft: Bool
        let prerelease: Bool
        let body: String?
        let published_at: String?
        let assets: [Asset]
    }

    /// The releases of GitHub's answer that can be installed: no draft, no pre-release, an archive.
    public static func parse(_ json: Data) throws -> [Release] {
        let iso = ISO8601DateFormatter()
        return try JSONDecoder().decode([Payload].self, from: json).compactMap { payload in
            // Only an archive of this repository's releases (review, minor 6).
            guard !payload.draft, !payload.prerelease, let version = SemanticVersion(payload.tag_name),
                  let asset = archiveNames.lazy.compactMap({ name in payload.assets.first { $0.name == name } }).first,
                  downloadPrefixes.contains(where: asset.browser_download_url.hasPrefix), let url = URL(string: asset.browser_download_url)
            else { return nil }
            return Release(version: version, notes: (payload.body ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                           publishedAt: payload.published_at.flatMap(iso.date(from:)), archiveURL: url)
        }
    }

    /// The releases newer than the installed version, the newest first.
    public static func newer(than current: SemanticVersion, in releases: [Release]) -> [Release] {
        releases.filter { $0.version > current }.sorted { $0.version > $1.version }
    }
}
