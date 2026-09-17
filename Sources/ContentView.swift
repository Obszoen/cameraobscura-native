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
    @Environment(\.scenePhase) private var scenePhase

    enum Mode { case photo, video }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            preview
            VStack {
                topBar
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
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
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
                if let image = camera.previewImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                } else {
                    Color.black
                    ProgressView().tint(.white)
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
            VStack(spacing: 18) {
                if camera.maxZoom > camera.minZoom + 0.1 {
                    HStack {
                        Text("Zoom").font(.caption).foregroundStyle(.secondary)
                        Slider(value: Binding(get: { camera.zoomFactor }, set: { camera.setZoom($0) }),
                               in: camera.minZoom...min(camera.maxZoom, 8))
                        Text(String(format: "%.1f×", camera.zoomFactor)).font(.caption.monospacedDigit())
                    }
                }

                labeledSlider("Fisheye", value: $camera.fisheyeStrength)
                labeledSlider("Farbsaum", value: $camera.chromaticAberration)
                labeledSlider("Vignette", value: $camera.vignetteAmount)

                if camera.hasLiDAR {
                    Toggle("Tiefenschärfe-Warp (LiDAR)", isOn: $camera.depthEnabled)
                        .toggleStyle(.switch)
                        .tint(Brand.rose)
                        .font(.caption)
                }

                Picker("Look", selection: $camera.lookID) {
                    ForEach(LensLook.all) { look in
                        Text(look.name).tag(look.id)
                    }
                }
                .pickerStyle(.menu)

                labeledSlider("Look-Intensität", value: $camera.lookIntensity)

                presetBar

                if camera.proRAWAvailable && mode == .photo {
                    Toggle("ProRAW", isOn: $camera.proRAWEnabled)
                        .toggleStyle(.switch)
                        .tint(Brand.mint)
                        .font(.caption)
                }

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
            .padding(.top, 4)
        }
        .tint(Brand.rose)
    }

    private var presetBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
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

    private func labeledSlider(_ title: String, value: Binding<Double>) -> some View {
        HStack {
            Text(title).font(.caption).foregroundStyle(.secondary).frame(width: 100, alignment: .leading)
            Slider(value: value, in: 0...1).tint(Brand.rose)
            Text("\(Int(value.wrappedValue * 100))%").font(.caption.monospacedDigit()).frame(width: 40)
        }
    }

    private func timeString(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
