import AppKit
import CoreImage
import SwiftUI

public enum ImageColors {
    private static let context = CIContext(options: [.workingColorSpace: NSNull()])

    /// Average color of the image, brightened so it reads against black. Nil for unreadable images.
    public static func dominantColor(of image: NSImage) -> Color? {
        guard let tiff = image.tiffRepresentation, let input = CIImage(data: tiff) else { return nil }
        return average(input, in: input.extent)
    }

    /// Top-half and bottom-half averages, for a vertical gradient that follows the artwork.
    public static func gradientColors(of image: NSImage) -> [Color]? {
        guard let tiff = image.tiffRepresentation, let input = CIImage(data: tiff) else { return nil }
        let extent = input.extent
        let half = extent.height / 2
        let top = CGRect(x: extent.minX, y: extent.minY + half, width: extent.width, height: half)
        let bottom = CGRect(x: extent.minX, y: extent.minY, width: extent.width, height: half)
        guard let first = average(input, in: top), let second = average(input, in: bottom) else { return nil }
        return [first, second]
    }

    private static func average(_ input: CIImage, in extent: CGRect) -> Color? {
        let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: input,
            kCIInputExtentKey: CIVector(cgRect: extent),
        ])
        guard let output = filter?.outputImage else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(output, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(origin: output.extent.origin, size: CGSize(width: 1, height: 1)), format: .RGBA8, colorSpace: nil)
        let color = NSColor(
            red: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255, blue: CGFloat(pixel[2]) / 255, alpha: 1
        )
        guard let hsb = color.usingColorSpace(.deviceRGB) else { return Color(nsColor: color) }
        let adjusted = NSColor(
            hue: hsb.hueComponent,
            saturation: min(1, hsb.saturationComponent * 1.15),
            brightness: max(0.6, hsb.brightnessComponent),
            alpha: 1
        )
        return Color(nsColor: adjusted)
    }
}
