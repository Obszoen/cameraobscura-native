import CoreGraphics

/// Turns detected people's bounding boxes into plain-language framing nudges and target
/// points for the crosshair overlay(s) — the "tell a layperson how to stand for a great
/// photo" idea: real geometry (golden ratio, headroom, distance-from-frame-fill, group
/// arrangement), grounded in documented composition principles used across editorial/
/// fashion, selfie and landscape photography — not literal per-photographer parameters
/// (no such dataset exists publicly; this is technique, not proprietary data).
///
/// `box` is Vision's boundingBox convention throughout: normalized 0...1, origin
/// bottom-left. This enum doesn't care where it came from, only that it's already in the
/// same up-and-mirrored orientation the person visibly appears in — see CameraModel's
/// composition analysis for why that's true for the buffer it's fed.
enum CompositionCoach {
    /// One hint per box, same order as `boxes`. With more than one person, camera-panning
    /// guidance stops making sense (the camera can't reposition two different people
    /// independently) — hints always address the individual subject directly once there's
    /// more than one, regardless of `mode`.
    static func hints(for boxes: [CGRect], mode: CameraModel.CoachMode, style: CameraModel.CompositionStyle,
                       distancesMeters: [Double?]) -> [String] {
        guard !boxes.isEmpty else { return [] }
        if boxes.count == 1 {
            return [hint(for: boxes[0], mode: mode, style: style, distanceMeters: distancesMeters.first ?? nil)]
        }

        // Group arrangement: assign each person (by their current left-to-right rank) a
        // target x position from a layout template. Two people balance across the two
        // rule-of-thirds lines; three form the classic golden triangle; beyond that, an
        // even staggered spread — all standard group-portrait composition, not a guess.
        let targets = groupTargetPositions(count: boxes.count)
        let order = boxes.indices.sorted { boxes[$0].midX < boxes[$1].midX }
        var result = [String](repeating: "", count: boxes.count)
        for (rank, index) in order.enumerated() {
            let box = boxes[index]
            let target = targets[rank]
            let offset = box.midX - target
            let label = "Person \(index + 1)"
            if abs(offset) < 0.05 {
                result[index] = "\(label): Position sitzt ✓"
            } else {
                result[index] = offset > 0 ? "\(label): einen Schritt nach links" : "\(label): einen Schritt nach rechts"
            }
        }
        return result
    }

    /// Target x-positions (fraction of frame width, left to right) for a group of `count`
    /// people. 1-2: rule-of-thirds balance. 3: the golden triangle fashion/portrait
    /// photography uses for trios. 4+: even staggered spread — documented group-portrait
    /// principles, not a single-subject rule stretched to fit.
    static func groupTargetPositions(count: Int) -> [CGFloat] {
        switch count {
        case ...1: return [0.5]
        case 2: return [1.0 / 3.0, 2.0 / 3.0]
        case 3: return [1.0 / 6.0, 0.5, 5.0 / 6.0]
        default: return (1...count).map { CGFloat($0) / CGFloat(count + 1) }
        }
    }

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

        // Comfortable framing distance range, tuned per style: selfies are shot at
        // arm's length, editorial/fashion tends tighter than a casual portrait, landscape
        // has no single subject distance to speak of (skipped below).
        let (idealMin, idealMax): (Double, Double) = {
            switch style {
            case .selfie: return (0.35, 0.7)
            case .fashion: return (1.0, 2.0)
            default: return (1.2, 2.4)
            }
        }()
        if style != .landscape, let distanceMeters {
            if distanceMeters < idealMin {
                let text = distanceLabel(idealMin - distanceMeters)
                return mode == .photographerMoves ? "\(text) zurücktreten" : "Bitte \(text) zurücktreten"
            }
            if distanceMeters > idealMax {
                let text = distanceLabel(distanceMeters - idealMax)
                return mode == .photographerMoves ? "\(text) näher rangehen" : "Bitte \(text) näher kommen"
            }
        } else if style != .landscape {
            if height < 0.22 {
                return mode == .photographerMoves ? "Näher rangehen" : "Bitte näher zur Kamera kommen"
            }
            if height > 0.88 {
                return mode == .photographerMoves ? "Etwas zurücktreten" : "Bitte einen Schritt zurück"
            }
        }

        // Headroom tolerance, tuned per style: editorial crops tighter (less headroom
        // tolerated at the top — the tight-crop look fashion editorial is known for),
        // selfies tolerate more (arm's-length framing rarely gets it razor-precise),
        // landscape deliberately keeps more sky/environment above a foreground subject.
        let (headroomMax, headroomMin): (Double, Double) = {
            switch style {
            case .fashion: return (0.18, 0.01)
            case .selfie: return (0.35, 0.0)
            case .landscape: return (0.45, 0.05)
            default: return (0.28, 0.02)
            }
        }()
        if headroom > headroomMax {
            return mode == .photographerMoves ? "Kamera senken – zu viel Luft über dem Kopf" : "Kamera wird gesenkt, bitte kurz warten"
        }
        if headroom < headroomMin {
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

    /// One target per box, same order — used by the overlay when more than one person is
    /// in frame, reusing the same group layout `hints(for:...)` assigns.
    static func targets(for boxes: [CGRect]) -> [CGPoint?] {
        guard boxes.count > 1 else { return boxes.map { CGPoint(x: $0.midX, y: $0.midY) } }
        let targetXs = groupTargetPositions(count: boxes.count)
        let order = boxes.indices.sorted { boxes[$0].midX < boxes[$1].midX }
        var result = [CGPoint?](repeating: nil, count: boxes.count)
        for (rank, index) in order.enumerated() {
            result[index] = CGPoint(x: targetXs[rank], y: boxes[index].midY)
        }
        return result
    }

    /// A distance delta in meters as a short German label — centimeters under a meter
    /// (people judge close-range distance that way), meters with one decimal beyond it.
    private static func distanceLabel(_ deltaMeters: Double) -> String {
        deltaMeters < 1 ? "\(Int((deltaMeters * 100).rounded()))cm" : String(format: "%.1fm", deltaMeters)
    }

    /// Positive = subject is to the right of their target line; nil once within tolerance
    /// (nothing left to nudge). The target line itself depends on `style`: the two
    /// rule-of-thirds lines, dead-center, or (fashion/landscape) the golden-ratio points
    /// (0.382/0.618) editorial and landscape work leans on more than strict thirds.
    private static func horizontalOffset(for box: CGRect, style: CameraModel.CompositionStyle) -> CGFloat? {
        let centerX = box.midX
        let target: CGFloat
        switch style {
        case .thirds, .selfie:
            target = centerX < 0.5 ? (1.0 / 3.0) : (2.0 / 3.0)
        case .centered:
            target = 0.5
        case .fashion, .landscape:
            target = centerX < 0.5 ? 0.382 : 0.618
        }
        let offset = centerX - target
        return abs(offset) > 0.09 ? offset : nil
    }
}
