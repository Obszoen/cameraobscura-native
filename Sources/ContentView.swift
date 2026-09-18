import SwiftUI
import UIKit

/// Full-screen viewfinder with a slim always-visible bottom bar (mode, shutter, flip,
/// tune) — the standard layout every camera app on the App Store uses — instead of a
/// boxed preview stacked above a permanently-expanded wall of sliders. The sliders/looks/
/// presets live in a native resizable sheet (drag handle, half/full height, swipe to
/// dismiss) opened from the "Tune" button, so the viewfinder always fits the screen and
/// nothing is ever clipped off the bottom on any device size.
struct ContentView: View {
    @StateObject private var camera = CameraModel()
    @StateObject private var presetStore = PresetStore()
    @StateObject private var settings = AppSettings()
    @StateObject private var activeControl = ActiveControl()
    @State private var mode: Mode = .photo
    @State private var showingSavePresetAlert = false
    @State private var newPresetName = ""
    @State private var showingAdjustments = false
    @State private var showingSettings = false
    @State private var pinchStartZoom: CGFloat?
    @State private var rotationStartValue: Double?
    @State private var selfieSwipeStartValue: Double?
    @State private var captureFlash = false
    @State private var savedThumbnail: UIImage?
    @State private var showTimerCountdown = false
    @State private var timerSecondsLeft = 0
    @AppStorage("com.danielschweiger.cameraobscura.selfTimerSeconds") private var selfTimerSeconds = 0 // 0 = off
    @AppStorage("com.danielschweiger.cameraobscura.hasSeenPrivacyNote") private var hasSeenPrivacyNote = false
    @State private var showingPrivacyNote = false
    @State private var lastCompositionPresetIndex: Int?
    /// Favorite looks are stored as IDs so the user's filter curation survives
    /// reopening the panel and relaunching the app.
    @State private var favoriteLookIDs: Set<String> = []
    @AppStorage("com.danielschweiger.cameraobscura.favoriteLookIDs") private var favoriteLookIDsData = Data()
    // Shown once, ever, per device — asked for directly: two custom gestures (rotate,
    // double-tap-reset) had no explanation anywhere, so the good feel of the rotate
    // gesture in particular "read as a random find" instead of an intentional control.
    @AppStorage("com.danielschweiger.cameraobscura.hasSeenRotateHint") private var hasSeenRotateHint = false
    @State private var showGrid = false
    @State private var lastShuffleIndex: Int?
    @State private var shuffledPresetName: String?
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
            if showingAdjustments {
                adjustmentsPanel
                    .zIndex(2)
                    .transition(.move(edge: settings.panelEdge.edge).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.86), value: showingAdjustments)
        .environmentObject(activeControl)
        .environmentObject(settings)
        .onAppear {
            camera.start()
            if let decoded = try? JSONDecoder().decode(Set<String>.self, from: favoriteLookIDsData) {
                favoriteLookIDs = decoded
            }
        }
        .onChange(of: favoriteLookIDs) { updated in
            favoriteLookIDsData = (try? JSONEncoder().encode(updated)) ?? Data()
        }
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
        // `.onReceive`, not `.onChange(of:)` — UIImage isn't Equatable, which
        // `.onChange(of:perform:)` requires; Combine's publisher has no such constraint.
        .onReceive(camera.$lastSavedThumbnail) { thumb in
            guard thumb != nil else { return }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { savedThumbnail = thumb }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                withAnimation(.easeOut(duration: 0.3)) { savedThumbnail = nil }
            }
        }
        .onAppear {
            if !hasSeenPrivacyNote { showingPrivacyNote = true }
        }
        .sheet(isPresented: $showingPrivacyNote, onDismiss: { hasSeenPrivacyNote = true }) {
            PrivacyNoteSheet()
        }
        .fullScreenCover(isPresented: Binding(
            get: { camera.reviewProcessed != nil },
            set: { if !$0 { camera.discardReview() } }
        )) {
            BeforeAfterView(camera: camera)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsPanel(settings: settings)
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

                if let aspect = camera.frameGuide.aspectRatio {
                    FrameGuideOverlay(aspectRatio: aspect)
                        .allowsHitTesting(false)
                }

                LevelLine(rollDegrees: camera.rollDegrees, accent: settings.levelLineColor)
                    .allowsHitTesting(false)

                if camera.showCompositionCoach, !camera.personBoxes.isEmpty {
                    CompositionCoachMultiOverlay(
                        personBoxes: camera.personBoxes,
                        targets: camera.personBoxes.count > 1
                            ? CompositionCoach.targets(for: camera.personBoxes)
                            : [CompositionCoach.target(for: camera.personBoxes[0], style: camera.compositionStyle, preset: camera.compositionPreset)],
                        bufferSize: camera.compositionFrameSize,
                        accent: settings.crosshairColor
                    )
                    .allowsHitTesting(false)
                }

                if camera.showCompositionCoach, let hint = camera.compositionHint {
                    VStack {
                        Spacer()
                        Text(hint)
                            .font(.caption.bold())
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
                            .foregroundStyle(settings.crosshairColor)
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

                Color.white
                    .opacity(captureFlash ? 0.85 : 0)
                    .allowsHitTesting(false)
                    .blendMode(.plusLighter)

                if showTimerCountdown {
                    ZStack {
                        Circle()
                            .trim(from: 0, to: CGFloat(timerSecondsLeft) / CGFloat(max(selfTimerSeconds, 1)))
                            .stroke(Brand.rose, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .frame(width: 90, height: 90)
                            .animation(.linear(duration: 1), value: timerSecondsLeft)
                        Text("\(timerSecondsLeft)")
                            .font(.system(size: 40, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white)
                    }
                    .allowsHitTesting(false)
                }

                if camera.showHistogram, let histogram = camera.liveHistogram {
                    VStack {
                        HistogramView(bins: histogram)
                            .frame(width: 140, height: 50)
                            .padding(6)
                            .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
                            .padding(.top, 60)
                            .padding(.trailing, 12)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        Spacer()
                    }
                    .allowsHitTesting(false)
                }

                if let thumb = savedThumbnail {
                    VStack {
                        Spacer()
                        HStack {
                            Image(uiImage: thumb)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 44, height: 44)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.6), lineWidth: 1))
                                .shadow(radius: 4)
                                .padding(.leading, 16)
                                .padding(.bottom, 100)
                                .transition(.scale.combined(with: .opacity))
                            Spacer()
                        }
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

                // Accent-colored edge tint while any knob/fader is being touched — asked for
                // directly, so peripheral vision alone tells you which control is live
                // without looking down at the panel.
                if let accent = activeControl.label != nil ? activeControl.accent : nil {
                    Rectangle()
                        .strokeBorder(accent, lineWidth: 3)
                        .opacity(0.55)
                        .allowsHitTesting(false)
                }

                // The large in-viewfinder value readout — asked for directly: seeing the
                // effect change is one thing, but the exact number without glancing at the
                // small in-panel label is what actually keeps eyes on the shot.
                if let label = activeControl.label, let value = activeControl.value {
                    VStack(spacing: 2) {
                        Text(label.uppercased())
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .tracking(2)
                            .foregroundStyle(.white.opacity(0.65))
                        Text("\(Int(value * 100))")
                            .font(.system(size: 52, weight: .bold, design: .monospaced))
                            .foregroundStyle(activeControl.accent)
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 16)
                    .background(.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 18))
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
                    .allowsHitTesting(false)
                }

                // A persistent (not just while dragging) badge showing which control a
                // two-finger rotation on the viewfinder currently targets — reported
                // directly: the gesture worked and felt good, but with nothing showing
                // what it was bound to, it read as a random find, not a real control.
                // Touching any knob/fader in the panel rebinds it; this is just visibility.
                if let label = activeControl.lastLabel, activeControl.label == nil {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Label(label, systemImage: "arrow.triangle.2.circlepath")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(activeControl.lastAccent)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(.black.opacity(0.45), in: Capsule())
                                .padding(.trailing, 12)
                        }
                        .padding(.bottom, 100)
                    }
                    .allowsHitTesting(false)
                }

                // Two custom gestures nowhere in the UI actually explains themselves —
                // same problem as the rotate gesture, same fix, combined into one tip
                // instead of two separate popups on first launch.
                if !hasSeenRotateHint {
                    VStack {
                        Spacer()
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Zwei-Finger-Dreh-Geste", systemImage: "hand.draw")
                                .font(.caption.bold())
                            Text("Mit zwei Fingern direkt im Sucher drehen, um den zuletzt berührten Regler zu verstellen — welcher das ist, siehst du unten rechts markiert. Bei der Frontkamera reicht ein Finger: einfach senkrecht wischen, praktisch für Selfies mit nur einer freien Hand.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Label("Doppeltipp auf einen Regler", systemImage: "hand.tap")
                                .font(.caption.bold())
                            Text("Setzt diesen einen Regler sofort auf seinen neutralen Wert zurück.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Button("Verstanden") {
                                hasSeenRotateHint = true
                            }
                            .font(.caption.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(Brand.rose, in: Capsule())
                            .foregroundStyle(Brand.ground)
                        }
                        .padding(16)
                        .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal, 40)
                        Spacer().frame(height: 160)
                    }
                }
            }
            .animation(.easeOut(duration: 0.15), value: activeControl.label)
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
            // Two-finger rotate directly on the shot, adjusting whichever knob/fader was
            // last touched — asked for directly: eyes stay on the frame, fingers work
            // "blind" the way real lens/aperture rings do. `.simultaneousGesture`, not a
            // second `.gesture()`, specifically so it coexists with the pinch-to-zoom above
            // rather than replacing it — pinch and rotate are two fingers doing two
            // different things at once, exactly what iOS's own gesture recognizers already
            // expect apps like this to combine.
            .simultaneousGesture(
                RotationGesture()
                    .onChanged { angle in
                        guard let getter = activeControl.lastGetter, let setter = activeControl.lastSetter else { return }
                        if rotationStartValue == nil { rotationStartValue = getter() }
                        // A full 180° turn sweeps the whole 0...1 range — enough travel to
                        // feel deliberate without needing an unrealistic full rotation.
                        let delta = angle.degrees / 180
                        let previousValue = getter()
                        let newValue = min(max((rotationStartValue ?? previousValue) + delta, 0), 1)
                        // A tick every 10% crossed, asked for directly — same feel as the
                        // knobs themselves, so the gesture reads as a real control, not a
                        // silent one.
                        if Int((previousValue * 10).rounded()) != Int((newValue * 10).rounded()) {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.4)
                        }
                        setter(newValue)
                        activeControl.showWhileRotating(value: newValue)
                    }
                    .onEnded { _ in
                        rotationStartValue = nil
                        activeControl.end()
                    }
            )
            // One-finger vertical swipe, same target/effect as the two-finger rotate above
            // — asked for directly: a selfie is usually shot one-handed (thumb only), where
            // a two-finger gesture simply isn't reachable. Always attached (a ternary
            // Optional-Gesture here would risk a type-inference dead end, the same reason
            // the bottom-edge panel-dismiss gesture elsewhere in this file checks its
            // condition inside the handler instead) but only acts for the front camera,
            // where the one-handed constraint actually applies — the rear camera keeps
            // two-finger rotate as the primary gesture so this doesn't fight tap-to-focus/
            // pinch-zoom there. `minimumDistance: 16` so a plain tap-to-focus still
            // recognizes cleanly.
            .simultaneousGesture(
                DragGesture(minimumDistance: 16)
                    .onChanged { drag in
                        guard camera.isUsingFrontCamera,
                              let getter = activeControl.lastGetter, let setter = activeControl.lastSetter else { return }
                        if selfieSwipeStartValue == nil { selfieSwipeStartValue = getter() }
                        let previousValue = getter()
                        let delta = Double(-drag.translation.height / 220)
                        let newValue = min(max((selfieSwipeStartValue ?? previousValue) + delta, 0), 1)
                        if Int((previousValue * 10).rounded()) != Int((newValue * 10).rounded()) {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.4)
                        }
                        setter(newValue)
                        activeControl.showWhileRotating(value: newValue)
                    }
                    .onEnded { _ in
                        guard selfieSwipeStartValue != nil else { return }
                        selfieSwipeStartValue = nil
                        activeControl.end()
                    }
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
                if !camera.showCompositionCoach { camera.personBoxes = [] }
            }

            chromeButton("waveform", tint: camera.showHistogram ? Brand.skyBlue : .white) {
                camera.showHistogram.toggle()
                if !camera.showHistogram { camera.liveHistogram = nil }
            }

            // Cycles 0 (off) -> 3s -> 10s -> off — asked for directly ("Selbstauslöser
            // (3s/10s) mit sichtbarem Countdown-Ring").
            chromeButton(selfTimerSeconds == 0 ? "timer" : "timer.circle.fill",
                         tint: selfTimerSeconds > 0 ? Brand.rose : .white) {
                selfTimerSeconds = selfTimerSeconds == 0 ? 3 : (selfTimerSeconds == 3 ? 10 : 0)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
            .disabled(mode == .video)
            .opacity(mode == .video ? 0.35 : 1)
            .overlay(alignment: .bottomTrailing) {
                if selfTimerSeconds > 0 {
                    Text("\(selfTimerSeconds)")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(Brand.ground)
                        .padding(2)
                        .background(Brand.rose, in: Circle())
                        .offset(x: 2, y: 2)
                }
            }

            chromeButton("gearshape") {
                showingSettings = true
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
            HelpButton(text: "Der Composition Coach zeigt ein Fadenkreuz zum idealen Bildaufbau. 'Ich filme' spricht dich als Fotograf an, 'Ich bin im Bild' spricht die Person im Bild direkt an. Darunter: Stil (Drittel/Editorial/...) oder eines von 47 präzisen Presets würfeln.")
            Picker("Wer bewegt sich?", selection: $camera.coachMode) {
                Text("Ich filme").tag(CameraModel.CoachMode.photographerMoves)
                Text("Ich bin im Bild").tag(CameraModel.CoachMode.subjectMoves)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 260)

            // Five styles now (fashion/selfie/landscape added) — too many for a clean
            // segmented control, so a chip row instead, same language as the look picker.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(CameraModel.CompositionStyle.allCases, id: \.self) { style in
                        Button {
                            camera.compositionStyle = style
                            camera.compositionPreset = nil
                        } label: {
                            Text(style.label)
                                .font(.caption2.bold())
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(camera.compositionStyle == style && camera.compositionPreset == nil ? Brand.mint.opacity(0.25) : Color.black.opacity(0.4))
                                .foregroundStyle(camera.compositionStyle == style && camera.compositionPreset == nil ? Brand.mint : .white.opacity(0.7))
                                .clipShape(Capsule())
                        }
                    }
                }
            }
            .frame(maxWidth: 280)

            // 47 finer numeric presets (30 general + 15 selfie + 2 Passfoto), asked for
            // directly — overrides the coarse style row above when one is picked.
            // Randomizable ("wahlweise randomisieren", asked for directly), same "never
            // twice in a row" pattern as the photo-preset shuffle.
            HStack(spacing: 6) {
                Button {
                    var index = Int.random(in: 0..<CompositionPresets.all.count)
                    if index == lastCompositionPresetIndex {
                        index = (index + 1) % CompositionPresets.all.count
                    }
                    lastCompositionPresetIndex = index
                    camera.compositionPreset = CompositionPresets.all[index]
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                } label: {
                    Label("Präzise Presets würfeln", systemImage: "dice.fill")
                        .font(.caption2.bold())
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Brand.skyBlue.opacity(0.22))
                        .foregroundStyle(Brand.skyBlue)
                        .clipShape(Capsule())
                }
                if let preset = camera.compositionPreset {
                    Text(preset.name)
                        .font(.caption2.bold())
                        .foregroundStyle(Brand.skyBlue)
                        .lineLimit(1)
                }
            }
        }
        .padding(.top, 6)
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            if let ok = camera.lastSaveOK {
                // An LED + monospaced label instead of a plain colored capsule — the same
                // "status" language real hardware uses, not a system-style toast.
                HStack(spacing: 6) {
                    PanelLED(isOn: true, color: ok ? Brand.mint : .red)
                    Text(ok ? "GESPEICHERT" : "FEHLER")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .tracking(1.0)
                        .foregroundStyle(ok ? Brand.mint : .red)
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(.black.opacity(0.6), in: Capsule())
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
                    .disabled(camera.isRecording)
                    .opacity(camera.isRecording ? 0.35 : 1)
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
                if selfTimerSeconds > 0 {
                    startSelfTimerAndCapture()
                } else {
                    fireShutter()
                }
            } else if camera.isRecording {
                if settings.soundEnabled { CameraSounds.recordStop() }
                camera.stopRecording()
            } else {
                if settings.soundEnabled { CameraSounds.recordStart() }
                camera.startRecording()
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

    private func fireShutter() {
        if settings.soundEnabled { CameraSounds.shutter() }
        // A one-frame flash on the viewfinder itself, like a real shutter — asked for
        // directly, on top of the sound/haptic that already fire.
        withAnimation(.easeOut(duration: 0.06)) { captureFlash = true }
        withAnimation(.easeIn(duration: 0.15).delay(0.06)) { captureFlash = false }
        camera.capturePhoto()
    }

    /// Counts down `selfTimerSeconds`, one haptic tick per second, then fires — asked for
    /// directly ("Selbstauslöser (3s/10s) mit sichtbarem Countdown-Ring").
    private func startSelfTimerAndCapture() {
        timerSecondsLeft = selfTimerSeconds
        showTimerCountdown = true
        func tick() {
            guard timerSecondsLeft > 0 else {
                showTimerCountdown = false
                fireShutter()
                return
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                timerSecondsLeft -= 1
                tick()
            }
        }
        tick()
    }

    // MARK: - Adjustments panel (fisheye/look/presets) — everything that used to be a
    // permanently-stacked wall of controls now lives here, scrollable and dismissible,
    // so it never clips regardless of screen size. Slides in from a user-chosen screen
    // edge (Einstellungen) instead of always being a bottom sheet — `adjustmentsPanel`
    // below owns sizing/positioning/the close control; this is just the scrolling content.

    private var adjustmentsContent: some View {
        ScrollView {
            VStack(spacing: 14) {
                PanelLegend(text: "Optik")
                PanelTicks()
                knobRow

                if camera.hasDepthCapability {
                    // Label kept sensor-agnostic — this flag covers both LiDAR devices and
                    // iPhone Air's LiDAR-free single-lens depth pipeline, so "(LiDAR)" would
                    // be wrong on exactly the device this app was built for.
                    HStack {
                        PanelToggle(title: "Tiefenschärfe-Warp", isOn: $camera.depthEnabled, accent: Brand.rose)
                        Spacer()
                    }
                }

                PanelGroove()

                // Live framing guide, asked for directly — the sensor still captures the
                // full frame regardless (see ExportPreset.apply), this only previews the
                // crop choice, still fully changeable after the shot on the review screen.
                PanelLegend(text: "Rahmen")
                PanelTicks()
                frameGuidePicker

                PanelGroove()

                // The baseline every pro photo app leads with (Belichtung/Kontrast/
                // Sättigung/Schärfe, Weißabgleich/Lichter/Schatten) — asked for directly,
                // named "Tonwerte" rather than "Ton" so it doesn't read as the audio toggle
                // below in "Modi".
                HStack(spacing: 4) {
                    PanelLegend(text: "Tonwerte")
                    HelpButton(text: "Alle sieben Regler sind bei 50% neutral (unverändert) — nach links = weniger, nach rechts = mehr. 'Natürlichkeit' zieht Kontrast/Sättigung sanft zurück, falls die anderen Regler zusammen zu stark wirken.")
                    Spacer()
                }
                PanelTicks()
                toneKnobRowPrimary
                toneKnobRowSecondary

                PanelGroove()

                PanelLegend(text: "Look")
                PanelTicks()
                lookPicker
                HStack(spacing: 0) {
                    RotaryKnob(title: "Intensität", value: $camera.lookIntensity, accent: Brand.mint, neutralValue: 0)
                        .frame(maxWidth: .infinity)
                    RotaryKnob(title: "Farbsaum", value: $camera.chromaticAberration, accent: Brand.skyBlue, neutralValue: 0)
                        .frame(maxWidth: .infinity)
                }

                PanelGroove()

                PanelLegend(text: "Presets")
                PanelTicks()
                presetBar

                if let shuffledPresetName {
                    Text("Gewürfelt: \(shuffledPresetName)")
                        .font(.caption2)
                        .foregroundStyle(Brand.skyBlue)
                }

                if camera.proRAWAvailable && mode == .photo {
                    HStack {
                        PanelToggle(title: "ProRAW", isOn: $camera.proRAWEnabled, accent: Brand.mint)
                        Spacer()
                    }
                }

                PanelGroove()

                PanelLegend(text: "Modi")
                PanelTicks()
                // Two rows of three, not one row of five/six — a single HStack would
                // overflow the narrower leading/trailing panel widths (Einstellungen →
                // Menü-Richtung), and wrapping isn't automatic for a plain HStack.
                VStack(spacing: 14) {
                    HStack(spacing: 14) {
                        PanelToggle(title: "Auto", isOn: $camera.autoEnhance, accent: Brand.mint)
                        PanelToggle(title: "Rund", isOn: $camera.circleMask, accent: Brand.mint)
                        PanelToggle(title: "Korn", isOn: $camera.grain, accent: Brand.mint)
                    }
                    HStack(spacing: 14) {
                        // Distinct from "Auto" above (Apple's generic auto-adjust) —
                        // specifically watches for and corrects overexposure, asked for
                        // directly, independently toggleable.
                        PanelToggle(title: "Belichtung", isOn: $camera.autoExposureCorrection, accent: Brand.skyBlue)
                        if mode == .photo {
                            PanelToggle(title: "Live", isOn: $camera.livePhotoEnabled, accent: Brand.mint)
                        } else {
                            PanelToggle(title: "Ton", isOn: $camera.audioEnabled, accent: Brand.mint)
                                .disabled(camera.isRecording)
                        }
                    }
                }

                FeedbackBox()
            }
            .padding()
            .padding(.top, 2)
        }
        .scrollContentBackground(.hidden)
        .tint(Brand.rose)
    }

    /// Sizes, positions and closes the panel per `settings.panelEdge` — full width capped
    /// height for top/bottom, capped width full height for the sides, so the viewfinder
    /// stays partially visible around it regardless of which edge someone picks. The close
    /// button is the one reliable dismiss path on every edge; a swipe back toward the
    /// panel's own edge is added on top for the bottom case, matching the old sheet's
    /// familiar swipe-down.
    private var adjustmentsPanel: some View {
        GeometryReader { geo in
            let edge = settings.panelEdge
            let panelSize: CGSize = edge.isVertical
                ? CGSize(width: min(300, geo.size.width * 0.82), height: geo.size.height)
                : CGSize(width: geo.size.width, height: min(440, geo.size.height * 0.62))

            VStack(spacing: 0) {
                HStack {
                    Capsule().fill(.white.opacity(0.2)).frame(width: 36, height: 4)
                    Spacer()
                    Button { showingAdjustments = false } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)

                adjustmentsContent
            }
            .frame(width: panelSize.width, height: panelSize.height)
            .background { FaceplateBackground(opacity: settings.panelOpacity) }
            .clipShape(Rectangle())
            .shadow(color: .black.opacity(0.5), radius: 14)
            .ignoresSafeArea(edges: edge == .bottom ? .bottom : (edge == .top ? .top : []))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: edge.alignment)
            // Always attached (avoids an Optional-Gesture type headache) but only acts for
            // the bottom edge, matching the old sheet's familiar swipe-down-to-dismiss; the
            // close button above is the one dismiss path guaranteed to work on every edge.
            .gesture(
                DragGesture()
                    .onEnded { drag in
                        guard edge == .bottom, drag.translation.height > 60 else { return }
                        showingAdjustments = false
                    }
            )
        }
    }

    /// The core adjustment knobs, side by side — compact (a knob is a quarter the width of
    /// a full slider row) and reads as a considered instrument panel rather than a stack of
    /// generic form controls.
    private var knobRow: some View {
        HStack(spacing: 0) {
            if camera.maxZoom > camera.minZoom + 0.1 {
                let span = min(camera.maxZoom, 8) - camera.minZoom
                ZoomFader(
                    value: Binding(
                        get: { Double((camera.zoomFactor - camera.minZoom) / span) },
                        set: { camera.setZoom(camera.minZoom + CGFloat($0) * span) }
                    ),
                    nativeStops: camera.nativeZoomFactors.compactMap { factor in
                        guard factor > camera.minZoom, factor < min(camera.maxZoom, 8) else { return nil }
                        return Double((factor - camera.minZoom) / span)
                    },
                    label: "Zoom",
                    valueText: String(format: "%.1f×", camera.zoomFactor)
                )
                .frame(maxWidth: .infinity)
            }
            RotaryKnob(title: "Fisheye", value: $camera.fisheyeStrength, neutralValue: 0)
                .frame(maxWidth: .infinity)
            RotaryKnob(title: "Vignette", value: $camera.vignetteAmount, accent: Brand.skyBlue, neutralValue: 0)
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
            RotaryKnob(title: "Schärfe", value: $camera.sharpness, accent: Brand.rose, neutralValue: 0)
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
            // Continuously damps how far contrast/saturation stray from neutral — a real,
            // visible-across-its-whole-range dial, not just an on/off — asked for directly.
            RotaryKnob(title: "Natürlichkeit", value: $camera.naturalness, accent: Brand.rose, neutralValue: 0)
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
                        // A metal-bezel chip instead of a flat colored circle — reported
                        // directly as "garbage": plain color dots didn't match the rest of
                        // the panel's rendered-hardware language at all. Same bevel gradient
                        // as the knob track, an LED (not a thick ring) marks the selection.
                        Button {
                            camera.lookID = look.id
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            if settings.soundEnabled { CameraSounds.toggleClick() }
                        } label: {
                            VStack(spacing: 4) {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(look.previewColor)
                                    .frame(width: 38, height: 38)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .strokeBorder(
                                                LinearGradient(colors: [.white.opacity(0.35), .black.opacity(0.5)],
                                                               startPoint: .topLeading, endPoint: .bottomTrailing),
                                                lineWidth: 1.5
                                            )
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .strokeBorder(Brand.rose, lineWidth: camera.lookID == look.id ? 2 : 0)
                                    )
                                    .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                                    // A real Blender-rendered switch per filter, asked for
                                    // literally ("Kippschalter für die Filter") — a favorite
                                    // pin, not the selection itself (a 22-way choice can't
                                    // structurally be a binary switch, but each one can
                                    // still carry a real switch element).
                                    .overlay(alignment: .topTrailing) {
                                        Button {
                                            if favoriteLookIDs.contains(look.id) {
                                                favoriteLookIDs.remove(look.id)
                                            } else {
                                                favoriteLookIDs.insert(look.id)
                                            }
                                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                            if settings.soundEnabled { CameraSounds.toggleClick() }
                                        } label: {
                                            Image(favoriteLookIDs.contains(look.id) ? "SwitchOn" : "SwitchOff")
                                                .resizable()
                                                .frame(width: 18, height: 18)
                                                .offset(x: 6, y: -6)
                                        }
                                    }
                                PanelLED(isOn: camera.lookID == look.id, color: Brand.rose)
                            }
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

    private var frameGuidePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ExportPreset.allCases.filter { $0 != .print }) { preset in
                    Button {
                        camera.frameGuide = preset
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        if settings.soundEnabled { CameraSounds.toggleClick() }
                    } label: {
                        Text(preset.label)
                            .font(.caption.bold())
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(camera.frameGuide == preset ? Brand.rose.opacity(0.25) : Color.white.opacity(0.05))
                            .foregroundStyle(camera.frameGuide == preset ? Brand.rose : .white.opacity(0.75))
                            .overlay(Capsule().strokeBorder(camera.frameGuide == preset ? Brand.rose : .white.opacity(0.12), lineWidth: 1))
                            .clipShape(Capsule())
                    }
                }
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
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    if settings.soundEnabled { CameraSounds.toggleClick() }
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
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        if settings.soundEnabled { CameraSounds.toggleClick() }
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
