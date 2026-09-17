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

            ZStack {
                if let subjectPoint, let targetPoint {
                    Path { path in
                        path.move(to: subjectPoint)
                        path.addLine(to: targetPoint)
                    }
                    .stroke(accent.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                }
                if let subjectPoint {
                    Circle()
                        .stroke(.white.opacity(0.8), lineWidth: 2)
                        .frame(width: 14, height: 14)
                        .position(subjectPoint)
                }
                if let targetPoint {
                    CrosshairShape()
                        .stroke(accent, lineWidth: 2)
                        .frame(width: 34, height: 34)
                        .position(targetPoint)
                }
            }
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

/// A horizon level line, the same idea as the native Camera app's: a line across the
/// middle of the frame that rotates with the phone's roll and switches to an accent color
/// once you're close enough to level to actually mean it — a small snap-to-attention cue,
/// not just a passive protractor reading.
struct LevelLine: View {
    let rollDegrees: Double
    private let levelThreshold = 1.0

    private var isLevel: Bool { abs(rollDegrees) < levelThreshold }

    var body: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(isLevel ? Brand.mint : .white.opacity(0.65))
                .frame(width: 76, height: isLevel ? 2.5 : 2)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
                .rotationEffect(.degrees(-rollDegrees))
                .animation(.easeOut(duration: 0.12), value: rollDegrees)
                .shadow(color: .black.opacity(0.5), radius: 2)
        }
    }
}
