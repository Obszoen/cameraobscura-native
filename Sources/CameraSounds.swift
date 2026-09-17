import AudioToolbox

/// Plays the same system sound IDs Apple's own Camera/screen-recording UI uses (1108
/// shutter, 1117/1118 begin/end recording) — no bundled audio asset needed, and it matches
/// what people already associate with those actions. Asked for directly, with an explicit
/// "optional ausstellbar in Einstellungen" — callers check `AppSettings.soundEnabled`
/// themselves before calling in, this type just plays what it's told to.
enum CameraSounds {
    static func shutter() { AudioServicesPlaySystemSound(1108) }
    static func recordStart() { AudioServicesPlaySystemSound(1117) }
    static func recordStop() { AudioServicesPlaySystemSound(1118) }
}
