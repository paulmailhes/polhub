import AudioCapture
import CoreAudio
import Foundation

/// The name macOS shows for an audio device, from its identifier; the identifier itself when it has none.
public enum DeviceNames {
    public static func name(forUID uid: String) -> String {
        guard let device = try? HAL.device(forUID: uid),
              let name = try? HAL.string(device, kAudioObjectPropertyName), !name.isEmpty
        else { return uid }
        return name
    }
}
