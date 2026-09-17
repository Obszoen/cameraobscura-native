import Foundation

struct SavedPreset: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var lookID: String
    var fisheyeStrength: Double
    var lookIntensity: Double
    var chromaticAberration: Double
    var vignetteAmount: Double
    // Added after the first presets shipped — decoded with a neutral (0.5) fallback below
    // so presets already saved on-device (UserDefaults, not re-installed) keep loading
    // instead of silently vanishing because a key was missing.
    var brightness: Double = 0.5
    var contrast: Double = 0.5
    var saturation: Double = 0.5
    var warmth: Double = 0.5
    var highlights: Double = 0.5
    var shadows: Double = 0.5
    var sharpness: Double = 0.2
    var grain: Bool
    var circleMask: Bool
    var autoEnhance: Bool

    init(id: UUID = UUID(), name: String, lookID: String, fisheyeStrength: Double, lookIntensity: Double,
         chromaticAberration: Double, vignetteAmount: Double,
         brightness: Double = 0.5, contrast: Double = 0.5, saturation: Double = 0.5,
         warmth: Double = 0.5, highlights: Double = 0.5, shadows: Double = 0.5, sharpness: Double = 0.2,
         grain: Bool, circleMask: Bool, autoEnhance: Bool) {
        self.id = id
        self.name = name
        self.lookID = lookID
        self.fisheyeStrength = fisheyeStrength
        self.lookIntensity = lookIntensity
        self.chromaticAberration = chromaticAberration
        self.vignetteAmount = vignetteAmount
        self.brightness = brightness
        self.contrast = contrast
        self.saturation = saturation
        self.warmth = warmth
        self.highlights = highlights
        self.shadows = shadows
        self.sharpness = sharpness
        self.grain = grain
        self.circleMask = circleMask
        self.autoEnhance = autoEnhance
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        lookID = try c.decode(String.self, forKey: .lookID)
        fisheyeStrength = try c.decode(Double.self, forKey: .fisheyeStrength)
        lookIntensity = try c.decode(Double.self, forKey: .lookIntensity)
        chromaticAberration = try c.decode(Double.self, forKey: .chromaticAberration)
        vignetteAmount = try c.decode(Double.self, forKey: .vignetteAmount)
        brightness = try c.decodeIfPresent(Double.self, forKey: .brightness) ?? 0.5
        contrast = try c.decodeIfPresent(Double.self, forKey: .contrast) ?? 0.5
        saturation = try c.decodeIfPresent(Double.self, forKey: .saturation) ?? 0.5
        warmth = try c.decodeIfPresent(Double.self, forKey: .warmth) ?? 0.5
        highlights = try c.decodeIfPresent(Double.self, forKey: .highlights) ?? 0.5
        shadows = try c.decodeIfPresent(Double.self, forKey: .shadows) ?? 0.5
        sharpness = try c.decodeIfPresent(Double.self, forKey: .sharpness) ?? 0.2
        grain = try c.decode(Bool.self, forKey: .grain)
        circleMask = try c.decode(Bool.self, forKey: .circleMask)
        autoEnhance = try c.decode(Bool.self, forKey: .autoEnhance)
    }
}

/// Presets live in UserDefaults, not iCloud/a server — they're a personal look someone
/// dialed in, not something that needs an account or a backend to exist.
final class PresetStore: ObservableObject {
    @Published private(set) var presets: [SavedPreset] = []
    private let key = "com.danielschweiger.cameraobscura.customPresets"

    init() { load() }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([SavedPreset].self, from: data) else { return }
        presets = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(presets) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    func add(_ preset: SavedPreset) {
        presets.append(preset)
        persist()
    }

    func remove(at offsets: IndexSet) {
        presets.remove(atOffsets: offsets)
        persist()
    }
}
