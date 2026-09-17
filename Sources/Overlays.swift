import SwiftUI

/// Classic rule-of-thirds grid: two vertical + two horizontal lines, evenly spaced.
struct GridOverlay: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let xStep = rect.width / 3
        let yStep = rect.height / 3
        for i in 1...2 {
            let x = rect.minX + xStep * CGFloat(i)
            path.move(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: x, y: rect.maxY))
            let y = rect.minY + yStep * CGFloat(i)
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
        }
        return path
    }
}

/// Converts a Vision-normalized point (0...1, origin bottom-left, relative to the raw
/// capture buffer) into on-screen coordinates for a view of `viewSize` showing that buffer
/// "fill"-cropped (matching MetalPreviewView's own scale-to-fill math exactly) — without
/// this, the crosshair would sit wherever the UNCROPPED buffer would have put it, visibly
/// offset from the person actually on screen.
func compositionScreenPoint(normalized: CGPoint, bufferSize: CGSize, viewSize: CGSize) -> CGPoint? {
    guard bufferSize.width > 0, bufferSize.height > 0 else { return nil }
    let scale = max(viewSize.width / bufferSize.width, viewSize.height / bufferSize.height)
    let scaledWidth = bufferSize.width * scale
    let scaledHeight = bufferSize.height * scale
    let offsetX = (scaledWidth - viewSize.width) / 2
    let offsetY = (scaledHeight - viewSize.height) / 2
    let x = normalized.x * bufferSize.width * scale - offsetX
    let y = (1 - normalized.y) * bufferSize.height * scale - offsetY
    return CGPoint(x: x, y: y)
}

/// The composition coach's crosshair: a target reticle at the nearest rule-of-thirds line,
/// a dot at the subject's actual current position, and a connecting line between them —
/// the same geometry regardless of mode (photographer- or subject-moves), since it's the
/// wording elsewhere that changes who is meant to close that gap.
///
/// The line/crosshair alone read as static — asked for explicitly: "mehr Feedback" while
/// closing the gap, not just a fixed dashed line and a text hint that only changes at
/// thresholds. So everything here also scales continuously with `proximity` (0 = just
/// entered frame, 1 = dead on target): the line brightens and thickens, the crosshair grows
/// and brightens, and once truly on target (`target == nil`, the coach has nothing left to
/// nudge) a solid mint ring confirms it instead of the crosshair just disappearing.
struct CompositionCoachOverlay: View {
    let personBox: CGRect
    let target: CGPoint?
    let bufferSize: CGSize
    let accent: Color

    var body: some View {
        GeometryReader { geo in
            let viewSize = geo.size
            let subjectPoint = compositionScreenPoint(
                normalized: CGPoint(x: personBox.midX, y: personBox.midY),
                bufferSize: bufferSize, viewSize: viewSize)
            let targetPoint = target.flatMap {
                compositionScreenPoint(normalized: $0, bufferSize: bufferSize, viewSize: viewSize)
            }
            let proximity: Double = {
                guard let subjectPoint, let targetPoint else { return 1 }
                let distance = hypot(subjectPoint.x - targetPoint.x, subjectPoint.y - targetPoint.y)
                let maxDistance = max(viewSize.width, viewSize.height) * 0.5
                guard maxDistance > 0 else { return 1 }
                return max(0, 1 - Double(distance / maxDistance))
            }()

            ZStack {
                if let subjectPoint, let targetPoint {
                    Path { path in
                        path.move(to: subjectPoint)
                        path.addLine(to: targetPoint)
                    }
                    .stroke(accent.opacity(0.35 + proximity * 0.45),
                            style: StrokeStyle(lineWidth: 1.5 + proximity * 2, dash: [4, 4]))
                }
                if let subjectPoint {
                    Circle()
                        .stroke(.white.opacity(0.55 + proximity * 0.45), lineWidth: 2)
                        .frame(width: 14, height: 14)
                        .position(subjectPoint)
                }
                if let targetPoint {
                    CrosshairShape()
                        .stroke(accent, lineWidth: 2 + proximity * 1.5)
                        .frame(width: 30 + proximity * 14, height: 30 + proximity * 14)
                        .opacity(0.55 + proximity * 0.45)
                        .position(targetPoint)
                } else if let subjectPoint {
                    // Nothing left to nudge — confirm it instead of just removing the
                    // crosshair, so "good" reads as a positive signal, not an absence.
                    Circle()
                        .stroke(Brand.mint, lineWidth: 3)
                        .frame(width: 22, height: 22)
                        .position(subjectPoint)
                }
            }
            .animation(.easeOut(duration: 0.15), value: proximity)
        }
    }
}

private struct CrosshairShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addEllipse(in: rect.insetBy(dx: rect.width * 0.18, dy: rect.height * 0.18))
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.2))
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY - rect.height * 0.2))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.2, y: rect.midY))
        path.move(to: CGPoint(x: rect.maxX - rect.width * 0.2, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

/// A horizon level line, the same idea as the native Camera app's — but split into two
/// segments with a gap at the exact center instead of one solid bar. Asked for directly:
/// a full line straight across the middle of the frame sits right over whatever the
/// subject actually is, which both looks wrong (nothing should permanently block the
/// center of a camera viewfinder — the one thing App Review consistently flags on camera
/// UIs) and gives no real sense of the shot. Leaving that center point open lets the
/// subject show through untouched while the two flanking segments still read as a level.
/// The gap and segment length aren't fixed either — both scale continuously with how far
/// off level the phone actually is (the literal "Skalierung ... der X-Achse" asked for),
/// so the whole element tightens toward center as it approaches level instead of just
/// flipping color at the threshold — the line becomes the feedback, not just a label on it.
struct LevelLine: View {
    let rollDegrees: Double
    private let levelThreshold = 1.0

    private var isLevel: Bool { abs(rollDegrees) < levelThreshold }

    /// 0...1, how far off level, capped at 12° — drives both segment length and gap width.
    private var tilt: Double { min(abs(rollDegrees) / 12, 1) }

    var body: some View {
        GeometryReader { geo in
            let color = isLevel ? Brand.mint : Color.white.opacity(0.65)
            let thickness: CGFloat = isLevel ? 2.5 : 2
            // Off level: segments reach outward and the center gap widens, giving the tilt
            // more visual weight. Near level: both pull back in — a tightening, not just a
            // color swap, so approaching level reads as "closing in on the mark".
            let segmentLength: CGFloat = 22 + tilt * 18
            let gap: CGFloat = isLevel ? 12 : 16 + tilt * 10

            HStack(spacing: gap) {
                Capsule().fill(color).frame(width: segmentLength, height: thickness)
                Capsule().fill(color).frame(width: segmentLength, height: thickness)
            }
            .shadow(color: .black.opacity(0.5), radius: 2)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
            .rotationEffect(.degrees(-rollDegrees))
            .animation(.easeOut(duration: 0.12), value: rollDegrees)
        }
    }
}
