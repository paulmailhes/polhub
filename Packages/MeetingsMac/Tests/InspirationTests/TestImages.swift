import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Images drawn by the tests themselves: no binary in the repository.
enum TestImages {
    struct Color {
        let red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat
        static let red = Color(red: 1, green: 0, blue: 0, alpha: 1)
        static let blue = Color(red: 0, green: 0, blue: 1, alpha: 1)
        static let green = Color(red: 0, green: 0.6, blue: 0.2, alpha: 1)
        static let clear = Color(red: 0, green: 0, blue: 0, alpha: 0)
    }

    /// A plain image, with a darker square in its middle so that it is not one flat color.
    static func image(width: Int, height: Int, color: Color, background: Color? = nil, space: CGColorSpace? = nil) -> CGImage {
        let space = space ?? CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        if let background {
            context.setFillColor(CGColor(colorSpace: space, components: [background.red, background.green, background.blue, background.alpha])!)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        let inset = CGRect(x: width / 4, y: height / 4, width: width / 2, height: height / 2)
        context.setFillColor(CGColor(colorSpace: space, components: [color.red, color.green, color.blue, color.alpha])!)
        context.fill(background == nil ? inset : CGRect(x: 0, y: 0, width: width, height: height))
        if background != nil || color.alpha == 1 {
            context.setFillColor(CGColor(colorSpace: space, components: [color.red * 0.6, color.green * 0.6, color.blue * 0.6, 1])!)
            context.fill(CGRect(x: width / 2 - 2, y: height / 2 - 2, width: 4, height: 4))
        }
        return context.makeImage()!
    }

    static func encode(_ images: [CGImage], type: UTType, properties: [CFString: Any] = [:], frameProperties: [CFString: Any] = [:]) -> Data {
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, images.count, nil)!
        CGImageDestinationSetProperties(destination, properties as CFDictionary)
        for image in images { CGImageDestinationAddImage(destination, image, frameProperties as CFDictionary) }
        precondition(CGImageDestinationFinalize(destination))
        return data as Data
    }

    static func png(width: Int, height: Int, color: Color = .green, transparent: Bool = false, space: CGColorSpace? = nil) -> Data {
        encode([image(width: width, height: height, color: color, background: transparent ? nil : .blue, space: space)], type: .png)
    }

    static func jpeg(width: Int, height: Int, color: Color = .green, frameProperties: [CFString: Any] = [:]) -> Data {
        encode([image(width: width, height: height, color: color, background: .blue)], type: .jpeg, frameProperties: frameProperties)
    }

    /// An animated GIF: one full frame per color.
    static func gif(width: Int, height: Int, frames: [Color]) -> Data {
        let images = frames.map { image(width: width, height: height, color: $0, background: $0) }
        return encode(images, type: .gif,
                      properties: [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]],
                      frameProperties: [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.1]])
    }

    /// What an image file holds: its size, type, color space, properties and the color of one pixel.
    struct Probe {
        let width: Int
        let height: Int
        let type: String
        let colorSpace: String?
        let properties: [CFString: Any]

        init?(_ url: URL) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
            width = image.width
            height = image.height
            type = CGImageSourceGetType(source) as String? ?? ""
            colorSpace = image.colorSpace?.name as String?
            properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
            self.image = image
        }

        private let image: CGImage

        /// The color at (x, y), from the top left, in sRGB 0…255.
        func pixel(x: Int, y: Int) -> (red: Int, green: Int, blue: Int) {
            var bytes = [UInt8](repeating: 0, count: 4)
            let context = CGContext(data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: -x, y: -(height - 1 - y), width: width, height: height))
            return (Int(bytes[0]), Int(bytes[1]), Int(bytes[2]))
        }
    }
}
