import SwiftUI

/// Branded intro shown for ~1.6s after the (necessarily static) system launch screen.
/// Dark ground, a simple gentle fade/scale-in on the camera mark — no drifting stripe
/// animation, no social handle overlay. The feedback channel lives in ContentView's
/// FeedbackBox, where it belongs, not stamped across the first thing people see.
struct SplashView: View {
    @State private var appeared = false
    let onFinished: () -> Void

    private let ground = Color(red: 0x13 / 255, green: 0x11 / 255, blue: 0x13 / 255)
    private let bodyColor = Color(red: 0xF5 / 255, green: 0xF1 / 255, blue: 0xEC / 255)
    private let accent = Color(red: 0x4C / 255, green: 0x7E / 255, blue: 0xFF / 255)

    var body: some View {
        ZStack {
            ground.ignoresSafeArea()
            VStack(spacing: 26) {
                CameraMark(bodyColor: bodyColor, accent: accent, ground: ground)
                    .frame(width: 132, height: 132)
                Text("CameraObscura")
                    .font(.system(size: 32, weight: .medium, design: .serif))
                    .italic()
                    .foregroundStyle(bodyColor)
            }
            .scaleEffect(appeared ? 1 : 0.92)
            .opacity(appeared ? 1 : 0)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) { appeared = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { onFinished() }
        }
    }
}

/// The brand mark: a camera body with a big lens deliberately breaking the top edge —
/// the "even a single-lens phone gets a big wide lens now" idea in one shape. Same
/// composition (and the same 1024-unit coordinate space) as the app icon artwork so the
/// two always read as the same brand.
struct CameraMark: View {
    let bodyColor: Color
    let accent: Color
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
                    .stroke(accent, lineWidth: 14 * s)
                    .frame(width: 460 * s, height: 460 * s)
                    .position(x: 512 * s, y: 440 * s)
                Circle()
                    .stroke(accent.opacity(0.55), lineWidth: 10 * s)
                    .frame(width: 336 * s, height: 336 * s)
                    .position(x: 512 * s, y: 440 * s)
                Circle()
                    .fill(accent)
                    .frame(width: 236 * s, height: 236 * s)
                    .position(x: 512 * s, y: 440 * s)
                Circle()
                    .fill(bodyColor.opacity(0.85))
                    .frame(width: 48 * s, height: 48 * s)
                    .position(x: 466 * s, y: 394 * s)
            }
        }
    }
}
