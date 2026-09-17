import AVFoundation
import CoreImage
import UIKit
import Photos

@MainActor
final class CameraModel: NSObject, ObservableObject {
    // Live state shown in the UI
    @Published var previewImage: UIImage?
    @Published var isUsingFrontCamera = false
    @Published var fisheyeStrength: Double = 0.55       // 0...1, matches the web version's slider
    @Published var lookID: String = "none"
    @Published var lookIntensity: Double = 0.8
    @Published var autoEnhance = true
    @Published var circleMask = false
    @Published var grain = true
    @Published var livePhotoEnabled = true
    @Published var torchOn = false
    @Published var torchAvailable = false
    @Published var zoomFactor: CGFloat = 1.0
    @Published var minZoom: CGFloat = 1.0
    @Published var maxZoom: CGFloat = 1.0
    @Published var lastSaveOK: Bool?
    @Published var isRecording = false
    @Published var recordingSeconds: Int = 0
    @Published var chromaticAberration: Double = 0.6
    @Published var vignetteAmount: Double = 0.5
    @Published var hasLiDAR = false
    @Published var depthEnabled = true // only has any effect where hasLiDAR is true
    @Published var proRAWAvailable = false
    @Published var proRAWEnabled = false

    // Before/after review, shown after a photo capture instead of saving immediately.
    @Published var reviewOriginal: UIImage?
    @Published var reviewProcessed: UIImage?
    private var reviewLivePhotoURL: URL?
    @Published var audioEnabled = true {
        didSet {
            guard oldValue != audioEnabled, !isRecording else { return }
            sessionQueue.async { [weak self] in self?.configureSession() }
        }
    }

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "cameraobscura.session")
    private let videoOutput = AVCaptureVideoDataOutput()
    private let audioOutput = AVCaptureAudioDataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private let depthOutput = AVCaptureDepthDataOutput()
    private let depthQueue = DispatchQueue(label: "cameraobscura.depth")
    private var latestDepthMask: CIImage?
    // Explicit Metal (never the CPU renderer, which would genuinely cook the phone),
    // and no working-space conversion — we don't need color management for a live filter
    // preview, and skipping it noticeably cuts GPU time per frame.
    private let context = CIContext(options: [.useSoftwareRenderer: false, .workingColorSpace: NSNull()])
    private var currentDevice: AVCaptureDevice?
    private var currentAudioDevice: AVCaptureDevice?
    private var recordingTimer: Timer?

    // Thermal/battery guard: the live preview does not need the full sensor frame rate to
    // look smooth to the eye, so we halve the processing rate whenever we're only showing a
    // preview — full frame rate only kicks back in the moment an actual recording starts,
    // when quality matters more than headroom. Depth (LiDAR only) updates even less often,
    // since a soft depth mask doesn't need to track motion frame-accurately.
    private var frameCounter = 0
    private var depthFrameCounter = 0
    private let previewFrameSkip = 2
    private let depthFrameSkip = 3

    // Custom recording pipeline: unlike AVCaptureMovieFileOutput, this actually bakes
    // the fisheye/look effect into the saved file, because every frame runs through
    // `process()` before being written — the same pipeline the live preview uses.
    private var assetWriter: AVAssetWriter?
    private var writerVideoInput: AVAssetWriterInput?
    private var writerAudioInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var recordingURL: URL?
    private var writerSessionStarted = false

    var currentLook: LensLook { LensLook.all.first { $0.id == lookID } ?? LensLook.all[0] }

    func start() {
        configureAudioSession()
        sessionQueue.async { [weak self] in
            self?.configureSession()
            self?.session.startRunning()
        }
    }

    /// Fixes audio in/out routing up front: record from the built-in mic (not whatever
    /// port happens to be default), but still let a connected Bluetooth/wired mic take
    /// over if the user has one, and always play back through the speaker, not the earpiece.
    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .videoRecording,
                                     options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            // Recording will simply fail later with a clear error from AVCaptureDeviceInput
            // if this didn't work — nothing silent about it.
        }
    }

    func stop() {
        if isRecording { stopRecording() } // finish the file cleanly before tearing the session down
        sessionQueue.async { [weak self] in
            self?.session.stopRunning()
        }
    }

    func switchCamera() {
        isUsingFrontCamera.toggle()
        sessionQueue.async { [weak self] in
            self?.configureSession()
        }
    }

    private func configureSession() {
        session.beginConfiguration()
        session.sessionPreset = .hd1920x1080
        session.inputs.forEach { session.removeInput($0) }
        session.outputs.forEach { session.removeOutput($0) }

        let position: AVCaptureDevice.Position = isUsingFrontCamera ? .front : .back
        // Prefer the virtual multi-lens device: iOS then handles ultra-wide/wide/tele
        // switching internally as one continuous zoom factor — a real native advantage
        // the web version could never get (it only had discrete lens picking).
        let device = AVCaptureDevice.default(.builtInTripleCamera, for: .video, position: position)
            ?? AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: position)
            ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)

        guard let device, let input = try? AVCaptureDeviceInput(device: device) else {
            session.commitConfiguration()
            return
        }
        currentDevice = device
        if session.canAddInput(input) { session.addInput(input) }

        if audioEnabled, let audioDevice = AVCaptureDevice.default(for: .audio),
           let audioInput = try? AVCaptureDeviceInput(device: audioDevice) {
            currentAudioDevice = audioDevice
            if session.canAddInput(audioInput) { session.addInput(audioInput) }
        }

        videoOutput.setSampleBufferDelegate(self, queue: sessionQueue)
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }
        videoOutput.connection(with: .video)?.videoOrientation = .portrait

        audioOutput.setSampleBufferDelegate(self, queue: sessionQueue)
        if session.canAddOutput(audioOutput) { session.addOutput(audioOutput) }

        if session.canAddOutput(photoOutput) { session.addOutput(photoOutput) }
        // Must come after addOutput — these capability flags aren't meaningful until the
        // output is actually attached to the session.
        photoOutput.isLivePhotoCaptureEnabled = photoOutput.isLivePhotoCaptureSupported
        photoOutput.isAppleProRAWEnabled = photoOutput.isAppleProRAWSupported

        // LiDAR-only: real depth-aware fisheye (background warps more than the subject).
        // Every other device simply never populates hasLiDAR, and the effect quietly
        // falls back to the uniform warp — no crash, no dead UI, just a smaller feature set.
        let supportsDepth = !device.activeFormat.supportedDepthDataFormats.isEmpty
        if supportsDepth {
            depthOutput.setDelegate(self, callbackQueue: depthQueue)
            depthOutput.isFilteringEnabled = true
            if session.canAddOutput(depthOutput) { session.addOutput(depthOutput) }
            // Without this, depth arrives sensor-native (landscape) while the color image
            // is already rotated to portrait — the blend mask would land rotated 90° off.
            depthOutput.connection(with: .depthData)?.videoOrientation = .portrait
            if let depthFormat = device.activeFormat.supportedDepthDataFormats.first {
                try? device.lockForConfiguration()
                device.activeDepthDataFormat = depthFormat
                device.unlockForConfiguration()
            }
        }

        session.commitConfiguration()

        DispatchQueue.main.async { [weak self] in
            guard let self, let device = self.currentDevice else { return }
            self.torchAvailable = device.hasTorch
            self.minZoom = device.minAvailableVideoZoomFactor
            self.maxZoom = device.maxAvailableVideoZoomFactor
            self.zoomFactor = device.videoZoomFactor
            self.hasLiDAR = supportsDepth
            self.proRAWAvailable = self.photoOutput.isAppleProRAWSupported
        }
    }

    // MARK: - Real hardware controls the web version never had access to

    func setTorch(_ on: Bool) {
        guard let device = currentDevice, device.hasTorch else { return }
        sessionQueue.async {
            try? device.lockForConfiguration()
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
            DispatchQueue.main.async { self.torchOn = on }
        }
    }

    func setZoom(_ factor: CGFloat) {
        guard let device = currentDevice else { return }
        sessionQueue.async {
            try? device.lockForConfiguration()
            device.videoZoomFactor = max(device.minAvailableVideoZoomFactor,
                                          min(factor, device.maxAvailableVideoZoomFactor))
            device.unlockForConfiguration()
        }
    }

    func focusAndExpose(at point: CGPoint) {
        guard let device = currentDevice else { return }
        sessionQueue.async {
            try? device.lockForConfiguration()
            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = point
                device.focusMode = .autoFocus
            }
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = point
                device.exposureMode = .autoExpose
            }
            device.unlockForConfiguration()
        }
    }

    // MARK: - Custom presets

    func currentSettingsAsPreset(named name: String) -> SavedPreset {
        SavedPreset(name: name, lookID: lookID, fisheyeStrength: fisheyeStrength, lookIntensity: lookIntensity,
                    chromaticAberration: chromaticAberration, vignetteAmount: vignetteAmount,
                    grain: grain, circleMask: circleMask, autoEnhance: autoEnhance)
    }

    func apply(_ preset: SavedPreset) {
        lookID = preset.lookID
        fisheyeStrength = preset.fisheyeStrength
        lookIntensity = preset.lookIntensity
        chromaticAberration = preset.chromaticAberration
        vignetteAmount = preset.vignetteAmount
        grain = preset.grain
        circleMask = preset.circleMask
        autoEnhance = preset.autoEnhance
    }

    // MARK: - Shared processing pipeline (same math the web version used, now GPU-accelerated)

    /// Lens-accurate equisolid fisheye warp + chromatic aberration + vignette (see
    /// FisheyeFilter.swift) — a real optical model, not a generic
    /// radial bump. Uses the live depth map for depth-aware distortion on LiDAR devices.
    private func applyFisheye(to image: CIImage) -> CIImage {
        guard fisheyeStrength > 0.001 else { return image }
        return FisheyeFilter.shared.apply(
            to: image,
            strength: fisheyeStrength,
            chromaticAberration: chromaticAberration,
            vignette: vignetteAmount,
            depthMask: depthEnabled ? latestDepthMask : nil
        )
    }

    private func applyGrain(to image: CIImage) -> CIImage {
        guard grain else { return image }
        guard let noise = CIFilter(name: "CIRandomGenerator")?.outputImage?.cropped(to: image.extent) else { return image }
        let monochrome = noise.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0, y: 1, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: 1, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 1, z: 0, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0.08),
        ])
        return monochrome.composited(over: image)
    }

    private func applyCircleMask(to image: CIImage) -> CIImage {
        guard circleMask else { return image }
        let extent = image.extent
        let radius = min(extent.width, extent.height) * 0.49
        let gradient = CIFilter(name: "CIRadialGradient")!
        gradient.setValue(CIVector(cgPoint: CGPoint(x: extent.midX, y: extent.midY)), forKey: "inputCenter")
        gradient.setValue(radius - 2, forKey: "inputRadius0")
        gradient.setValue(radius, forKey: "inputRadius1")
        gradient.setValue(CIColor(red: 1, green: 1, blue: 1, alpha: 1), forKey: "inputColor0")
        gradient.setValue(CIColor(red: 0.03, green: 0.03, blue: 0.04, alpha: 1), forKey: "inputColor1")
        guard let mask = gradient.outputImage?.cropped(to: extent) else { return image }
        let blend = CIFilter(name: "CIBlendWithMask")!
        blend.setValue(image, forKey: kCIInputImageKey)
        blend.setValue(CIImage(color: CIColor(red: 0.03, green: 0.03, blue: 0.04)).cropped(to: extent), forKey: kCIInputBackgroundImageKey)
        blend.setValue(mask, forKey: kCIInputMaskImageKey)
        return blend.outputImage ?? image
    }

    /// Full pipeline: fisheye → look grading (blended by intensity) → auto-enhance → grain → circle mask.
    func process(_ input: CIImage) -> CIImage {
        var image = applyFisheye(to: input)

        if lookIntensity > 0.001 && lookID != "none" {
            let graded = currentLook.apply(to: image)
            image = graded.applyingFilter("CIDissolveTransition", parameters: [
                kCIInputTargetImageKey: image, kCIInputTimeKey: 1 - lookIntensity,
            ])
        }

        if autoEnhance {
            let adjustments = image.autoAdjustmentFilters(options: [.enhance: true])
            for filter in adjustments {
                filter.setValue(image, forKey: kCIInputImageKey)
                if let output = filter.outputImage { image = output }
            }
        }

        image = applyGrain(to: image)
        image = applyCircleMask(to: image)
        return image
    }

    // MARK: - Capture

    private var expectingRawCapture = false

    func capturePhoto() {
        var settings = AVCapturePhotoSettings()

        if proRAWEnabled, photoOutput.isAppleProRAWEnabled,
           let rawFormat = photoOutput.availableRawPhotoPixelFormatTypes.first(where: {
               AVCapturePhotoOutput.isAppleProRAWPixelFormat($0)
           }) {
            let processedFormat: [String: Any] = photoOutput.availablePhotoCodecTypes.contains(.hevc)
                ? [AVVideoCodecKey: AVVideoCodecType.hevc] : [:]
            settings = AVCapturePhotoSettings(rawPixelFormatType: rawFormat, processedFormat: processedFormat)
            expectingRawCapture = true
        } else if photoOutput.availablePhotoCodecTypes.contains(.hevc) {
            settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
            expectingRawCapture = false
        }

        if livePhotoEnabled && photoOutput.isLivePhotoCaptureEnabled {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
            settings.livePhotoMovieFileURL = url
        }
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    /// ProRAW carries far more real sensor data than the compressed HEIC companion —
    /// decoding it ourselves before running the fisheye/look pipeline gives noticeably
    /// more shadow/highlight headroom, especially on the darker editorial looks.
    private func processRawAndReview(_ rawData: Data) {
        guard let rawFilter = CIFilter(imageData: rawData, options: [.allowDraftMode: false]),
              let decoded = rawFilter.outputImage else { return }
        finishReview(original: decoded)
    }

    func startRecording() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
        try? FileManager.default.removeItem(at: url)

        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mov) else { return }

        // 1080×1920, not 1920×1080: the capture connection is locked to .portrait, which
        // means AVFoundation delivers already-rotated portrait pixel buffers — writer
        // dimensions that don't match what's actually appended would silently drop frames
        // or squash the video.
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 1080,
            AVVideoHeightKey: 1920,
        ]
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = true
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoInput, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ])
        guard writer.canAdd(videoInput) else { return }
        writer.add(videoInput)

        var audioInput: AVAssetWriterInput?
        if audioEnabled {
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVNumberOfChannelsKey: 1,
                AVSampleRateKey: 44100,
                AVEncoderBitRateKey: 64000,
            ]
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            input.expectsMediaDataInRealTime = true
            if writer.canAdd(input) { writer.add(input); audioInput = input }
        }

        recordingURL = url
        assetWriter = writer
        writerVideoInput = videoInput
        writerAudioInput = audioInput
        pixelBufferAdaptor = adaptor
        writerSessionStarted = false

        isRecording = true
        recordingSeconds = 0
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.recordingSeconds += 1 }
        }
    }

    func stopRecording() {
        recordingTimer?.invalidate()
        isRecording = false

        guard let writer = assetWriter, let url = recordingURL, writer.status == .writing else {
            resetWriter()
            return
        }
        writerVideoInput?.markAsFinished()
        writerAudioInput?.markAsFinished()
        writer.finishWriting { [weak self] in
            Task { @MainActor in
                self?.saveVideo(at: url)
                self?.resetWriter()
            }
        }
    }

    private func resetWriter() {
        assetWriter = nil
        writerVideoInput = nil
        writerAudioInput = nil
        pixelBufferAdaptor = nil
        writerSessionStarted = false
    }

    private func saveVideo(at url: URL) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else { return }
            PHPhotoLibrary.shared().performChanges({
                let options = PHAssetResourceCreationOptions()
                options.shouldMoveFile = true
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .video, fileURL: url, options: options)
            }, completionHandler: nil)
        }
    }

    /// Renders one processed frame into the recording, called from the video sample
    /// buffer delegate below whenever `isRecording` is true.
    private func appendVideoFrame(_ image: CIImage, presentationTime: CMTime) {
        guard isRecording, let writer = assetWriter, let input = writerVideoInput,
              let adaptor = pixelBufferAdaptor, let pool = adaptor.pixelBufferPool else { return }

        if !writerSessionStarted {
            writer.startWriting()
            writer.startSession(atSourceTime: presentationTime)
            writerSessionStarted = true
        }
        guard input.isReadyForMoreMediaData else { return }

        var pixelBufferOut: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBufferOut)
        guard let pixelBuffer = pixelBufferOut else { return }
        context.render(image, to: pixelBuffer)
        adaptor.append(pixelBuffer, withPresentationTime: presentationTime)
    }

    private func appendAudioSample(_ sampleBuffer: CMSampleBuffer) {
        guard isRecording, writerSessionStarted, let input = writerAudioInput, input.isReadyForMoreMediaData else { return }
        input.append(sampleBuffer)
    }
}

extension CameraModel: AVCaptureDepthDataOutputDelegate {
    nonisolated func depthDataOutput(_ output: AVCaptureDepthDataOutput, didOutput depthData: AVDepthData,
                                      timestamp: CMTime, connection: AVCaptureConnection) {
        Task { @MainActor in
            // LiDAR depth is only ever used as a soft blend mask, so it doesn't need to
            // keep up with the full video frame rate — skipping most callbacks here is
            // one more real, meaningful cut to sustained GPU/thermal load on Pro devices.
            self.depthFrameCounter += 1
            guard self.depthFrameCounter % self.depthFrameSkip == 0 else { return }

            let converted = depthData.converting(toDepthDataType: kCVPixelFormatType_DisparityFloat32)
            let depthImage = CIImage(cvPixelBuffer: converted.depthDataMap)

            // Disparity (inverse depth) already reads higher = nearer, roughly 0...4 in
            // practice for portrait/handheld distances — a fixed scale is stable frame to
            // frame (unlike a genuine per-frame min/max, which would flicker as the scene
            // changes) and is more than good enough for a soft blend mask, not a measurement.
            self.latestDepthMask = depthImage.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0.28, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0.28, y: 0, z: 0, w: 0),
                "inputBVector": CIVector(x: 0.28, y: 0, z: 0, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            ])
        }
    }
}

extension CameraModel: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Whether this buffer is audio or video is decided once we're on the main actor,
        // so nothing here touches an actor-isolated property from outside the actor.
        let isVideoConnection = connection.output is AVCaptureVideoDataOutput
        if !isVideoConnection {
            Task { @MainActor in self.appendAudioSample(sampleBuffer) }
            return
        }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        Task { @MainActor in
            // Recording always gets every frame (smooth video, correct A/V timing);
            // idle preview deliberately skips frames to keep the phone cool and the
            // battery from draining just from someone holding the app open framing a shot.
            if !self.isRecording {
                self.frameCounter += 1
                if self.frameCounter % self.previewFrameSkip != 0 { return }
            }
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            let processed = self.process(ciImage)
            guard let cgImage = self.context.createCGImage(processed, from: processed.extent) else { return }
            self.previewImage = UIImage(cgImage: cgImage)
            if self.isRecording {
                self.appendVideoFrame(processed, presentationTime: presentationTime)
            }
        }
    }
}

extension CameraModel: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil, let data = photo.fileDataRepresentation() else { return }
        if photo.isRawPhoto {
            Task { @MainActor in self.processRawAndReview(data) }
            return
        }
        Task { @MainActor in
            // A ProRAW capture also delivers this processed HEIC companion — when we asked
            // for RAW we use that instead (more headroom), so skip this one to avoid
            // presenting two review screens for one shutter press.
            guard !self.expectingRawCapture, let ciImage = CIImage(data: data) else { return }
            self.finishReview(original: ciImage)
        }
    }

    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingLivePhotoToMovieFileAt outputFileURL: URL,
                                  duration: CMTime, photoDisplayName: String?, resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        guard error == nil else { return }
        Task { @MainActor in
            self.reviewLivePhotoURL = outputFileURL
        }
    }
}

// MARK: - Before/after review (shown instead of saving immediately)
extension CameraModel {
    fileprivate func finishReview(original: CIImage) {
        let processed = process(original)
        guard let processedCG = context.createCGImage(processed, from: processed.extent),
              let originalCG = context.createCGImage(original, from: original.extent) else { return }
        reviewOriginal = UIImage(cgImage: originalCG)
        reviewProcessed = UIImage(cgImage: processedCG)
    }

    /// Called from the review screen's "Behalten" button.
    func confirmSave(exportPreset: ExportPreset = .original) {
        guard let processed = reviewProcessed else { return }
        let exported = exportPreset.apply(to: processed)
        save(photo: exported, pairedLivePhotoURL: reviewLivePhotoURL)
        discardReview()
    }

    /// Called from the review screen's "Verwerfen" button, or automatically after saving.
    func discardReview() {
        reviewOriginal = nil
        reviewProcessed = nil
        reviewLivePhotoURL = nil
    }
}

// Live Photo pairing needs both the still (already graded above) and the untouched
// paired movie clip saved together in one PHPhotoLibrary change request. Single-shot
// capture UX only (no rapid burst mode), so one instance-level slot is enough.
//
// Privacy, by construction and on purpose: `photo` here already passed through
// CIImage → CGImage → UIImage, which does not carry the original capture's EXIF/GPS
// metadata forward — `jpegData(compressionQuality:)` writes a fresh file with none of
// that baked in. No hash, no hidden identifier, no steganographic watermark is added
// anywhere in this app. Do not "fix" this by re-attaching the original metadata.
extension CameraModel {
    func save(photo: UIImage, pairedLivePhotoURL movieURL: URL?) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                Task { @MainActor in self.lastSaveOK = false }
                return
            }
            PHPhotoLibrary.shared().performChanges({
                let request = PHAssetCreationRequest.forAsset()
                guard let jpeg = photo.jpegData(compressionQuality: 0.95) else { return }
                let options = PHAssetResourceCreationOptions()
                request.addResource(with: .photo, data: jpeg, options: options)
                if let movieURL {
                    let movieOptions = PHAssetResourceCreationOptions()
                    movieOptions.shouldMoveFile = true
                    request.addResource(with: .pairedVideo, fileURL: movieURL, options: movieOptions)
                }
            }) { success, _ in
                Task { @MainActor in
                    self.lastSaveOK = success
                }
            }
        }
    }
}

extension CameraModel: AVCaptureAudioDataOutputSampleBufferDelegate {
    // Intentionally empty: AVCaptureAudioDataOutputSampleBufferDelegate and
    // AVCaptureVideoDataOutputSampleBufferDelegate share the exact same required method,
    // so the single implementation above (in the video delegate extension) handles both —
    // it distinguishes video vs. audio buffers by checking which `output` called it.
}
