import Foundation
import Observability

/// Where the models are: downloaded once, with Paul's agreement (13/11/2026), and never by the app. The
/// production and development versions share them.
public struct ModelLocations: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    public static var standard: ModelLocations {
        ModelLocations(root: AppFolders.support(dev: false).appending(path: "Models", directoryHint: .isDirectory))
    }

    /// WhisperKit's large-v3-turbo (`argmaxinc/whisperkit-coreml`).
    public var whisperFolder: URL { root.appending(path: "whisperkit/openai_whisper-large-v3-v20240930_turbo", directoryHint: .isDirectory) }
    /// The tokenizer, in the Hugging Face layout WhisperKit reads (`models/openai/whisper-large-v3`).
    public var tokenizerFolder: URL { root.appending(path: "whisperkit/tokenizer", directoryHint: .isDirectory) }
    /// Silero, compiled for Core ML (`FluidInference/silero-vad-coreml`).
    public var sileroModel: URL { root.appending(path: "silero/silero-vad-unified-256ms-v6.2.1.mlmodelc", directoryHint: .isDirectory) }

    /// The models that are not where they should be, named for the Diagnostic.
    public func missing() -> [String] {
        let manager = FileManager.default
        var missing: [String] = []
        if !manager.fileExists(atPath: whisperFolder.appending(path: "AudioEncoder.mlmodelc").path(percentEncoded: false)) {
            missing.append("modèle de transcription (WhisperKit)")
        }
        if !manager.fileExists(atPath: tokenizerFolder.appending(path: "models/openai/whisper-large-v3/tokenizer.json").path(percentEncoded: false)) {
            missing.append("tokeniseur de WhisperKit")
        }
        if !manager.fileExists(atPath: sileroModel.path(percentEncoded: false)) {
            missing.append("détecteur de voix (Silero)")
        }
        return missing
    }
}
