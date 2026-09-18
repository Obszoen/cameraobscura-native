import SwiftUI

/// Shared live state for "which control is being touched right now" — lets the viewfinder
/// show a large value readout and an accent-colored edge tint while a knob/fader is in use,
/// without `preview` and the adjustments panel (siblings in the view tree, not parent/child)
/// needing a direct reference to each other. Asked for directly: seeing the effect change
/// in the sucher is one thing, but knowing the exact value without glancing down at the
/// small in-panel label is what actually lets someone keep their eyes on the shot.
final class ActiveControl: ObservableObject {
    @Published var label: String?      // non-nil only while actually touched — drives overlay visibility
    @Published var value: Double?      // 0...1
    @Published var accent: Color = Brand.rose

    // Persist across `end()` — "whichever control was touched most recently" — so the
    // viewfinder's two-finger rotate gesture has something to adjust even when no finger
    // is currently on the panel itself. Plain closures over the knob/fader's own binding,
    // not a reference to the (transient, struct) view that set them, so they stay valid
    // after that particular view is re-rendered or discarded.
    private(set) var lastSetter: ((Double) -> Void)?
    private(set) var lastGetter: (() -> Double)?
    // Published (unlike the two closures above) — reported directly: the rotate gesture
    // only ever adjusted "Schatten" with no way to see or change that binding, so it read
    // as a random find rather than a real control. This drives a small persistent badge in
    // the viewfinder showing which control a two-finger rotation currently targets, even
    // when nothing is actively being dragged.
    @Published private(set) var lastLabel: String?
    @Published private(set) var lastAccent: Color = Brand.rose

    func begin(label: String, value: Double, accent: Color,
               setter: @escaping (Double) -> Void, getter: @escaping () -> Double) {
        self.label = label
        self.value = value
        self.accent = accent
        self.lastLabel = label
        self.lastAccent = accent
        self.lastSetter = setter
        self.lastGetter = getter
    }

    func update(value: Double) {
        self.value = value
    }

    func end() {
        label = nil
        value = nil
    }

    /// Called by the viewfinder's rotate gesture: shows the overlay again, reusing
    /// whichever control was last touched in the panel, while a rotation is adjusting it.
    func showWhileRotating(value: Double) {
        label = lastLabel
        self.value = value
    }
}
