# Arcfold

## Status

- **Ziel:** Eine offene SwiftUI-App, die mehrere Konsolen emuliert und jedes System für den Falz des iPhone Duo auslegt.
- **Stand:** M0 (Fundament), M1 (GBA läuft) und M2 (DS am Falz) sind abgenommen und auf `main`; ADR 0005 und ADR 0006 sind angenommen. M2 wurde am 10. November 2026 anhand des Pull Requests abgenommen. Das Repo ist seit 7. November 2026 öffentlich.

  M2 · DS am Falz (Plan, Abschnitt 10) ist im Duo-Simulator geprüft, auch mit echten Posen, mit den Nachbesserungen nach der Prüfung:
  - melonDS DS 1.4.0 als eingebettetes Framework ohne JIT, ohne Schlüsselmaterial des DSi und ohne Download von Nintendos Servern (Patch und Ersetzungen im Rezept ohne einen Schlüsselwert im Repo, Prüfung nach jedem Bau mit den Werten aus der unveränderten Quelle, Beleg aus dem Store-Bundle), DNS-Option so gesetzt, dass die erzeugte Firmware keinen Server nennt, Testprogramm `selftest.nds`, Lizenzbildschirm mit 24 Einträgen, allen Urhebern, Urhebervermerk und Quellort von Arcfold und Arcfolds Änderungen an melonDS DS und melonDS mit Datum,
  - FoldLayout mit Pose aus der Division-Region und Layouts für alle Posen, ein Mechanismus für DS und GBA, Schutzrand oben von 64 pt für alles, was Berührungen nimmt; Renderer mit einem Viewport je Bildschirm aus einer Textur,
  - Touchscreen pixelgenau über den libretro-Zeiger, Pause beim Zuklappen, Fortsetzen auf dem Außendisplay; ein Spiel ersetzt die Bibliothek im Fenster (`RootView`), weil ein Vollbild über ihr oben Berührungen verschluckte,
  - echte Posen im Simulator per Software (privates Werkzeug außerhalb des Repos, eingebunden über `POSE_CHECK_POSTURE_TOOL`): `Scripts/pose-check.sh` für DS und GBA ohne Lücke, Neusynchronisation oder Pause beim Wechsel, Zuklappen pausiert, Aufklappen läuft weiter, eine Szene für beide Displays; für UI-Tests zusätzlich eingespeiste Posen über `DebugRemote` (Debug-Build),
  - Builds Store und JIT ohne Warnung im eigenen Code, Tests grün (Store 249, JIT 229),
  - ADR 0006 angenommen, Belege in den Abschnitten „Umsetzung in M2“, „Nachbesserungen nach der Prüfung“ und „Posenprüfung per Software“.

  Die Liquid-Glass-Oberfläche (ADR 0007, aus M4 vorgezogen, vorgeschlagen) folgt als eigener Pull Request, Branch `m4/liquid-glass` (10. November 2026). Die Architektur von M2 gilt, Glas liefert das Aussehen: Bibliothek als Raster, Glastasten in den Zonen von FoldLayout in jeder Pose und für GBA und DS, Pause-Knopf aus Glas an der Stelle aus `GameLayout`, Pausenmenü als System-Sheet auch nach dem Zuklappen außen, Hinweise und Chip auf dem Bild (`OverlayPlacement` aus `GameLayout`). Kein Zoom von der Kachel ins Spiel, weil ein Spiel die Bibliothek ersetzt. Geprüft in jeder echten Pose mit dem privaten Posen-Werkzeug und der Bildschirmfoto-Tour (`Scripts/screenshot-tour.sh`, ADR 0007, Abschnitt „Zusammenführung mit M2“); Builds ohne Warnung im eigenen Code, Tests grün. Die Oberfläche wartet auf die Abnahme.
- **Nächster Schritt:** Abnahme der Liquid-Glass-Oberfläche durch Fatih anhand des Pull Requests von `m4/liquid-glass`; M3 · PSP (Plan, Abschnitt 10) darf beginnen. Offen bleibt der Gerätetest auf dem Duo für M1, M2 und ADR 0002 (`docs/wissen/geraetetest.md`). Die CI läuft vorerst nur auf manuellen Start (`workflow_dispatch`, `docs/wissen/bauen-und-ci.md`).
- **Datum:** 10. November 2026

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
- **Lizenzen.** Die ganze App steht unter GPL-3.0-or-later. Nur Kerne mit GPL-3.0-kompatibler Lizenz. Die Lizenzhinweise aller Kerne erscheinen in der App unter „Lizenzen“.
- **JIT nur im JIT-Build.** Der Store-Build darf keinen JIT-Code-Pfad enthalten.
- **Marken.** Kein Nintendo, PlayStation, PSP oder Duo im App-Namen oder Icon. Controller-Skins sind eigene Entwürfe ohne Original-Logos oder geschützte Tastensymbole. Kompatibilität darf sachlich im README stehen.
- **Keine Cover-Bilder** mitliefern oder automatisch laden. Nutzer können eigene Bilder setzen.
- **Store-Einreichung** erst, nachdem die Kern-Entwickler gefragt wurden, weil GPL und App Store als umstritten gelten.

## Aufbau

```
project.yml     Xcode-Projekt für XcodeGen (ADR 0004)
App/            SwiftUI-App: Quellen, String Catalog, Entitlements des JIT-Builds
Packages/       LibretroKit, FoldLayout, Renderer (lokale Swift-Pakete)
Cores/          Kerne als Git-Submodule, auf Tags oder Commits fixiert, melonds-ds-deps/ mit den Abhängigkeiten
                von melonDS DS; Build/ mit den xcframeworks (ignoriert)
Scripts/        bootstrap.sh, build-core.sh, cores/ mit einem Rezept je Kern, pose-check.sh, screenshot-tour.sh
Spikes/         Spike-Code aus M0 (PSPGPU, PS2JIT) als Referenz, nicht Teil der App
Tests/          ArcfoldTests (Unit-Tests mit der App als Host), ArcfoldUITests (auch GlassUITests und die
                ScreenshotTour, die nur über Scripts/screenshot-tour.sh läuft), Fixtures/ (Homebrew-ROMs, Lizenzen)
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

# Die Prüfungen nach jedem Bau ohne Bau wiederholen (Exporte, Importe, mmap, JIT-Spuren, Rezept)
Scripts/build-core.sh melondsds --check   # ebenso mgba

# Bauen: Store und JIT für den Simulator, Store für ein Gerät ohne Signatur
xcodebuild build -project Arcfold.xcodeproj -scheme Store -destination 'generic/platform=iOS Simulator' -derivedDataPath build/DerivedData
xcodebuild build -project Arcfold.xcodeproj -scheme JIT -destination 'generic/platform=iOS Simulator' -derivedDataPath build/DerivedData
xcodebuild build -project Arcfold.xcodeproj -scheme Store -destination 'generic/platform=iOS' -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO

# Testen (ArcfoldTests, LibretroKitTests, FoldLayoutTests, RendererTests; ArcfoldUITests nur mit Store, die
# Zustände der ScreenshotTour überspringen sich ohne Scripts/screenshot-tour.sh) auf dem
# Duo-Simulator mit iOS 27.1, ebenso mit -scheme JIT
xcodebuild test -project Arcfold.xcodeproj -scheme Store -destination 'platform=iOS Simulator,name=iPhone Duo,OS=27.1' -derivedDataPath build/DerivedData

# Alternative: iPhone 18 Pro mit iOS 27.2
xcodebuild test -project Arcfold.xcodeproj -scheme Store -destination 'platform=iOS Simulator,name=iPhone 18 Pro,OS=27.2' -derivedDataPath build/DerivedData

# Ein Spiel im Simulator starten (nur Debug-Build, nur Simulator): importiert wie der
# Datei-Import und startet; die Messzeilen des Debug-Overlays kommen alle 10 s ins Log
xcrun simctl launch <UDID> com.faentiver.arcfold -ArcfoldAutorun "$PWD/Tests/Fixtures/gba/selftest.gba"
xcrun simctl spawn <UDID> log stream --predicate 'subsystem == "com.faentiver.arcfold" AND category == "stats"'
xcrun simctl io <UDID> screenshot --display=1 shot.png   # Duo: 1 außen, 3 innen

# Seit M2, nur Debug-Build: Spielansicht mit Testmuster ohne Kern, künstlicher Falz beim Start
xcrun simctl launch <UDID> com.faentiver.arcfold -ArcfoldTestPattern ds -ArcfoldFoldOverride tabletop
# Posen bei laufendem Spiel (DebugRemote): fold.flat|book|tabletop|measured,
# hinge.closed|open, overlay.hide|show; Pose, Layout und Lücken stehen im Log (Kategorie fold)
xcrun simctl spawn <UDID> notifyutil -p com.faentiver.arcfold.debug.fold.tabletop
xcrun simctl spawn <UDID> log stream --predicate 'subsystem == "com.faentiver.arcfold" AND category == "fold"'

# Posenprüfung mit echten Posen (ADR 0006, Abschnitt 15). Per Software mit einem privaten
# Posen-Werkzeug außerhalb des Repos, das "<UDID> closed|open|book|tabletop
# [--orientation landscape-left] --quiet" versteht (je etwa 2 Minuten, docs/wissen/falz.md);
# außen quer stellt es mit "closed --orientation landscape-left"
POSE_CHECK_POSTURE_TOOL=<Werkzeug> Scripts/pose-check.sh ds    # danach gba
# Ohne Werkzeug (oder mit POSE_CHECK_HUB=1) fragt das Skript je Schritt nach dem Wechsel in
# Device Hub (je etwa 5 Minuten)
Scripts/pose-check.sh ds

# Bildschirmfoto-Tour der Oberfläche (ADR 0007): Varianten hell, dunkel, Kontrast, große Schrift
# und mit poses jede echte Pose des Duo, eingestellt mit dem privaten Posen-Werkzeug
# (POSE_CHECK_POSTURE_TOOL wie bei pose-check.sh; ohne die Variable überspringt der Teil poses
# mit einem Hinweis); ohne Argumente alles
POSE_CHECK_POSTURE_TOOL=<Werkzeug> Scripts/screenshot-tour.sh <UDID> <Ordner> [light dark contrast large poses]

# CI-Workflow prüfen (optional, braucht actionlint)
actionlint -ignore 'label "xcode-27" is unknown' .github/workflows/ci.yml
```

- Projekteinstellungen nur in `project.yml` ändern, danach `xcodegen generate`. `Arcfold.xcodeproj` wird nicht committet.
- Ein neuer Kern braucht ein Rezept in `Scripts/cores/` und einen Eintrag unter den Abhängigkeiten in `project.yml`; bootstrap baut ihn dann mit. Braucht er weitere Submodule des Repos, nennt das Rezept sie in `CORE_DEPENDENCIES`; bootstrap holt alle Submodule eines Kerns flach (`--depth 1`). Außerdem braucht er in `.github/workflows/ci.yml` seine Submodule im Schritt „Fetch core sources“ und im Cache-Schlüssel („Compute core cache key“), bis die CI die Liste selbst aus `project.yml` und den Rezepten liest (geplant für M3). Jeder Kern exportiert genau die 25 libretro-Funktionen. `build-core.sh` prüft nach jedem Bau jede Scheibe: die Exporte, die Importe (nichts, was Speicher ausführbar macht, Code lädt, ein Programm startet oder die Codesignatur lockert), jeden `mmap`-Aufruf (konstantes `prot` ohne `PROT_EXEC`, `flags` ohne `MAP_JIT`), rohe Systemaufrufe (`svc`) und JIT-Spuren in Symbolen und Zeichenketten, danach die Prüfungen des Rezepts über `core_check` (bei melonDS DS Schlüsselmaterial, `nintendowifi` und die KEY1-Tabelle der FreeBIOS). Schlägt eine fehl, bricht der Bau mit Exit 70 ab. `Scripts/build-core.sh <kern> --check` wiederholt sie ohne Bau an den Scheiben in `Cores/Build/` (`docs/wissen/bauen-und-ci.md`).
- Meldet Xcode „There is no XCFramework found at …/Cores/Build/…“, fehlt ein Kern: `Scripts/bootstrap.sh` ausführen.
- Der Duo-Simulator braucht die Runtime iOS 27.1; sie ist lokal installiert. Die Runtime iOS 27.2 schließt das Duo aus, für Tests mit iOS 27.2 dient deshalb das iPhone 18 Pro (siehe `docs/wissen/umgebung.md`).
- Echte Posen wechseln im Simulator Device Hub oder ein privates Posen-Werkzeug außerhalb des Repos, das `Scripts/pose-check.sh` über `POSE_CHECK_POSTURE_TOOL` einbindet. Es nutzt private Schnittstellen des Simulators und kommt deshalb nie ins Repo oder in die App; nach einem Update von Xcode oder der Runtime prüfen, ob es noch geht (`docs/wissen/falz.md`). UI-Tests können die Pose nicht selbst wechseln und nehmen `DebugRemote` (Darwin-Benachrichtigungen, nur Debug-Build); den Wechsel des Displays zeigt das nicht. Ein Vollbild über einem `NavigationStack` verschluckte nach einer Berührung der Oberkante alle späteren in den obersten 60 bis 70 pt; Spiele ersetzen deshalb die Bibliothek (`RootView`, `docs/wissen/falz.md`).
- CI: `.github/workflows/ci.yml` auf dem Image `xcode-27`. Die CI läuft vorerst nur auf manuellen Start (`workflow_dispatch`); Details und Kosten in `docs/wissen/bauen-und-ci.md`.

## Wissen

- `docs/PLAN.md`: Plan, Entscheidungen, Meilensteine
- `docs/adr/`: Architektur-Entscheidungen
- `docs/wissen/umgebung.md`: Werkzeuge, Versionen, Stolperfallen und wie man alles wieder entfernt
- `docs/wissen/bauen-und-ci.md`: bootstrap.sh, Stempel, XcodeGen, Eigenheiten von Xcode 27.2, GitHub Actions
- `docs/wissen/libretrokit.md`: Aufbau und Entscheidungen in LibretroKit, Takt, Environment, Batteriespeicher, Zeiger, Eigenheiten von mGBA und melonDS DS, Stolperfallen
- `docs/wissen/renderer.md`: Bildpostfach, Metal-Ansicht mit Viewports je Bildschirm, Tonring in C, Audioausgabe mit gerundeter Rate, Stolperfallen
- `docs/wissen/app.md`: Bibliothek, Import, Spielansicht mit Falz-Layouts, Touchscreen, Lebenszyklus mit Pause beim Zuklappen, Eingabe, Debug-Overlay, Debug-Start, Lizenzen, Gestaltung, Stolperfallen
- `docs/wissen/oberflaeche.md`: Liquid-Glass-Oberfläche (zu ADR 0007): Regeln R1 bis R9, Bausteine, Tokens, Messwerte der Tour auch in den echten Posen, Abweichungen, Zusammenführung mit M2, Stolperfallen
- `docs/wissen/falz.md`: Duo-APIs (Scharnier, reservierte Regionen, vertikale Leiste), Duo-Simulator, echte Posen per Software (privates Werkzeug über `POSE_CHECK_POSTURE_TOOL`) und mit Device Hub, Maße, FoldLayout, `DebugRemote`, Stolperfallen (zu ADR 0006)
- `docs/wissen/psp-grafik.md`: PPSSPP als libretro-Kern bauen und hosten, Grafikwege, Stolperfallen (zu ADR 0001)
- `docs/wissen/geraetetest.md`: Anleitung für alle ausstehenden Gerätetests auf dem Duo (M1, M2, ADR 0002), mit Kriterien
- `docs/wissen/ps2-jit.md`: PS2 mit JIT, StikDebug und TXM, Einbau in den JIT-Build, Anleitung für den Gerätetest (zu ADR 0002)
- `Spikes/`: Spike-Code aus M0 als Referenz, nicht Teil der App
