import SwiftUI

/// Branded intro shown for ~1.8s after the (necessarily static) system launch screen.
/// A soft bloom-in on the camera mark plus a slow ambient pulse behind it — a small,
/// tasteful bit of motion instead of either a flat static logo or the old drifting
/// rainbow-stripe animation. No social handle overlay: the feedback channel lives in
/// ContentView's FeedbackBox, where it belongs.
struct SplashView: View {
    @State private var appeared = false
    @State private var pulsing = false
    let onFinished: () -> Void

    var body: some View {
        ZStack {
            Brand.ground.ignoresSafeArea()

            // Ambient glow pulse behind the mark, in the same accents as the mark itself.
            Circle()
                .fill(
                    RadialGradient(colors: [Brand.rose.opacity(0.35), .clear],
                                   center: .center, startRadius: 0, endRadius: 220)
                )
                .frame(width: 440, height: 440)
                .scaleEffect(pulsing ? 1.08 : 0.92)
                .opacity(appeared ? 1 : 0)

            VStack(spacing: 26) {
                CameraMark(bodyColor: Brand.paper, ground: Brand.ground)
                    .frame(width: 132, height: 132)
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

/// The brand mark: a camera body with a big lens deliberately breaking the top edge —
/// the "even a single-lens phone gets a big wide lens now" idea in one shape. Rose outer
/// ring and glass, mint inner ring, sky-blue glint — the three brand accents in one mark.
/// Same composition (and the same 1024-unit coordinate space) as the app icon artwork so
/// the two always read as the same brand.
struct CameraMark: View {
    let bodyColor: Color
    let ground: Color

    var body: some View {
        GeometryReader { geo in
            let s = geo.size.width / 1024
            ZStack {
                RoundedRectangle(cornerRadius: 18 * s)
                    .fill(bodyColor)
                    .frame(width: 150 * s, height: 76 * s)
                    .position(x: 285 * s, y: 322 * s)
                RoundedRectangle(cornerRadius: 64 * s)
                    .fill(bodyColor)
                    .frame(width: 744 * s, height: 390 * s)
                    .position(x: 512 * s, y: 545 * s)
                Circle()
                    .fill(ground)
                    .frame(width: 460 * s, height: 460 * s)
                    .position(x: 512 * s, y: 440 * s)
                Circle()
                    .stroke(Brand.rose, lineWidth: 14 * s)
                    .frame(width: 460 * s, height: 460 * s)
                    .position(x: 512 * s, y: 440 * s)
                Circle()
                    .stroke(Brand.mint.opacity(0.7), lineWidth: 10 * s)
                    .frame(width: 336 * s, height: 336 * s)
                    .position(x: 512 * s, y: 440 * s)
                Circle()
                    .fill(Brand.rose)
                    .frame(width: 236 * s, height: 236 * s)
                    .position(x: 512 * s, y: 440 * s)
                Circle()
                    .fill(Brand.skyBlue)
                    .frame(width: 48 * s, height: 48 * s)
                    .position(x: 466 * s, y: 394 * s)
            }
        }
    }
}
