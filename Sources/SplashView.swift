import SwiftUI

/// Branded intro shown for ~1.8s after the (necessarily static) system launch screen.
/// A soft bloom-in on the camera mark plus a slow ambient pulse behind it — a small,
/// tasteful bit of motion instead of either a flat static logo or the old drifting
/// rainbow-stripe animation. No social handle overlay: the feedback channel lives in
/// ContentView's FeedbackBox, where it belongs.
///
/// The mark itself is "SplashMark" in the asset catalog — a copy of the actual app icon
/// artwork (same file, verified by rendering it before it was chosen), not a hand-redrawn
/// SwiftUI approximation. Redrawing it in SwiftUI shapes risked a subtly-off copy no one
/// would catch until it was already on screen, since that kind of view can't be rendered
/// and inspected the way the icon's own SVG mockup was before picking it.
struct SplashView: View {
    @State private var appeared = false
    @State private var pulsing = false
    let onFinished: () -> Void

    var body: some View {
        ZStack {
            Brand.ground.ignoresSafeArea()

            // Genuine complementary contrast (rose vs. mint, not one flat hue) — asked for
            // directly ("künstlerischer, mit Komplementärfarben spielen"), same pairing as
            // AccountGateView so the two screens read as one designed sequence.
            Circle()
                .fill(RadialGradient(colors: [Brand.rose.opacity(0.35), .clear], center: .center, startRadius: 0, endRadius: 220))
                .frame(width: 440, height: 440)
                .offset(x: -60, y: -40)
                .scaleEffect(pulsing ? 1.08 : 0.92)
                .opacity(appeared ? 1 : 0)
            Circle()
                .fill(RadialGradient(colors: [Brand.mint.opacity(0.28), .clear], center: .center, startRadius: 0, endRadius: 220))
                .frame(width: 440, height: 440)
                .offset(x: 60, y: 40)
                .scaleEffect(pulsing ? 0.92 : 1.08)
                .opacity(appeared ? 1 : 0)

            VStack(spacing: 26) {
                Image("SplashMark")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 132, height: 132)
                    .clipShape(RoundedRectangle(cornerRadius: 28))
                Text("CameraObscura")
                    .font(.system(size: 32, weight: .medium, design: .serif))
                    .italic()
                    .foregroundStyle(Brand.paper)
            }
            .scaleEffect(appeared ? 1 : 0.85)
            .opacity(appeared ? 1 : 0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.7)) { appeared = true }
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true).delay(0.3)) {
                pulsing = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { onFinished() }
        }
    }
}
