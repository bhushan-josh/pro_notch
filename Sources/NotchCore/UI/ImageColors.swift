import AppKit
import CoreImage
import SwiftUI

public enum ImageColors {
    private static let context = CIContext(options: [.workingColorSpace: NSNull()])

    /// Average color of the image, brightened so it reads against black. Nil for unreadable images.
    public static func dominantColor(of image: NSImage) -> Color? {
        guard let tiff = image.tiffRepresentation, let input = CIImage(data: tiff) else { return nil }
        let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: input,
            kCIInputExtentKey: CIVector(cgRect: input.extent),
        ])
        guard let output = filter?.outputImage else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(output, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
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
