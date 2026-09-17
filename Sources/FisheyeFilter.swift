import CoreImage

/// Loads the custom Metal-based CIKernels (FisheyeKernels.metal) and applies the
/// lens-accurate equisolid warp + chromatic aberration + vignette. Falls back to
/// CoreImage's built-in CIBumpDistortion if the Metal library can't be loaded for
/// any reason, so the app never just shows a blank frame.
final class FisheyeFilter {
    static let shared = FisheyeFilter()

    private let warpKernel: CIWarpKernel?
    private let gradeKernel: CIColorKernel?

    private init() {
        guard let url = Bundle.main.url(forResource: "default", withExtension: "metallib"),
              let data = try? Data(contentsOf: url) else {
            warpKernel = nil
            gradeKernel = nil
            return
        }
        warpKernel = try? CIWarpKernel(functionName: "fisheyeWarp", fromMetalLibraryData: data)
        gradeKernel = try? CIColorKernel(functionName: "fisheyeGrade", fromMetalLibraryData: data)
    }

    /// - Parameters:
    ///   - depthMask: optional CIImage (0 = far/background, 1 = near/subject), same extent
    ///     as `image`. When provided (LiDAR devices only), the warp is blended so subjects
    ///     close to the camera stay closer to their true shape while the background takes
    ///     the full bulge — real depth-aware distortion, not just a uniform effect.
    func apply(to image: CIImage, strength: Double, chromaticAberration: Double, vignette: Double,
               depthMask: CIImage?) -> CIImage {
        let extent = image.extent
        let w = Float(extent.width), h = Float(extent.height)

        guard let warpKernel else {
            return legacyFallback(image, strength: strength)
        }

        let full = warpKernel.apply(extent: extent, roiCallback: { _, rect in rect },
                                     image: image, arguments: [w, h, Float(strength)]) ?? image

        var warped = full
        if let depthMask, depthMask.extent.width > 0, depthMask.extent.height > 0 {
            // Depth data comes from a lower-resolution sensor than the color image, so the
            // mask must be scaled (and re-anchored to the origin) to line up pixel-for-pixel
            // before blending — otherwise this silently only affects a corner of the frame.
            let scaleX = extent.width / depthMask.extent.width
            let scaleY = extent.height / depthMask.extent.height
            let alignedMask = depthMask
                .transformed(by: CGAffineTransform(translationX: -depthMask.extent.origin.x, y: -depthMask.extent.origin.y))
                .transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

            // Background (mask≈0) gets the full warp; subject (mask≈1) gets a much gentler one.
            let gentle = warpKernel.apply(extent: extent, roiCallback: { _, rect in rect },
                                           image: image, arguments: [w, h, Float(strength) * 0.35]) ?? full
            warped = gentle.applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: full,
                kCIInputMaskImageKey: alignedMask,
            ])
        }

        guard let gradeKernel else { return warped }
        return gradeKernel.apply(extent: extent, arguments: [
            warped, w, h, Float(chromaticAberration), Float(vignette),
        ]) ?? warped
    }

    private func legacyFallback(_ image: CIImage, strength: Double) -> CIImage {
        guard strength > 0.001, let filter = CIFilter(name: "CIBumpDistortion") else { return image }
        let extent = image.extent
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgPoint: CGPoint(x: extent.midX, y: extent.midY)), forKey: kCIInputCenterKey)
        filter.setValue(min(extent.width, extent.height) * 0.95, forKey: kCIInputRadiusKey)
        filter.setValue(strength, forKey: kCIInputScaleKey)
        return filter.outputImage?.cropped(to: extent) ?? image
    }
}
