# Status

Letzter Stand: 2026-09-17 — läuft, installiert auf einem realen Gerät via
Sideloading (kostenloser Apple-ID-Signaturweg, 7 Tage gültig).

## Fertig & verifiziert (echter Build + echte Installation)

- Kamera-Session, Foto- und Videoaufnahme (AVFoundation)
- Fisheye-Verzerrung (Equisolid-Projektion) + chromatische Aberration +
  Vignette — Core Image Kernel Language, siehe `Sources/FisheyeFilter.swift`
  für die Begründung gegen einen Metal-Kernel
- 18 Editorial-Filmlooks (`Sources/LensLook.swift`)
- Video-Aufnahme backt den Effekt real ins gespeicherte Video (eigene
  `AVAssetWriter`-Pipeline, nicht nur Live-Vorschau)
- Vorher/Nachher-Wischvergleich, Export-Presets, eigene speicherbare Presets
- Splash-Animation, App-Icon, Feedback-Box (Instagram-Verweis)
- Thermal-/Akku-Schutz: reduzierte Vorschau-Framerate im Leerlauf, Kamera
  stoppt beim Backgrounding

## Bewusst (temporär) deaktiviert

- **Fotos-Editor-Erweiterung** (`PhotoEditingExtension/`) — Quellcode
  vorhanden, aber aus `project.yml` entfernt. Mit eingebundener Erweiterung
  blieb die Sideload-Installation zuverlässig bei 75 % hängen, ohne
  Fehlermeldung. Nicht abschließend debuggt; auf einem bezahlten
  Developer-Account (Installation via Xcode/TestFlight statt
  AltServer-Linux) vermutlich unproblematisch, da dort ein anderer
  Installationsweg läuft.
- **Sign in with Apple** — braucht das Entitlement
  `com.apple.developer.applesignin`, das kostenlose/Personal-Team-Accounts
  nicht ausstellen können; hat die Installation stillschweigend blockiert.
  Echte Implementierung liegt in der Git-Historie.

## Ungetestet auf echter Hardware

- ProRAW-Aufnahme (Gerät ohne ProRAW-Unterstützung im aktuellen Testgerät)
- LiDAR-Tiefenschärfe-Warp (Testgerät hat kein LiDAR)

## Build

GitHub Actions (`.github/workflows/build.yml`) baut bei jedem Push auf
`main` eine unsignierte `.ipa` auf einem `macos-14`-Runner mit explizit
gewähltem Xcode 16.2 (der Standard-Xcode des Runners kann das von
aktuellem XcodeGen erzeugte Projektformat nicht mehr lesen).
