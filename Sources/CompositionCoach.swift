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
    static func hint(for box: CGRect, mode: CameraModel.CoachMode) -> String {
        let headroom = 1 - box.maxY
        let height = box.height

        if height < 0.22 {
            return mode == .photographerMoves ? "Näher rangehen" : "Bitte näher zur Kamera kommen"
        }
        if height > 0.88 {
            return mode == .photographerMoves ? "Etwas zurücktreten" : "Bitte einen Schritt zurück"
        }
        if headroom > 0.28 {
            return mode == .photographerMoves ? "Kamera senken – zu viel Luft über dem Kopf" : "Kamera wird gesenkt, bitte kurz warten"
        }
        if headroom < 0.02 {
            return mode == .photographerMoves ? "Kamera leicht anheben" : "Kamera wird angehoben, bitte kurz warten"
        }

        guard let offset = horizontalOffset(for: box) else {
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
    static func target(for box: CGRect) -> CGPoint? {
        guard let offset = horizontalOffset(for: box) else { return nil }
        let targetX = box.midX - offset
        return CGPoint(x: targetX, y: box.midY)
    }

    /// Positive = subject is to the right of their nearest rule-of-thirds line; nil once
    /// within tolerance (nothing left to nudge).
    private static func horizontalOffset(for box: CGRect) -> CGFloat? {
        let centerX = box.midX
        let target: CGFloat = centerX < 0.5 ? (1.0 / 3.0) : (2.0 / 3.0)
        let offset = centerX - target
        return abs(offset) > 0.09 ? offset : nil
    }
}
