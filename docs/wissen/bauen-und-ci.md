---
name: bauen-und-ci
description: Wie Kerne, Xcode-Projekt und CI zusammenspielen (bootstrap.sh, Stempel, XcodeGen, GitHub Actions) und welche Eigenheiten von Xcode 27.2 dabei zählen
---

# Bauen und CI

Stand 6. November 2026, Xcode 27.2, XcodeGen 2.45.4. Die Entscheidungen dahinter stehen in ADR 0003 (Kerne) und ADR 0004 (XcodeGen).

## Ablauf

1. `Scripts/bootstrap.sh` liest aus `project.yml` die eingebetteten Kerne (`- framework: Cores/Build/<CORE_NAME>.xcframework`) und sucht in `Scripts/cores/` das Rezept mit diesem `CORE_NAME`.
2. Je Kern: Submodul auf den eingetragenen Commit bringen (`git submodule update --init --recursive`, nur wenn `git submodule status` nicht schon passt), dann bauen, wenn das xcframework fehlt oder veraltet ist. Das Build-Log landet in `build/logs/<rezept>.log`, bei einem Fehler zeigt bootstrap die letzten 30 Zeilen.
3. `xcodegen generate`. XcodeGen ruft vorher `Scripts/bootstrap.sh --check` auf (`preGenCommand`) und bricht ab, wenn ein Kern fehlt oder veraltet ist.

**Veraltet** heißt: Der Stempel `Cores/Build/<CORE_NAME>.stamp` stimmt nicht mehr mit `Scripts/build-core.sh <rezept> --fingerprint` überein. Der Fingerabdruck enthält den ausgecheckten Commit des Submoduls, SHA-256 von Rezept und `build-core.sh` sowie den Build-Typ. build-core.sh schreibt den Stempel nach jedem erfolgreichen Build, auch beim Aufruf von Hand. Ungespeicherte Änderungen im Submodul erfasst der Fingerabdruck nicht.

**Anwenden:** Nach jedem Pull `Scripts/bootstrap.sh`. Einen neuen Kern trägt man nur in `project.yml` ein (plus Rezept), bootstrap und die Prüfung ziehen nach.

## Eigenheiten von Xcode und XcodeGen

- **Fehlendes xcframework:** Xcode bricht schon in „CreateBuildDescription“ ab („There is no XCFramework found at …“), bevor irgendeine Build-Phase läuft. **Warum das zählt:** Ein Run-Script mit eigenem Hinweis kommt nie zum Zug. Den Hinweis gibt deshalb die Prüfung beim Generieren.
- **`embed: true` und `link: false`** auf einer `framework:`-Abhängigkeit erzeugen nur einen Eintrag in „Embed Frameworks“ (mit `CodeSignOnCopy`). Xcode verarbeitet das xcframework trotzdem und kopiert die passende Scheibe. Nebenwirkung: XcodeGen ergänzt `FRAMEWORK_SEARCH_PATHS = Cores/Build`.
- **Kern nur in bestimmten Konfigurationen einbetten:** `EXCLUDED_SOURCE_FILE_NAMES` wirkt auf „Embed Frameworks“, aber nur mit dem Namen des Frameworks (`mgba_libretro.framework`), nicht mit dem des xcframeworks. Ausprobiert am 6. November 2026.
- **Header-only C-Target:** Ein SwiftPM-C-Target nur mit Header baut, aber Xcode will beim Linken des Test-Bundles `CLibretro.o` und findet die Datei nicht („Build input file cannot be found“). Eine fast leere `.c`-Datei behebt das.
- **Paket in App und Tests:** Linken App und Test-Bundle dasselbe Paketprodukt, baut Xcode es in Test-Builds als dynamisches `<Paket>_<Hash>_PackageProduct.framework` und bettet es in die App ein. Im normalen Build ist es statisch. Code, der Frameworks im Bundle zählt, muss das aushalten.
- **`TARGETED_DEVICE_FAMILY`** muss im Target stehen, weil XcodeGens iOS-Preset dort `1,2` setzt.
- **`ARCHS`** auf Projektebene gilt nicht für lokale Pakete. Generische Simulator-Builds kompilieren die Pakete zusätzlich für x86_64.
- **Debug-Builds** haben dank Previews die Binärdateien `Arcfold` (Stub), `Arcfold.debug.dylib` und `__preview.dylib`. Wer prüfen will, was gelinkt ist, schaut mit `otool -L` auch auf `Arcfold.debug.dylib`, oder auf einen Release-Build.
- **Build-Log-Zeile** „appintentsmetadataprocessor … warning: Metadata extraction skipped, no AppIntents.framework dependency found“ kommt von Xcodes Werkzeug selbst und betrifft jedes Target ohne App Intents. Sie ist keine Compiler-Warnung.

## CI (GitHub Actions)

- Workflow `.github/workflows/ci.yml`, ein Job auf `runs-on: xcode-27`. Das ist ein Vorschau-Image (seit 16. Juli 2026, Issue actions/runner-images#14404) mit macOS 27, Xcode 27.0, 27.1 (Standard) und 27.2 RC, Simulatoren iOS 27.0 (iPhones) und iOS 27.1 (nur iPhone Duo), CMake 4.4.4, Ninja 1.13.2, xcbeautify, jq. XcodeGen fehlt und kommt per Homebrew. `macos-26` und `macos-latest` haben nur Xcode 26. Quelle: `images/macos/xcode-27-arm64-Readme.md` im Repo actions/runner-images, Image-Version 20261026.0314.1.
- Actions: `actions/checkout@v7`, `actions/cache/restore@v6` und `actions/cache/save@v6` (aktuelle Major-Versionen am 6. November 2026).
- Gewählt wird das Standard-Xcode des Images, wenn es mindestens 27.1 ist, sonst das neueste installierte. Ohne Xcode 27.1 gibt der Job eine `::notice::` aus, überspringt den Rest und bleibt grün.
- Die Kerne werden gecacht, Schlüssel aus Xcode-Build, Submodul-Commit (`git rev-parse HEAD:Cores/mgba`), Rezept und `build-core.sh`. Gespeichert wird gleich nach dem Bauen, damit ein roter Test den Cache nicht verwirft.
- **Kosten:** Das Repo ist privat. macOS-Minuten zählen zehnfach gegen das Gratis-Kontingent. Deshalb ein Job, Cache und `cancel-in-progress`.
- **Flacher Submodul-Klon:** Ohne Tags setzt build-core.sh die Framework-Version (`CFBundleShortVersionString`) auf 0.0.0. mGBA meldet trotzdem „0.10.5“, weil es im abgelösten HEAD auf seine CMake-Version zurückfällt. Für die CI reicht das.
- Lokal nachgestellt am 6. November 2026: frischer Klon, `git submodule update --init --depth 1 -- Cores/mgba`, `Scripts/bootstrap.sh` (mGBA kalt in 11 s), Tests Store grün, JIT gebaut, keine Warnungen. Auf GitHub selbst lief der Workflow noch nicht, weil der Branch nicht gepusht ist.
- Prüfen: `actionlint -ignore 'label "xcode-27" is unknown' .github/workflows/ci.yml` (das Label kennt actionlint 1.7.12 noch nicht).
