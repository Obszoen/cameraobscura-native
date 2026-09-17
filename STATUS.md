# Status

Letzter Stand: 2026-09-18 (nachts) — läuft, installiert auf einem realen
Gerät via Sideloading (kostenloser Apple-ID-Signaturweg, 7 Tage gültig,
läuft am 2026-09-24 ab). Ausführlicher Session-Log der Nacht 2026-09-17→18
in `../../PROJECT.md` (Abschnitt "Account-Übergabe" oben in der Datei).

## Fertig & verifiziert (echter Build + echte Installation)

- Kamera-Session, Foto- und Videoaufnahme (AVFoundation)
- Fisheye-Verzerrung (Equisolid-Projektion) + chromatische Aberration +
  Vignette — Core Image Kernel Language, siehe `Sources/FisheyeFilter.swift`
  für die Begründung gegen einen Metal-Kernel. Farbsaum/Vignette-Kernel-Bug
  (falscher Kernel-Typ, stiller Compile-Fehler) behoben.
- 18 Editorial-Filmlooks (`Sources/LensLook.swift`) — **Markennamen entfernt**
  (Leica/Kodak/Hasselblad/Fuji/Ilford/Polaroid/Zeiss/Technicolor durch
  beschreibende Fantasienamen ersetzt, Abmahnrisiko-Punkt weiter unten ist
  damit erledigt), plus visuelle Swatch-Auswahl statt Text-Menü
- Video-Aufnahme backt den Effekt real ins gespeicherte Video (eigene
  `AVAssetWriter`-Pipeline, nicht nur Live-Vorschau)
- Live-Vorschau läuft über einen echten Metal-Renderer (`MTKView`,
  `MetalPreviewView.swift`) statt einer CGImage/UIImage-Brücke — kein
  Einfrieren mehr während Aufnahme, spürbar geringere Latenz
- **Composition Coach**: Live-Fadenkreuz per Vision-Personenerkennung, zwei
  Modi ("Ich filme" / "Ich bin im Bild"), Drittel-Regel + Headroom-Logik
  (`CompositionCoach.swift`, `Overlays.swift`)
- Drehregler (`RotaryKnob.swift`) statt Schieberegler für alle
  Bild-Parameter, Drittel-Raster + Libellen-/Level-Anzeige (CoreMotion)
- Preset-Roulette: 30 kuratierte Presets, Würfel-Button, keine Wiederholung
  in Folge (`CuratedPresets.swift`)
- Echte Bildstabilisierung (`.cinematicExtended`) + Low-Light-Boost
- Kamera-Session-Unterbrechungen behandelt (Anruf, Fremdzugriff, System-
  druck, Media-Services-Crash) mit Klartext-Meldung + Auto-Recovery
- Vollbild-Sucher + herausziehbares Regler-Sheet statt permanenter
  Regler-Wand; Selfie-Kamera-Spiegelung korrigiert; Foto-Qualität auf
  `.photo`-Preset (vorher fälschlich `.hd1920x1080`) angehoben
- Neues App-Icon ("Cozy Instant Camera") + daran angeglichener Splash
  (identische Icon-Geometrie, kein separates Motiv)
- Vorher/Nachher-Wischvergleich, Export-Presets, eigene speicherbare Presets
- Feedback-Box (Instagram-Verweis)
- Thermal-/Akku-Schutz: reduzierte Vorschau-Framerate im Leerlauf, Kamera
  stoppt beim Backgrounding, MTKView pausiert bei verdecktem/inaktivem Sucher

## Behobene Abstürze dieser Nacht (siehe PROJECT.md für Details)

- Crash bei jedem Kamerazugriff (Info.plist wurde von Xcode automatisch
  generiert und überschrieb unsere Berechtigungstexte)
- Crash bei jedem Foto mit Live Photo aktiv (falsche Delegate-Signatur)
- Crash durch gleichzeitige CoreImage-Renders auf demselben Kontext
  (SIGSEGV) — durch den Metal-Umbau strukturell behoben, nicht nur gepatcht

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
