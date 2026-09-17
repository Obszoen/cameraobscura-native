# CameraObscura (native)

Echte native iOS-App (Swift/SwiftUI), kein Web-Wrapper. Gebaut ohne eigenen Mac über
GitHub Actions (kostenloser Cloud-Mac-Runner mit Xcode), signiert/installiert über
Sideloadly oder SideStore mit einer kostenlosen Apple-ID.

## Was hier nativ besser ist als die Web-Version

- **Echter Blitz/Taschenlampe** (`AVCaptureDevice.torchMode`) — ging in Safari gar nicht.
- **Echter durchgehender Zoom über alle Objektive** (Ultra-Weitwinkel → Weitwinkel → Tele
  als ein Regler, über `builtInTripleCamera`) statt diskreter Auswahl wie im Web.
- **Antippen zum Fokussieren/Belichten** — kein Web-API dafür vorhanden.
- **Echte Live Photos** (`PHAssetCreationRequest` mit gepaartem Video) — technisch im
  Browser unmöglich, hier real umgesetzt.
- **GPU-beschleunigte Filter** (CoreImage/Metal) in voller Auflösung statt einer
  JavaScript-Pixelschleife.
- **Automatische Bildverbesserung** über Apples eigene `autoAdjustmentFilters` statt
  selbstgebauter Histogramm-Logik.
- Direktes Speichern in die Fotos-Bibliothek, kein Umweg über einen Teilen-Dialog.

## Ehrlich: was in diesem v1 noch fehlt

- **Video-Aufnahme zeichnet die echte Kamera auf, aber ohne den Fisheye-/Look-Effekt
  fest eingebrannt.** Die Live-Vorschau zeigt den Effekt beim Filmen, aber das gespeicherte
  Video ist unbearbeitetes Rohmaterial. Effekt *ins Video* zu backen braucht eine eigene
  `AVAssetWriter`-Pipeline — bewusst nicht in diesem Wurf, um nichts Halbfertiges abzuliefern.
- Objektiv-Looks tragen noch echte Markennamen (Leica, Kodak, …) — bewusst so belassen,
  wird vor einem eventuellen Verkauf umbenannt.

## So kommt die App aufs iPhone

1. **Dieses Verzeichnis zu GitHub pushen** (braucht einmalig deinen Login):
   ```bash
   cd native/CameraObscura
   git init && git add . && git commit -m "CameraObscura native v1"
   gh repo create cameraobscura-native --public --source=. --push
   ```
   Ohne `gh`: manuell ein leeres Repo auf github.com anlegen und `git remote add origin <url>` + `git push`.
2. GitHub Actions baut automatisch (Reiter "Actions" im Repo) und legt eine
   `CameraObscura-unsigned-ipa` als Download bereit (Artefakt am Ende des Workflow-Laufs).
3. Die `.ipa` mit **Sideloadly** (Windows/Linux über Wine) oder **SideStore** mit einer
   kostenlosen Apple-ID signieren und aufs iPhone installieren.
4. Alle 7 Tage muss neu signiert werden (Apple-Limit der kostenlosen Schiene) — dafür
   Handy kurz wieder mit dem Rechner verbinden. Mit dem 99$/Jahr-Account entfällt das.

## Warum kein Mac nötig war

Xcode selbst läuft nur auf macOS — das ist eine echte, unumgehbare Einschränkung von
Apple, keine Ausrede. Die Lösung hier: GitHub stellt für genau diesen Zweck kostenlose
Cloud-Mac-Runner mit vorinstalliertem Xcode bereit, die den Code für uns kompilieren.
