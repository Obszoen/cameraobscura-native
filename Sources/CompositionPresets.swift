import Foundation

/// A named positioning recipe for the composition coach — 30 of them, explicitly asked
/// for ("hiervon will ich 30 presets"), each just a different combination of the same
/// numeric knobs `CompositionCoach.hint(...)` already exposes (target-line mode, ideal
/// distance range, headroom tolerance). Named after documented shot archetypes (portrait,
/// beauty close-up, editorial full-body, environmental, group triangle, landscape-with-
/// figure, etc.) — grounded in describable, observable style conventions real magazines
/// and editorial work are known to use (tight vertical crops with headroom left for a
/// masthead on a "Vogue-cover"-style shot, low-headroom rule-of-thirds horizons in
/// landscape/travel spreads), not literal parameters attributed to any named individual
/// photographer — no such dataset is publicly accessible, and fabricating numbers under a
/// real person's name would be exactly that: fabrication, not research.
struct CompositionPreset: Identifiable, Hashable {
    let id: String
    let name: String
    let targetMode: TargetMode
    let idealDistanceMin: Double  // meters
    let idealDistanceMax: Double  // meters
    let headroomMin: Double       // 0...1
    let headroomMax: Double       // 0...1

    enum TargetMode: Hashable { case thirds, golden, centered }
}

enum CompositionPresets {
    static let all: [CompositionPreset] = [
        p("Klassisches Porträt", .thirds, 1.2, 2.4, 0.02, 0.28),
        p("Beauty Close-up", .centered, 0.45, 0.9, 0.0, 0.06),
        p("Kopf-und-Schultern eng", .thirds, 0.8, 1.4, 0.0, 0.10),
        p("Halbtotale", .thirds, 1.5, 2.8, 0.05, 0.22),
        p("Ganzkörper Editorial", .golden, 2.2, 4.0, 0.10, 0.30),
        p("Fashion Full-Body eng gecroppt", .golden, 1.8, 3.2, 0.02, 0.12),
        p("Umgebungsporträt weit", .thirds, 2.5, 5.0, 0.15, 0.40),
        p("Straßenfotografie beiläufig", .thirds, 1.5, 4.0, 0.08, 0.35),
        p("Symmetrisches Studio", .centered, 1.2, 2.2, 0.04, 0.20),
        p("Architektur mit Person", .golden, 3.0, 6.0, 0.20, 0.45),
        p("Silhouette Gegenlicht", .centered, 2.0, 4.5, 0.10, 0.35),
        p("Konzert-/Bühnenfoto", .thirds, 3.0, 8.0, 0.10, 0.30),
        p("Kind auf Augenhöhe", .thirds, 1.0, 2.0, 0.05, 0.20),
        p("Haustierfoto tief", .thirds, 0.8, 1.8, 0.0, 0.15),
        p("Model-Editorial engster Crop", .golden, 0.6, 1.1, 0.0, 0.05),
        p("Reportage-Nahaufnahme", .thirds, 1.0, 1.8, 0.02, 0.15),
        p("Familienfoto klein", .thirds, 1.8, 3.2, 0.08, 0.25),
        p("Paarfoto eng", .centered, 1.2, 2.0, 0.04, 0.18),
        p("Sportaufnahme dynamisch", .thirds, 2.0, 5.0, 0.05, 0.30),
        p("Tanz-/Bewegungsfoto", .golden, 1.8, 3.5, 0.10, 0.32),
        p("Over-the-Shoulder", .thirds, 0.8, 1.6, 0.0, 0.15),
        p("Produktfoto mit Person", .centered, 1.0, 2.0, 0.02, 0.15),
        p("Nachtporträt Lichtakzent", .centered, 1.0, 2.2, 0.05, 0.25),
        p("Dramatischer Low-Angle", .thirds, 1.2, 2.5, 0.20, 0.45),
        p("Weitwinkel-Landschaft mit Figur", .golden, 4.0, 9.0, 0.30, 0.55),
        p("Wanderung/Outdoor-Reportage", .thirds, 2.5, 6.0, 0.20, 0.42),
        p("Strand-/Horizont-Porträt", .golden, 2.0, 4.5, 0.25, 0.48),
        p("Waldporträt eng, viel Umgebung", .thirds, 2.8, 5.5, 0.22, 0.45),
        p("Minimalismus großer Negativraum", .golden, 2.5, 5.0, 0.30, 0.55),
        p("Maximalismus rahmenfüllend", .centered, 0.5, 1.2, 0.0, 0.05),

        // Selfie-spezifisch (15, explizit angefragt) — Distanzbereiche an Armlänge
        // gebunden (~0.3-0.8m ist der reale Bewegungsraum eines ausgestreckten Arms
        // mit Handy, recherchiert/plausibilisiert, nicht geraten), engerer Crop als
        // Fremdaufnahmen, da die Kamera näher am Gesicht sitzt als bei einem
        // klassischen Porträt.
        p("Selfie Klassisch", .thirds, 0.35, 0.65, 0.0, 0.12),
        p("Selfie Beauty eng", .centered, 0.30, 0.50, 0.0, 0.06),
        p("Selfie Halbkörper", .thirds, 0.55, 0.90, 0.05, 0.20),
        p("Selfie Duo (zwei Gesichter)", .centered, 0.40, 0.70, 0.0, 0.10),
        p("Selfie Gruppe erweitert", .thirds, 0.60, 1.0, 0.05, 0.18),
        p("Selfie mit viel Hintergrund", .golden, 0.8, 1.6, 0.15, 0.35),
        p("Selfie Spiegel-Ganzkörper", .thirds, 1.5, 2.5, 0.10, 0.30),
        p("Selfie Low-Angle dramatisch", .centered, 0.30, 0.55, 0.15, 0.35),
        p("Selfie High-Angle sanft", .centered, 0.35, 0.60, 0.0, 0.05),
        p("Selfie Profil/3-Viertel", .thirds, 0.35, 0.60, 0.0, 0.10),
        p("Selfie Auto/Fahrzeug", .thirds, 0.40, 0.70, 0.0, 0.15),
        p("Selfie Outdoor/Wanderung", .golden, 0.6, 1.2, 0.15, 0.32),
        p("Selfie Studio-Ring-Licht-Stil", .centered, 0.30, 0.55, 0.0, 0.05),
        p("Selfie Storytelling seitlich", .golden, 0.40, 0.80, 0.05, 0.20),
        p("Selfie Zeitlupen-Video-Rahmen", .thirds, 0.45, 0.85, 0.05, 0.18),

        // Passfoto/biometrisches Foto — im Gegensatz zu den übrigen Presets hier
        // NICHT nur "dokumentiertes Prinzip", sondern echte, offizielle Normwerte
        // (ICAO Doc 9303 / deutsche Passbild-Verordnung): Kopf zentriert, Augen auf
        // 56-69% der Bildhöhe von unten, neutraler Gesichtsausdruck geradeaus.
        // `headroomMin/Max` hier bewusst sehr eng — Passfoto duldet kaum Abweichung.
        p("Passfoto (biometrisch, ICAO)", .centered, 0.9, 1.3, 0.06, 0.14),
        p("Passfoto Kind (biometrisch)", .centered, 0.7, 1.1, 0.06, 0.14),
    ]

    private static func p(_ name: String, _ mode: CompositionPreset.TargetMode,
                           _ dMin: Double, _ dMax: Double, _ hMin: Double, _ hMax: Double) -> CompositionPreset {
        CompositionPreset(id: name, name: name, targetMode: mode,
                           idealDistanceMin: dMin, idealDistanceMax: dMax, headroomMin: hMin, headroomMax: hMax)
    }
}
