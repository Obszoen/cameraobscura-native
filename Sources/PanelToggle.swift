import SwiftUI
import UIKit

/// A small rocker switch instead of SwiftUI's default Toggle chrome — asked for directly
/// ("Kippschalter-Grafik statt Standard-Toggle"), the same reasoning as the rotary knobs:
/// a plain system control reads as a placeholder next to a rendered metal panel.
struct PanelToggle: View {
    let title: String
    @Binding var isOn: Bool
    var accent: Color = Brand.mint

    var body: some View {
        Button {
            isOn.toggle()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            VStack(spacing: 5) {
                ZStack(alignment: isOn ? .trailing : .leading) {
                    Capsule()
                        .fill(isOn ? accent.opacity(0.25) : Color.black.opacity(0.45))
                        .overlay(Capsule().strokeBorder(isOn ? accent.opacity(0.6) : .white.opacity(0.12), lineWidth: 1))
                        .frame(width: 38, height: 20)

                    Circle()
                        .fill(LinearGradient(colors: [Color(white: 0.62), Color(white: 0.22)],
                                              startPoint: .top, endPoint: .bottom))
                        .overlay(Circle().strokeBorder(.black.opacity(0.5), lineWidth: 0.5))
                        .frame(width: 16, height: 16)
                        .shadow(color: isOn ? accent.opacity(0.6) : .clear, radius: 3)
                        .padding(2)
                }
                .animation(.spring(response: 0.28, dampingFraction: 0.75), value: isOn)

                Text(title)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(0.5)
                    .textCase(.uppercase)
                    .foregroundStyle(isOn ? accent : .secondary)
            }
        }
        .buttonStyle(.plain)
    }
}
