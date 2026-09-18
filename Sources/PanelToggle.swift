import SwiftUI
import UIKit

/// A real Blender-rendered rocker switch (SwitchOff/SwitchOn imagesets — same dark
/// anodized-metal material recipe and studio lighting as the knob cap, see
/// `render_switch2.py` in the session scratch history) instead of SwiftUI-drawn chrome.
/// Two earlier render attempts were discarded (one lost its material to a boolean-modifier
/// bug and rendered flat white, one didn't read clearly as on/off from its camera angle) —
/// this one rotates the paddle in the camera-facing plane (Z axis) rather than pitching it
/// toward/away from the camera, so the tilt is unambiguous under the same straight-down
/// orthographic camera that already worked for the knob.
struct PanelToggle: View {
    @EnvironmentObject var settings: AppSettings

    let title: String
    @Binding var isOn: Bool
    var accent: Color = Brand.mint

    var body: some View {
        Button {
            isOn.toggle()
            // Switches click audibly when flipped, encoders don't — asked for directly
            // ("wenn man an nem Encoder dreht soll kein Sound kommen... aber ein Switch
            // schon"). RotaryKnob/ZoomFader deliberately have no equivalent sound call.
            // Stronger than the encoders' feedback (asked for directly) — a switch flip
            // should feel like a definite physical event, not a soft tap.
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            if settings.soundEnabled { CameraSounds.toggleClick() }
        } label: {
            VStack(spacing: 5) {
                ZStack {
                    Image(isOn ? "SwitchOn" : "SwitchOff")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 40, height: 40)
                        .shadow(color: isOn ? accent.opacity(0.5) : .clear, radius: 6)
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isOn)

                Text(title)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(0.5)
                    .textCase(.uppercase)
                    .foregroundStyle(isOn ? accent : .secondary)
            }
        }
        .buttonStyle(.plain)
    }
}
