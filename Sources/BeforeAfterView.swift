import SwiftUI

/// Shown right after a photo capture instead of saving immediately — dragging the
/// divider is the moment someone actually sees what the effect did, which is what
/// makes "keep it" or "try again" a real decision instead of a guess.
struct BeforeAfterView: View {
    @ObservedObject var camera: CameraModel
    @State private var dividerX: CGFloat = 0.5
    @State private var exportPreset: ExportPreset = .original

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

                        HStack {
                            Text("Original").font(.caption2.bold()).padding(6).background(.black.opacity(0.5)).cornerRadius(6)
                            Spacer()
                            Text("Bearbeitet").font(.caption2.bold()).padding(6).background(.black.opacity(0.5)).cornerRadius(6)
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

                Picker("Export", selection: $exportPreset) {
                    ForEach(ExportPreset.allCases) { preset in
                        Text(preset.label).tag(preset)
                    }
                }
                .pickerStyle(.segmented)
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
                        camera.confirmSave(exportPreset: exportPreset)
                    } label: {
                        Label("Behalten", systemImage: "checkmark")
                            .frame(maxWidth: .infinity).padding()
                    }
                    .background(.pink).foregroundStyle(.white).clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
        }
        .background(Color.black.ignoresSafeArea())
    }
}
