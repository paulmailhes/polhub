import CryptoKit
import Foundation

/// A folder of a model on Hugging Face, at a fixed revision, and where it goes on this Mac (20/11, the add-ons: a new user
/// who installs Réunions downloads its model; on Paul's Mac it is already there).
public struct ModelSource: Sendable {
    public let repo: String
    public let revision: String
    /// The folder of the repository; empty for its root.
    public let folder: String
    /// The files of the folder that are taken, by their path in it.
    public let include: @Sendable (String) -> Bool
    public let destination: URL

    public init(repo: String, revision: String, folder: String, include: @escaping @Sendable (String) -> Bool, destination: URL) {
        self.repo = repo
        self.revision = revision
        self.folder = folder
        self.include = include
        self.destination = destination
    }

    /// The three models of Réunions, at the revisions measured on 20/11: WhisperKit's large-v3-turbo (24 files, 1.6 GB),
    /// the tokenizer of whisper-large-v3 (its small files at the root) and Silero.
    public static func standard(_ locations: ModelLocations) -> [ModelSource] {
        [
            ModelSource(repo: "argmaxinc/whisperkit-coreml", revision: "0f63a7800b00dd0226abd051b906c246e1907482",
                        folder: "openai_whisper-large-v3-v20240930_turbo", include: { _ in true }, destination: locations.whisperFolder),
            ModelSource(repo: "openai/whisper-large-v3", revision: "06f233fe06e710322aca913c1bc4249a0d71fce1", folder: "",
                        include: { path in !path.contains("/") && (path.hasSuffix(".json") || path.hasSuffix(".txt")) },
                        destination: locations.tokenizerFolder.appending(path: "models/openai/whisper-large-v3", directoryHint: .isDirectory)),
            ModelSource(repo: "FluidInference/silero-vad-coreml", revision: "b419383c55c110e2c9271fa6ee0ea83d03c70d96",
                        folder: "silero-vad-unified-256ms-v6.2.1.mlmodelc", include: { _ in true }, destination: locations.sileroModel),
        ]
    }
}

/// A file of a model: its path in the folder, its size, and the fingerprint it is checked against (SHA-256 for a large
/// file kept by Git LFS, the Git fingerprint of its blob otherwise).
public struct ModelFile: Sendable, Equatable {
    public let path: String
    public let size: Int64
    public let sha256: String?
    public let gitSHA1: String?
}

public enum ModelDownloadError: Error, Equatable, CustomStringConvertible {
    case listing(String)
    case mismatch(String)
    case http(Int)

    public var description: String {
        switch self {
        case .listing(let repo): "la liste des fichiers de \(repo) est illisible"
        case .mismatch(let path): "« \(path) » est arrivé abîmé"
        case .http(let status): "Hugging Face a répondu \(status)"
        }
    }
}

/// Downloads models from Hugging Face: each file checked by its fingerprint, into a folder beside the destination, which
/// replaces it in one gesture once every file is right. A file that does not match installs nothing.
public struct ModelDownload: Sendable {
    let session: URLSession
    let host: URL

    public init(session: URLSession = .shared, host: URL = URL(string: "https://huggingface.co")!) {
        self.session = session
        self.host = host
    }

    private struct Entry: Decodable {
        struct LFS: Decodable { let oid: String; let size: Int64 }
        let type: String
        let path: String
        let size: Int64?
        let oid: String?
        let lfs: LFS?
    }

    /// The files of the source's folder that it takes, their paths made relative to the folder.
    public func files(_ source: ModelSource) async throws -> [ModelFile] {
        var url = host.appending(path: "api/models/\(source.repo)/tree/\(source.revision)")
        if !source.folder.isEmpty { url = url.appending(path: source.folder) }
        url.append(queryItems: [URLQueryItem(name: "recursive", value: "true")])
        let (data, response) = try await session.data(from: url)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw ModelDownloadError.http(status) }
        guard let entries = try? JSONDecoder().decode([Entry].self, from: data) else { throw ModelDownloadError.listing(source.repo) }
        let prefix = source.folder.isEmpty ? "" : source.folder + "/"
        return entries.compactMap { entry in
            guard entry.type == "file", entry.path.hasPrefix(prefix) else { return nil }
            let path = String(entry.path.dropFirst(prefix.count))
            guard source.include(path) else { return nil }
            if let lfs = entry.lfs { return ModelFile(path: path, size: lfs.size, sha256: lfs.oid, gitSHA1: nil) }
            return ModelFile(path: path, size: entry.size ?? 0, sha256: nil, gitSHA1: entry.oid)
        }
    }

    /// Every source, its files listed, downloaded, checked, then put in place; `progress` gets the bytes done and the total.
    public func install(_ sources: [ModelSource], progress: @Sendable (Int64, Int64) -> Void) async throws {
        var plan: [(ModelSource, [ModelFile])] = []
        for source in sources { plan.append((source, try await files(source))) }
        let total = plan.flatMap(\.1).reduce(0) { $0 + $1.size }
        var done: Int64 = 0
        progress(0, total)
        let manager = FileManager.default
        for (source, files) in plan {
            let partial = source.destination.deletingLastPathComponent()
                .appending(path: source.destination.lastPathComponent + ".partiel", directoryHint: .isDirectory)
            try? manager.removeItem(at: partial)
            try manager.createDirectory(at: partial, withIntermediateDirectories: true)
            do {
                for file in files {
                    let target = partial.appending(path: file.path)
                    try manager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try await fetch(source, file, to: target)
                    guard try Self.matches(target, file) else { throw ModelDownloadError.mismatch(file.path) }
                    done += file.size
                    progress(done, total)
                }
                if manager.fileExists(atPath: source.destination.path(percentEncoded: false)) {
                    _ = try manager.replaceItemAt(source.destination, withItemAt: partial)
                } else {
                    try manager.createDirectory(at: source.destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try manager.moveItem(at: partial, to: source.destination)
                }
            } catch {
                try? manager.removeItem(at: partial)
                throw error
            }
        }
    }

    private func fetch(_ source: ModelSource, _ file: ModelFile, to target: URL) async throws {
        var url = host.appending(path: "\(source.repo)/resolve/\(source.revision)")
        if !source.folder.isEmpty { url = url.appending(path: source.folder) }
        url = url.appending(path: file.path)
        let (downloaded, response) = try await session.download(from: url)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw ModelDownloadError.http(status) }
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.moveItem(at: downloaded, to: target)
    }

    /// Read by pieces: a model's weights do not fit in memory twice.
    static func matches(_ url: URL, _ file: ModelFile) throws -> Bool {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        if let expected = file.sha256 {
            var hasher = SHA256()
            while let piece = try handle.read(upToCount: 4 << 20), !piece.isEmpty { hasher.update(data: piece) }
            return hex(hasher.finalize()) == expected
        }
        guard let expected = file.gitSHA1 else { return false }
        let size = try FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))[.size] as? Int ?? 0
        var hasher = Insecure.SHA1()
        hasher.update(data: Data("blob \(size)\0".utf8))
        while let piece = try handle.read(upToCount: 4 << 20), !piece.isEmpty { hasher.update(data: piece) }
        return hex(hasher.finalize()) == expected
    }

    static func hex(_ digest: some Sequence<UInt8>) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}
