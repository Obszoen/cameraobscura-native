import Foundation

struct SavedPreset: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var lookID: String
    var fisheyeStrength: Double
    var lookIntensity: Double
    var chromaticAberration: Double
    var vignetteAmount: Double
    var grain: Bool
    var circleMask: Bool
    var autoEnhance: Bool
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
