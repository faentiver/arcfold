# Arcfold

## Status

- **Ziel:** Eine offene SwiftUI-App, die mehrere Konsolen emuliert und jedes System für den Falz des iPhone Duo auslegt.
- **Stand:** M0 (Fundament) läuft. Repo, Lizenz, Regeln und Plan stehen.
- **Nächster Schritt:** M0 fertigstellen (Xcode-Projekt, Pakete, mGBA als Framework, CI, Spikes zu PSP-Grafik und PS2-JIT), danach Abnahme durch Fatih.
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
App/            SwiftUI-App, erzeugt aus project.yml (XcodeGen)
Packages/       LibretroKit, FoldLayout, Renderer (lokale Swift-Pakete)
Cores/          Kerne als Git-Submodule, auf Tags oder Commits fixiert
Scripts/        build-core.sh und weitere Build-Skripte
Tests/          Homebrew-ROMs, Referenz-Prüfsummen
docs/           PLAN.md, adr/, wissen/
```

## Bauen und Testen

Folgt mit M0.

## Wissen

- `docs/PLAN.md`: Plan, Entscheidungen, Meilensteine
- `docs/adr/`: Architektur-Entscheidungen
- `docs/wissen/umgebung.md`: Werkzeuge, Versionen, Stolperfallen und wie man alles wieder entfernt
