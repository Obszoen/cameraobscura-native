import CoreImage
import SwiftUI

/// Color-grade recipe for one "lens look". Mirrors the web version's FILTERS table
/// (mul/off/sat/con) so photos look the same across both versions during development.
struct LensLook: Identifiable {
    let id: String
    let name: String
    let subtitle: String
    let mul: (r: Double, g: Double, b: Double)
    let off: (r: Double, g: Double, b: Double) // 0...255 scale, matches the web app's table
    let saturation: Double
    let contrast: Double

    /// A small representative swatch color for the look picker — applies this look's
    /// grade to a neutral mid-gray so people can see the color character (warm/cool/
    /// desaturated/tinted) at a glance instead of reading a name off a text menu.
    var previewColor: Color {
        let base = 0.55
        var r = base * mul.r + off.r / 255
        var g = base * mul.g + off.g / 255
        var b = base * mul.b + off.b / 255
        let gray = (r + g + b) / 3
        r = gray + (r - gray) * saturation
        g = gray + (g - gray) * saturation
        b = gray + (b - gray) * saturation
        func clamp(_ v: Double) -> Double { min(max(v, 0), 1) }
        return Color(red: clamp(r), green: clamp(g), blue: clamp(b))
    }

    static let all: [LensLook] = [
        LensLook(id: "none", name: "Original", subtitle: "unverändert",
                  mul: (1.00, 1.00, 1.00), off: (0, 0, 0), saturation: 1.00, contrast: 1.00),
        LensLook(id: "vision3", name: "Cine Stock 500T", subtitle: "bläuliche Tiefen, Kino-Kontrast",
                  mul: (0.97, 1.00, 1.08), off: (-4, 0, 10), saturation: 0.90, contrast: 1.12),
        LensLook(id: "portra", name: "Portrait Negative 400", subtitle: "weiche, teure Hauttöne",
                  mul: (1.08, 1.02, 0.94), off: (10, 4, 0), saturation: 0.96, contrast: 0.96),
        LensLook(id: "velvia", name: "Velvet Slide 50", subtitle: "knallig gesättigt",
                  mul: (1.05, 1.10, 0.98), off: (2, 4, -2), saturation: 1.35, contrast: 1.15),
        LensLook(id: "cinestill", name: "Tungsten Night Glow 800", subtitle: "warmes Halo-Leuchten bei Nacht",
                  mul: (1.18, 0.95, 0.92), off: (14, -4, 6), saturation: 1.05, contrast: 1.05),
        LensLook(id: "hp5", name: "Hyper Pan 400", subtitle: "klassisches Schwarzweiß",
                  mul: (1.00, 1.00, 1.00), off: (0, 0, 0), saturation: 0.00, contrast: 1.15),
        LensLook(id: "agfa", name: "Vista Amateur 200", subtitle: "warmer Amateurfilm-Charme",
                  mul: (1.08, 1.03, 0.90), off: (8, 4, -4), saturation: 0.95, contrast: 0.95),
        LensLook(id: "polaroid", name: "Instant 600", subtitle: "pastellig, angehobenes Schwarz",
                  mul: (1.05, 1.00, 0.92), off: (18, 10, 4), saturation: 0.85, contrast: 0.85),
        LensLook(id: "leica", name: "German Rangefinder Vintage", subtitle: "warm & kontrastreich",
                  mul: (1.09, 1.00, 0.90), off: (8, 2, -6), saturation: 0.92, contrast: 1.14),
        LensLook(id: "hasselblad", name: "Swedish Medium Format", subtitle: "sanft & naturgetreu",
                  mul: (1.02, 1.01, 0.99), off: (2, 1, 0), saturation: 1.05, contrast: 1.03),
        LensLook(id: "zeiss", name: "German Cine Glass", subtitle: "kühl & filmisch",
                  mul: (0.94, 1.00, 1.10), off: (-4, 0, 10), saturation: 1.00, contrast: 1.16),
        LensLook(id: "rollei", name: "Infrared Twin-Lens", subtitle: "feinkörnig, entrückt",
                  mul: (0.90, 1.05, 0.95), off: (0, 10, -5), saturation: 0.15, contrast: 1.20),
        LensLook(id: "noir", name: "Noir Rouge", subtitle: "dramatisches Schwarz-Rot",
                  mul: (1.15, 0.55, 0.55), off: (6, -10, -10), saturation: 0.55, contrast: 1.35),
        LensLook(id: "bleach", name: "Bleach Bypass", subtitle: "entsättigt, hartes Actionkino",
                  mul: (1.00, 1.00, 1.00), off: (0, 0, 0), saturation: 0.35, contrast: 1.45),
        LensLook(id: "technicolor", name: "Three-Strip Bold", subtitle: "satte Primärfarben, Filmklassiker",
                  mul: (1.15, 1.05, 1.15), off: (4, 0, 4), saturation: 1.40, contrast: 1.20),
        LensLook(id: "sepia", name: "Sepia Archiv", subtitle: "historische Bräunung",
                  mul: (1.20, 1.00, 0.75), off: (20, 8, -15), saturation: 0.25, contrast: 1.05),
        LensLook(id: "nightvision", name: "Nachtsicht-Stil", subtitle: "grünes Monochrom, kein echtes Nachtsichtgerät",
                  mul: (0.30, 1.35, 0.30), off: (-15, 25, -15), saturation: 0.35, contrast: 1.30),
        LensLook(id: "negativ", name: "Negativ", subtitle: "Farben umgekehrt",
                  mul: (-1.00, -1.00, -1.00), off: (255, 255, 255), saturation: 1.00, contrast: 1.00),
    ]

    /// Builds the CIFilter chain for this look: color matrix (channel gain + offset) → saturation/contrast.
    func apply(to image: CIImage) -> CIImage {
        let matrix = CIFilter(name: "CIColorMatrix")!
        matrix.setValue(image, forKey: kCIInputImageKey)
        matrix.setValue(CIVector(x: CGFloat(mul.r), y: 0, z: 0, w: 0), forKey: "inputRVector")
        matrix.setValue(CIVector(x: 0, y: CGFloat(mul.g), z: 0, w: 0), forKey: "inputGVector")
        matrix.setValue(CIVector(x: 0, y: 0, z: CGFloat(mul.b), w: 0), forKey: "inputBVector")
        matrix.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
        matrix.setValue(CIVector(x: CGFloat(off.r / 255), y: CGFloat(off.g / 255), z: CGFloat(off.b / 255), w: 0),
                         forKey: "inputBiasVector")
        guard let graded = matrix.outputImage else { return image }

        let controls = CIFilter(name: "CIColorControls")!
        controls.setValue(graded, forKey: kCIInputImageKey)
        controls.setValue(saturation, forKey: kCIInputSaturationKey)
        controls.setValue(contrast, forKey: kCIInputContrastKey)
        return controls.outputImage ?? graded
    }
}
