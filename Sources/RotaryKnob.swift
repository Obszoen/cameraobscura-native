import SwiftUI

/// A real rotary knob (270° sweep, gap at the bottom) instead of a horizontal slider —
/// asked for explicitly: sliders read as generic/cheap here, a knob reads as a considered
/// instrument control. Angle math verified numerically before writing this (top of the
/// knob = 0.5, the two ends of the gap = 0.0/1.0) rather than trusted on faith.
struct RotaryKnob: View {
    let title: String
    @Binding var value: Double // 0...1
    var accent: Color = Brand.rose
    var size: CGFloat = 52

    /// The sweep is 270° with a 90° gap centered at the bottom, purely for how the value is
    /// drawn — see below for how it's actually set by touch.
    private let sweepDegrees: Double = 270

    @State private var isDragging = false
    // The value at the moment the current drag began, so `onChanged` can add a delta to it
    // rather than re-deriving an absolute value from the touch every callback.
    @State private var dragStartValue: Double?

    var body: some View {
        VStack(spacing: 5) {
            GeometryReader { geo in
                ZStack {
                    // Track: the full available travel, dim.
                    Circle()
                        .trim(from: 0, to: sweepDegrees / 360)
                        .stroke(Color.white.opacity(0.14), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(135))

                    // Fill: how far the value has turned.
                    Circle()
                        .trim(from: 0, to: (sweepDegrees / 360) * value)
                        .stroke(accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(135))

                    Circle()
                        .fill(Color.white.opacity(isDragging ? 0.14 : 0.07))
                        .padding(7)

                    // Pointer dot at the current angle. 225° is the top-of-gap reference in
                    // the same native-angle convention as the trim above (135°); both were
                    // derived to agree at the gap's two ends.
                    Circle()
                        .fill(accent)
                        .frame(width: 5, height: 5)
                        .offset(y: -(size / 2 - 7))
                        .rotationEffect(.degrees(225 + sweepDegrees * value))
                }
                .frame(width: size, height: size)
                .contentShape(Circle())
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
                // A real knob doesn't jump to wherever your finger's raw angle-from-center
                // happens to be — on a 52pt control that made tiny, barely-intentional
                // finger movements near the center swing the value wildly ("hektisch",
                // reported directly). Instead: track vertical drag distance as a delta on
                // top of the value the knob already had when the touch started, the same
                // jog-wheel feel iOS's own volume/brightness sliders use. Slow, predictable,
                // and still draws at the correct angle above since that only reads `value`.
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { drag in
                            isDragging = true
                            if dragStartValue == nil { dragStartValue = value }
                            let travelPoints: CGFloat = 150 // full 0...1 sweep over this much vertical drag
                            let delta = Double(-drag.translation.height / travelPoints)
                            value = min(max(0, (dragStartValue ?? value) + delta), 1)
                        }
                        .onEnded { _ in
                            isDragging = false
                            dragStartValue = nil
                        }
                )
            }
            .frame(width: size, height: size)

            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text("\(Int(value * 100))%").font(.caption2.monospacedDigit()).foregroundStyle(.primary)
        }
    }
}
