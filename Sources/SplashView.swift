import SwiftUI

/// The branded 5-second intro, exact timeline as specified: a person's reflection sits in
/// the lens for 1.5s, then the shutter fires and the aperture goes through a real
/// mechanical close-hold-reopen — an actual Blender-rendered clip
/// (`Resources/aperture.mp4`, see `render_aperture.py` in the session scratch history), not
/// a vector approximation. Third geometry attempt on that render, each of the first two
/// diagnosed and fixed rather than blindly retried (double-offset mesh construction on the
/// first; a rotation pivot that coincided with the tip vertex — provably unable to move —
/// on the second); this one uses simple wedges with the tip fixed exactly at the world
/// origin by construction and scale-animates them open/closed, which has no equivalent
/// failure mode. Flattened onto Brand.ground during render (not a real alpha channel), so
/// it composites as a plain rectangle — same background color as the splash itself.
///
/// The "reflection" is necessarily abstract (a soft humanoid silhouette, not a real camera
/// feed — nothing is actually being captured yet at this point in the app) but reads
/// correctly as "someone looking into the lens" at a glance, which is the actual effect
/// asked for.
struct SplashView: View {
    let onFinished: () -> Void

    @State private var silhouetteOpacity: Double = 0
    @State private var breathe = false
    @State private var playAperture = false
    @State private var flashOpacity: Double = 0
    @State private var gradientProgress: Double = 0
    @State private var iconAppear: Double = 0

    var body: some View {
        ZStack {
            Brand.ground.ignoresSafeArea()

            // Complementary sweep (rose -> mint -> sky blue -> warm ochre-white), asked for
            // directly, driving through the palette as the aperture reopens rather than
            // sitting static.
            AngularGradient(
                colors: [Brand.rose, Brand.mint, Brand.skyBlue, Color(red: 0.94, green: 0.88, blue: 0.74), Brand.rose],
                center: .center, angle: .degrees(gradientProgress * 140)
            )
            .opacity(0.30 + gradientProgress * 0.25)
            .blendMode(.plusLighter)
            .mask(Circle().frame(width: 300, height: 300))

            ZStack {
                // The reflection — abstract, deliberately soft, gone the instant the
                // shutter fires (0.0-1.5s only). Sits behind the aperture video so the
                // video's own rendered lens face naturally covers it once playback starts.
                SilhouetteShape()
                    .fill(LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0.05)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 120, height: 170)
                    .offset(y: breathe ? -3 : 3)
                    .blur(radius: 3)
                    .opacity(silhouetteOpacity)

                ApertureVideoView(trigger: playAperture)
                    .frame(width: 240, height: 240)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(.white.opacity(0.12), lineWidth: 2))

                Circle()
                    .fill(.white)
                    .frame(width: 260, height: 260)
                    .opacity(flashOpacity)
                    .blendMode(.plusLighter)
            }

            VStack(spacing: 22) {
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
            .scaleEffect(0.85 + iconAppear * 0.15)
            .opacity(iconAppear)
        }
        .onAppear { runTimeline() }
    }

    /// 1.5s reflection, then the rendered aperture clip (44 frames / 30fps ≈ 1.47s: closes
    /// fast, holds, reopens) plays once, then icon reveal fills the rest — sums to 5.0s.
    private func runTimeline() {
        withAnimation(.easeOut(duration: 0.3)) { silhouetteOpacity = 1 }
        withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) { breathe = true }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.linear(duration: 0.1)) { silhouetteOpacity = 0 }
            withAnimation(.easeOut(duration: 0.08)) { flashOpacity = 0.7 }
            withAnimation(.easeIn(duration: 0.25).delay(0.08)) { flashOpacity = 0 }
            playAperture = true
            withAnimation(.easeInOut(duration: 1.47)) { gradientProgress = 1 }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.97) {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.75)) { iconAppear = 1 }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { onFinished() }
    }
}

/// A soft, deliberately abstract head-and-shoulders silhouette — reads as "a person looking
/// into the lens" without needing (or pretending to have) a real camera feed at this point.
private struct SilhouetteShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let headRadius = rect.width * 0.28
        let headCenter = CGPoint(x: rect.midX, y: rect.minY + headRadius * 1.1)
        path.addEllipse(in: CGRect(x: headCenter.x - headRadius, y: headCenter.y - headRadius,
                                    width: headRadius * 2, height: headRadius * 2))
        path.move(to: CGPoint(x: rect.midX, y: headCenter.y + headRadius * 0.6))
        path.addCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY),
            control1: CGPoint(x: rect.midX - rect.width * 0.1, y: headCenter.y + headRadius),
            control2: CGPoint(x: rect.minX - rect.width * 0.1, y: rect.maxY - rect.height * 0.15)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addCurve(
            to: CGPoint(x: rect.midX, y: headCenter.y + headRadius * 0.6),
            control1: CGPoint(x: rect.maxX + rect.width * 0.1, y: rect.maxY - rect.height * 0.15),
            control2: CGPoint(x: rect.midX + rect.width * 0.1, y: headCenter.y + headRadius)
        )
        return path
    }
}
