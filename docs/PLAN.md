# Projektplan: Multi-System-Emulator fürs iPhone Duo

Stand: 6. November 2026 · Owner: Fatih (GitHub: `faentiver`) · Arbeitsgrundlage für Claude Code

---

## 0. Arbeitsregeln für Claude Code

- Lies diesen Plan vollständig, bevor du Code schreibst. Die harten Regeln in Abschnitt 8 gelten immer.
- Arbeite Meilenstein für Meilenstein. Der nächste beginnt erst, wenn Fatih die Abnahme des vorigen bestätigt hat.
- Halte jede größere technische Entscheidung als ADR in `docs/adr/` fest: Kontext, Optionen, Entscheidung, Folgen.
- Weicht die Umsetzung vom Plan ab, aktualisiere `docs/PLAN.md` im selben Pull Request.
- Kommuniziere mit Fatih auf Deutsch, knapp und direkt. Code, Kommentare und Commit-Messages sind englisch.
- Der Projektname ist Arcfold, das Repo heißt `faentiver/arcfold`. Er lässt sich jederzeit ändern, dann Repo, Bundle-IDs und Texte gemeinsam umbenennen.

## 1. Ziel

Eine offene SwiftUI-App, die mehrere Konsolen emuliert und jedes System für den Falz des iPhone Duo auslegt. Das Alleinstellungsmerkmal: PSP und DS in einer App, beide fold-nativ, dazu ein Tabletop-Modus für PSP mit Bild oben und allen Tasten unten. Das Projekt dient Fatih zum Lernen und als Portfolio und soll später als Store-Build in den App Store.

## 2. Entscheidungen

| Thema | Entscheidung |
| --- | --- |
| Projekt | Weiter wie geplant, obwohl PPSSPP und Delta 2.0 das Duo inzwischen unterstützen |
| Name | Arcfold, gewählt am 6. November 2026 aus Arcfold, Foldplay, Twofold, Crease und Gatefold. Nur Arcfold ist im App Store (DE, US) und auf GitHub frei, „Foldplay“ ist schon eine Spiele-App. Jederzeit änderbar |
| Repo | `github.com/faentiver/arcfold`, GPL-3.0. Zunächst privat angelegt, öffentlich nach Fatihs Okay |
| Apple-Account | Vorerst kostenlose Apple-ID. Das Developer Program kommt später für TestFlight und Store |
| Ziel | Lernen und Portfolio, später App Store mit einem Store-Build ohne PS2 |
| Reihenfolge | GBA, DS, PSP, danach PS2 als JIT-Build, dann GB/GBC, NES, SNES, PS1 |
| Bauen und Testen | Claude Code auf dem Mac mini, zuerst im Duo-Simulator von Xcode 27.1 oder neuer. Installiert ist Xcode 27.2 mit iOS-SDK 27.2 |
| Tests auf dem Duo | Noch offen. Empfehlung: ab M0 mit kostenloser Apple-ID, weil der Simulator nichts über Bildrate, Wärme und JIT aussagt |
| Controller | Vorhanden |

## 3. Ausgangslage (Recherche, Anfang November 2026)

- **iPhone Duo:** Buch-Falz, innen 7,6 Zoll mit 1878 × 2670 px (etwa 1,42 : 1), außen 5,4 Zoll mit 1398 × 2034 px, A20 Pro, 12 GB RAM, ProMotion, iOS 27.
- **Falz-Zustand:** `onHingeChange` (SwiftUI) und `UIHingeInteraction` (UIKit) liefern den Zustand (zu, teilweise offen als `.partiallyOpen`, offen) und den Winkel live. `context.hinge` ist `nil` auf Geräten ohne Scharnier. Apple sieht diese API für Interaktionen und Effekte vor.
- **Falz-Layout (iOS 27.1):** `reservedRegions(kind: .division)` liefert den Falz als Rechteck und ist nur aktiv, wenn das Gerät geknickt ist. `ArrangementView` verteilt zwei Views um den Falz, als Split oder Overlay.
- **Posen:** zugeklappt, halb geklappt wie ein Buch, Tabletop (oben ansehen, unten bedienen), flach.
- **Simulator:** Xcode 27.1 simuliert das Duo mit Öffnen, Schließen, Drehen und Falten.
- **Apples Rat für Spiele:** lieber das Seitenverhältnis anpassen als Balken zeigen.
- **PPSSPP:** Duo-Support für Ränder und Touch-Steuerung am 26. Oktober gemergt, Meilenstein 1.21, nur im Simulator getestet. Posen-Layouts sind nicht bekannt.
- **Delta 2.0:** seit 22. Oktober DS-Modus mit Falz. Kein PSP.
- **3DS:** Folium ist der einzige 3DS-Emulator im App Store, ohne Duo-Anpassung.
- **PS2:** JIT ist praktisch Pflicht. Play! stürzt ohne JIT ab, Provenance startet PS2 nur mit JIT. iPSX2, ein Port von ARMSX2, gibt es nur per Sideloading und mit eigenem BIOS-Dump.
- **JIT:** im App Store verboten. PSP läuft laut PPSSPP trotzdem in voller Geschwindigkeit. Per Sideloading geht JIT unter iOS 26 und 27 nur über StikDebug und bisher nur mit wenigen gelisteten Apps. Voraussetzungen sind `get-task-allow`, eine Pairing-Datei und LocalDevVPN.
- **App Store:** Emulatoren dürfen Spiele zum Download anbieten (Richtlinie 4.7). Ausführbaren Code nachladen ist verboten, die App muss in sich geschlossen sein (2.5.2).

## 4. Umfang

**Ziele für Version 1**

- Mehrere Systeme in einer App, mit einer Bibliothek, einheitlichen Spielständen und Einstellungen.
- Fold-nativ von Anfang an: ein Layout pro System und Pose, der Wechsel passiert ohne Neustart.
- PSP im Tabletop-Modus mit Bild oben und allen Tasten unten.
- DS mit beiden Bildschirmen am Falz und pixelgenauem Touch.
- PS2 als eigener JIT-Build per Sideloading.
- Liquid-Glass-Oberfläche, Controller-Support und Haptik.
- Läuft auch auf anderen iPhones, das Duo bleibt die Referenz.

**Nicht-Ziele für Version 1**

- Kein eigener Emulationskern. CPU- und Grafik-Emulation kommen aus den Kernen.
- Keine Spiele, BIOS-Dateien oder Download-Links in App oder Repo.
- Kein 3DS und kein N64. Beide brauchen ohne JIT viel Leistung und werden erst nach Version 1 gemessen.
- Kein Netplay, keine Cheats, keine Cloud-Synchronisierung.

## 5. Architektur

```
App (SwiftUI)
  Bibliothek      Import über die Dateien-App, Spielstände, Einstellungen
  Spielansicht    Bild und Touch-Tasten, pausiert beim Zuklappen
  FoldLayout      Pose und Falz-Rechteck -> Rechtecke für Bild und Tasten

Laufzeit (lokale Swift-Pakete)
  LibretroKit     Emulations-Thread, Takt, Spielstände, lädt die Kerne
  Renderer        Metal für das Bild, Audio-Ausgabe
  Eingabe         Touch-Overlay, GameController, Haptik

Kerne (C/C++, je ein Framework, angesprochen über die Libretro-API)
  mGBA, melonDS, PPSSPP, Play!, SameBoy, Mesen 2, bsnes, PCSX ReARMed
```

Ablauf: Die Spielansicht startet und pausiert LibretroKit. LibretroKit ruft den Kern über die Libretro-API auf und reicht Bild und Ton an den Renderer. FoldLayout liefert der Spielansicht die Rechtecke für die aktuelle Pose.

Technische Leitplanken:

1. **Ein Kern pro Framework.** Alle Libretro-Kerne exportieren dieselben Funktionsnamen (`retro_run` usw.). Jeder Kern wird deshalb ein eigenes dynamisches Framework im App-Bundle, das LibretroKit beim Spielstart per `dlopen` aus `Bundle.main.privateFrameworksURL` lädt.
2. **Zwei Build-Varianten.** Scheme `Store` ohne JIT und ohne PS2. Scheme `JIT` für Sideloading, mit PS2 und freigeschalteten Rekompilierern, gesteuert über das Compiler-Flag `JIT_BUILD`.
3. **Callbacks ohne Kontext.** Die Libretro-Callbacks haben keinen User-Data-Zeiger. Es gibt daher genau einen aktiven Kern, und statische Trampolin-Funktionen leiten an die aktive Host-Instanz weiter.
4. **Eigener Emulations-Thread.** Der Kern läuft nie auf dem Main Thread. Der Takt kommt aus `retro_get_system_av_info` und ist unabhängig von den 120 Hz des Displays.
5. **Bild.** Software-Kerne liefern einen Pixelpuffer (RGB565 oder XRGB8888), den der Renderer als Metal-Textur in ganzen Vielfachen skaliert. GPU-Kerne (PSP, PS2) brauchen einen HW-Render-Kontext über `RETRO_ENVIRONMENT_SET_HW_RENDER`: Vulkan über MoltenVK oder OpenGL ES, Entscheidung in ADR 0001.
6. **Ton.** Samples landen in einem lock-freien Ringpuffer, den ein `AVAudioSourceNode` abspielt. Leichtes dynamisches Resampling gleicht Taktunterschiede aus.
7. **Eingabe.** Touch-Overlay und GameController-Framework schreiben in einen gemeinsamen Eingabezustand, den der Kern über `input_state` abfragt.
8. **Spielstände.** Batteriespeicher über `retro_get_memory_data(RETRO_MEMORY_SAVE_RAM)`, Save States über `retro_serialize`, jeweils mit Vorschaubild.
9. **FoldLayout.** Liest `onHingeChange` und `reservedRegions(kind: .division)` und berechnet pro System die Rechtecke. Wechsel sind animiert, die Emulation läuft weiter.
10. **Plattform.** Deployment-Target iOS 27.0, Duo-APIs hinter `if #available(iOS 27.1, *)`. Swift 6 mit Strict Concurrency.

## 6. Systeme und Kerne

| Meilenstein | System | Kern | Lizenz | BIOS | Bildausgabe | Risiko |
| --- | --- | --- | --- | --- | --- | --- |
| M1 | GBA | [mGBA](https://github.com/mgba-emu/mgba) | MPL-2.0 | nicht nötig, eingebauter Ersatz | Software | niedrig |
| M2 | DS | [melonDS](https://github.com/melonDS-emu/melonDS) | GPL-3.0 | nicht nötig, freier Ersatz; DSi braucht echtes BIOS | Software | mittel |
| M3 | PSP | [PPSSPP](https://github.com/hrydgard/ppsspp) | GPL-2.0 oder später | nicht nötig | GPU über Vulkan oder OpenGL ES | hoch |
| nach M3, JIT-Build | PS2 | [Play!](https://github.com/jpd002/Play-), Alternative [ARMSX2](https://github.com/ARMSX2/ARMSX2) | Play!: BSD, ARMSX2: GPL-3.0 | Play!: nicht nötig, eingebauter Ersatz; ARMSX2: eigener Dump | GPU | sehr hoch, nur mit JIT |
| M5 | GB, GBC | [SameBoy](https://github.com/LIJI32/SameBoy) | MIT | nicht nötig, eigene Boot-ROMs | Software | niedrig |
| M5 | NES | [Mesen 2](https://github.com/SourMesen/Mesen2) | GPL-3.0 | nicht nötig | Software | niedrig |
| M5 | SNES | [bsnes](https://github.com/bsnes-emu/bsnes) | GPL-3.0 oder später | nur für Spiele mit Spezialchips | Software | mittel |
| M5 | PS1 | [PCSX ReARMed](https://github.com/libretro/pcsx_rearmed) | GPL-2.0 oder später | optional, eingebauter Ersatz | Software | mittel |

Play! bringt eine Libretro-Oberfläche (`Source/ui_libretro`) und ein iOS-Frontend mit, ARMSX2 einen Libretro-Kern (`pcsx2-libretro`). Ob Mesen 2 eine passende Libretro-Schnittstelle hat, wird in M5 geprüft, sonst kommt der Vorgänger Mesen zum Einsatz.

Ausgeschlossen: snes9x (nur nicht-kommerziell), Genesis Plus GX (keine kommerzielle Nutzung), Gambatte (nur GPL-2.0, nicht mit GPL-3.0 kombinierbar). Alle Lizenzen wurden direkt in den Repos geprüft.

## 7. Duo-Layouts

| System | Zugeklappt | Flach aufgeklappt | Tabletop |
| --- | --- | --- | --- |
| PSP | Bild groß, Tasten am Rand | Bild über die ganze Breite, 5-fach (2400 × 1360 px), Tasten seitlich | Bild oben, alle Tasten unten. Gibt es so bisher in keiner App |
| DS | Beide Bildschirme klein, Tasten über dem Bild | Oben und unten am Falz getrennt, Tasten seitlich | Oberer Bildschirm 6-fach in der oberen Hälfte (1536 × 1152 von 1878 × 1335 px), Touch und Tasten unten |
| GBA und weitere | Wie PSP, im Seitenverhältnis des Systems | Wie PSP | Bild oben, Tasten unten |

- Zuklappen während des Spiels pausiert wie beim DS. Fortsetzen geht dann auf dem Außendisplay.
- Halb geklappt wie ein Buch wird in Version 1 wie flach behandelt.
- Skaliert wird in ganzen Vielfachen, damit Pixel scharf bleiben. Die Pixelzahlen oben sind eigene Rechnungen aus der Panel-Auflösung.

## 8. Harte Regeln

- **Keine Spiele und kein BIOS.** Niemals ROMs, ISOs, BIOS-Dateien, Firmware oder Schlüssel ins Repo oder in die App, auch keine Download-Links. Tests nur mit frei lizenzierten Homebrew-ROMs, deren Lizenzen in `Tests/Fixtures/LICENSES.md` stehen.
- **Kein nachgeladener Code.** Alle Kerne stecken fest im App-Bundle (Richtlinie 2.5.2).
- **Lizenzen.** Die ganze App steht unter GPL-3.0. Nur Kerne mit GPL-3.0-kompatibler Lizenz. Die Lizenzhinweise aller Kerne erscheinen in der App unter „Lizenzen".
- **JIT nur im JIT-Build.** Der Store-Build darf keinen JIT-Code-Pfad enthalten.
- **Marken.** Kein Nintendo, PlayStation, PSP oder Duo im App-Namen oder Icon. Controller-Skins sind eigene Entwürfe ohne Original-Logos oder geschützte Tastensymbole. Kompatibilität darf sachlich im README stehen.
- **Keine Cover-Bilder** mitliefern oder automatisch laden. Nutzer können eigene Bilder setzen.
- **Store-Einreichung** erst, nachdem die Kern-Entwickler gefragt wurden, weil GPL und App Store als umstritten gelten.

## 9. Repo-Struktur und Konventionen

```
<repo>/
├── App/                 SwiftUI-App, erzeugt aus project.yml (XcodeGen)
├── Packages/
│   ├── LibretroKit/     Emulations-Thread, Libretro-Brücke, Spielstände
│   ├── FoldLayout/      Posen, Falz-Rechteck, Layouts je System
│   └── Renderer/        Metal für das Bild, Audio-Ausgabe
├── Cores/               Kerne als Git-Submodule, auf Tags oder Commits fixiert
├── Scripts/             build-core.sh und weitere Build-Skripte
├── Tests/               Homebrew-ROMs, Referenz-Prüfsummen
├── docs/
│   ├── PLAN.md          dieser Plan
│   └── adr/             Architektur-Entscheidungen
├── CLAUDE.md
└── LICENSE              GPL-3.0
```

- Das Xcode-Projekt entsteht per XcodeGen aus `project.yml` (Vorschlag), damit es textbasiert und im Review lesbar bleibt.
- Gearbeitet wird in Branches `m<Nummer>/<thema>` mit Pull Requests, die Fatih am iPhone prüfen kann.
- Commit-Messages im Stil von Conventional Commits.
- Tests: Emulation ist deterministisch. Unit-Tests prüfen deshalb die Bild-Prüfsumme nach einer festen Zahl Frames.
- CI: GitHub Actions baut für den Simulator und führt die Tests aus, sobald Xcode 27.1 auf den gehosteten Runnern verfügbar ist. Bis dahin baut der Mac mini lokal.
- Debug-Overlay mit Bildrate, Audio-Aussetzern und `ProcessInfo.thermalState`, damit Abnahmen auf Messwerten stehen.

## 10. Meilensteine

Jeder Meilenstein endet mit einer Abnahme durch Fatih. Bildrate und Wärme zählen nur auf dem Duo, weil der Simulator auf dem Chip des Macs läuft.

### M0 · Fundament

1. Repo anlegen mit `gh repo create faentiver/arcfold`, zunächst mit `--private`, öffentlich nach Fatihs Okay. Dazu GPL-3.0-`LICENSE`, kurzes `README.md`, `.gitignore` für Swift und Xcode, `CLAUDE.md` mit den Regeln aus Abschnitt 0 und 8, dieser Plan als `docs/PLAN.md`.
2. `project.yml` für XcodeGen: App-Target, Deployment-Target iOS 27.0, Swift 6, Schemes `Store` und `JIT`.
3. Lokale Pakete `LibretroKit` (mit C-Target für `libretro.h`), `FoldLayout` und `Renderer` anlegen.
4. mGBA als Submodul unter `Cores/`. `Scripts/build-core.sh <kern>` baut ein `.xcframework` mit dynamischem Framework für Gerät und Simulator (arm64).
5. LibretroKit lädt das Framework per `dlopen` und ruft `retro_get_system_info` auf. Ein Unit-Test prüft `library_name`.
6. GitHub-Actions-Workflow für Simulator-Build und Tests anlegen.
7. Spike PSP-Grafik: PPSSPP-Libretro-Kern für iOS bauen, HW-Render mit Vulkan über MoltenVK gegen OpenGL ES vergleichen. Ergebnis in ADR 0001.
8. Spike PS2-JIT, braucht das Duo: Play!-Libretro-Kern bauen, JIT per StikDebug unter iOS 27 prüfen. Ergebnis in ADR 0002.

**Abnahme:** Build grün, mGBA-Test grün, ADR 0001 und 0002 geschrieben.

### M1 · GBA läuft

Emulations-Thread mit Takt, Metal-Bild, Ton, Touch-Overlay, GameController, Import über `.fileImporter`, Batteriespeicher, Debug-Overlay.

**Abnahme:** Homebrew-ROM läuft stabil mit 60 fps, Ton ohne Knacken, Speicherstand überlebt einen Neustart.

### M2 · DS am Falz

melonDS-Kern. Der Kern liefert beide Bildschirme in einem Puffer, der Renderer teilt ihn in zwei Texturen. Touch-Abbildung auf den unteren Bildschirm, FoldLayout mit `onHingeChange` und `reservedRegions`, Layouts für alle Posen, Pause beim Zuklappen.

**Abnahme:** Touch pixelgenau, Posenwechsel ohne Ruckler und ohne Emulationsstopp, alle Posen im Duo-Simulator geprüft.

### M3 · PSP

PPSSPP-Kern mit dem GPU-Weg aus ADR 0001, PSP-Layouts inklusive Tabletop, Leistungsoptimierung.

**Abnahme:** volle Geschwindigkeit in einer anspruchsvollen Homebrew-Demo, 30 Minuten ohne thermische Drosselung auf dem Duo.

### PS2 · JIT-Build (nach M3, parallel zu M4 und M5)

Play!-Kern nur im Scheme `JIT`, JIT-Aktivierung gemäß ADR 0002, GPU-Weg aus M3, PS2-Layouts, Anleitung zum Sideloading im README.

**Abnahme:** Homebrew läuft flüssig mit JIT auf dem Duo.

### M4 · Feinschliff

Liquid-Glass-Oberfläche mit `.glassEffect` und `GlassEffectContainer`, Save States mit Vorschaubild, eigene Controller-Skins, Tastenbelegung, Haptik, Einstellungen.

**Abnahme:** Fatihs Okay.

### M5 · Mehr Systeme

Einzeln nacheinander: SameBoy (GB, GBC), Mesen 2 (NES), bsnes (SNES), PCSX ReARMed (PS1).

**Abnahme je System:** wie M1, dazu eigene Layouts für alle Posen.

### M6 · Release

README mit Screenshots, Lizenzhinweise, Sideloading-Anleitung für den JIT-Build, Entscheidung über den Store nach Rückfrage bei den Kern-Entwicklern.

**Abnahme:** Tag `v1.0`.

### Nebenbei · Beitrag zu PPSSPP

Fork von `hrydgard/ppsspp`, Tabletop-Layout über `UIHingeInteraction`, Test auf dem echten Duo, Pull Request an das Original-Projekt. Unabhängig vom Hauptprojekt und jederzeit möglich.

## 11. Risiken

| Risiko | Folge | Gegenmaßnahme |
| --- | --- | --- |
| PSP-Grafik im eigenen Host | M3 verzögert sich stark | Spike in M0, Ausweg über PPSSPPs Software-Renderer |
| Gleiche Funktionsnamen aller Kerne | Kerne lassen sich nicht zusammen linken | Jeder Kern als eigenes Framework, zur Laufzeit geladen |
| Delta und PPSSPP decken schon viel ab | Weniger Nutzer als erhofft | Fokus auf PSP und DS gemeinsam plus Tabletop. Als Lern- und Portfolio-Projekt lohnt es sich so oder so |
| Kein JIT im Store | Schwere Systeme zu langsam, PS2 gar nicht | Store-Build nur mit Systemen, die per Interpreter flüssig laufen. PS2 nur im JIT-Build, Test in M0 |
| JIT unter iOS 27 unzuverlässig | PS2 startet nicht | ADR 0002 vor jeder PS2-Arbeit, Play! als Kern ohne BIOS-Zwang |
| GPL und App Store | Keine Store-Veröffentlichung | Erst eigene Geräte, vor einer Einreichung die Kern-Entwickler fragen |
| Neue Duo-APIs, lückenhafte Doku | Verhalten weicht ab | Hinter `#available(iOS 27.1, *)` kapseln, früh auf dem Duo testen |
| Knacken im Ton, unruhiger Takt bei 120 Hz | Spielgefühl leidet | Eigener Takt je Kern, Resampling, Messwerte im Debug-Overlay |
| Wärme und Akku | Lange Sessions brechen ein | Messung in jedem Meilenstein, Bildraten-Begrenzer |
| Markenrecht | Abmahnung oder Ablehnung | Neutraler Name, eigene Skins, keine Logos |
| Der Umfang wächst | Nichts wird fertig | Abnahme pro Meilenstein, das nächste System erst danach |

## 12. Offene Punkte

- [x] Projektname festlegen (englisch), danach App Store und GitHub auf Konflikte prüfen. Ergebnis: Arcfold, geprüft am 6. November 2026.
- [ ] Repo öffentlich schalten (Fatihs Okay).
- [ ] Tests auf dem Duo schon ab M0 mit kostenloser Apple-ID?
- [ ] Libretro-Schnittstelle von Mesen 2 prüfen (M5).

## 13. Quellen

- [Tom's Guide: iPhone Duo, Preis und technische Daten](https://www.tomsguide.com/phones/iphones/iphone-duo-is-official-price-release-date-specs-and-everything-you-need-to-know)
- [Blake Crosley: iPhone Duo for Developers](https://blakecrosley.com/blog/iphone-duo-for-developers)
- [Apple Tech Talk 111464: Leverage multiple displays and scenes on iPhone Duo](https://developer.apple.com/videos/play/tech-talks/111464/)
- [Apple Tech Talk 111463: Strike a pose with adaptive layouts on iPhone Duo](https://developer.apple.com/videos/play/tech-talks/111463/)
- [PPSSPP Issue #22762](https://github.com/hrydgard/ppsspp/issues/22762) und [PR #22788](https://github.com/hrydgard/ppsspp/pull/22788)
- [PPSSPP für iOS](https://ppsspp.org/docs/reference/ios-support)
- [heldgames: DS und 3DS auf dem iPhone Duo](https://heldgames.com/guides/iphone-duo-ds-3ds-emulation)
- [iTechGuides: PS2-Emulation auf dem iPhone](https://www.itechguides.com/ps2-emulation-on-iphone-which-apps-work-and-what-you-need-to-know/)
- [Pocket Gaming: iPSX2 auf iOS](https://pocket-gaming.org/2026/03/22/how-to-play-ps2-games-on-ios-the-ultimate-ipsx2-setup-guide/)
- [SideStore-Doku: JIT aktivieren](https://docs.sidestore.io/docs/advanced/jit)
- [App Store Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
