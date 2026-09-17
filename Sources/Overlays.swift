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
