import SwiftUI

/// Shared live state for "which control is being touched right now" — lets the viewfinder
/// show a large value readout and an accent-colored edge tint while a knob/fader is in use,
/// without `preview` and the adjustments panel (siblings in the view tree, not parent/child)
/// needing a direct reference to each other. Asked for directly: seeing the effect change
/// in the sucher is one thing, but knowing the exact value without glancing down at the
/// small in-panel label is what actually lets someone keep their eyes on the shot.
final class ActiveControl: ObservableObject {
    @Published var label: String?
    @Published var value: Double? // 0...1
    @Published var accent: Color = Brand.rose

    func begin(label: String, value: Double, accent: Color) {
        self.label = label
        self.value = value
        self.accent = accent
    }

    func update(value: Double) {
        self.value = value
    }

    func end() {
        label = nil
        value = nil
    }
}
