# Arcfold

## Status

- **Ziel:** Eine offene SwiftUI-App, die mehrere Konsolen emuliert und jedes System für den Falz des iPhone Duo auslegt.
- **Stand:** M0 (Fundament) läuft. Repo, Lizenz, Regeln und Plan stehen. Auf `m0/fundament`: Xcode-Projekt per XcodeGen mit den Schemes Store und JIT, die Pakete LibretroKit, FoldLayout und Renderer, mGBA 0.10.5 als eingebettetes, nicht gelinktes Framework, der mGBA-Test grün, CI-Workflow angelegt. Die Spikes zu PSP-Grafik und PS2-JIT laufen in eigenen Branches.
- **Nächster Schritt:** Pull Request von `m0/fundament` prüfen und den ersten CI-Lauf ansehen, Spikes abschließen (ADR 0001 und 0002), danach Abnahme durch Fatih. Für Tests im Duo-Simulator fehlt lokal die Runtime iOS 27.1.
- **Datum:** 6. November 2026

## Arbeitsregeln

- `docs/PLAN.md` vollständig lesen, bevor du Code schreibst. Die harten Regeln unten gelten immer.
- Meilenstein für Meilenstein arbeiten. Der nächste beginnt erst, wenn Fatih die Abnahme des vorigen bestätigt hat.
- Jede größere technische Entscheidung als ADR in `docs/adr/` festhalten: Kontext, Optionen, Entscheidung, Folgen.
- Weicht die Umsetzung vom Plan ab, `docs/PLAN.md` im selben Pull Request aktualisieren.
- Mit Fatih auf Deutsch, knapp und direkt. Code, Kommentare und Commit-Messages sind englisch.
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
Tests/          ArcfoldTests (Unit-Tests mit der App als Host), Fixtures/ (Homebrew-ROMs, Lizenzen)
docs/           PLAN.md, adr/, wissen/
```

## Bauen und Testen

Voraussetzungen: Xcode 27.1 oder neuer, dazu `brew install xcodegen cmake ninja`.

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

# Testen (ArcfoldTests und LibretroKitTests), ebenso mit -scheme JIT
xcodebuild test -project Arcfold.xcodeproj -scheme Store -destination 'platform=iOS Simulator,name=iPhone 18 Pro,OS=latest' -derivedDataPath build/DerivedData

# CI-Workflow prüfen
actionlint -ignore 'label "xcode-27" is unknown' .github/workflows/ci.yml
```

- Projekteinstellungen nur in `project.yml` ändern, danach `xcodegen generate`. `Arcfold.xcodeproj` wird nicht committet.
- Ein neuer Kern braucht ein Rezept in `Scripts/cores/` und einen Eintrag unter den Abhängigkeiten in `project.yml`. Mehr nicht, bootstrap baut ihn dann mit.
- Meldet Xcode „There is no XCFramework found at …/Cores/Build/…“, fehlt ein Kern: `Scripts/bootstrap.sh` ausführen.
- Der Duo-Simulator braucht die Runtime iOS 27.1. Die Runtime iOS 27.2 schließt das Duo aus, bis dahin auf einem anderen iPhone mit iOS 27.2 testen (siehe `docs/wissen/umgebung.md`).
- CI: `.github/workflows/ci.yml` auf dem Image `xcode-27`. Details und Kosten in `docs/wissen/bauen-und-ci.md`.

## Wissen

- `docs/PLAN.md`: Plan, Entscheidungen, Meilensteine
- `docs/adr/`: Architektur-Entscheidungen
- `docs/wissen/umgebung.md`: Werkzeuge, Versionen, Stolperfallen und wie man alles wieder entfernt
- `docs/wissen/bauen-und-ci.md`: bootstrap.sh, Stempel, XcodeGen, Eigenheiten von Xcode 27.2, GitHub Actions
- `docs/wissen/libretrokit.md`: Aufbau und Entscheidungen in LibretroKit, Stolperfallen
