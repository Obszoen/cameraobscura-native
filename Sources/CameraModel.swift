import AVFoundation
import CoreImage
import CoreMotion
import UIKit
import Photos
import Vision

@MainActor
final class CameraModel: NSObject, ObservableObject {
    // Live state shown in the UI
    // Feeds MetalPreviewView directly — building a CIImage recipe here is cheap, the actual
    // GPU render happens on the view's own Metal draw loop, not on this property's setter.
    @Published var latestFrame: CIImage?
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
    // Set whenever configureSession() can't get a usable camera — no device found, or the
    // input couldn't be created (in use by another app, permission revoked mid-session,
    // etc.) — so the screen can say why the preview is black instead of just staying dark.
    @Published var configurationError: String?
    // Set while the system has taken the camera away from us (an incoming call, another
    // app using it, Control Center's camera access, a media-services crash) — the session
    // stops running whether we like it or not, so the screen should say why instead of
    // just going dark with no explanation, and we resume automatically once it's ours again.
    @Published var interruptionMessage: String?
    // Roll in degrees, 0 = level, holding the phone upright in portrait — same sign
    // convention as Apple's own Camera app: tilt the top of the phone right and this goes
    // positive. Read by the level-line overlay, which also decides for itself when that
    // counts as "level enough" to turn its accent color.
    @Published var rollDegrees: Double = 0
    // Composition coach: off by default (real work for the CPU, and not everyone wants a
    // coach) — enabled from a toolbar toggle. Analysis only runs at all while this is true.
    @Published var showCompositionCoach = false
    @Published var coachMode: CoachMode = .photographerMoves
    @Published var compositionHint: String?
    // Vision's boundingBox convention: normalized 0...1, origin bottom-left, relative to
    // `compositionFrameSize` (the raw, undistorted capture buffer's pixel size at analysis
    // time — deliberately the buffer BEFORE the fisheye warp, since coaching is about real
    // framing, not the artistic distortion). The overlay needs the actual buffer size to
    // correctly place the crosshair on screen, because the on-screen preview is a cropped
    // "fill" of that buffer, not a 1:1 mapping.
    @Published var personBoxNormalized: CGRect?
    @Published var compositionFrameSize: CGSize = .zero

    enum CoachMode: Hashable { case photographerMoves, subjectMoves }

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
    private let motionManager = CMMotionManager()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let audioOutput = AVCaptureAudioDataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private let depthOutput = AVCaptureDepthDataOutput()
    private let depthQueue = DispatchQueue(label: "cameraobscura.depth")
    private var latestDepthMask: CIImage?
    // Used only for photo/video capture (rendering a final frame into a CGImage or into the
    // asset writer's pixel buffer) — never for the live viewfinder, which is MetalPreviewView's
    // own separate CIContext now. They used to be the same CIContext for both jobs, and
    // issuing renders from both at once corrupted CoreImage's internal tile-task state and
    // crashed with SIGSEGV, confirmed on-device. Two independent contexts, each with exactly
    // one caller, can't race each other — no queue bookkeeping needed to prevent it.
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

    // Composition coach: Vision analysis is real CPU work, so it runs at ~2-3fps (not every
    // frame) on its own queue, and `isAnalyzingComposition` skips scheduling a new request
    // while one is still in flight instead of piling them up — the same drop-not-queue
    // pattern that fixed the live preview's stale-frame backlog earlier.
    private var coachFrameCounter = 0
    private let coachFrameSkip = 10
    private let visionQueue = DispatchQueue(label: "cameraobscura.vision")
    private var isAnalyzingComposition = false

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

    override init() {
        super.init()
        observeSessionNotifications()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// A real camera app has to survive the system taking the camera away without warning
    /// — a phone call, Control Center, another app, or (rare but real) a media-services
    /// crash — and come back on its own once it's ours again, not just sit on a frozen
    /// last frame forever. None of this was previously observed at all.
    private func observeSessionNotifications() {
        let center = NotificationCenter.default
        center.addObserver(forName: .AVCaptureSessionWasInterrupted, object: session, queue: .main) { [weak self] note in
            guard let self else { return }
            let reasonValue = (note.userInfo?[AVCaptureSessionInterruptionReasonKey] as? NSNumber)?.intValue
            let reason = reasonValue.flatMap(AVCaptureSession.InterruptionReason.init)
            self.interruptionMessage = Self.describe(interruption: reason)
        }
        center.addObserver(forName: .AVCaptureSessionInterruptionEnded, object: session, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.interruptionMessage = nil
            // The session doesn't resume itself just because the interruption ended.
            self.sessionQueue.async { [weak self] in
                guard let self, !self.session.isRunning else { return }
                self.session.startRunning()
            }
        }
        center.addObserver(forName: .AVCaptureSessionRuntimeError, object: session, queue: .main) { [weak self] note in
            guard let self else { return }
            self.interruptionMessage = "Kamera-Fehler – versuche neu zu starten…"
            // A media-services reset invalidates the whole session; restarting it fresh
            // (not just calling startRunning again) is Apple's own documented recovery.
            self.sessionQueue.async { [weak self] in
                guard let self else { return }
                self.configureSession()
                self.session.startRunning()
                DispatchQueue.main.async { self.interruptionMessage = nil }
            }
        }
    }

    private static func describe(interruption reason: AVCaptureSession.InterruptionReason?) -> String {
        switch reason {
        case .videoDeviceNotAvailableInBackground: return "Kamera pausiert im Hintergrund"
        case .audioDeviceInUseByAnotherClient: return "Mikrofon wird von einer anderen App genutzt"
        case .videoDeviceInUseByAnotherClient: return "Kamera wird von einer anderen App genutzt"
        case .videoDeviceNotAvailableWithMultipleForegroundApps: return "Kamera nicht verfügbar (Split View)"
        case .videoDeviceNotAvailableDueToSystemPressure: return "Kamera pausiert – Gerät zu heiß"
        default: return "Kamera kurz unterbrochen…"
        }
    }

    func start() {
        configureAudioSession()
        sessionQueue.async { [weak self] in
            self?.configureSession()
            self?.session.startRunning()
        }
        startLevelUpdates()
    }

    /// Roll angle for the level-line overlay. Device orientation is always portrait here
    /// (the capture connection is locked to it), so gravity's x/y in the device's own frame
    /// converts directly to a roll angle without needing full attitude/reference-frame math.
    private func startLevelUpdates() {
        guard motionManager.isDeviceMotionAvailable else { return }
        motionManager.deviceMotionUpdateInterval = 1.0 / 30.0
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let gravity = motion?.gravity else { return }
            self.rollDegrees = atan2(gravity.x, -gravity.y) * 180 / .pi
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
        motionManager.stopDeviceMotionUpdates()
    }

    func switchCamera() {
        isUsingFrontCamera.toggle()
        sessionQueue.async { [weak self] in
            self?.configureSession()
        }
    }

    private func configureSession() {
        session.beginConfiguration()
        // .hd1920x1080 caps the active device format at 1080p-video-oriented, which also
        // caps AVCapturePhotoOutput's still resolution — that's the whole session, photos
        // included, running well below what the sensor (and the stock Camera app) delivers.
        // .photo selects the highest-resolution still-photo format the device offers while
        // still supporting video capture, matching what a real camera app actually uses.
        session.sessionPreset = .photo
        session.inputs.forEach { session.removeInput($0) }
        session.outputs.forEach { session.removeOutput($0) }

        let position: AVCaptureDevice.Position = isUsingFrontCamera ? .front : .back
        // Prefer the virtual multi-lens device: iOS then handles ultra-wide/wide/tele
        // switching internally as one continuous zoom factor — a real native advantage
        // the web version could never get (it only had discrete lens picking).
        let device = AVCaptureDevice.default(.builtInTripleCamera, for: .video, position: position)
            ?? AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: position)
            ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)

        guard let device else {
            session.commitConfiguration()
            let message = "Keine Kamera gefunden."
            DispatchQueue.main.async { self.configurationError = message }
            return
        }
        guard let input = try? AVCaptureDeviceInput(device: device) else {
            session.commitConfiguration()
            let message = "Kamera ist gerade nicht verfügbar (evtl. von einer anderen App belegt)."
            DispatchQueue.main.async { self.configurationError = message }
            return
        }
        DispatchQueue.main.async { self.configurationError = nil }
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
        if let conn = videoOutput.connection(with: .video) {
            conn.videoOrientation = .portrait
            // We bypass AVCaptureVideoPreviewLayer entirely (the preview is our own
            // CIImage → CGImage pipeline), so the front-camera auto-mirroring that a
            // preview layer gets for free never happens here — without this, the selfie
            // camera's live preview (and anything recorded from it) came out reading
            // backwards instead of mirrored like every other camera app.
            if conn.isVideoMirroringSupported {
                conn.automaticallyAdjustsVideoMirroring = false
                conn.isVideoMirrored = isUsingFrontCamera
            }
            // Real electronic image stabilization (Apple's own EIS, not a fake "feels
            // smoother" gimmick) — .cinematicExtended is the strongest mode devices that
            // support it offer; conn.activeVideoStabilizationMode reports back whichever
            // mode the device actually granted, since not every device supports the
            // strongest tier and AVFoundation silently falls back on its own.
            if conn.isVideoStabilizationSupported {
                conn.preferredVideoStabilizationMode = .cinematicExtended
            }
        }

        // Real low-light boost (Apple's own API for it) — not a green-tinted "night vision"
        // filter pretending to be something the hardware can't do. There is no thermal
        // sensor on an iPhone; a fake heat-map filter would just be lying to whoever uses it.
        if device.isLowLightBoostSupported {
            try? device.lockForConfiguration()
            device.automaticallyEnablesLowLightBoostWhenAvailable = true
            device.unlockForConfiguration()
        }

        audioOutput.setSampleBufferDelegate(self, queue: sessionQueue)
        if session.canAddOutput(audioOutput) { session.addOutput(audioOutput) }

        if session.canAddOutput(photoOutput) { session.addOutput(photoOutput) }
        // Must come after addOutput — these capability flags aren't meaningful until the
        // output is actually attached to the session.
        photoOutput.isLivePhotoCaptureEnabled = photoOutput.isLivePhotoCaptureSupported
        photoOutput.isAppleProRAWEnabled = photoOutput.isAppleProRAWSupported
        if let conn = photoOutput.connection(with: .video), conn.isVideoMirroringSupported {
            // Same fix, same reason, for the still-photo path — otherwise a selfie photo
            // and the live preview it was framed from would mirror inconsistently.
            conn.automaticallyAdjustsVideoMirroring = false
            conn.isVideoMirrored = isUsingFrontCamera
        }

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

        // Read the real active format instead of hardcoding 1080×1920: with the session on
        // .photo (for full-resolution stills) the delivered frames are the device's actual
        // sensor size, not 1080p, and that varies by device/lens. Swapped width/height
        // because the capture connection is locked to .portrait, so AVFoundation delivers
        // already-rotated portrait pixel buffers — writer dimensions that don't match what's
        // actually appended would silently crop the video to the top-left corner.
        let sensorDims = currentDevice?.activeFormat.formatDescription.dimensions
        let portraitWidth = Int(sensorDims?.height ?? 1080)
        let portraitHeight = Int(sensorDims?.width ?? 1920)
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: portraitWidth,
            AVVideoHeightKey: portraitHeight,
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

    // MARK: - Composition coach

    /// Runs on the raw (undistorted) buffer, not the fisheye-warped preview — coaching is
    /// about real-world framing, and warping a person's silhouette before measuring it
    /// would make the geometry meaningless. `.up` is correct here (not `.right`/`.left`)
    /// because the capture connection already delivers portrait-rotated, correctly-mirrored
    /// buffers — the exact same orientation assumption the video-writer dimension swap
    /// elsewhere in this file already relies on.
    private func analyzeComposition(pixelBuffer: CVPixelBuffer) {
        let width = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let height = CGFloat(CVPixelBufferGetHeight(pixelBuffer))
        let request = VNDetectHumanRectanglesRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        visionQueue.async { [weak self] in
            try? handler.perform([request])
            let box = (request.results as? [VNHumanObservation])?.first?.boundingBox
            Task { @MainActor in
                guard let self else { return }
                self.isAnalyzingComposition = false
                self.personBoxNormalized = box
                self.compositionFrameSize = CGSize(width: width, height: height)
                self.compositionHint = box.map { CompositionCoach.hint(for: $0, mode: self.coachMode) }
            }
        }
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
            // Building this CIImage recipe is cheap — no GPU render happens here. The
            // viewfinder (MetalPreviewView) renders it on its own Metal draw loop, and
            // recording renders it into the asset writer's pixel buffer on `self.context`
            // below — two independent CIContexts, two independent consumers of the same
            // immutable recipe, so unlike before there is nothing here that can race or
            // starve the other: the preview keeps updating live even while recording.
            self.latestFrame = processed
            if self.isRecording {
                self.appendVideoFrame(processed, presentationTime: presentationTime)
            }

            if self.showCompositionCoach, !self.isAnalyzingComposition {
                self.coachFrameCounter += 1
                if self.coachFrameCounter % self.coachFrameSkip == 0 {
                    self.isAnalyzingComposition = true
                    self.analyzeComposition(pixelBuffer: pixelBuffer)
                }
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

    // Parameter name matters here, not just type: this is an @objc optional protocol
    // requirement, so Swift/ObjC selector matching is by full signature. The previous
    // `photoDisplayName: String?` (wrong name AND wrong type — should be `photoDisplayTime:
    // CMTime`) meant this never actually satisfied AVCapturePhotoCaptureDelegate's live-photo
    // callback. AVCapturePhotoOutput checks -respondsToSelector: before starting a Live Photo
    // capture and, finding no match, threw NSInvalidArgumentException and crashed the app —
    // every single time Live Photo was on, confirmed via the device's live crash log.
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingLivePhotoToMovieFileAt outputFileURL: URL,
                                  duration: CMTime, photoDisplayTime: CMTime, resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
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
