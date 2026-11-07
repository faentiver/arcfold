---
name: bauen-und-ci
description: Wie Kerne, Xcode-Projekt und CI zusammenspielen (bootstrap.sh, Stempel, XcodeGen, GitHub Actions) und welche Eigenheiten von Xcode 27.2 dabei zählen
---

# Bauen und CI

Stand 7. November 2026, Xcode 27.2, XcodeGen 2.45.4. Die Entscheidungen dahinter stehen in ADR 0003 (Kerne) und ADR 0004 (XcodeGen).

## Ablauf

1. `Scripts/bootstrap.sh` liest aus `project.yml` die eingebetteten Kerne (`- framework: Cores/Build/<CORE_NAME>.xcframework`) und sucht in `Scripts/cores/` das Rezept mit diesem `CORE_NAME`.
2. Je Kern: Submodul auf den eingetragenen Commit bringen (`git submodule update --init --recursive`, nur wenn `git submodule status` nicht schon passt), dann bauen, wenn das xcframework fehlt oder veraltet ist. Das Build-Log landet in `build/logs/<rezept>.log`, bei einem Fehler zeigt bootstrap die letzten 30 Zeilen.
3. `xcodegen generate`. XcodeGen ruft vorher `Scripts/bootstrap.sh --check` auf (`preGenCommand`) und bricht ab, wenn ein Kern fehlt oder veraltet ist.

**Veraltet** heißt: Der Stempel `Cores/Build/<CORE_NAME>.stamp` stimmt nicht mehr mit `Scripts/build-core.sh <rezept> --fingerprint` überein. Der Fingerabdruck enthält den ausgecheckten Commit des Submoduls, SHA-256 von Rezept und `build-core.sh` sowie den Build-Typ. build-core.sh schreibt den Stempel nach jedem erfolgreichen Build, auch beim Aufruf von Hand. Ungespeicherte Änderungen im Submodul erfasst der Fingerabdruck nicht.

**Anwenden:** Nach jedem Pull `Scripts/bootstrap.sh`. Einen neuen Kern trägt man in `project.yml` ein (plus Rezept), bootstrap und die Prüfung ziehen nach. Außerdem braucht er in `.github/workflows/ci.yml` den Submodul-Schritt („Fetch core sources“) und den Cache-Schlüssel („Compute core cache key“), bis die CI die Liste selbst aus `project.yml` liest (geplant für M3 zusammen mit dem Rezept-Haken für Unter-Submodule).

## Eigenheiten von Xcode und XcodeGen

- **Metal-Toolchain:** Seit M1 übersetzt der Build den Shader `Packages/Renderer/Sources/Renderer/Shaders/Picture.metal` zu `default.metallib` im Bundle `Renderer_Renderer.bundle`. Xcode 27 liefert den Metal-Compiler als eigene Komponente; ohne sie bricht der Build mit „cannot execute tool 'metal' due to missing Metal Toolchain“ ab. **Anwenden:** einmal pro Xcode `xcodebuild -downloadComponent metaltoolchain` (rund 840 MB, ohne sudo), prüfen mit `xcodebuild -showComponent metaltoolchain`. Die CI lädt sie im Schritt „Install the Metal toolchain if missing“ nur, wenn der Status nicht `installed` ist.

- **Fehlendes xcframework:** Xcode bricht schon in „CreateBuildDescription“ ab („There is no XCFramework found at …“), bevor irgendeine Build-Phase läuft. **Warum das zählt:** Ein Run-Script mit eigenem Hinweis kommt nie zum Zug. Den Hinweis gibt deshalb die Prüfung beim Generieren.
- **`embed: true` und `link: false`** auf einer `framework:`-Abhängigkeit erzeugen nur einen Eintrag in „Embed Frameworks“ (mit `CodeSignOnCopy`). Xcode verarbeitet das xcframework trotzdem und kopiert die passende Scheibe. Nebenwirkung: XcodeGen ergänzt `FRAMEWORK_SEARCH_PATHS = Cores/Build`.
- **Kern nur in bestimmten Konfigurationen einbetten:** `EXCLUDED_SOURCE_FILE_NAMES` wirkt auf „Embed Frameworks“, aber nur mit dem Namen des Frameworks (`mgba_libretro.framework`), nicht mit dem des xcframeworks. Ausprobiert am 6. November 2026.
- **Header-only C-Target:** Ein SwiftPM-C-Target nur mit Header baut, aber Xcode will beim Linken des Test-Bundles `CLibretro.o` und findet die Datei nicht („Build input file cannot be found“). Eine fast leere `.c`-Datei behebt das.
- **Paket in App und Tests:** Linken App und Test-Bundle dasselbe Paketprodukt, baut Xcode es in Test-Builds als dynamisches `<Paket>_<Hash>_PackageProduct.framework` und bettet es in die App ein. Im normalen Build ist es statisch. Code, der Frameworks im Bundle zählt, muss das aushalten.
- **`TARGETED_DEVICE_FAMILY`** muss im Target stehen, weil XcodeGens iOS-Preset dort `1,2` setzt.
- **`ARCHS`** auf Projektebene gilt nicht für lokale Pakete. Generische Simulator-Builds kompilieren die Pakete zusätzlich für x86_64.
- **Debug-Builds** haben dank Previews die Binärdateien `Arcfold` (Stub), `Arcfold.debug.dylib` und `__preview.dylib`. Wer prüfen will, was gelinkt ist, schaut mit `otool -L` auch auf `Arcfold.debug.dylib`, oder auf einen Release-Build.
- **Build-Log-Zeile** „appintentsmetadataprocessor … warning: Metadata extraction skipped, no AppIntents.framework dependency found“ kommt von Xcodes Werkzeug selbst und betrifft jedes Target ohne App Intents. Sie ist keine Compiler-Warnung.

## Erweiterungen in `project.yml` für M1

Stand 6. November 2026, belegt mit den Builds Store und JIT für den Simulator, Store für ein Gerät und den Tests beider Schemes auf dem Duo-Simulator mit iOS 27.1.

- **Partielle Info.plist:** `INFOPLIST_FILE: App/Info.plist` zusammen mit `GENERATE_INFOPLIST_FILE = YES`. Xcode führt die Datei mit den `INFOPLIST_KEY_*`-Einstellungen zusammen. Dort stehen Schlüssel ohne eigene Build-Einstellung (`CADisableMinimumFrameDurationOnPhone`, `LSSupportsGameMode`, `UTImportedTypeDeclarations`). **Anwenden:** Die Datei steht unter `excludes` der App-Quellen, sonst landet sie als Ressource im Bundle.
- **Lizenztexte:** je Komponente eine Quelle mit `buildPhase: copyFiles`, `destination: resources` und `subpath: Licenses/<Komponente>`. XcodeGen legt pro Unterordner eine eigene Phase „Copy Files“ an, die Dateien landen in `Arcfold.app/Licenses/<Komponente>/`. Gleichnamige Dateien wie `LICENSE` kollidieren so nicht, und im Repo gibt es keine Kopien. **Warum das zählt:** Die Texte aus `Cores/` brauchen das ausgecheckte Submodul, das `Scripts/bootstrap.sh` sicherstellt.
- **Test-Ressourcen:** `path: Tests/Fixtures/gba` mit `includes: ["*.gba"]` und `buildPhase: resources`, in `ArcfoldTests` und `ArcfoldUITests`. Nur die ROMs kommen mit, flach in die Wurzel des Test-Bundles; Generatoren und Lizenzdateien bleiben draußen. Tests finden sie mit `Bundle(for:)` (`Tests/ArcfoldTests/Support/Fixture.swift`). `BundleContentTests` prüft, dass keine ROM im App-Bundle außerhalb von `PlugIns` liegt.
- **UI-Tests:** `ArcfoldUITests` ist ein `bundle.ui-testing` mit der App als Abhängigkeit; XcodeGen setzt `TEST_TARGET_NAME = Arcfold` selbst. Nur das Scheme Store führt die UI-Tests aus, weil die Oberfläche in beiden Builds gleich ist.
- **Paket hängt von Paket ab:** Renderer bindet LibretroKit mit `.package(path: "../LibretroKit")` ein. Xcode führt das mit dem lokalen Paket des Projekts zusammen, ohne Warnung. Die Paket-Tests `RendererTests` stehen in beiden Schemes.

## CI (GitHub Actions)

- Workflow `.github/workflows/ci.yml`, ein Job auf `runs-on: xcode-27`. Das ist ein Vorschau-Image (seit 16. Juli 2026, Issue actions/runner-images#14404) mit macOS 27, Xcode 27.0, 27.1 (Standard) und 27.2 RC, Simulatoren iOS 27.0 (iPhones) und iOS 27.1 (nur iPhone Duo), CMake 4.4.4, Ninja 1.13.2, xcbeautify, jq. XcodeGen fehlt und kommt per Homebrew. `macos-26` und `macos-latest` haben nur Xcode 26. Quelle: `images/macos/xcode-27-arm64-Readme.md` im Repo actions/runner-images, Image-Version 20261026.0314.1.
- Actions: `actions/checkout@v7`, `actions/cache/restore@v6` und `actions/cache/save@v6` (aktuelle Major-Versionen am 6. November 2026).
- Gewählt wird das Standard-Xcode des Images, wenn es mindestens 27.1 ist, sonst das neueste installierte. Ohne Xcode 27.1 gibt der Job eine `::notice::` aus, überspringt den Rest und bleibt grün.
- Die Metal-Toolchain prüft der Schritt „Install the Metal toolchain if missing“ mit `xcodebuild -showComponent metaltoolchain -json` und lädt sie nur, wenn sie fehlt. Ob das Image `xcode-27` sie mitbringt, ist offen, bis der Workflow einmal läuft; das Laden kostet etwa 840 MB Download.
- `RendererTests/AudioOutputTests` starten eine echte `AVAudioEngine`; der Simulator gibt den Ton über das Audiogerät des Macs aus. Ob die Runner eines haben, zeigt erst der erste Lauf (offen).
- Die Kerne werden gecacht, Schlüssel aus Xcode-Build, Submodul-Commit (`git rev-parse HEAD:Cores/mgba`), Rezept und `build-core.sh`. Gespeichert wird gleich nach dem Bauen, damit ein roter Test den Cache nicht verwirft.
- **Kosten:** Das Repo ist privat. macOS-Minuten zählen zehnfach gegen das Gratis-Kontingent. Sparmaßnahmen: ein einziger Job, der Cache und `cancel-in-progress`. Geplant war, nur bei `pull_request` und auf manuellen Start zu laufen; seit 7. November 2026 läuft der Workflow nur auf manuellen Start (`workflow_dispatch`), siehe nächster Punkt.
- **Nur manueller Start (seit 7. November 2026).** Die CI läuft vorerst nur auf manuellen Start (`workflow_dispatch`, etwa `gh workflow run ci.yml --ref <Branch>`); geprüft wird lokal auf dem Mac mini. `pull_request:` kommt später zurück in `on:`.
- **Flacher Submodul-Klon:** Ohne Tags setzt build-core.sh die Framework-Version (`CFBundleShortVersionString`) auf 0.0.0. mGBA meldet trotzdem „0.10.5“, weil es im abgelösten HEAD auf seine CMake-Version zurückfällt. Für die CI reicht das.
- Lokal nachgestellt am 6. November 2026: frischer Klon, `git submodule update --init --depth 1 -- Cores/mgba`, `Scripts/bootstrap.sh` (mGBA kalt in 11 s), Tests Store grün, JIT gebaut, keine Warnungen. Auf GitHub ist der Workflow bisher nicht gelaufen.
- Prüfen: `actionlint -ignore 'label "xcode-27" is unknown' .github/workflows/ci.yml` (das Label kennt actionlint 1.7.12 noch nicht).
