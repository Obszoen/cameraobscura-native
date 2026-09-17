import Foundation

/// 30 hand-picked parameter combinations — the actual idea behind this: most people don't
/// know how to dial in fisheye/chroma/vignette/grain themselves, so instead of forcing them
/// to learn, one tap drops them into a combination modeled on how a specific kind of shot
/// (portrait, landscape, night reportage, ...) actually gets treated by someone who does
/// this for a living. Random on purpose — it's a "surprise me" button, not a menu; picking
/// blind is what makes someone actually try five different ones in a row.
enum CuratedPresets {
    static let all: [SavedPreset] = [
        preset("Goldene Stunde Portrait", .portra, fisheye: 0.35, intensity: 0.85, chroma: 0.3, vignette: 0.35, grain: true, circle: false, auto: true),
        preset("Straßenreportage S/W", .hp5, fisheye: 0.4, intensity: 1.0, chroma: 0.1, vignette: 0.5, grain: true, circle: false, auto: true),
        preset("Nächtliches Kino", .cinestill, fisheye: 0.5, intensity: 0.9, chroma: 0.6, vignette: 0.6, grain: true, circle: false, auto: false),
        preset("Verträumtes Pastell", .polaroid, fisheye: 0.6, intensity: 0.7, chroma: 0.2, vignette: 0.3, grain: false, circle: true, auto: true),
        preset("Knalliges Landschaftsgrün", .velvia, fisheye: 0.45, intensity: 1.0, chroma: 0.2, vignette: 0.4, grain: false, circle: false, auto: true),
        preset("Kühle Editorial-Tiefe", .vision3, fisheye: 0.3, intensity: 0.85, chroma: 0.35, vignette: 0.45, grain: true, circle: false, auto: true),
        preset("Warmer Amateurfilm", .agfa, fisheye: 0.55, intensity: 0.8, chroma: 0.25, vignette: 0.3, grain: true, circle: false, auto: true),
        preset("Deutsche Präzisionsoptik", .leica, fisheye: 0.4, intensity: 0.9, chroma: 0.15, vignette: 0.4, grain: false, circle: false, auto: true),
        preset("Skandinavisch Natürlich", .hasselblad, fisheye: 0.25, intensity: 0.75, chroma: 0.1, vignette: 0.2, grain: false, circle: false, auto: true),
        preset("Kühles Kino-Blau", .zeiss, fisheye: 0.4, intensity: 0.95, chroma: 0.4, vignette: 0.55, grain: true, circle: false, auto: false),
        preset("Entrückt Infrarot", .rollei, fisheye: 0.5, intensity: 0.85, chroma: 0.3, vignette: 0.45, grain: true, circle: false, auto: true),
        preset("Dramatisches Rot-Schwarz", .noir, fisheye: 0.6, intensity: 1.0, chroma: 0.5, vignette: 0.65, grain: true, circle: false, auto: false),
        preset("Hartes Actionkino", .bleach, fisheye: 0.5, intensity: 0.9, chroma: 0.2, vignette: 0.5, grain: true, circle: false, auto: false),
        preset("Technicolor Klassiker", .technicolor, fisheye: 0.4, intensity: 1.0, chroma: 0.15, vignette: 0.35, grain: false, circle: false, auto: true),
        preset("Historisches Archiv", .sepia, fisheye: 0.45, intensity: 0.9, chroma: 0.1, vignette: 0.55, grain: true, circle: true, auto: true),
        preset("Zirkulares Fisheye-Extrem", .none, fisheye: 1.0, intensity: 0, chroma: 0.7, vignette: 0.75, grain: false, circle: true, auto: true),
        preset("Sanfter Alltag", .none, fisheye: 0.2, intensity: 0, chroma: 0.05, vignette: 0.15, grain: false, circle: false, auto: true),
        preset("Retro Sofortbild Party", .polaroid, fisheye: 0.5, intensity: 0.9, chroma: 0.35, vignette: 0.4, grain: true, circle: false, auto: true),
        preset("Kino-Weitwinkel Nacht", .cinestill, fisheye: 0.7, intensity: 0.8, chroma: 0.55, vignette: 0.5, grain: true, circle: false, auto: false),
        preset("Klassische Reportage", .hp5, fisheye: 0.3, intensity: 0.9, chroma: 0.05, vignette: 0.3, grain: true, circle: false, auto: true),
        preset("Editorial Hauttöne", .portra, fisheye: 0.25, intensity: 0.75, chroma: 0.1, vignette: 0.25, grain: false, circle: false, auto: true),
        preset("Satte Sommerlandschaft", .velvia, fisheye: 0.6, intensity: 0.95, chroma: 0.3, vignette: 0.45, grain: false, circle: false, auto: true),
        preset("Kühler Zukunftslook", .zeiss, fisheye: 0.55, intensity: 1.0, chroma: 0.45, vignette: 0.6, grain: false, circle: false, auto: false),
        preset("Warmer Vintage-Charme", .agfa, fisheye: 0.35, intensity: 0.7, chroma: 0.2, vignette: 0.35, grain: true, circle: false, auto: true),
        preset("Extremes Rund-Fisheye", .leica, fisheye: 0.9, intensity: 0.8, chroma: 0.4, vignette: 0.6, grain: false, circle: true, auto: true),
        preset("Minimal Natürlich", .hasselblad, fisheye: 0.15, intensity: 0.6, chroma: 0.05, vignette: 0.1, grain: false, circle: false, auto: true),
        preset("Nachtsicht-Experiment", .nightvision, fisheye: 0.4, intensity: 1.0, chroma: 0.2, vignette: 0.4, grain: true, circle: false, auto: false),
        preset("Invertiertes Experiment", .negativ, fisheye: 0.3, intensity: 1.0, chroma: 0.1, vignette: 0.2, grain: false, circle: false, auto: false),
        preset("Weiches Grobkorn", .hp5, fisheye: 0.5, intensity: 0.8, chroma: 0.15, vignette: 0.4, grain: true, circle: false, auto: true),
        preset("Maximaler Kino-Effekt", .cinestill, fisheye: 0.75, intensity: 1.0, chroma: 0.65, vignette: 0.7, grain: true, circle: false, auto: false),
    ]

    private static func preset(
        _ name: String, _ look: LookRef, fisheye: Double, intensity: Double,
        chroma: Double, vignette: Double, grain: Bool, circle: Bool, auto: Bool
    ) -> SavedPreset {
        SavedPreset(name: name, lookID: look.rawValue, fisheyeStrength: fisheye, lookIntensity: intensity,
                    chromaticAberration: chroma, vignetteAmount: vignette, grain: grain, circleMask: circle, autoEnhance: auto)
    }

    /// Just the known LensLook ids, spelled out so a typo here is a compile error instead
    /// of a silently-ignored preset that falls back to "Original".
    private enum LookRef: String {
        case none, vision3, portra, velvia, cinestill, hp5, agfa, polaroid
        case leica, hasselblad, zeiss, rollei, noir, bleach, technicolor, sepia
        case nightvision, negativ
    }
}
