import CoreImage

/// Lens-accurate equisolid fisheye warp + chromatic aberration + vignette, written in
/// Core Image Kernel Language (CIKL) rather than a compiled Metal shader.
///
/// This is a deliberate choice, not the "default" option: a hand-written `.metal` file
/// using CoreImage.h's `[[stitchable]]`-style kernels needs the AIR linker to resolve
/// `coreimage::sample`/`coreimage::sampler` against a runtime implementation that a plain
/// `default.metallib` build does not provide — Xcode's normal Metal-library packaging
/// step fails with "symbol(s) not found" no matter how the target is configured, because
/// that implementation is only supplied by Core Image itself at the point it actually
/// runs the kernel, not at static link time. CIKL sidesteps the whole problem: Core Image
/// compiles this source string itself, on-device, when the filter first runs — there is
/// no separate build step that can fail this way. The API is officially deprecated (in
/// favor of the Metal approach) but still fully supported; correctness and a build that
/// actually succeeds outweigh using the newer API here.
final class FisheyeFilter {
    static let shared = FisheyeFilter()

    private let warpKernel: CIWarpKernel?
    // Not CIColorKernel: Apple defines a color kernel as strictly a per-pixel function of
    // its inputs at the SAME coordinate — no neighborhood/offset sampling allowed. This
    // kernel offsets its red/blue samples for the chromatic-aberration effect, which
    // violates that contract; on-device, CIColorKernel(source:) silently failed to compile
    // it, `try?` swallowed the error, and chromatic aberration + vignette (both computed in
    // this one kernel) never rendered — confirmed by testing, not theoretical. A general
    // CIKernel has no such restriction; it just needs an explicit ROI callback since Core
    // Image can no longer assume 1:1 input/output pixel mapping.
    private let gradeKernel: CIKernel?

    private init() {
        warpKernel = try? CIWarpKernel(source: Self.warpSource)
        gradeKernel = try? CIKernel(source: Self.gradeSource)
    }

    private static let warpSource = """
    kernel vec2 fisheyeWarp(float width, float height, float strength)
    {
        vec2 center = vec2(width, height) * 0.5;
        vec2 position = destCoord();
        vec2 d = position - center;
        float maxR = length(center);
        if (maxR < 1.0 || strength < 0.001) {
            return position;
        }
        float r = length(d) / maxR;
        if (r < 0.0001) {
            return position;
        }
        vec2 dir = d / (r * maxR);
        float fov = strength * 2.6179939;
        float halfFov = fov * 0.5;
        float theta = r * halfFov;
        float srcR = tan(theta) / tan(halfFov);
        srcR = clamp(srcR, 0.0, 4.0);
        return center + dir * srcR * maxR;
    }
    """

    private static let gradeSource = """
    kernel vec4 fisheyeGrade(sampler src, float width, float height, float chromaAmt, float vignetteAmt)
    {
        vec2 position = destCoord();
        vec2 center = vec2(width, height) * 0.5;
        vec2 d = position - center;
        float maxR = length(center);
        float r = maxR > 1.0 ? length(d) / maxR : 0.0;
        vec2 dir = maxR > 1.0 ? d / maxR : vec2(0.0, 0.0);

        float shift = chromaAmt * r * r * 0.012 * maxR;
        vec4 cR = sample(src, samplerTransform(src, position + dir * shift));
        vec4 cG = sample(src, samplerCoord(src));
        vec4 cB = sample(src, samplerTransform(src, position - dir * shift));
        vec4 color = vec4(cR.r, cG.g, cB.b, cG.a);

        float vignette = 1.0 - vignetteAmt * pow(r, 2.2) * 0.55;
        color.rgb *= clamp(vignette, 0.0, 1.0);
        return color;
    }
    """

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
        return gradeKernel.apply(
            extent: extent,
            // The chromatic-aberration sample reaches a few pixels away from each output
            // pixel; pad the region read from `warped` so Core Image doesn't starve the
            // kernel of source pixels right at the frame edges.
            roiCallback: { _, rect in rect.insetBy(dx: -40, dy: -40) },
            arguments: [warped, w, h, Float(chromaticAberration), Float(vignette)]
        ) ?? warped
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
