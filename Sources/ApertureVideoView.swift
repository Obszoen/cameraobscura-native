import SwiftUI
import AVFoundation

/// Plays the Blender-rendered aperture iris clip (`aperture.mp4`, bundled — see
/// `render_aperture.py` in the session scratch history for the generating script) once,
/// starting when `trigger` flips true. Flattened onto Brand.ground during rendering (not a
/// real alpha channel — HEVC-with-alpha adds real complexity for one short clip), so it
/// composites as a plain rectangle over the splash background, which is the same color.
struct ApertureVideoView: UIViewRepresentable {
    var trigger: Bool

    func makeUIView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        guard let url = Bundle.main.url(forResource: "aperture", withExtension: "mp4") else { return view }
        let player = AVPlayer(url: url)
        player.actionAtItemEnd = .pause
        view.playerLayer.player = player
        context.coordinator.player = player
        return view
    }

    func updateUIView(_ uiView: PlayerContainerView, context: Context) {
        if trigger, !context.coordinator.hasPlayed {
            context.coordinator.hasPlayed = true
            context.coordinator.player?.seek(to: .zero)
            context.coordinator.player?.play()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var player: AVPlayer?
        var hasPlayed = false
    }

    final class PlayerContainerView: UIView {
        let playerLayer = AVPlayerLayer()
        override init(frame: CGRect) {
            super.init(frame: frame)
            playerLayer.videoGravity = .resizeAspectFill
            layer.addSublayer(playerLayer)
        }
        required init?(coder: NSCoder) { fatalError() }
        override func layoutSubviews() {
            super.layoutSubviews()
            playerLayer.frame = bounds
        }
    }
}
