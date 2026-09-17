import SwiftUI

/// Which screen edge the adjustments panel slides in from — asked for directly: some
/// people want it from the bottom, others from the top, or sliding in from either side.
enum PanelEdge: String, CaseIterable, Codable, Identifiable {
    case bottom, top, leading, trailing
    var id: String { rawValue }

    var edge: Edge {
        switch self {
        case .bottom: return .bottom
        case .top: return .top
        case .leading: return .leading
        case .trailing: return .trailing
        }
    }

    var alignment: Alignment {
        switch self {
        case .bottom: return .bottom
        case .top: return .top
        case .leading: return .leading
        case .trailing: return .trailing
        }
    }

    var isVertical: Bool { self == .leading || self == .trailing }

    var label: String {
        switch self {
        case .bottom: return "Unten"
        case .top: return "Oben"
        case .leading: return "Links"
        case .trailing: return "Rechts"
        }
    }

    /// Icon pointing the direction the panel travels when it OPENS (into frame).
    var icon: String {
        switch self {
        case .bottom: return "arrow.up.to.line"
        case .top: return "arrow.down.to.line"
        case .leading: return "arrow.right.to.line"
        case .trailing: return "arrow.left.to.line"
        }
    }
}

/// Persisted, user-facing app preferences — currently just the two asked for directly
/// (panel slide-in edge, panel transparency). Plain UserDefaults, same reasoning as
/// PresetStore: a personal preference, not something that needs an account or a server.
final class AppSettings: ObservableObject {
    @Published var panelEdge: PanelEdge {
        didSet { UserDefaults.standard.set(panelEdge.rawValue, forKey: Keys.edge) }
    }
    @Published var panelOpacity: Double {
        didSet { UserDefaults.standard.set(panelOpacity, forKey: Keys.opacity) }
    }
    // Shutter/record sounds — asked for directly, explicitly "optional ausstellbar".
    @Published var soundEnabled: Bool {
        didSet { UserDefaults.standard.set(soundEnabled, forKey: Keys.sound) }
    }

    private enum Keys {
        static let edge = "com.danielschweiger.cameraobscura.panelEdge"
        static let opacity = "com.danielschweiger.cameraobscura.panelOpacity"
        static let sound = "com.danielschweiger.cameraobscura.soundEnabled"
    }

    init() {
        let defaults = UserDefaults.standard
        panelEdge = defaults.string(forKey: Keys.edge).flatMap(PanelEdge.init(rawValue:)) ?? .bottom
        // 0 would make the panel invisible and effectively un-closeable-by-sight; keep a
        // usable floor while still letting it get quite see-through.
        let storedOpacity = defaults.object(forKey: Keys.opacity) as? Double
        panelOpacity = storedOpacity ?? 0.97
        soundEnabled = (defaults.object(forKey: Keys.sound) as? Bool) ?? true
    }
}
