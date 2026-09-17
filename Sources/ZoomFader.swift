import SwiftUI
import UIKit

/// A vertical fader — asked for directly ("wie ein Mixer-Pin den man schiebt") — for zoom
/// specifically, because zoom is a genuinely linear quantity, unlike the fisheye/tone
/// knobs' artistic 0...1 range that suits a rotary control better. Absolute positioning
/// (the pin follows the touch point 1:1), unlike RotaryKnob's relative-delta drag: a
/// fader's track is long enough that 1:1 tracking doesn't read as "hektisch" the way a
/// small knob's raw touch-angle did on a 52pt control — it's the correct, expected fader
/// interaction, the same one real mixers and this app's own knobs both avoid for knobs but
/// want here.
struct ZoomFader: View {
    @Binding var value: Double // 0...1
    /// Normalized (0...1) positions of "real" native-resolution zoom steps (e.g. the 48MP
    /// Fusion sensor's 2x crop mode) — drawn as brighter ticks and magnetically snapped to
    /// on release, the same tactile stop real camera apps give their 1x/2x pips.
    var nativeStops: [Double] = []
    var accent: Color = Brand.skyBlue
    var label: String
    var valueText: String

    private let trackHeight: CGFloat = 92
    private let capWidth: CGFloat = 30
    private let capHeight: CGFloat = 13
    private let snapTolerance: Double = 0.035

    @State private var isDragging = false

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                Capsule()
                    .fill(Color.black.opacity(0.55))
                    .frame(width: 8, height: trackHeight)
                    .overlay(Capsule().strokeBorder(.white.opacity(0.08), lineWidth: 1))

                ForEach(Array(tickPositions.enumerated()), id: \.offset) { _, tick in
                    Rectangle()
                        .fill(tick.isNative ? accent : Color.white.opacity(0.3))
                        .frame(width: tick.isNative ? 16 : 10, height: tick.isNative ? 2 : 1)
                        .offset(y: trackHeight / 2 - CGFloat(tick.position) * trackHeight)
                }

                RoundedRectangle(cornerRadius: 3)
                    .fill(LinearGradient(colors: [Color(white: 0.55), Color(white: 0.16)],
                                          startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(.black.opacity(0.6), lineWidth: 0.5))
                    .overlay(Rectangle().fill(.white.opacity(0.7)).frame(width: 22, height: 1.5))
                    .frame(width: capWidth, height: capHeight)
                    .shadow(color: .black.opacity(0.5), radius: isDragging ? 4 : 2, y: 1)
                    .scaleEffect(isDragging ? 1.05 : 1.0)
                    .offset(y: trackHeight / 2 - CGFloat(value) * trackHeight)
                    .animation(.easeOut(duration: 0.12), value: isDragging)
            }
            .frame(width: capWidth + 4, height: trackHeight)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        isDragging = true
                        let raw = 1 - Double(drag.location.y / trackHeight)
                        value = min(max(raw, 0), 1)
                    }
                    .onEnded { _ in
                        isDragging = false
                        if let snapped = nearestStop(to: value) {
                            value = snapped
                            UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.7)
                        }
                    }
            )

            Text(label)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(1.0)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            Text(valueText)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.primary.opacity(0.85))
        }
    }

    private struct Tick { let position: Double; let isNative: Bool }
    private var tickPositions: [Tick] {
        [Tick(position: 0, isNative: false), Tick(position: 1, isNative: false)]
            + nativeStops.map { Tick(position: $0, isNative: true) }
    }

    private func nearestStop(to value: Double) -> Double? {
        let candidates = [0.0, 1.0] + nativeStops
        guard let closest = candidates.min(by: { abs($0 - value) < abs($1 - value) }) else { return nil }
        return abs(closest - value) <= snapTolerance ? closest : nil
    }
}
