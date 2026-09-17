import CoreGraphics

/// Turns a detected person's bounding box into one plain-language framing nudge and a
/// target point for the crosshair overlay — the "tell a layperson how to stand for a great
/// photo" idea: real geometry (rule of thirds, headroom, distance-from-frame-fill), not a
/// guess.
///
/// `box` is Vision's boundingBox convention throughout: normalized 0...1, origin
/// bottom-left. This enum doesn't care where it came from, only that it's already in the
/// same up-and-mirrored orientation the person visibly appears in — see CameraModel's
/// composition analysis for why that's true for the buffer it's fed.
enum CompositionCoach {
    /// Two audiences for the same geometry: a photographer repositions the camera (so a
    /// subject that reads "too far right" needs the camera panned right, moving the whole
    /// scene left in frame); a subject standing in for a remote/tripod shot repositions
    /// themselves instead (the opposite sense — they'd need to physically move left).
    /// - Parameter distanceMeters: real measured distance to the subject (from the depth
    ///   sensor — LiDAR, or iPhone Air's LiDAR-free ML depth pipeline, whichever the device
    ///   has), when available. Gives an exact, actionable callout ("40cm näher") instead of
    ///   the bounding-box-height guess — asked for directly, and a real accessibility win
    ///   for anyone who can't judge framing distance by eye alone. Falls back to the
    ///   heuristic below wherever depth isn't available (older devices, or before the first
    ///   depth frame arrives).
    static func hint(for box: CGRect, mode: CameraModel.CoachMode, style: CameraModel.CompositionStyle,
                      distanceMeters: Double? = nil) -> String {
        let headroom = 1 - box.maxY
        let height = box.height

        // Comfortable portrait framing range for a single subject — outside it, lead with
        // the precise distance callout rather than the cruder height-based guess.
        let idealMin = 1.2, idealMax = 2.4
        if let distanceMeters {
            if distanceMeters < idealMin {
                let text = distanceLabel(idealMin - distanceMeters)
                return mode == .photographerMoves ? "\(text) zurücktreten" : "Bitte \(text) zurücktreten"
            }
            if distanceMeters > idealMax {
                let text = distanceLabel(distanceMeters - idealMax)
                return mode == .photographerMoves ? "\(text) näher rangehen" : "Bitte \(text) näher kommen"
            }
        } else {
            if height < 0.22 {
                return mode == .photographerMoves ? "Näher rangehen" : "Bitte näher zur Kamera kommen"
            }
            if height > 0.88 {
                return mode == .photographerMoves ? "Etwas zurücktreten" : "Bitte einen Schritt zurück"
            }
        }
        if headroom > 0.28 {
            return mode == .photographerMoves ? "Kamera senken – zu viel Luft über dem Kopf" : "Kamera wird gesenkt, bitte kurz warten"
        }
        if headroom < 0.02 {
            return mode == .photographerMoves ? "Kamera leicht anheben" : "Kamera wird angehoben, bitte kurz warten"
        }

        guard let offset = horizontalOffset(for: box, style: style) else {
            return "Komposition sitzt ✓"
        }
        if mode == .photographerMoves {
            // Subject reads too far right in frame -> panning the camera itself to the
            // right moves the whole scene left in the image, correcting toward target.
            return offset > 0 ? "Kamera leicht nach rechts schwenken" : "Kamera leicht nach links schwenken"
        } else {
            // The subject repositions themselves directly, so the sense flips.
            return offset > 0 ? "Bitte einen Schritt nach links" : "Bitte einen Schritt nach rechts"
        }
    }

    /// The crosshair's target position, normalized 0...1 bottom-left — same convention as
    /// `box` — or nil once the subject is already close enough to it to stop nudging.
    static func target(for box: CGRect, style: CameraModel.CompositionStyle) -> CGPoint? {
        guard let offset = horizontalOffset(for: box, style: style) else { return nil }
        let targetX = box.midX - offset
        return CGPoint(x: targetX, y: box.midY)
    }

    /// A distance delta in meters as a short German label — centimeters under a meter
    /// (people judge close-range distance that way), meters with one decimal beyond it.
    private static func distanceLabel(_ deltaMeters: Double) -> String {
        deltaMeters < 1 ? "\(Int((deltaMeters * 100).rounded()))cm" : String(format: "%.1fm", deltaMeters)
    }

    /// Positive = subject is to the right of their target line; nil once within tolerance
    /// (nothing left to nudge). The target line itself depends on `style`: the two
    /// rule-of-thirds lines, or dead-center for a deliberately symmetric portrait.
    private static func horizontalOffset(for box: CGRect, style: CameraModel.CompositionStyle) -> CGFloat? {
        let centerX = box.midX
        let target: CGFloat
        switch style {
        case .thirds:
            target = centerX < 0.5 ? (1.0 / 3.0) : (2.0 / 3.0)
        case .centered:
            target = 0.5
        }
        let offset = centerX - target
        return abs(offset) > 0.09 ? offset : nil
    }
}
