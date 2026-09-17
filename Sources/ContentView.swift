import SwiftUI

struct ContentView: View {
    @StateObject private var camera = CameraModel()
    @StateObject private var presetStore = PresetStore()
    @State private var mode: Mode = .photo
    @State private var showingSavePresetAlert = false
    @State private var newPresetName = ""
    @Environment(\.scenePhase) private var scenePhase

    enum Mode { case photo, video }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                preview
                controls
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
                        .padding()
                        Spacer()
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                let normalized = CGPoint(x: location.x / geo.size.width, y: location.y / geo.size.height)
                camera.focusAndExpose(at: normalized)
            }
        }
        .aspectRatio(3.0/4.0, contentMode: .fit)
        .background(Color.black)
    }

    private var controls: some View {
        VStack(spacing: 14) {
            HStack {
                Picker("Modus", selection: $mode) {
                    Text("Foto").tag(Mode.photo)
                    Text("Video").tag(Mode.video)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 200)

                Spacer()

                Button { camera.switchCamera() } label: {
                    Image(systemName: "arrow.triangle.2.circlepath.camera")
                }
                if camera.torchAvailable {
                    Button { camera.setTorch(!camera.torchOn) } label: {
                        Image(systemName: camera.torchOn ? "bolt.fill" : "bolt.slash")
                    }
                }
            }
            .font(.title3)
            .foregroundStyle(.white)

            if camera.maxZoom > camera.minZoom + 0.1 {
                HStack {
                    Text("Zoom").font(.caption).foregroundStyle(.white.opacity(0.7))
                    Slider(value: Binding(get: { camera.zoomFactor }, set: { camera.setZoom($0) }),
                           in: camera.minZoom...min(camera.maxZoom, 8))
                    Text(String(format: "%.1f×", camera.zoomFactor)).font(.caption.monospacedDigit()).foregroundStyle(.white)
                }
            }

            labeledSlider("Fisheye", value: $camera.fisheyeStrength)
            labeledSlider("Farbsaum", value: $camera.chromaticAberration)
            labeledSlider("Vignette", value: $camera.vignetteAmount)

            if camera.hasLiDAR {
                Toggle("Tiefenschärfe-Warp (LiDAR)", isOn: $camera.depthEnabled)
                    .toggleStyle(.switch)
                    .tint(.pink)
                    .font(.caption)
                    .foregroundStyle(.white)
            }

            Picker("Look", selection: $camera.lookID) {
                ForEach(LensLook.all) { look in
                    Text(look.name).tag(look.id)
                }
            }
            .pickerStyle(.menu)
            .tint(.white)

            labeledSlider("Look-Intensität", value: $camera.lookIntensity)

            presetBar

            if camera.proRAWAvailable && mode == .photo {
                Toggle("ProRAW", isOn: $camera.proRAWEnabled)
                    .toggleStyle(.switch)
                    .tint(.pink)
                    .font(.caption)
                    .foregroundStyle(.white)
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
            .tint(.pink)

            captureButton

            if let ok = camera.lastSaveOK {
                Text(ok ? "In Fotos gespeichert ✓" : "Speichern fehlgeschlagen")
                    .font(.caption)
                    .foregroundStyle(ok ? .green : .red)
            }
        }
        .padding()
        .background(Color(white: 0.08))
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
                Circle().stroke(.white, lineWidth: 4).frame(width: 72, height: 72)
                if mode == .video && camera.isRecording {
                    RoundedRectangle(cornerRadius: 6).fill(.red).frame(width: 28, height: 28)
                } else {
                    Circle().fill(mode == .video ? .red : .white).frame(width: 60, height: 60)
                }
            }
        }
        .frame(maxWidth: .infinity)
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
                        .background(Color.pink.opacity(0.25))
                        .foregroundStyle(.pink)
                        .clipShape(Capsule())
                }
                ForEach(presetStore.presets) { preset in
                    Button {
                        camera.apply(preset)
                    } label: {
                        Text(preset.name)
                            .font(.caption.bold())
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Color.white.opacity(0.12))
                            .foregroundStyle(.white)
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
            Text(title).font(.caption).foregroundStyle(.white.opacity(0.7)).frame(width: 100, alignment: .leading)
            Slider(value: value, in: 0...1)
            Text("\(Int(value.wrappedValue * 100))%").font(.caption.monospacedDigit()).foregroundStyle(.white).frame(width: 40)
        }
    }

    private func timeString(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
