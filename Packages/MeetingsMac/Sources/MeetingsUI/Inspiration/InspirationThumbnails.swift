import AppKit
import ImageIO
import PolhubDesign
import SwiftUI

// The images of « Inspiration », light on memory (16/11): a card of 300 points never decodes the 1 600-pixel image
// it shows, only a thumbnail at the pixels it fills, made by ImageIO off the main thread and kept in memory while
// there is room. Smooth with a thousand cards.

/// How an image takes its box: cropped to fill it (a card, 4:3), or whole inside it (an item's page).
enum ThumbnailMode: Hashable, Sendable {
    case fill, fit
}

/// The thumbnails made, by file and size; the least recently shown go when the memory set aside is full, all of them
/// when macOS runs short of memory. Its own cache rather than `NSCache`, which lets go of images whenever it likes:
/// what it keeps is then known (16/11: the tests failed under load).
final class InspirationThumbnails: @unchecked Sendable {
    static let shared = InspirationThumbnails()

    /// About forty card thumbnails, a few screens of a grid (review of 16/11: 256 Mo stayed all day in an app that
    /// never quits).
    static let memory = 64 << 20
    /// The sizes asked go up by steps: a window resized by a few points reuses the thumbnails made.
    static let step = 128

    private let limit: Int
    private let lock = NSLock()
    private var entries: [String: (image: CGImage, cost: Int)] = [:]
    /// The keys, the least recently shown first.
    private var order: [String] = []
    private var total = 0
    private var pressure: (any DispatchSourceMemoryPressure)?

    init(memory: Int = InspirationThumbnails.memory) {
        limit = memory
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .global(qos: .utility))
        source.setEventHandler { [weak self] in self?.purge() }
        source.resume()
        pressure = source
    }

    deinit {
        pressure?.cancel()
    }

    private func object(_ key: String) -> CGImage? {
        lock.withLock {
            guard let entry = entries[key] else { return nil }
            if let index = order.firstIndex(of: key) {
                order.remove(at: index)
                order.append(key)
            }
            return entry.image
        }
    }

    private func store(_ image: CGImage, key: String) {
        let cost = image.bytesPerRow * image.height
        lock.withLock {
            if let old = entries[key] {
                total -= old.cost
                order.removeAll { $0 == key }
            }
            entries[key] = (image, cost)
            order.append(key)
            total += cost
            // The newest always stays, even alone past the limit.
            while total > limit, order.count > 1 {
                total -= entries.removeValue(forKey: order.removeFirst())?.cost ?? 0
            }
        }
    }

    static func key(_ url: URL, pixels: CGSize, mode: ThumbnailMode) -> String {
        "\(url.path(percentEncoded: false))|\(Int(pixels.width))x\(Int(pixels.height))|\(mode == .fill ? "f" : "t")"
    }

    /// The box in pixels, rounded up to the step.
    static func bucket(_ size: CGSize) -> CGSize {
        func up(_ value: CGFloat) -> CGFloat { CGFloat((max(1, Int(value.rounded(.up))) + step - 1) / step * step) }
        return CGSize(width: up(size.width), height: up(size.height))
    }

    /// Paul left « Inspiration », or the window closed: the thumbnails go.
    func purge() {
        lock.withLock {
            entries.removeAll()
            order.removeAll()
            total = 0
        }
    }

    func cached(_ url: URL, pixels: CGSize, mode: ThumbnailMode) -> CGImage? {
        object(Self.key(url, pixels: Self.bucket(pixels), mode: mode))
    }

    /// The image of `url` for a box of `pixels`, from memory or made now off the main thread; `nil` when the file
    /// is missing or not an image.
    func image(_ url: URL, pixels: CGSize, mode: ThumbnailMode) async -> CGImage? {
        let box = Self.bucket(pixels)
        let key = Self.key(url, pixels: box, mode: mode)
        if let image = object(key) { return image }
        let made = await Self.make(url, pixels: box, mode: mode)
        if let made { store(made, key: key) }
        return made
    }

    @concurrent
    static func make(_ url: URL, pixels: CGSize, mode: ThumbnailMode) async -> CGImage? {
        guard !Task.isCancelled else { return nil }
        return decode(url, pixels: pixels, mode: mode)
    }

    /// ImageIO's thumbnail, its long side just what the box needs: the file's header gives the image's size, the
    /// image is never decoded whole.
    static func decode(_ url: URL, pixels: CGSize, mode: ThumbnailMode) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue, width > 0, height > 0 else { return nil }
        let side = longSide(image: CGSize(width: width, height: height), box: pixels, mode: mode)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: side,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// The image's size in pixels, from its header alone.
    static func pixelSize(_ url: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue, width > 0, height > 0 else { return nil }
        return CGSize(width: width, height: height)
    }

    @concurrent
    static func aspectRatio(_ url: URL) async -> CGFloat? {
        pixelSize(url).map { $0.width / $0.height }
    }

    /// The long side of the thumbnail that fills (or fits in) the box, never larger than the image.
    static func longSide(image: CGSize, box: CGSize, mode: ThumbnailMode) -> Int {
        guard image.width > 0, image.height > 0, box.width > 0, box.height > 0 else { return 1 }
        let scales = (box.width / image.width, box.height / image.height)
        let scale = min(1, mode == .fill ? max(scales.0, scales.1) : min(scales.0, scales.1))
        return max(1, Int((max(image.width, image.height) * scale).rounded(.up)))
    }
}

/// An image of « Inspiration » in its box: cropped to fill it, or whole inside it; a calm placeholder while it
/// loads or when the file is missing.
struct InspirationImage: View {
    let url: URL?
    var mode: ThumbnailMode = .fill
    /// The icon of the placeholder.
    var icon: AppIcon = .inspiration
    var thumbnails: InspirationThumbnails = .shared
    @State private var image: CGImage?
    @State private var box: CGSize = .zero
    @Environment(\.displayScale) private var scale

    var body: some View {
        let pixels = CGSize(width: box.width * scale, height: box.height * scale)
        // The box is the space offered, never the image's: the image sits in an overlay, so it cannot make its card
        // larger, whatever its size or the moment it arrives.
        Rectangle()
            .fill(image == nil ? Surface.fill : Color.clear)
            .overlay {
                if image == nil { AppIconImage(icon, size: 28).foregroundStyle(.tertiary) }
            }
            .overlay {
                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: mode == .fill ? .fill : .fit)
                        .transition(.opacity)
                }
            }
            .clipped()
        .onGeometryChange(for: CGSize.self) { $0.size } action: { box = $0 }
        .task(id: TaskKey(url: url, pixels: InspirationThumbnails.bucket(pixels), mode: mode)) {
            guard let url, box.width > 0, box.height > 0 else { return }
            if let hit = thumbnails.cached(url, pixels: pixels, mode: mode) {
                image = hit
                return
            }
            let made = await thumbnails.image(url, pixels: pixels, mode: mode)
            guard !Task.isCancelled else { return }
            withAnimation(Motion.quick) { image = made }
        }
        .accessibilityHidden(true)
    }

    private struct TaskKey: Hashable {
        let url: URL?
        let width: Int
        let height: Int
        let mode: ThumbnailMode

        init(url: URL?, pixels: CGSize, mode: ThumbnailMode) {
            self.url = url
            self.width = Int(pixels.width)
            self.height = Int(pixels.height)
            self.mode = mode
        }
    }
}
