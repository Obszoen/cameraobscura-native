import SwiftUI

/// Placeholder confirmation screen. The real plan here is Sign in with Apple — but that
/// needs the com.apple.developer.applesignin entitlement, which a free/personal-team
/// signing tier cannot get issued at all. Requesting it doesn't just break the button,
/// it silently fails the entire app install on-device with no error anywhere in the
/// transfer log (found the hard way). Swap this for the real AccountGateView (kept in
/// git history) once this project moves to a paid Apple Developer Program account.
/// Redesigned after direct, repeated feedback ("gefällt mir noch garnicht... künstlerischer,
/// mit Komplementärfarben spielen") — the old version was a generic SF Symbol on a flat
/// pink field with a plain black button, sharing nothing with the rest of the app's now-
/// established brand language. This reuses the same `CameraMark` geometry as the icon and
/// splash (so it reads as the same object, not a different logo), and leans into genuine
/// complementary contrast — Brand.rose and Brand.mint sit close to opposite each other on
/// the color wheel, so instead of one flat color this plays them against each other as two
/// glows from opposite corners of a near-black ground. Uses the "SplashMark" asset (the
/// actual app icon artwork), not a redrawn shape — same reasoning as SplashView: a hand-
/// rebuilt copy risks a subtly-off version no one would catch until it's already shipped.
/// Researched onboarding practice
/// (industry consensus: get to real value fast, one clear screen beats a multi-step tour a
/// user just taps through) rather than assumed — this stays a single screen, one action.
struct AccountGateView: View {
    let onVerified: () -> Void
    @State private var appeared = false

    var body: some View {
        ZStack {
            Brand.ground.ignoresSafeArea()

            // Two glows from opposite corners — genuine complementary contrast, not a
            // single-hue wash.
            Circle()
                .fill(RadialGradient(colors: [Brand.rose.opacity(0.4), .clear], center: .center, startRadius: 0, endRadius: 260))
                .frame(width: 480, height: 480)
                .position(x: 40, y: 60)
                .blur(radius: 10)
            Circle()
                .fill(RadialGradient(colors: [Brand.mint.opacity(0.32), .clear], center: .center, startRadius: 0, endRadius: 260))
                .frame(width: 480, height: 480)
                .position(x: 350, y: 720)
                .blur(radius: 10)

            VStack(spacing: 28) {
                Spacer()

                Image("SplashMark")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 132, height: 132)
                    .clipShape(RoundedRectangle(cornerRadius: 28))
                    .shadow(color: .black.opacity(0.4), radius: 20, y: 10)

                VStack(spacing: 10) {
                    Text("CameraObscura")
                        .font(.system(size: 34, weight: .medium, design: .serif))
                        .italic()
                        .foregroundStyle(Brand.paper)
                    Text("Optiken, die dein iPhone nicht eingebaut hat.")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(Brand.paper.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 48)
                }

                Spacer()

                Button {
                    UserDefaults.standard.set(true, forKey: "accountVerified")
                    onVerified()
                } label: {
                    Text("Los geht's")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Brand.rose)
                        .foregroundStyle(Brand.ground)
                        .clipShape(Capsule())
                        .shadow(color: Brand.rose.opacity(0.4), radius: 16, y: 6)
                }
                .padding(.horizontal, 36)
                Spacer().frame(height: 28)
            }
            .scaleEffect(appeared ? 1 : 0.94)
            .opacity(appeared ? 1 : 0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) { appeared = true }
        }
    }
}
