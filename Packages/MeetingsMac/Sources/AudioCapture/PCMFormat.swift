/// Linear PCM as the capture chain carries it: 32-bit float, little-endian, interleaved.
public struct PCMFormat: Equatable, Sendable, Codable {
    public let sampleRate: Double
    public let channels: Int

    public init(sampleRate: Double, channels: Int) {
        self.sampleRate = sampleRate
        self.channels = channels
    }

    public var bytesPerFrame: Int { channels * MemoryLayout<Float>.size }
}
