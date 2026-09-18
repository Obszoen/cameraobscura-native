import SwiftUI

/// Shown right after a photo capture instead of saving immediately — dragging the
/// divider is the moment someone actually sees what the effect did, which is what
/// makes "keep it" or "try again" a real decision instead of a guess.
struct BeforeAfterView: View {
    @ObservedObject var camera: CameraModel
    @State private var dividerX: CGFloat = 0.5
    // Pre-selected from the live viewfinder framing guide (still fully changeable here —
    // the sensor always captured the full frame, this is only the starting suggestion).
    @State private var exportPreset: ExportPreset
    @State private var alsoSaveOriginal = false

    init(camera: CameraModel) {
        self.camera = camera
        _exportPreset = State(initialValue: camera.frameGuide)
    }

    var body: some View {
        VStack(spacing: 16) {
            if let original = camera.reviewOriginal, let processed = camera.reviewProcessed {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Image(uiImage: original)
                            .resizable().scaledToFill()
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()

                        Image(uiImage: processed)
                            .resizable().scaledToFill()
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                            .mask(alignment: .leading) {
                                Rectangle().frame(width: geo.size.width * dividerX)
                            }

                        Rectangle()
                            .fill(.white)
                            .frame(width: 2)
                            .position(x: geo.size.width * dividerX, y: geo.size.height / 2)
                            .shadow(radius: 2)

                        // The mask above reveals `processed` only within the leading
                        // `dividerX` fraction, with `original` as the full-size background
                        // showing through the rest — so the LEFT side is the edited version
                        // and the RIGHT side is the untouched one. Labels must match that,
                        // not just read left-to-right as "before/after" (they didn't:
                        // reported directly, verified against the mask logic above).
                        HStack {
                            Text("Bearbeitet").font(.caption2.bold()).padding(6).background(.black.opacity(0.5)).cornerRadius(6)
                            Spacer()
                            Text("Original").font(.caption2.bold()).padding(6).background(.black.opacity(0.5)).cornerRadius(6)
                        }
                        .foregroundStyle(.white)
                        .padding(10)
                    }
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                        dividerX = min(max(0, value.location.x / geo.size.width), 1)
                    })
                }
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding()

                Text("Gespeichert wird die bearbeitete Version — die Auswahl unten ist die Ausgabegröße.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                // Six presets now (16:9/4:3/panorama added) — a chip row instead of
                // `.segmented`, which would cram six labels unreadably into one bar.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(ExportPreset.allCases) { preset in
                            Button {
                                exportPreset = preset
                            } label: {
                                Text(preset.label)
                                    .font(.caption.bold())
                                    .padding(.horizontal, 12).padding(.vertical, 8)
                                    .background(exportPreset == preset ? Brand.rose.opacity(0.3) : Color.white.opacity(0.08))
                                    .foregroundStyle(exportPreset == preset ? Brand.rose : .white.opacity(0.75))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    .padding(.horizontal)
                }

                Toggle("Auch Original behalten", isOn: $alsoSaveOriginal)
                    .toggleStyle(.switch)
                    .tint(Brand.rose)
                    .font(.footnote)
                    .foregroundStyle(.white)
                    .padding(.horizontal)

                HStack(spacing: 14) {
                    Button {
                        camera.discardReview()
                    } label: {
                        Label("Verwerfen", systemImage: "trash")
                            .frame(maxWidth: .infinity).padding()
                    }
                    .background(Color(white: 0.15)).foregroundStyle(.white).clipShape(RoundedRectangle(cornerRadius: 12))

                    Button {
                        camera.confirmSave(exportPreset: exportPreset, alsoSaveOriginal: alsoSaveOriginal)
                    } label: {
                        Label(alsoSaveOriginal ? "Beide behalten" : "Behalten", systemImage: "checkmark")
                            .frame(maxWidth: .infinity).padding()
                    }
                    .background(Brand.rose).foregroundStyle(.white).clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal)

                // The system share sheet, not a hand-rolled per-platform integration —
                // asked for directly ("teilbar mit den häufigsten... Insta, Facebook, Kick,
                // TikTok, Etsy, Pinterest, X, LinkedIn"), and this is how every one of those
                // actually gets covered: any installed app that accepts image content
                // registers itself here automatically, nothing to hand-wire per platform.
                ShareLink(
                    item: Image(uiImage: exportPreset.apply(to: camera.reviewProcessed ?? UIImage())),
                    preview: SharePreview("CameraObscura-Foto", image: Image(uiImage: exportPreset.apply(to: camera.reviewProcessed ?? UIImage())))
                ) {
                    Label("Teilen", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity).padding()
                }
                .background(Brand.mint.opacity(0.2)).foregroundStyle(Brand.mint).clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)
                .padding(.bottom)
            }
        }
        .background(Color.black.ignoresSafeArea())
    }
}
