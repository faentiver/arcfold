# Arcfold

## Status

- **Ziel:** Eine offene SwiftUI-App, die mehrere Konsolen emuliert und jedes System für den Falz des iPhone Duo auslegt.
- **Stand:** M0 (Fundament) ist abgenommen: XcodeGen-Projekt mit den Schemes Store und JIT, die Pakete LibretroKit, FoldLayout und Renderer, mGBA 0.10.5 als eingebettetes, nicht gelinktes Framework, der CI-Workflow, ADR 0001 angenommen, ADR 0002 mit ausstehendem Gerätetest.

  M1 · GBA läuft (Plan, Abschnitt 10) ist auf dem Branch `m1/gba` umgesetzt und im Duo-Simulator belegt; die Abnahme durch Fatih steht aus:
  - LibretroKit: Emulations-Thread mit Takt, der der Tonuhr folgt, Callbacks, Environment, Eingabe, Batteriespeicher, Messwerte,
  - Renderer: Bild über Metal mit `CAMetalDisplayLink`, Ton über einen Ring in C und `AVAudioEngine`,
  - App: Bibliothek mit Import über `.fileImporter`, Spielansicht mit Touch-Tasten, Controller und Tastatur, Debug-Overlay, Bildschirm „Lizenzen“,
  - Builds Store und JIT ohne Warnung, Tests grün (Store 136, JIT 130),
  - im Simulator: `selftest.gba` zehn Minuten mit 59,73 Bildern/s, ohne Aussetzer und Neusynchronisation, Spielstand übersteht `simctl terminate`,
  - eine unabhängige Prüfung fand keine Fehler, von ihren acht kleineren Befunden sind sieben behoben (ADR 0005, „Nachbesserungen nach der Prüfung“), einer wartet auf das Gerät,
  - ADR 0005 (Laufzeit für Software-Kerne) ist mit den Belegen nachgezogen und weiter vorgeschlagen.
- **Nächster Schritt:** M1-Abnahme durch Fatih und Pull Request von `m1/gba`. Offen sind der Gerätetest auf dem Duo (Bildrate, Wärme, Ton, Mehrfachberührung, Controller) und die Annahme von ADR 0005.
- **Datum:** 7. November 2026

## Arbeitsregeln

- `docs/PLAN.md` vollständig lesen, bevor du Code schreibst. Die harten Regeln unten gelten immer.
- Meilenstein für Meilenstein arbeiten. Der nächste beginnt erst, wenn Fatih die Abnahme des vorigen bestätigt hat.
- Jede größere technische Entscheidung als ADR in `docs/adr/` festhalten: Kontext, Optionen, Entscheidung, Folgen.
- Weicht die Umsetzung vom Plan ab, `docs/PLAN.md` im selben Pull Request aktualisieren.
- Mit Fatih auf Deutsch, knapp und direkt. Code, Kommentare und Commit-Messages sind englisch.
- README.md ist englisch, weil es die öffentliche Projektseite ist; alle übrigen Dokumente sind deutsch.
- Branches heißen `m<Nummer>/<thema>`. Jede Änderung kommt als Pull Request, den Fatih am iPhone prüfen kann. Commit-Messages im Stil von Conventional Commits.

## Harte Regeln

- **Keine Spiele und kein BIOS.** Niemals ROMs, ISOs, BIOS-Dateien, Firmware oder Schlüssel ins Repo oder in die App, auch keine Download-Links. Tests nur mit frei lizenzierten Homebrew-ROMs, deren Lizenzen in `Tests/Fixtures/LICENSES.md` stehen.
- **Kein nachgeladener Code.** Alle Kerne stecken fest im App-Bundle (Richtlinie 2.5.2).
- **Lizenzen.** Die ganze App steht unter GPL-3.0. Nur Kerne mit GPL-3.0-kompatibler Lizenz. Die Lizenzhinweise aller Kerne erscheinen in der App unter „Lizenzen“.
- **JIT nur im JIT-Build.** Der Store-Build darf keinen JIT-Code-Pfad enthalten.
- **Marken.** Kein Nintendo, PlayStation, PSP oder Duo im App-Namen oder Icon. Controller-Skins sind eigene Entwürfe ohne Original-Logos oder geschützte Tastensymbole. Kompatibilität darf sachlich im README stehen.
- **Keine Cover-Bilder** mitliefern oder automatisch laden. Nutzer können eigene Bilder setzen.
- **Store-Einreichung** erst, nachdem die Kern-Entwickler gefragt wurden, weil GPL und App Store als umstritten gelten.

## Aufbau

```
project.yml     Xcode-Projekt für XcodeGen (ADR 0004)
App/            SwiftUI-App: Quellen, String Catalog, Entitlements des JIT-Builds
Packages/       LibretroKit, FoldLayout, Renderer (lokale Swift-Pakete)
Cores/          Kerne als Git-Submodule, auf Tags oder Commits fixiert; Build/ mit den xcframeworks (ignoriert)
Scripts/        bootstrap.sh, build-core.sh, cores/ mit einem Rezept je Kern
Spikes/         Spike-Code aus M0 (PSPGPU, PS2JIT) als Referenz, nicht Teil der App
Tests/          ArcfoldTests (Unit-Tests mit der App als Host), ArcfoldUITests, Fixtures/ (Homebrew-ROMs, Lizenzen)
docs/           PLAN.md, adr/, wissen/
.github/        workflows/ci.yml, die CI mit GitHub Actions
```

## Bauen und Testen

Voraussetzungen: Xcode 27.1 oder neuer mit Metal-Toolchain (`xcodebuild -downloadComponent metaltoolchain`, einmal pro Xcode), dazu `brew install xcodegen cmake ninja`. Optional für die Prüfung des CI-Workflows: `brew install actionlint`. Die Test-ROMs sind klein und liegen als normale Dateien im Repo, ohne Git LFS (`docs/wissen/umgebung.md`).

```bash
# Nach dem Klonen und nach jedem Pull: Submodule der Kerne, fehlende oder
# veraltete Kerne bauen (Cores/Build/), Arcfold.xcodeproj erzeugen
Scripts/bootstrap.sh

# Nur prüfen, ob alle Kerne da und aktuell sind (läuft auch vor jedem xcodegen generate)
Scripts/bootstrap.sh --check

# Einen Kern von Hand bauen, etwa nach einer Änderung am Rezept
CMAKE_BUILD_PARALLEL_LEVEL=6 Scripts/build-core.sh mgba

# Bauen: Store und JIT für den Simulator, Store für ein Gerät ohne Signatur
xcodebuild build -project Arcfold.xcodeproj -scheme Store -destination 'generic/platform=iOS Simulator' -derivedDataPath build/DerivedData
xcodebuild build -project Arcfold.xcodeproj -scheme JIT -destination 'generic/platform=iOS Simulator' -derivedDataPath build/DerivedData
xcodebuild build -project Arcfold.xcodeproj -scheme Store -destination 'generic/platform=iOS' -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO

# Testen (ArcfoldTests, LibretroKitTests, RendererTests; ArcfoldUITests nur mit Store) auf dem
# Duo-Simulator mit iOS 27.1, ebenso mit -scheme JIT
xcodebuild test -project Arcfold.xcodeproj -scheme Store -destination 'platform=iOS Simulator,name=iPhone Duo,OS=27.1' -derivedDataPath build/DerivedData

# Alternative: iPhone 18 Pro mit iOS 27.2
xcodebuild test -project Arcfold.xcodeproj -scheme Store -destination 'platform=iOS Simulator,name=iPhone 18 Pro,OS=27.2' -derivedDataPath build/DerivedData

# Ein Spiel im Simulator starten (nur Debug-Build, nur Simulator): importiert wie der
# Datei-Import und startet; die Messzeilen des Debug-Overlays kommen alle 10 s ins Log
xcrun simctl launch <UDID> com.faentiver.arcfold -ArcfoldAutorun "$PWD/Tests/Fixtures/gba/selftest.gba"
xcrun simctl spawn <UDID> log stream --predicate 'subsystem == "com.faentiver.arcfold" AND category == "stats"'
xcrun simctl io <UDID> screenshot --display=1 shot.png   # Duo: 1 außen, 3 innen

# CI-Workflow prüfen (optional, braucht actionlint)
actionlint -ignore 'label "xcode-27" is unknown' .github/workflows/ci.yml
```

- Projekteinstellungen nur in `project.yml` ändern, danach `xcodegen generate`. `Arcfold.xcodeproj` wird nicht committet.
- Ein neuer Kern braucht ein Rezept in `Scripts/cores/` und einen Eintrag unter den Abhängigkeiten in `project.yml`; bootstrap baut ihn dann mit. Außerdem braucht er in `.github/workflows/ci.yml` den Submodul-Schritt („Fetch core sources“) und den Cache-Schlüssel („Compute core cache key“), bis die CI die Liste selbst aus `project.yml` liest (geplant für M3 zusammen mit dem Rezept-Haken für Unter-Submodule).
- Meldet Xcode „There is no XCFramework found at …/Cores/Build/…“, fehlt ein Kern: `Scripts/bootstrap.sh` ausführen.
- Der Duo-Simulator braucht die Runtime iOS 27.1; sie ist lokal installiert. Die Runtime iOS 27.2 schließt das Duo aus, für Tests mit iOS 27.2 dient deshalb das iPhone 18 Pro (siehe `docs/wissen/umgebung.md`).
- CI: `.github/workflows/ci.yml` auf dem Image `xcode-27`. Details und Kosten in `docs/wissen/bauen-und-ci.md`.

## Wissen

- `docs/PLAN.md`: Plan, Entscheidungen, Meilensteine
- `docs/adr/`: Architektur-Entscheidungen
- `docs/wissen/umgebung.md`: Werkzeuge, Versionen, Stolperfallen und wie man alles wieder entfernt
- `docs/wissen/bauen-und-ci.md`: bootstrap.sh, Stempel, XcodeGen, Eigenheiten von Xcode 27.2, GitHub Actions
- `docs/wissen/libretrokit.md`: Aufbau und Entscheidungen in LibretroKit, Takt, Environment, Batteriespeicher, Stolperfallen
- `docs/wissen/renderer.md`: Bildpostfach, Metal-Ansicht, Tonring in C, Audioausgabe, Stolperfallen
- `docs/wissen/app.md`: Bibliothek, Import, Spielansicht, Lebenszyklus, Eingabe, Debug-Overlay, Lizenzen, Stolperfallen
- `docs/wissen/psp-grafik.md`: PPSSPP als libretro-Kern bauen und hosten, Grafikwege, Stolperfallen (zu ADR 0001)
- `docs/wissen/ps2-jit.md`: PS2 mit JIT, StikDebug und TXM, Einbau in den JIT-Build, Anleitung für den Gerätetest (zu ADR 0002)
- `Spikes/`: Spike-Code aus M0 als Referenz, nicht Teil der App
