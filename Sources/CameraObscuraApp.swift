import SwiftUI

@main
struct CameraObscuraApp: App {
    @State private var stage: Stage = .splash

    enum Stage { case splash, accountGate, main }

    var body: some Scene {
        WindowGroup {
            switch stage {
            case .splash:
                SplashView {
                    let alreadyVerified = UserDefaults.standard.bool(forKey: "accountVerified")
                    stage = alreadyVerified ? .main : .accountGate
                }
            case .accountGate:
                AccountGateView { stage = .main }
            case .main:
                ContentView()
                    .preferredColorScheme(.dark)
            }
        }
    }
}
