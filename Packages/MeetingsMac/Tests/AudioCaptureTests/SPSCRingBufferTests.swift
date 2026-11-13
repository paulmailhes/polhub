import Testing
@testable import AudioCapture

@Suite struct SPSCRingBufferTests {
    func write(_ ring: SPSCRingBuffer, _ values: [Float], frames: Int) -> Int {
        values.withUnsafeBufferPointer { ring.write($0.baseAddress!, frames: frames) }
    }

    func read(_ ring: SPSCRingBuffer, frames: Int, channels: Int = 1) -> [Float] {
        var out = [Float](repeating: -1, count: frames * channels)
        let n = out.withUnsafeMutableBufferPointer { ring.read(into: $0.baseAddress!, maxFrames: frames) }
        return Array(out.prefix(n * channels))
    }

    @Test func ringRoundTripsAcrossWraparound() {
        let ring = SPSCRingBuffer(capacityFrames: 8, channels: 1)
        #expect(write(ring, [1, 2, 3, 4, 5, 6], frames: 6) == 6)
        #expect(read(ring, frames: 6) == [1, 2, 3, 4, 5, 6])
        #expect(write(ring, [7, 8, 9, 10, 11, 12], frames: 6) == 6)   // wraps past the end of the storage
        #expect(read(ring, frames: 6) == [7, 8, 9, 10, 11, 12])
        #expect(ring.droppedFrames == 0)
    }

    @Test func ringReportsOverflow() {
        let ring = SPSCRingBuffer(capacityFrames: 8, channels: 1)
        #expect(write(ring, [Float](repeating: 1, count: 12), frames: 12) == 8)
        #expect(ring.droppedFrames == 4)
        #expect(read(ring, frames: 20).count == 8)
    }

    @Test func ringKeepsStereoFramesWhole() {
        let ring = SPSCRingBuffer(capacityFrames: 4, channels: 2)
        #expect(write(ring, [1, -1, 2, -2, 3, -3], frames: 3) == 3)
        #expect(read(ring, frames: 2, channels: 2) == [1, -1, 2, -2])
        #expect(write(ring, [4, -4, 5, -5, 6, -6], frames: 3) == 3)
        #expect(read(ring, frames: 4, channels: 2) == [3, -3, 4, -4, 5, -5, 6, -6])
    }
}
