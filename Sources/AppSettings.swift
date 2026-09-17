import SwiftUI
import UIKit

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
    // Composition coach crosshair + level-line colors — asked for directly ("Nutzer lieben
    // das"). `Color` itself isn't Codable, so these persist as their sRGB components.
    @Published var crosshairColor: Color {
        didSet { Self.saveColor(crosshairColor, key: Keys.crosshairColor) }
    }
    @Published var levelLineColor: Color {
        didSet { Self.saveColor(levelLineColor, key: Keys.levelLineColor) }
    }

    private enum Keys {
        static let edge = "com.danielschweiger.cameraobscura.panelEdge"
        static let opacity = "com.danielschweiger.cameraobscura.panelOpacity"
        static let sound = "com.danielschweiger.cameraobscura.soundEnabled"
        static let crosshairColor = "com.danielschweiger.cameraobscura.crosshairColor"
        static let levelLineColor = "com.danielschweiger.cameraobscura.levelLineColor"
    }

    init() {
        let defaults = UserDefaults.standard
        panelEdge = defaults.string(forKey: Keys.edge).flatMap(PanelEdge.init(rawValue:)) ?? .bottom
        // 0 would make the panel invisible and effectively un-closeable-by-sight; keep a
        // usable floor while still letting it get quite see-through.
        let storedOpacity = defaults.object(forKey: Keys.opacity) as? Double
        panelOpacity = storedOpacity ?? 0.97
        soundEnabled = (defaults.object(forKey: Keys.sound) as? Bool) ?? true
        crosshairColor = Self.loadColor(Keys.crosshairColor, default: Brand.mint)
        levelLineColor = Self.loadColor(Keys.levelLineColor, default: Brand.mint)
    }

    private static func saveColor(_ color: Color, key: String) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        let data = try? JSONEncoder().encode([Double(r), Double(g), Double(b), Double(a)])
        UserDefaults.standard.set(data, forKey: key)
    }

    private static func loadColor(_ key: String, default fallback: Color) -> Color {
        guard let data = UserDefaults.standard.data(forKey: key),
              let comps = try? JSONDecoder().decode([Double].self, from: data), comps.count == 4 else {
            return fallback
        }
        return Color(.sRGB, red: comps[0], green: comps[1], blue: comps[2], opacity: comps[3])
    }
}
