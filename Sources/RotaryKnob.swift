import SwiftUI
import UIKit

/// A real rotary knob (270° sweep, gap at the bottom) instead of a horizontal slider —
/// asked for explicitly: sliders read as generic/cheap here, a knob reads as a considered
/// instrument control. Angle math verified numerically before writing this (top of the
/// knob = 0.5, the two ends of the gap = 0.0/1.0) rather than trusted on faith.
///
/// The cap itself is a Blender-rendered dark anodized-aluminum knob (see
/// `../../render_knob.py` in the project's scratch history for the generating script,
/// asset lives at `Assets.xcassets/RotaryKnobCap`) — a flat vector circle read as generic
/// "Baukasten" UI, reported directly. Rendered orthographic/straight-down specifically so
/// it can be freely rotated here in 2D without ever betraying a 3D perspective. The accent-
/// colored arc stays as a printed-scale/LED-ring cue behind the cap — real hardware
/// (synths, older cameras) commonly combines both around one physical knob.
struct RotaryKnob: View {
    let title: String
    @Binding var value: Double // 0...1
    var accent: Color = Brand.rose
    var size: CGFloat = 52
    /// Where a double-tap resets to — the knob's actual aesthetic "off"/default point, not
    /// always 0 (e.g. vignette/tone knobs default mid-scale). Lets someone get back to a
    /// sane starting point without hunting for it by eye or opening the sheet fully.
    var neutralValue: Double = 0.5

    /// The sweep is 270° with a 90° gap centered at the bottom, purely for how the value is
    /// drawn — see below for how it's actually set by touch.
    private let sweepDegrees: Double = 270

    @State private var isDragging = false
    // The value at the moment the current drag began, so `onChanged` can add a delta to it
    // rather than re-deriving an absolute value from the touch every callback.
    @State private var dragStartValue: Double?
    // Fires once per drag when a run hits 0% or 100%, not on every frame stuck at the end.
    @State private var endStopFired = false

    var body: some View {
        VStack(spacing: 5) {
            GeometryReader { geo in
                ZStack {
                    // Track: the full available travel, dim — reads as the panel's printed
                    // scale, sitting still while only the knob cap on top rotates.
                    Circle()
                        .trim(from: 0, to: sweepDegrees / 360)
                        .stroke(Color.white.opacity(0.14), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(135))

                    // Fill: how far the value has turned — the LED-ring cue real encoder
                    // knobs (Korg's included) pair with a printed scale.
                    Circle()
                        .trim(from: 0, to: (sweepDegrees / 360) * value)
                        .stroke(accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(135))
                        .shadow(color: accent.opacity(isDragging ? 0.7 : 0.35), radius: isDragging ? 4 : 2)

                    // The rendered metal cap, inset from the scale ring so both stay legible.
                    // 225° is the top-of-gap reference in the same native-angle convention as
                    // the track's 135° above; the cap's printed indicator points "up" in the
                    // source render, so this rotation alone places it correctly.
                    Image("RotaryKnobCap")
                        .resizable()
                        .scaledToFit()
                        .frame(width: size - 12, height: size - 12)
                        .rotationEffect(.degrees(225 + sweepDegrees * value))
                        .scaleEffect(isDragging ? 1.06 : 1.0)
                        .shadow(color: .black.opacity(0.5), radius: isDragging ? 5 : 3, y: 2)
                        .animation(.easeOut(duration: 0.12), value: isDragging)
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
                            let newValue = min(max(0, (dragStartValue ?? value) + delta), 1)
                            // A real knob's end-of-travel has a physical stop you feel, not
                            // just a value that stops changing — one buzz per arrival, not
                            // once per frame while pinned there.
                            if (newValue <= 0.001 || newValue >= 0.999), !endStopFired {
                                endStopFired = true
                                UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.6)
                            } else if newValue > 0.001, newValue < 0.999 {
                                endStopFired = false
                            }
                            value = newValue
                        }
                        .onEnded { _ in
                            isDragging = false
                            dragStartValue = nil
                            endStopFired = false
                        }
                )
                // `.simultaneousGesture`, not a second `.gesture()` — the drag above uses
                // minimumDistance 0 (it has to, for the jog-wheel feel), so a normal
                // `.onTapGesture` chained afterward would compete with it for the same
                // touch-down and likely never fire. Simultaneous recognition lets both live:
                // the drag still tracks every touch, and a clean double-tap-without-motion
                // is still detected on top of it.
                .simultaneousGesture(
                    TapGesture(count: 2).onEnded {
                        value = neutralValue
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                )
            }
            .frame(width: size, height: size)

            // Silkscreened-panel-legend look: small caps, letter-spaced, monospaced value —
            // the same printed-label language as the faceplate around it.
            Text(title)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(1.0)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            Text("\(Int(value * 100))")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.primary.opacity(0.85))
        }
    }
}
