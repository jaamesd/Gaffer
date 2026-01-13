import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

class ImageProcessor {
    static let shared = ImageProcessor()

    // Tahoe window corner radius in pixels (measured from actual windows)
    var baseCornerRadius: CGFloat = 17

    private init() {}

    func processWallpaper(source: URL, output: URL, display: DisplayInfo, frameIndex: Int? = nil) async -> URL? {
        let ext = source.pathExtension.lowercased()

        if ext == "heic" {
            return await processHEIC(source: source, output: output, display: display, frameIndex: frameIndex)
        } else {
            return await processStaticImage(source: source, output: output, display: display)
        }
    }

    private func processStaticImage(source: URL, output: URL, display: DisplayInfo) async -> URL? {
        guard let image = NSImage(contentsOf: source) else {
            print("Failed to load image: \(source)")
            return nil
        }

        let targetSize = display.physicalRes
        guard let processed = applyMask(to: image, display: display, targetSize: targetSize) else {
            return nil
        }

        let ext = source.pathExtension.isEmpty ? "png" : source.pathExtension
        guard saveImage(processed, to: output, format: ext) else {
            return nil
        }

        return output
    }

    private func processHEIC(source: URL, output: URL, display: DisplayInfo, frameIndex: Int? = nil) async -> URL? {
        guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil) else {
            print("Failed to create image source for HEIC")
            return nil
        }

        let imageCount = CGImageSourceGetCount(imageSource)

        // If a specific frame is selected, extract and process just that frame
        if let idx = frameIndex, idx < imageCount {
            guard let cgImage = CGImageSourceCreateImageAtIndex(imageSource, idx, nil) else {
                print("Failed to load image at index \(idx)")
                return nil
            }

            let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))

            guard let processedNSImage = applyMask(to: nsImage, display: display, targetSize: display.physicalRes),
                  let processedCGImage = processedNSImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                print("Failed to process single frame")
                return nil
            }

            // Save as single-frame HEIC
            guard let destination = CGImageDestinationCreateWithURL(
                output as CFURL,
                UTType.heic.identifier as CFString,
                1,
                nil
            ) else {
                print("Failed to create HEIC destination")
                return nil
            }

            let imageProperties = CGImageSourceCopyPropertiesAtIndex(imageSource, idx, nil)
            CGImageDestinationAddImage(destination, processedCGImage, imageProperties)

            guard CGImageDestinationFinalize(destination) else {
                print("Failed to finalize HEIC")
                return nil
            }

            return output
        }

        // Process all frames (preserve dynamic wallpaper)
        guard let sourceProperties = CGImageSourceCopyProperties(imageSource, nil) as? [String: Any] else {
            return await processStaticImage(source: source, output: output, display: display)
        }

        guard let destination = CGImageDestinationCreateWithURL(
            output as CFURL,
            UTType.heic.identifier as CFString,
            imageCount,
            nil
        ) else {
            print("Failed to create HEIC destination")
            return nil
        }

        CGImageDestinationSetProperties(destination, sourceProperties as CFDictionary)

        for i in 0..<imageCount {
            guard let cgImage = CGImageSourceCreateImageAtIndex(imageSource, i, nil) else {
                print("Failed to load image at index \(i)")
                continue
            }

            let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))

            guard let processedNSImage = applyMask(to: nsImage, display: display, targetSize: display.physicalRes),
                  let processedCGImage = processedNSImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                print("Failed to process image at index \(i)")
                let imageProperties = CGImageSourceCopyPropertiesAtIndex(imageSource, i, nil)
                CGImageDestinationAddImage(destination, cgImage, imageProperties)
                continue
            }

            let imageProperties = CGImageSourceCopyPropertiesAtIndex(imageSource, i, nil)
            CGImageDestinationAddImage(destination, processedCGImage, imageProperties)
        }

        guard CGImageDestinationFinalize(destination) else {
            print("Failed to finalize HEIC")
            return nil
        }

        return output
    }

    private func applyMask(to image: NSImage, display: DisplayInfo, targetSize: CGSize) -> NSImage? {
        let width = Int(targetSize.width.rounded())
        let height = Int(targetSize.height.rounded())

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            print("Failed to create graphics context")
            return nil
        }

        // Draw the original image scaled to fill (CGContext origin is bottom-left)
        let imageRect = CGRect(x: 0, y: 0, width: width, height: height)
        if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            context.draw(cgImage, in: imageRect)
        } else {
            // Fallback for images without CGImage representation
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            image.draw(in: NSRect(origin: .zero, size: targetSize))
            NSGraphicsContext.restoreGraphicsState()
        }

        // Create inverse mask (flipped for CGContext's bottom-left origin)
        let maskPath = ContinuousCurve.inverseMaskFlipped(
            size: targetSize,
            menuBarHeight: display.menuBarHeight,
            cornerRadius: baseCornerRadius
        )

        // Fill the mask areas with black
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        context.addPath(maskPath)
        context.fillPath()

        guard let outputCGImage = context.makeImage() else {
            print("Failed to create output image")
            return nil
        }

        // Sanity check: verify black pixel count matches expected mask area
        if !validateBlackPixelCount(outputCGImage, display: display, targetSize: targetSize) {
            print("Warning: Black pixel count mismatch for \(display.name)")
        }

        return NSImage(cgImage: outputCGImage, size: NSSize(width: width, height: height))
    }

    /// Validate that the number of black pixels matches expected mask area
    private func validateBlackPixelCount(_ image: CGImage, display: DisplayInfo, targetSize: CGSize) -> Bool {
        let width = image.width
        let height = image.height

        // Calculate expected black pixel count
        // 1. Menubar strip: width * menuBarHeight
        let menubarPixels = Int(targetSize.width * display.menuBarHeight)

        // 2. Four corner regions (approximate - each corner is roughly r * r * (1 - π/4) pixels)
        // But with continuous curvature, the corner area is slightly larger
        let r = baseCornerRadius * display.scaleFactor
        let cornerArea = r * r * (1 - 0.785)  // 1 - π/4 ≈ 0.215
        let cornerPixels = Int(cornerArea * 4)

        let expectedBlack = menubarPixels + cornerPixels

        // Count actual black pixels (sample for performance)
        guard let dataProvider = image.dataProvider,
              let data = dataProvider.data,
              let ptr = CFDataGetBytePtr(data) else {
            return true  // Can't validate, assume OK
        }

        let bytesPerPixel = image.bitsPerPixel / 8
        let totalPixels = width * height
        var blackCount = 0

        // Sample every 10th pixel for performance
        let sampleRate = 10
        for i in stride(from: 0, to: totalPixels, by: sampleRate) {
            let offset = i * bytesPerPixel
            let r = ptr[offset]
            let g = ptr[offset + 1]
            let b = ptr[offset + 2]
            if r == 0 && g == 0 && b == 0 {
                blackCount += 1
            }
        }

        // Extrapolate to full image
        let actualBlack = blackCount * sampleRate

        // Allow 5% tolerance for rounding and sampling errors
        let tolerance = Double(expectedBlack) * 0.05 + 100  // +100 for very small masks
        let diff = abs(Double(actualBlack - expectedBlack))

        if diff > tolerance {
            print("Black pixel validation: expected ~\(expectedBlack), got ~\(actualBlack) (diff: \(Int(diff)))")
            return false
        }

        return true
    }

    /// Generate a preview image with mask applied (for UI display)
    func generatePreview(source: URL, cornerRadius: CGFloat, previewSize: CGSize) -> NSImage? {
        guard let image = NSImage(contentsOf: source) else { return nil }

        let width = Int(previewSize.width)
        let height = Int(previewSize.height)

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        let imageRect = CGRect(x: 0, y: 0, width: width, height: height)
        if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            context.draw(cgImage, in: imageRect)
        }

        // Scale corner radius for preview
        let scale = previewSize.width / 1920  // Assume preview represents ~1920px screen
        let scaledRadius = cornerRadius * scale * 2  // 2x for retina

        // Simple rounded corners for preview (no menubar)
        let cornerPath = CGMutablePath()
        cornerPath.addRect(CGRect(origin: .zero, size: previewSize))
        cornerPath.addRoundedRect(
            in: CGRect(origin: .zero, size: previewSize),
            cornerWidth: scaledRadius,
            cornerHeight: scaledRadius
        )

        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        context.addPath(cornerPath)
        context.fillPath(using: .evenOdd)

        guard let outputCGImage = context.makeImage() else { return nil }
        return NSImage(cgImage: outputCGImage, size: previewSize)
    }

    private func saveImage(_ image: NSImage, to url: URL, format: String) -> Bool {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return false
        }

        let uti: CFString
        switch format.lowercased() {
        case "png":
            uti = UTType.png.identifier as CFString
        case "jpg", "jpeg":
            uti = UTType.jpeg.identifier as CFString
        case "heic":
            uti = UTType.heic.identifier as CFString
        default:
            uti = UTType.png.identifier as CFString
        }

        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, uti, 1, nil) else {
            return false
        }

        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 0.95
        ]

        CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)
        return CGImageDestinationFinalize(destination)
    }
}
