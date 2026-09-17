import SwiftUI

/// Placeholder confirmation screen. The real plan here is Sign in with Apple — but that
/// needs the com.apple.developer.applesignin entitlement, which a free/personal-team
/// signing tier cannot get issued at all. Requesting it doesn't just break the button,
/// it silently fails the entire app install on-device with no error anywhere in the
/// transfer log (found the hard way). Swap this for the real AccountGateView (kept in
/// git history) once this project moves to a paid Apple Developer Program account.
struct AccountGateView: View {
    let onVerified: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            Image(systemName: "camera.aperture")
                .font(.system(size: 54))
                .foregroundStyle(.pink)
            Text("CameraObscura")
                .font(.system(size: 26, weight: .heavy, design: .rounded))
            Text("Schön, dass du da bist.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
            Spacer()

            Button {
                UserDefaults.standard.set(true, forKey: "accountVerified")
                onVerified()
            } label: {
                Text("Los geht's")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.black)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 32)
            Spacer().frame(height: 24)
        }
        .background(Color(red: 0.98, green: 0.85, blue: 0.90).ignoresSafeArea())
    }
}
