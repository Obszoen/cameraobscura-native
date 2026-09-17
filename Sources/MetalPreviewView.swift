import SwiftUI
import MetalKit
import CoreImage

/// The live viewfinder, rendered straight to a Metal drawable instead of round-tripping
/// every camera frame through CGImage → UIImage → SwiftUI.Image. That CPU-side conversion
/// was the whole reason the preview ever felt laggy or "not flawless" — a GPU-bound
/// CIContext rendering directly into an MTKView's drawable is the standard architecture
/// for exactly this (real-time filtered camera preview), confirmed against Apple's own
/// guidance rather than assumed.
///
/// Just as important: this view owns its OWN CIContext, entirely separate from the one
/// CameraModel uses to render frames into the video-writer's pixel buffer. Two independent
/// CIContext instances working on independent (immutable) CIImage graphs can never race
/// each other — the display's own draw loop (paced by the screen, not by incoming camera
/// frames or by recording) and the recording path simply can't collide anymore, by
/// construction, not by careful queue bookkeeping.
struct MetalPreviewView: UIViewRepresentable {
    /// Set by CameraModel every time a new processed frame is ready. Building this CIImage
    /// is cheap (Core Image just records a filter recipe); the actual GPU render happens
    /// on the MTKView's own draw tick, not here.
    var frame: CIImage?
    /// Backgrounded or covered by the full-height adjustments sheet: a continuous 60fps
    /// Metal draw loop would otherwise keep redrawing the same cached frame forever for no
    /// one to see it, burning GPU/battery for nothing — the same thermal/battery reasoning
    /// CameraModel already applies to the capture session itself.
    var isActive: Bool = true

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        guard let device = MTLCreateSystemDefaultDevice() else { return view }
        view.device = device
        view.delegate = context.coordinator
        context.coordinator.ciContext = CIContext(mtlDevice: device)
        context.coordinator.commandQueue = device.makeCommandQueue()
        // Continuous redraw at the display's own pace, independent of camera frame timing —
        // if a new frame hasn't arrived yet, it just redraws the last one, which is exactly
        // what a live viewfinder should do rather than stall.
        view.enableSetNeedsDisplay = false
        view.isPaused = !isActive
        view.preferredFramesPerSecond = 60
        view.framebufferOnly = false
        view.backgroundColor = .black
        // Reported directly: the live preview looked "krass unschärfer" than the actual
        // captured photo. A plain MTKView created programmatically (not from a storyboard)
        // isn't guaranteed to pick up the screen's Retina scale on its own — without this,
        // its drawable renders at 1x point-resolution instead of the device's real 3x pixel
        // density, which would look exactly like this: soft/blurry on screen, but the
        // actual capture (an entirely separate AVCapturePhotoOutput path, full resolution
        // regardless of what the live preview renders) comes out sharp. Setting this
        // explicitly is the standard fix, not a guess based on this one symptom alone.
        view.contentScaleFactor = UIScreen.main.scale
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.latestFrame = frame
        uiView.isPaused = !isActive
    }

    final class Coordinator: NSObject, MTKViewDelegate {
        var ciContext: CIContext?
        var commandQueue: MTLCommandQueue?
        var latestFrame: CIImage?

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        func draw(in view: MTKView) {
            guard let image = latestFrame,
                  let drawable = view.currentDrawable,
                  let ciContext, let commandQueue,
                  let commandBuffer = commandQueue.makeCommandBuffer() else { return }

            // Fill (not fit) the drawable — edge-to-edge, cropping overflow — matching the
            // .scaledToFill() the SwiftUI Image-based preview used before this rewrite, so
            // the viewfinder still looks the same, just renders through a faster path.
            let drawableSize = view.drawableSize
            let imageExtent = image.extent
            guard imageExtent.width > 0, imageExtent.height > 0 else { return }
            let scale = max(drawableSize.width / imageExtent.width, drawableSize.height / imageExtent.height)
            let scaledImage = image
                .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            let dx = (drawableSize.width - scaledImage.extent.width) / 2 - scaledImage.extent.origin.x
            let dy = (drawableSize.height - scaledImage.extent.height) / 2 - scaledImage.extent.origin.y
            let centeredImage = scaledImage.transformed(by: CGAffineTransform(translationX: dx, y: dy))

            ciContext.render(centeredImage, to: drawable.texture, commandBuffer: commandBuffer,
                              bounds: CGRect(origin: .zero, size: drawableSize), colorSpace: CGColorSpaceCreateDeviceRGB())
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
    }
}
