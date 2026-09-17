import SwiftUI

/// The adjustments sheet as a hardware instrument faceplate instead of a plain iOS sheet —
/// the whole point of the RotaryKnob rework: a knob alone still sits on a "Baukasten" white
/// sheet and looks like a mockup. Dark brushed panel, embossed edge, corner screws, printed
/// section legends. Modeled after synth control surfaces (Korg) and older cameras' metal
/// control plates — used-pro-gear character, kept precise rather than grungy.
struct FaceplateBackground: View {
    /// User-adjustable (Einstellungen → Transparenz) — asked for directly, so the panel can
    /// go from a solid instrument face to see-through-enough that the viewfinder stays
    /// legible behind it while dialing something in. Only fades the backing panel itself;
    /// applied as a `.background()`, so it never touches the controls drawn on top of it.
    var opacity: Double = 1.0

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.10, green: 0.105, blue: 0.115), Color(red: 0.055, green: 0.058, blue: 0.065)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )

            // Brushed-metal grain: many thin, faint lines at a shallow diagonal — a cheap,
            // deterministic stand-in for a real anisotropic material, but reads correctly
            // at UI scale and costs nothing to redraw.
            Canvas { context, size in
                let spacing: CGFloat = 2.5
                var x: CGFloat = -size.height
                var i = 0
                while x < size.width {
                    let opacity = 0.02 + 0.015 * abs(sin(Double(i) * 0.7))
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x + size.height * 0.35, y: size.height))
                    context.stroke(path, with: .color(.white.opacity(opacity)), lineWidth: 1)
                    x += spacing
                    i += 1
                }
            }
            .blendMode(.plusLighter)

            // Vignette so the panel reads as lit from above, not a flat fill.
            RadialGradient(colors: [.clear, .black.opacity(0.35)], center: .center, startRadius: 180, endRadius: 420)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 0)
                .strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.18), .black.opacity(0.4)], startPoint: .top, endPoint: .bottom),
                    lineWidth: 1
                )
        )
        .overlay(alignment: .topLeading) { PanelScrew().padding(10) }
        .overlay(alignment: .topTrailing) { PanelScrew().padding(10) }
        .opacity(opacity)
        // Deliberately NOT `.ignoresSafeArea()` here anymore: this view is now used as the
        // background of a panel whose own size/position (full-bleed on one edge, floating
        // on the others) is decided by whoever places it — ContentView's adjustmentsPanel
        // applies safe-area-ignoring itself, only for the edges where it's actually wanted.
    }
}

/// A small flush screw head — the detail that sells "this is a physical panel", not a color.
private struct PanelScrew: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Color(white: 0.35), Color(white: 0.08)], center: .topLeading, startRadius: 0, endRadius: 7))
            Circle().stroke(.black.opacity(0.6), lineWidth: 0.5)
            Rectangle()
                .fill(.black.opacity(0.55))
                .frame(width: 6, height: 1)
                .rotationEffect(.degrees(28))
        }
        .frame(width: 9, height: 9)
    }
}

/// Printed section legend, like the silkscreened group labels on a real control surface.
struct PanelLegend: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .tracking(2.0)
            .textCase(.uppercase)
            .foregroundStyle(Brand.paper.opacity(0.55))
    }
}

/// A thin embossed groove — light edge over dark edge — used to separate panel sections
/// instead of a plain system Divider, which reads flat against the brushed background.
struct PanelGroove: View {
    var body: some View {
        VStack(spacing: 1) {
            Rectangle().fill(.black.opacity(0.5)).frame(height: 1)
            Rectangle().fill(.white.opacity(0.06)).frame(height: 1)
        }
    }
}

/// A row of engraved calibration ticks, like the printed scale along the edge of a real
/// mixer or camera control plate — asked for directly to run through the whole faceplate,
/// not just the zoom fader. Purely decorative (no values attached), which is the point:
/// it's the same "this is a measured instrument" cue real gear uses on the panel itself,
/// independent of any one control.
struct PanelTicks: View {
    var count: Int = 28
    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { i in
                Rectangle()
                    .fill(.white.opacity(i % 4 == 0 ? 0.22 : 0.09))
                    .frame(width: 1, height: i % 4 == 0 ? 6 : 3)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 6)
    }
}

/// A small status LED with a soft glow, replacing a plain colored capsule label — the same
/// language a real device uses for "saved"/"error" instead of a system-style toast.
struct PanelLED: View {
    let isOn: Bool
    var color: Color = Brand.mint
    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
            .shadow(color: color.opacity(isOn ? 0.9 : 0), radius: isOn ? 5 : 0)
            .opacity(isOn ? 1 : 0.25)
    }
}
