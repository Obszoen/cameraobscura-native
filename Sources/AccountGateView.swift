import SwiftUI
import AuthenticationServices

/// "Account verification" without running any server of our own: Sign in with Apple is
/// a real, native identity check Apple performs on-device — no backend, no password
/// database for us to store or leak, and it only ever has to happen once per install.
struct AccountGateView: View {
    let onVerified: () -> Void
    @State private var errorText: String?

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            Image(systemName: "camera.aperture")
                .font(.system(size: 54))
                .foregroundStyle(.pink)
            Text("CameraObscura")
                .font(.system(size: 26, weight: .heavy, design: .rounded))
            Text("Kurz bestätigen, dass du es bist — einmalig, ohne Passwort, ohne dass wir irgendetwas davon auf einem Server speichern.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
            Spacer()

            SignInWithAppleButton(.continue, onRequest: { request in
                request.requestedScopes = []
            }, onCompletion: { result in
                switch result {
                case .success:
                    UserDefaults.standard.set(true, forKey: "accountVerified")
                    onVerified()
                case .failure(let error):
                    errorText = "Bestätigung fehlgeschlagen: \(error.localizedDescription)"
                }
            })
            .signInWithAppleButtonStyle(.black)
            .frame(height: 50)
            .padding(.horizontal, 32)

            if let errorText {
                Text(errorText).font(.caption).foregroundStyle(.red).padding(.horizontal, 32)
            }
            Spacer().frame(height: 24)
        }
        .background(Color(red: 0.98, green: 0.85, blue: 0.90).ignoresSafeArea())
    }
}
