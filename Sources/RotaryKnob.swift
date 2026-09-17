import SwiftUI

/// A real rotary knob (270° sweep, gap at the bottom) instead of a horizontal slider —
/// asked for explicitly: sliders read as generic/cheap here, a knob reads as a considered
/// instrument control. Angle math verified numerically before writing this (top of the
/// knob = 0.5, the two ends of the gap = 0.0/1.0) rather than trusted on faith.
struct RotaryKnob: View {
    let title: String
    @Binding var value: Double // 0...1
    var accent: Color = Brand.rose

    /// The sweep is 270° with a 90° gap centered at the bottom. In the plain screen-angle
    /// convention (0° = right/3-o'clock, clockwise positive, matching atan2(dy, dx)), the
    /// knob's zero point sits at native 135° (bottom-left) and its end at native 45°
    /// (bottom-right), sweeping clockwise through the top in between.
    private let sweepStartNativeDegrees: Double = 135
    private let sweepDegrees: Double = 270

    @State private var isDragging = false

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                let size = min(geo.size.width, geo.size.height)
                ZStack {
                    // Track: the full available travel, dim.
                    Circle()
                        .trim(from: 0, to: sweepDegrees / 360)
                        .stroke(Color.white.opacity(0.14), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(sweepStartNativeDegrees))

                    // Fill: how far the value has turned.
                    Circle()
                        .trim(from: 0, to: (sweepDegrees / 360) * value)
                        .stroke(accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(sweepStartNativeDegrees))

                    Circle()
                        .fill(Color.white.opacity(isDragging ? 0.14 : 0.07))
                        .padding(9)

                    // Pointer dot at the current angle. Placed at the top by the offset,
                    // then rotated clockwise from there — a different zero reference (top,
                    // not right) than the trim's, but both were derived to agree at the
                    // gap's two ends (see RotaryKnob's angle math check).
                    Circle()
                        .fill(accent)
                        .frame(width: 6, height: 6)
                        .offset(y: -(size / 2 - 9))
                        .rotationEffect(.degrees(225 + sweepDegrees * value))
                }
                .frame(width: size, height: size)
                .contentShape(Circle())
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { drag in
                            isDragging = true
                            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                            let dx = drag.location.x - center.x
                            let dy = drag.location.y - center.y
                            guard dx != 0 || dy != 0 else { return }
                            var angle = atan2(dy, dx) * 180 / .pi
                            if angle < 0 { angle += 360 }
                            var adjusted = angle - sweepStartNativeDegrees
                            if adjusted < 0 { adjusted += 360 }
                            if adjusted > sweepDegrees {
                                // In the bottom gap: snap to whichever end is closer rather
                                // than let the value jump discontinuously across it.
                                let gapWidth = 360 - sweepDegrees
                                adjusted = (adjusted - sweepDegrees) > gapWidth / 2 ? 0 : sweepDegrees
                            }
                            value = adjusted / sweepDegrees
                        }
                        .onEnded { _ in isDragging = false }
                )
            }
            .frame(width: 64, height: 64)

            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text("\(Int(value * 100))%").font(.caption2.monospacedDigit()).foregroundStyle(.primary)
        }
    }
}
