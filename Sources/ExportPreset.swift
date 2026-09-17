import UIKit

/// Ready-made export targets picked on the review screen, right before saving —
/// the moment people actually decide what a photo is for.
enum ExportPreset: String, CaseIterable, Identifiable {
    case original, story, print

    var id: String { rawValue }

    var label: String {
        switch self {
        case .original: return "Original (verlustfrei)"
        case .story: return "Story (9:16, Sicherheitszone)"
        case .print: return "Print (hohe Auflösung, sRGB)"
        }
    }

    func apply(to image: UIImage) -> UIImage {
        switch self {
        case .original:
            return image
        case .story:
            return Self.cropped(image, toAspect: 9.0 / 16.0)
        case .print:
            return Self.upscaledForPrint(image)
        }
    }

    private static func cropped(_ image: UIImage, toAspect targetAspect: CGFloat) -> UIImage {
        let size = image.size
        let currentAspect = size.width / size.height
        var cropRect = CGRect(origin: .zero, size: size)
        if currentAspect > targetAspect {
            let newWidth = size.height * targetAspect
            cropRect = CGRect(x: (size.width - newWidth) / 2, y: 0, width: newWidth, height: size.height)
        } else if currentAspect < targetAspect {
            let newHeight = size.width / targetAspect
            cropRect = CGRect(x: 0, y: (size.height - newHeight) / 2, width: size.width, height: newHeight)
        }
        let scaledRect = CGRect(x: cropRect.origin.x * image.scale, y: cropRect.origin.y * image.scale,
                                 width: cropRect.width * image.scale, height: cropRect.height * image.scale)
        guard let cgImage = image.cgImage, let cropped = cgImage.cropping(to: scaledRect) else { return image }
        return UIImage(cgImage: cropped, scale: image.scale, orientation: image.imageOrientation)
    }

    /// Renders through an explicit sRGB context at a print-safe resolution floor
    /// (long edge ≥ 3000px) instead of trusting whatever the device happened to capture at.
    private static func upscaledForPrint(_ image: UIImage) -> UIImage {
        let longEdge = max(image.size.width, image.size.height)
        let targetLongEdge: CGFloat = 3000
        let scaleFactor = max(1.0, targetLongEdge / longEdge)
        let targetSize = CGSize(width: image.size.width * scaleFactor, height: image.size.height * scaleFactor)

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: Int(targetSize.width), height: Int(targetSize.height),
                                       bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                                       bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let cgImage = image.cgImage else { return image }

        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(origin: .zero, size: targetSize))
        guard let output = context.makeImage() else { return image }
        return UIImage(cgImage: output)
    }
}
