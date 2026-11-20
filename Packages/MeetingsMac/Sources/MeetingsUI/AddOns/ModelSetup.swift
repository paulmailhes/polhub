import Foundation
import HubDesign
import Transcription

/// The model of Réunions on this Mac (20/11, the add-ons): downloaded when Réunions is installed and it is missing, its
/// progress shown in the row of Réglages › Add-ons, taken away when Réunions is removed. On Paul's Mac it is already there.
@MainActor public final class ModelSetup {
    let locations: ModelLocations
    let download: ModelDownload
    /// The page whose row shows the download's progress.
    public weak var control: AddOnControl?

    public init(locations: ModelLocations = .standard, download: ModelDownload = ModelDownload()) {
        self.locations = locations
        self.download = download
    }

    /// What is missing, already downloaded or not; nil when the model is ready, else why, in hub's words.
    public func prepare() async -> String? {
        guard !locations.missing().isEmpty else { return nil }
        do {
            try await download.install(ModelSource.standard(locations)) { [weak self] done, total in
                let value = total > 0 ? Double(done) / Double(total) : 0
                Task { @MainActor in self?.control?.progress = value }
            }
            return nil
        } catch {
            let problem = Words.problem("Le modèle de transcription n'a pas pu être téléchargé", error)
            if let journal = problem.journal { NSLog("%@", journal) }
            return problem.sentence
        }
    }

    /// Réunions removed: its model goes (1.6 GB); the meetings recorded stay.
    public func remove() {
        for folder in [locations.whisperFolder, locations.tokenizerFolder, locations.sileroModel] {
            try? FileManager.default.removeItem(at: folder)
        }
    }
}
