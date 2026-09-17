import UIKit
import SwiftUI
import Photos
import PhotosUI
import CoreImage

/// Lets someone open any photo already in their library, tap "Edit" → our extension
/// name, and apply the same fisheye/look pipeline right there — no need to open
/// CameraObscura separately for a photo that already exists.
@objc(PhotoEditingViewController)
final class PhotoEditingViewController: UIViewController, PHContentEditingController {
    private var input: PHContentEditingInput?
    private let context = CIContext(options: [.workingColorSpace: NSNull()])
    private var originalImage: CIImage?
    private let state = EditState()
    private var hosting: UIHostingController<PhotoEditView>?

    // MARK: - PHContentEditingController

    func canHandle(_ adjustmentData: PHAdjustmentData) -> Bool {
        adjustmentData.formatIdentifier == Self.formatIdentifier && adjustmentData.formatVersion == "1.0"
    }

    func startContentEditing(with contentEditingInput: PHContentEditingInput, placeholderImage: UIImage) {
        input = contentEditingInput
        if let url = contentEditingInput.fullSizeImageURL, let image = CIImage(contentsOf: url) {
            originalImage = image
        }
        state.previewImage = placeholderImage
        updatePreview()
    }

    var shouldShowCancelConfirmation: Bool { false }

    func cancelContentEditing() {}

    func finishContentEditing(completionHandler: @escaping (PHContentEditingOutput?) -> Void) {
        guard let input, let originalImage else { completionHandler(nil); return }
        let processed = Self.process(originalImage, state: state)
        guard let cgImage = context.createCGImage(processed, from: processed.extent) else {
            completionHandler(nil); return
        }
        let output = PHContentEditingOutput(contentEditingInput: input)
        guard let jpeg = UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.95) else {
            completionHandler(nil); return
        }
        do {
            try jpeg.write(to: output.renderedContentURL, options: .atomic)
            output.adjustmentData = PHAdjustmentData(formatIdentifier: Self.formatIdentifier, formatVersion: "1.0", data: Data())
            completionHandler(output)
        } catch {
            completionHandler(nil)
        }
    }

    static let formatIdentifier = "com.danielschweiger.cameraobscura"

    // MARK: - UI

    override func viewDidLoad() {
        super.viewDidLoad()
        let editView = PhotoEditView(state: state, onChange: { [weak self] in self?.updatePreview() })
        let host = UIHostingController(rootView: editView)
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
        hosting = host
    }

    private func updatePreview() {
        guard let originalImage else { return }
        let processed = Self.process(originalImage, state: state)
        guard let cgImage = context.createCGImage(processed, from: processed.extent) else { return }
        state.previewImage = UIImage(cgImage: cgImage)
    }

    private static func process(_ image: CIImage, state: EditState) -> CIImage {
        var result = image
        if state.fisheyeStrength > 0.001 {
            result = FisheyeFilter.shared.apply(to: result, strength: state.fisheyeStrength,
                                                 chromaticAberration: 0.6, vignette: 0.5, depthMask: nil)
        }
        if state.lookIntensity > 0.001, let look = LensLook.all.first(where: { $0.id == state.lookID }), state.lookID != "none" {
            let graded = look.apply(to: result)
            result = graded.applyingFilter("CIDissolveTransition", parameters: [
                kCIInputTargetImageKey: result, kCIInputTimeKey: 1 - state.lookIntensity,
            ])
        }
        return result
    }
}

/// Plain observable holder so the SwiftUI editing view and the UIKit controller
/// share one source of truth without re-plumbing bindings through the view controller.
final class EditState: ObservableObject {
    @Published var fisheyeStrength: Double = 0.5
    @Published var lookID: String = "none"
    @Published var lookIntensity: Double = 0.8
    @Published var previewImage: UIImage?
}

private struct PhotoEditView: View {
    @ObservedObject var state: EditState
    let onChange: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            if let image = state.previewImage {
                Image(uiImage: image).resizable().scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding()
            } else {
                ProgressView()
            }

            VStack(spacing: 12) {
                HStack {
                    Text("Fisheye").font(.caption)
                    Slider(value: $state.fisheyeStrength, in: 0...1)
                        .onChange(of: state.fisheyeStrength) { _ in onChange() }
                }
                Picker("Look", selection: $state.lookID) {
                    ForEach(LensLook.all) { look in Text(look.name).tag(look.id) }
                }
                .pickerStyle(.menu)
                .onChange(of: state.lookID) { _ in onChange() }
                HStack {
                    Text("Intensität").font(.caption)
                    Slider(value: $state.lookIntensity, in: 0...1)
                        .onChange(of: state.lookIntensity) { _ in onChange() }
                }
            }
            .padding(.horizontal)
            Spacer()
        }
        .background(Color(white: 0.08).ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}
