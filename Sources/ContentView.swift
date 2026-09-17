import SwiftUI

/// Full-screen viewfinder with a slim always-visible bottom bar (mode, shutter, flip,
/// tune) — the standard layout every camera app on the App Store uses — instead of a
/// boxed preview stacked above a permanently-expanded wall of sliders. The sliders/looks/
/// presets live in a native resizable sheet (drag handle, half/full height, swipe to
/// dismiss) opened from the "Tune" button, so the viewfinder always fits the screen and
/// nothing is ever clipped off the bottom on any device size.
struct ContentView: View {
    @StateObject private var camera = CameraModel()
    @StateObject private var presetStore = PresetStore()
    @State private var mode: Mode = .photo
    @State private var showingSavePresetAlert = false
    @State private var newPresetName = ""
    @State private var showingAdjustments = false
    @State private var pinchStartZoom: CGFloat?
    @State private var showGrid = false
    @State private var lastShuffleIndex: Int?
    @State private var shuffledPresetName: String?
    // Compact by default: the primary knobs + look picker fit here without dragging,
    // reported directly as "man muss zu viel ins Bild rücken" with the old .medium/.large
    // pair. `.large` stays reachable for the secondary controls (presets, toggles).
    @State private var adjustmentsDetent: PresentationDetent = .height(360)
    @Environment(\.scenePhase) private var scenePhase

    enum Mode { case photo, video }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            preview
            VStack {
                topBar
                if camera.showCompositionCoach {
                    coachModeSwitch
                }
                Spacer()
                bottomBar
            }
        }
        .onAppear { camera.start() }
        .onDisappear { camera.stop() }
        // Backgrounding the app must stop the camera/GPU pipeline immediately, not just
        // when the view happens to be torn down — a live camera + Metal filters running
        // behind a locked screen is exactly the kind of thing that overheats a phone
        // and drains the battery for no reason anyone would notice until it's too late.
        .onChange(of: scenePhase) { newPhase in
            switch newPhase {
            case .active: camera.start()
            default: camera.stop()
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { camera.reviewProcessed != nil },
            set: { if !$0 { camera.discardReview() } }
        )) {
            BeforeAfterView(camera: camera)
        }
        .sheet(isPresented: $showingAdjustments) {
            adjustmentsSheet
                .presentationDetents([.height(360), .large], selection: $adjustmentsDetent)
                // A custom grabber capsule is drawn inside adjustmentsSheet itself, styled
                // to match the panel — the plain system indicator would look like a second,
                // clashing element stacked on top of it.
                .presentationDragIndicator(.hidden)
                .presentationBackground { FaceplateBackground() }
        }
        .alert("Preset speichern", isPresented: $showingSavePresetAlert) {
            TextField("Name", text: $newPresetName)
            Button("Speichern") {
                guard !newPresetName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                presetStore.add(camera.currentSettingsAsPreset(named: newPresetName))
                newPresetName = ""
            }
            Button("Abbrechen", role: .cancel) { newPresetName = "" }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Full-screen viewfinder

    private var preview: some View {
        GeometryReader { geo in
            ZStack {
                if camera.latestFrame != nil {
                    MetalPreviewView(frame: camera.latestFrame, isActive: scenePhase == .active)
                        .frame(width: geo.size.width, height: geo.size.height)
                } else if let error = camera.configurationError {
                    Color.black
                    VStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle").font(.title).foregroundStyle(Brand.rose)
                        Text(error).font(.subheadline).foregroundStyle(.white).multilineTextAlignment(.center)
                    }
                    .padding(32)
                } else {
                    Color.black
                    ProgressView().tint(.white)
                }

                if showGrid {
                    GridOverlay()
                        .stroke(.white.opacity(0.45), lineWidth: 1)
                        .allowsHitTesting(false)
                }

                LevelLine(rollDegrees: camera.rollDegrees)
                    .allowsHitTesting(false)

                if camera.showCompositionCoach, let box = camera.personBoxNormalized {
                    CompositionCoachOverlay(
                        personBox: box,
                        target: CompositionCoach.target(for: box, style: camera.compositionStyle),
                        bufferSize: camera.compositionFrameSize,
                        accent: Brand.mint
                    )
                    .allowsHitTesting(false)
                }

                if camera.showCompositionCoach, let hint = camera.compositionHint {
                    VStack {
                        Spacer()
                        Text(hint)
                            .font(.caption.bold())
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(.black.opacity(0.6), in: Capsule())
                            .foregroundStyle(Brand.mint)
                        Spacer().frame(height: 150)
                    }
                    .allowsHitTesting(false)
                }

                if camera.isRecording {
                    VStack {
                        HStack {
                            Label(timeString(camera.recordingSeconds), systemImage: "circle.fill")
                                .font(.system(.footnote, design: .monospaced))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(.black.opacity(0.55), in: Capsule())
                            Spacer()
                        }
                        .padding(.top, 60)
                        .padding(.horizontal)
                        Spacer()
                    }
                }

                if let interruption = camera.interruptionMessage {
                    ZStack {
                        Color.black.opacity(0.55)
                        VStack(spacing: 10) {
                            Image(systemName: "pause.circle").font(.title).foregroundStyle(Brand.skyBlue)
                            Text(interruption).font(.subheadline).foregroundStyle(.white).multilineTextAlignment(.center)
                        }
                        .padding(32)
                    }
                    .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                let normalized = CGPoint(x: location.x / geo.size.width, y: location.y / geo.size.height)
                camera.focusAndExpose(at: normalized)
            }
            // Pinch-to-zoom, the gesture every camera app trains people to expect — the
            // slider in the tune sheet is a precise fallback, not the primary control.
            .gesture(
                MagnificationGesture()
                    .onChanged { scale in
                        let base = pinchStartZoom ?? camera.zoomFactor
                        if pinchStartZoom == nil { pinchStartZoom = base }
                        camera.setZoom(base * scale)
                    }
                    .onEnded { _ in pinchStartZoom = nil }
            )
        }
        .ignoresSafeArea()
    }

    // MARK: - Always-visible chrome

    private var topBar: some View {
        HStack {
            Picker("Modus", selection: $mode) {
                Text("Foto").tag(Mode.photo)
                Text("Video").tag(Mode.video)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 180)

            Spacer()

            chromeButton("grid", tint: showGrid ? Brand.mint : .white) {
                showGrid.toggle()
            }

            chromeButton("viewfinder", tint: camera.showCompositionCoach ? Brand.mint : .white) {
                camera.showCompositionCoach.toggle()
                if !camera.showCompositionCoach { camera.personBoxNormalized = nil }
            }

            if camera.torchAvailable {
                chromeButton(camera.torchOn ? "bolt.fill" : "bolt.slash",
                             tint: camera.torchOn ? Brand.skyBlue : .white) {
                    camera.setTorch(!camera.torchOn)
                }
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    /// Two independent parameters, asked for explicitly (one axis of input wasn't enough
    /// to make the coach feel adjustable): who moves, and what composition it aims for.
    private var coachModeSwitch: some View {
        VStack(spacing: 6) {
            Picker("Wer bewegt sich?", selection: $camera.coachMode) {
                Text("Ich filme").tag(CameraModel.CoachMode.photographerMoves)
                Text("Ich bin im Bild").tag(CameraModel.CoachMode.subjectMoves)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 260)

            Picker("Ziel-Komposition", selection: $camera.compositionStyle) {
                Text("Drittel").tag(CameraModel.CompositionStyle.thirds)
                Text("Zentriert").tag(CameraModel.CompositionStyle.centered)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 260)
        }
        .padding(.top, 6)
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            if let ok = camera.lastSaveOK {
                Text(ok ? "In Fotos gespeichert ✓" : "Speichern fehlgeschlagen")
                    .font(.caption2)
                    .foregroundStyle(ok ? .green : .red)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(.black.opacity(0.55), in: Capsule())
            }
            HStack {
                chromeButton("slider.horizontal.3") { showingAdjustments = true }
                    .overlay(alignment: .topTrailing) {
                        if camera.lookID != "none" || camera.fisheyeStrength > 0.01 {
                            Circle().fill(Brand.rose).frame(width: 7, height: 7).offset(x: 1, y: -1)
                        }
                    }

                Spacer()
                captureButton
                Spacer()

                chromeButton("arrow.triangle.2.circlepath.camera") { camera.switchCamera() }
            }
            .padding(.horizontal, 32)
        }
        .padding(.bottom, 12)
    }

    private func chromeButton(_ systemImage: String, tint: Color = .white, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.subheadline)
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(.black.opacity(0.35), in: Circle())
        }
    }

    private var captureButton: some View {
        Button {
            if mode == .photo {
                camera.capturePhoto()
            } else {
                camera.isRecording ? camera.stopRecording() : camera.startRecording()
            }
        } label: {
            ZStack {
                Circle().stroke(Brand.rose, lineWidth: 3).frame(width: 60, height: 60)
                if mode == .video && camera.isRecording {
                    RoundedRectangle(cornerRadius: 5).fill(.red).frame(width: 22, height: 22)
                } else {
                    Circle().fill(mode == .video ? .red : .white).frame(width: 50, height: 50)
                }
            }
        }
    }

    // MARK: - Adjustments sheet (fisheye/look/presets) — everything that used to be a
    // permanently-stacked wall of controls now lives here, scrollable and dismissible,
    // so it never clips regardless of screen size.

    private var adjustmentsSheet: some View {
        ScrollView {
            VStack(spacing: 14) {
                Capsule().fill(.white.opacity(0.2)).frame(width: 36, height: 4).padding(.top, 2)

                PanelLegend(text: "Optik")
                knobRow

                if camera.hasLiDAR {
                    Toggle("Tiefenschärfe-Warp (LiDAR)", isOn: $camera.depthEnabled)
                        .toggleStyle(.switch)
                        .tint(Brand.rose)
                        .font(.caption)
                }

                PanelGroove()

                // The baseline every pro photo app leads with (Belichtung/Kontrast/
                // Sättigung/Schärfe, Weißabgleich/Lichter/Schatten) — asked for directly,
                // named "Tonwerte" rather than "Ton" so it doesn't read as the audio toggle
                // below in "Modi".
                PanelLegend(text: "Tonwerte")
                toneKnobRowPrimary
                toneKnobRowSecondary

                PanelGroove()

                PanelLegend(text: "Look")
                lookPicker
                HStack(spacing: 0) {
                    RotaryKnob(title: "Intensität", value: $camera.lookIntensity, accent: Brand.mint)
                        .frame(maxWidth: .infinity)
                    RotaryKnob(title: "Farbsaum", value: $camera.chromaticAberration, accent: Brand.skyBlue)
                        .frame(maxWidth: .infinity)
                }

                PanelGroove()

                PanelLegend(text: "Presets")
                presetBar

                if let shuffledPresetName {
                    Text("Gewürfelt: \(shuffledPresetName)")
                        .font(.caption2)
                        .foregroundStyle(Brand.skyBlue)
                }

                if camera.proRAWAvailable && mode == .photo {
                    Toggle("ProRAW", isOn: $camera.proRAWEnabled)
                        .toggleStyle(.switch)
                        .tint(Brand.mint)
                        .font(.caption)
                }

                PanelGroove()

                PanelLegend(text: "Modi")
                HStack(spacing: 18) {
                    Toggle("Auto", isOn: $camera.autoEnhance).toggleStyle(.button)
                    Toggle("Rund", isOn: $camera.circleMask).toggleStyle(.button)
                    Toggle("Korn", isOn: $camera.grain).toggleStyle(.button)
                    if mode == .photo {
                        Toggle("Live", isOn: $camera.livePhotoEnabled).toggleStyle(.button)
                    } else {
                        Toggle("Ton", isOn: $camera.audioEnabled).toggleStyle(.button)
                            .disabled(camera.isRecording)
                    }
                }
                .font(.caption)
                .tint(Brand.mint)

                FeedbackBox()
            }
            .padding()
            .padding(.top, 2)
        }
        .scrollContentBackground(.hidden)
        .tint(Brand.rose)
    }

    /// The core adjustment knobs, side by side — compact (a knob is a quarter the width of
    /// a full slider row) and reads as a considered instrument panel rather than a stack of
    /// generic form controls.
    private var knobRow: some View {
        HStack(spacing: 0) {
            if camera.maxZoom > camera.minZoom + 0.1 {
                RotaryKnob(title: "Zoom", value: Binding(
                    get: { (camera.zoomFactor - camera.minZoom) / (min(camera.maxZoom, 8) - camera.minZoom) },
                    set: { camera.setZoom(camera.minZoom + $0 * (min(camera.maxZoom, 8) - camera.minZoom)) }
                ), accent: Brand.skyBlue)
                .frame(maxWidth: .infinity)
            }
            RotaryKnob(title: "Fisheye", value: $camera.fisheyeStrength)
                .frame(maxWidth: .infinity)
            RotaryKnob(title: "Vignette", value: $camera.vignetteAmount, accent: Brand.skyBlue)
                .frame(maxWidth: .infinity)
        }
    }

    /// Belichtung/Kontrast/Sättigung/Schärfe — the four controls virtually every photo
    /// app's basic panel leads with.
    private var toneKnobRowPrimary: some View {
        HStack(spacing: 0) {
            RotaryKnob(title: "Helligkeit", value: $camera.brightness)
                .frame(maxWidth: .infinity)
            RotaryKnob(title: "Kontrast", value: $camera.contrast, accent: Brand.mint)
                .frame(maxWidth: .infinity)
            RotaryKnob(title: "Sättigung", value: $camera.saturation, accent: Brand.skyBlue)
                .frame(maxWidth: .infinity)
            RotaryKnob(title: "Schärfe", value: $camera.sharpness, accent: Brand.rose)
                .frame(maxWidth: .infinity)
        }
    }

    /// Weißabgleich/Lichter/Schatten — the second tier most apps tuck one tap deeper.
    private var toneKnobRowSecondary: some View {
        HStack(spacing: 0) {
            RotaryKnob(title: "Wärme", value: $camera.warmth, accent: Brand.mint)
                .frame(maxWidth: .infinity)
            RotaryKnob(title: "Lichter", value: $camera.highlights, accent: Brand.skyBlue)
                .frame(maxWidth: .infinity)
            RotaryKnob(title: "Schatten", value: $camera.shadows)
                .frame(maxWidth: .infinity)
        }
    }

    /// Swatch-based look picker: each look's grade applied to a neutral gray, so the
    /// color character is visible at a glance instead of reading names off a menu.
    private var lookPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(LensLook.all) { look in
                        Button {
                            camera.lookID = look.id
                        } label: {
                            Circle()
                                .fill(look.previewColor)
                                .frame(width: 40, height: 40)
                                .overlay(
                                    Circle().stroke(Brand.rose, lineWidth: camera.lookID == look.id ? 3 : 0)
                                )
                                .overlay(
                                    Circle().stroke(.white.opacity(0.25), lineWidth: 1)
                                )
                        }
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 4)
            }
            if let current = LensLook.all.first(where: { $0.id == camera.lookID }) {
                Text("\(current.name) · \(current.subtitle)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var presetBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button {
                    // Never the same one twice in a row — repeating the last pick would
                    // read as broken ("I tapped shuffle and nothing happened"), not lucky.
                    var index = Int.random(in: 0..<CuratedPresets.all.count)
                    if CuratedPresets.all.count > 1, index == lastShuffleIndex {
                        index = (index + 1) % CuratedPresets.all.count
                    }
                    lastShuffleIndex = index
                    let preset = CuratedPresets.all[index]
                    camera.apply(preset)
                    shuffledPresetName = preset.name
                } label: {
                    Label("Würfeln", systemImage: "dice.fill")
                        .font(.caption.bold())
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Brand.skyBlue.opacity(0.22))
                        .foregroundStyle(Brand.skyBlue)
                        .clipShape(Capsule())
                }
                Button {
                    showingSavePresetAlert = true
                } label: {
                    Label("Speichern", systemImage: "plus.circle.fill")
                        .font(.caption.bold())
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Brand.rose.opacity(0.25))
                        .foregroundStyle(Brand.rose)
                        .clipShape(Capsule())
                }
                ForEach(presetStore.presets) { preset in
                    Button {
                        camera.apply(preset)
                    } label: {
                        Text(preset.name)
                            .font(.caption.bold())
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Brand.mint.opacity(0.18))
                            .foregroundStyle(Brand.mint)
                            .clipShape(Capsule())
                    }
                    .contextMenu {
                        Button("Löschen", role: .destructive) {
                            if let index = presetStore.presets.firstIndex(of: preset) {
                                presetStore.remove(at: IndexSet(integer: index))
                            }
                        }
                    }
                }
            }
        }
    }

    private func timeString(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
