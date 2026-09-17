import SwiftUI

/// Branded animated intro shown for ~2s after the (necessarily static) system launch
/// screen. Soft pink ground, mint + blue stripes drifting diagonally in both directions
/// for a floating, cozy-artsy feel — not a system launch screen (Apple doesn't allow those
/// to animate), just the first thing the app itself shows.
struct SplashView: View {
    @State private var drift = false
    let onFinished: () -> Void

    private let pink = Color(red: 0.98, green: 0.85, blue: 0.90)
    private let mint = Color(red: 0.65, green: 0.92, blue: 0.82)
    private let blue = Color(red: 0.68, green: 0.82, blue: 0.98)

    var body: some View {
        GeometryReader { geo in
            let d = max(geo.size.width, geo.size.height) * 1.6
            ZStack {
                pink.ignoresSafeArea()

                // Mint stripes drifting one way, blue stripes drifting the other —
                // opposing motion is what reads as "floating" rather than "sliding".
                StripeField(color: mint, stripeWidth: 26, spacing: 70, angle: 35)
                    .offset(x: drift ? d * 0.12 : -d * 0.12, y: drift ? -d * 0.08 : d * 0.08)
                    .opacity(0.55)
                StripeField(color: blue, stripeWidth: 20, spacing: 84, angle: -35)
                    .offset(x: drift ? -d * 0.10 : d * 0.10, y: drift ? d * 0.10 : -d * 0.10)
                    .opacity(0.5)

                VStack(spacing: 6) {
                    Text("CameraObscura")
                        .font(.system(size: 40, weight: .heavy, design: .rounded))
                        .foregroundStyle(.black)
                        .tracking(0.5)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                Link(destination: URL(string: "https://instagram.com/OBSZOEN_Official")!) {
                    Text("programmed by OBSZOEN_Official")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.black.opacity(0.55))
                }
                .padding(.trailing, 16)
                .padding(.bottom, 14)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 3.4).repeatForever(autoreverses: true)) {
                drift = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { onFinished() }
        }
    }
}

/// A field of diagonal stripes, big enough that rotating/offsetting it never shows an edge.
private struct StripeField: View {
    let color: Color
    let stripeWidth: CGFloat
    let spacing: CGFloat
    let angle: Double

    var body: some View {
        GeometryReader { geo in
            let d = max(geo.size.width, geo.size.height) * 2
            let count = Int(d / spacing) + 4
            ZStack {
                ForEach(0..<count, id: \.self) { i in
                    color
                        .frame(width: stripeWidth, height: d)
                        .offset(x: CGFloat(i) * spacing - d / 2)
                }
            }
            .frame(width: d, height: d)
            .rotationEffect(.degrees(angle))
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
    }
}
