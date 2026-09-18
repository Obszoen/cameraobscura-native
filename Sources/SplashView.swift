import SwiftUI

/// The branded 5-second intro, exact timeline as specified: a person's reflection sits in
/// the lens for 1.5s, then the shutter fires (blades snap shut fast), then a slow graceful
/// reopen sweeps through the brand's complementary palette and lands on the app icon at
/// t=5.0s.
///
/// Built natively in SwiftUI rather than as a pre-rendered Blender video — after tonight's
/// rocker-switch render came out unconvincing twice in a row (material/geometry issues that
/// needed real iteration to debug blind), a hand-tuned vector choreography here is the
/// reliable path to something that actually looks finished tonight, not a gamble on a third
/// render. The aperture blades are a stylized pinwheel-sweep, not a photometrically exact
/// iris — real depth/lighting/shading polish on an actual 3D-rendered version is exactly
/// the kind of follow-up work handed off separately (see the Codex brief in PROJECT.md).
///
/// The "reflection" is necessarily abstract (a soft humanoid silhouette, not a real camera
/// feed — nothing is actually being captured yet at this point in the app) but reads
/// correctly as "someone looking into the lens" at a glance, which is the actual effect
/// asked for.
struct SplashView: View {
    let onFinished: () -> Void

    @State private var silhouetteOpacity: Double = 0
    @State private var breathe = false
    @State private var bladeOpenness: Double = 1   // 1 = open/retracted, 0 = fully shut
    @State private var flashOpacity: Double = 0
    @State private var gradientProgress: Double = 0
    @State private var iconAppear: Double = 0

    private let bladeCount = 7

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
                // The lens: a dark glass disc with a faint rim highlight.
                Circle()
                    .fill(RadialGradient(colors: [Color(white: 0.14), Brand.ground], center: .center, startRadius: 0, endRadius: 150))
                    .overlay(Circle().stroke(.white.opacity(0.12), lineWidth: 2))
                    .frame(width: 240, height: 240)

                // The reflection — abstract, deliberately soft, gone the instant the
                // shutter fires (0.0-1.5s only).
                SilhouetteShape()
                    .fill(LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0.05)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 120, height: 170)
                    .offset(y: breathe ? -3 : 3)
                    .blur(radius: 3)
                    .opacity(silhouetteOpacity)

                // Aperture blades — closed = fully covers the lens (the shutter-fired
                // instant), open = retracted to a thin ring at the very edge.
                ForEach(0..<bladeCount, id: \.self) { i in
                    ApertureBlade(bladeCount: bladeCount, index: i, openness: bladeOpenness)
                        .fill(Brand.ground)
                }
                .frame(width: 240, height: 240)
                .clipShape(Circle())

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

    /// Every duration below sums to exactly 5.0s: 1.5s reflection, ~0.15s shutter-fire,
    /// ~2.6s graceful reopen (gradient sweeping the whole time), ~0.75s icon reveal.
    private func runTimeline() {
        withAnimation(.easeOut(duration: 0.3)) { silhouetteOpacity = 1 }
        withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) { breathe = true }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.linear(duration: 0.1)) { silhouetteOpacity = 0 }
            withAnimation(.easeIn(duration: 0.15)) { bladeOpenness = 0 }
            withAnimation(.easeOut(duration: 0.08).delay(0.1)) { flashOpacity = 0.7 }
            withAnimation(.easeIn(duration: 0.25).delay(0.15)) { flashOpacity = 0 }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.65) {
            withAnimation(.easeInOut(duration: 2.6)) {
                bladeOpenness = 1
                gradientProgress = 1
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 4.25) {
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

/// One aperture blade — a triangular wedge that sweeps from covering the whole lens
/// (`openness` 0) to retracted near its own outer edge (`openness` 1). `animatableData`
/// makes `openness` interpolate smoothly under `withAnimation`, exactly like any other
/// SwiftUI-animatable property.
private struct ApertureBlade: Shape {
    let bladeCount: Int
    let index: Int
    var openness: Double

    var animatableData: Double {
        get { openness }
        set { openness = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        // Exactly half the frame, not further — a Shape's fill isn't automatically clipped
        // to its own layout frame, so anything bigger would visibly overflow the lens circle.
        let radius = min(rect.width, rect.height) * 0.5
        let angleStep = 2 * Double.pi / Double(bladeCount)
        let baseAngle = angleStep * Double(index)
        let innerReach = radius * (1 - max(0, min(openness, 1)))
        let p1 = CGPoint(x: center.x + radius * cos(baseAngle), y: center.y + radius * sin(baseAngle))
        let p2 = CGPoint(x: center.x + radius * cos(baseAngle + angleStep), y: center.y + radius * sin(baseAngle + angleStep))
        let tip = CGPoint(x: center.x + innerReach * cos(baseAngle + angleStep / 2),
                           y: center.y + innerReach * sin(baseAngle + angleStep / 2))
        var path = Path()
        path.move(to: p1)
        path.addLine(to: tip)
        path.addLine(to: p2)
        path.addLine(to: p1)
        return path
    }
}
