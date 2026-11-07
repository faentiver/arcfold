# Projektplan: Multi-System-Emulator fürs iPhone Duo

Stand: 7. November 2026 · Owner: Fatih (GitHub: `faentiver`) · Arbeitsgrundlage für Claude Code

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
| Repo | `github.com/faentiver/arcfold`, GPL-3.0, privat. Öffentlich wird es erst, wenn die App an andere geht, denn erst dann verlangt die GPL den Quellcode für die Empfänger (Fatih, 6. November 2026) |
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
- **Simulator:** Xcode 27.1 simuliert das Duo mit Öffnen, Schließen, Drehen und Falten. Der Duo-Simulator braucht die Runtime iOS 27.1; die Runtime iOS 27.2 (24B8117) schließt das Duo aus (Stand 6. November 2026, `docs/wissen/umgebung.md`).
- **Apples Rat für Spiele:** lieber das Seitenverhältnis anpassen als Balken zeigen.
- **PPSSPP:** Duo-Support für Ränder und Touch-Steuerung am 26. Oktober gemergt, Meilenstein 1.21, nur im Simulator getestet. Posen-Layouts sind nicht bekannt.
- **Delta 2.0:** seit 22. Oktober DS-Modus mit Falz. Kein PSP.
- **3DS:** Folium ist der einzige 3DS-Emulator im App Store, ohne Duo-Anpassung.
- **PS2:** JIT ist praktisch Pflicht. Play! lehnt ohne JIT über `RETRO_ENVIRONMENT_GET_JIT_CAPABLE` sauber ab und stürzt nur ab, wenn das Frontend darauf nicht antwortet (Spike M0, ADR 0002). Provenance startet PS2 nur mit JIT. iPSX2, ein Port von ARMSX2, gibt es nur per Sideloading und mit eigenem BIOS-Dump.
- **JIT:** im App Store verboten. PSP läuft laut PPSSPP trotzdem in voller Geschwindigkeit. Per Sideloading geht JIT unter iOS 26 und 27 nur über StikDebug. Voraussetzungen sind `get-task-allow`, eine Pairing-Datei und LocalDevVPN. Die App-Liste von StikDebug ist eine Empfehlung, keine Sperre. Auf Geräten mit TXM (A15 und neuer, also auch beim Duo) muss die App das Haltepunkt-Protokoll von StikDebug umsetzen. Ob der Debugger während des Spielens verbunden bleiben muss, klärt der Gerätetest aus ADR 0002.
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
5. **Bild.** Software-Kerne liefern einen Pixelpuffer (RGB565 oder XRGB8888), den der Renderer als Metal-Textur in ganzen Vielfachen skaliert. GPU-Kerne (PSP, PS2) brauchen einen HW-Render-Kontext über `RETRO_ENVIRONMENT_SET_HW_RENDER`. PSP: Vulkan über MoltenVK, das Bild kommt als `MTLTexture` in den Renderer, der Software-Renderer bleibt als Ausweg (ADR 0001). Für PSP bekommt LibretroKit keinen OpenGL-ES-Code (ADR 0001). PS2: Play!s libretro-Kern kann nur OpenGL ES 3. Wo der OpenGL-ES-3-Kontext für Play! entsteht (LibretroKit, `App/JIT` oder ein eigenes Paket), wird vor der PS2-Spur entschieden (ADR 0002).
6. **Ton.** Samples landen in einem lock-freien Ringpuffer, den ein `AVAudioSourceNode` mit einem Echtzeit-Render-Block in C abspielt. Taktunterschiede gleicht kein Resampling aus: Die Emulation folgt der Tonuhr, indem der Füllstand des Puffers die Bildperiode um höchstens ±0,5 % trimmt (ADR 0005, vorgeschlagen).
7. **Eingabe.** Touch-Overlay und GameController-Framework schreiben in einen gemeinsamen Eingabezustand, den der Kern über `input_state` abfragt.
8. **Spielstände.** Batteriespeicher über `retro_get_memory_data(RETRO_MEMORY_SAVE_RAM)`, Save States über `retro_serialize`, jeweils mit Vorschaubild.
9. **FoldLayout.** Liest `onHingeChange` und `reservedRegions(kind: .division)` und berechnet pro System die Rechtecke. Wechsel sind animiert, die Emulation läuft weiter.
10. **Plattform.** Deployment-Target iOS 27.0, Duo-APIs hinter `if #available(iOS 27.1, *)`. Swift 6 mit Strict Concurrency.

## 6. Systeme und Kerne

| Meilenstein | System | Kern | Lizenz | BIOS | Bildausgabe | Risiko |
| --- | --- | --- | --- | --- | --- | --- |
| M1 | GBA | [mGBA](https://github.com/mgba-emu/mgba) | MPL-2.0 | nicht nötig, eingebauter Ersatz | Software | niedrig |
| M2 | DS | [melonDS](https://github.com/melonDS-emu/melonDS) | GPL-3.0 | nicht nötig, freier Ersatz; DSi braucht echtes BIOS | Software | mittel |
| M3 | PSP | [PPSSPP](https://github.com/hrydgard/ppsspp) | GPL-2.0 oder später; der gebaute Kern steht wegen gebündelter Teile effektiv unter GPL-3.0 (ADR 0001) | nicht nötig | GPU über Vulkan mit MoltenVK, Ausweg Software-Renderer (ADR 0001) | mittel, Spike bestanden |
| nach M3, JIT-Build | PS2 | [Play!](https://github.com/jpd002/Play-), Alternative [ARMSX2](https://github.com/ARMSX2/ARMSX2) | Play!: BSD, ARMSX2: GPL-3.0 | Play!: nicht nötig, eingebauter Ersatz; ARMSX2: eigener Dump | GPU über OpenGL ES 3 (ADR 0002) | sehr hoch, nur mit JIT |
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
- **Lizenzen.** Die ganze App steht unter GPL-3.0. Nur Kerne mit GPL-3.0-kompatibler Lizenz. Die Lizenzhinweise aller Kerne erscheinen in der App unter „Lizenzen“.
- **JIT nur im JIT-Build.** Der Store-Build darf keinen JIT-Code-Pfad enthalten.
- **Marken.** Kein Nintendo, PlayStation, PSP oder Duo im App-Namen oder Icon. Controller-Skins sind eigene Entwürfe ohne Original-Logos oder geschützte Tastensymbole. Kompatibilität darf sachlich im README stehen.
- **Keine Cover-Bilder** mitliefern oder automatisch laden. Nutzer können eigene Bilder setzen.
- **Store-Einreichung** erst, nachdem die Kern-Entwickler gefragt wurden, weil GPL und App Store als umstritten gelten.

## 9. Repo-Struktur und Konventionen

```
<repo>/
├── project.yml          XcodeGen-Spezifikation, aus ihr entsteht nur Arcfold.xcodeproj (nicht im Repo)
├── App/                 SwiftUI-App: Quellen, String Catalog, Entitlements des JIT-Builds
├── Packages/
│   ├── LibretroKit/     Emulations-Thread, Libretro-Brücke, Spielstände
│   ├── FoldLayout/      Posen, Falz-Rechteck, Layouts je System
│   └── Renderer/        Metal für das Bild, Audio-Ausgabe
├── Cores/               Kerne als Git-Submodule, auf Tags oder Commits fixiert; Build/ mit den xcframeworks (ignoriert)
├── Scripts/             bootstrap.sh, build-core.sh, cores/ mit einem Rezept je Kern
├── Spikes/              Spike-Code aus M0 als Referenz, nicht Teil der App
├── Tests/               ArcfoldTests (Unit-Tests mit der App als Host), ArcfoldUITests, Fixtures/ (Homebrew-ROMs, Lizenzen)
├── docs/
│   ├── PLAN.md          dieser Plan
│   ├── adr/             Architektur-Entscheidungen
│   └── wissen/          Projektwissen: Stand, Stolperfallen, Anleitungen
├── .github/
│   └── workflows/ci.yml CI mit GitHub Actions
├── CLAUDE.md
├── README.md
└── LICENSE              GPL-3.0
```

- Das Xcode-Projekt entsteht per XcodeGen aus `project.yml` (ADR 0004), damit es textbasiert und im Review lesbar bleibt. `Scripts/bootstrap.sh` baut vorher die eingebetteten Kerne.
- Gearbeitet wird in Branches `m<Nummer>/<thema>` mit Pull Requests, die Fatih am iPhone prüfen kann.
- Commit-Messages im Stil von Conventional Commits.
- Tests: Emulation ist deterministisch. Unit-Tests prüfen deshalb die Bild-Prüfsumme nach einer festen Zahl Frames. Für GBA dient das eigene Testprogramm `Tests/Fixtures/gba/selftest.gba` (Bild, Ton, Eingabe, Batteriespeicher); die Kern-Tests laufen kopflos ohne Echtzeittakt, UI-Tests in `ArcfoldUITests` (ADR 0005). Bei PSP geht das nur auf dem Vulkan- oder Software-Weg, OpenGL ES ist im Simulator nicht bitgenau (ADR 0001). Auch PS2 ist im Simulator nur mit Toleranz vergleichbar, weil Play! nur über OpenGL ES rendert (ADR 0002).
- CI: GitHub Actions baut für den Simulator und führt die Tests aus. Das Vorschau-Image `xcode-27` hat inzwischen Xcode 27.1 und den Duo-Simulator mit iOS 27.1 (Image vom 26. Oktober 2026), darauf läuft der Workflow. Fehlt Xcode 27.1 auf dem Runner, meldet der Job das und überspringt den Rest; dann baut der Mac mini lokal. Solange das Repo privat ist, zählt jede macOS-Minute zehnfach. Die CI läuft deshalb nur bei Pull Requests und auf manuellen Start.
- Debug-Overlay mit Bildrate, Audio-Aussetzern und `ProcessInfo.thermalState`, damit Abnahmen auf Messwerten stehen.

## 10. Meilensteine

Jeder Meilenstein endet mit einer Abnahme durch Fatih. Bildrate und Wärme zählen nur auf dem Duo, weil der Simulator auf dem Chip des Macs läuft.

### M0 · Fundament

1. Repo anlegen mit `gh repo create faentiver/arcfold --private`. Öffentlich wird es erst, wenn die App an andere geht. Dazu GPL-3.0-`LICENSE`, kurzes `README.md`, `.gitignore` für Swift und Xcode, `CLAUDE.md` mit den Regeln aus Abschnitt 0 und 8, dieser Plan als `docs/PLAN.md`.
2. `project.yml` für XcodeGen: App-Target, Deployment-Target iOS 27.0, Swift 6, Schemes `Store` und `JIT`.
3. Lokale Pakete `LibretroKit` (mit C-Target für `libretro.h`), `FoldLayout` und `Renderer` anlegen.
4. mGBA als Submodul unter `Cores/`. `Scripts/build-core.sh <kern>` baut ein `.xcframework` mit dynamischem Framework für Gerät und Simulator (arm64).
5. LibretroKit lädt das Framework per `dlopen` und ruft `retro_get_system_info` auf. Ein Unit-Test prüft `library_name`.
6. GitHub-Actions-Workflow für Simulator-Build und Tests anlegen.
7. Spike PSP-Grafik: PPSSPP-Libretro-Kern für iOS bauen, HW-Render mit Vulkan über MoltenVK gegen OpenGL ES vergleichen. Ergebnis in ADR 0001.
8. Spike PS2-JIT, braucht das Duo: Play!-Libretro-Kern bauen, JIT per StikDebug unter iOS 27 prüfen. Ergebnis in ADR 0002.

**Abnahme:** Build grün, mGBA-Test grün, ADR 0001 und 0002 geschrieben.

Abgenommen am 6. November 2026. Schritte 1 bis 7 sind erledigt, Schritt 8 ist im Simulator erledigt. Der Gerätetest aus ADR 0002 steht aus, bis das Duo für Tests eingerichtet ist.

### M1 · GBA läuft

Emulations-Thread mit Takt, Metal-Bild, Ton, Touch-Overlay, GameController, Import über `.fileImporter`, Batteriespeicher, Debug-Overlay. Dazu der Bildschirm „Lizenzen“ mit Arcfold (GPL-3.0), mGBA (MPL-2.0), den in mGBA gebauten Teilen blip_buf (LGPL-2.1-or-later) und inih (BSD-3-Clause) sowie `libretro.h` (MIT): Die harte Regel verlangt die Lizenzhinweise in der App, und M1 ist der erste spielbare Build. M3 erweitert ihn um PPSSPP und MoltenVK. Entwurf und Schnittstellen: ADR 0005 (vorgeschlagen).

**Abnahme:** Homebrew-ROM läuft stabil mit 60 fps, Ton ohne Knacken, Speicherstand überlebt einen Neustart.

Stand 7. November 2026: umgesetzt auf `m1/gba` und im Duo-Simulator belegt (ADR 0005, Abschnitt „Umsetzung in M1“). Die Abnahme durch Fatih und der Gerätetest auf dem Duo stehen aus.

### M2 · DS am Falz

melonDS-Kern. Der Kern liefert beide Bildschirme in einem Puffer, der Renderer teilt ihn in zwei Texturen. Touch-Abbildung auf den unteren Bildschirm, FoldLayout mit `onHingeChange` und `reservedRegions`, Layouts für alle Posen, Pause beim Zuklappen.

**Abnahme:** Touch pixelgenau, Posenwechsel ohne Ruckler und ohne Emulationsstopp, alle Posen im Duo-Simulator geprüft.

### M3 · PSP

PPSSPP-Kern mit dem GPU-Weg aus ADR 0001, PSP-Layouts inklusive Tabletop, Leistungsoptimierung.

Aus dem Spike (ADR 0001, Abschnitt Folgen) kommen dazu:
- ein eigenes FFmpeg-Rezept (LGPL) für Video und AAC, weil PPSSPPs vorkompiliertes FFmpeg keine arm64-Simulator-Scheibe hat;
- PPGe-Atlas und Ersatzschriften aus freien Schriften;
- GPU-Synchronisation über `MTLSharedEvent` und ein Test des gepufferten Renderns;
- den Kern erst nach dem ersten emulierten Bild entladen;
- die Link-Prüfung des Kerns behalten; streicht ein SDK die GL-Header, das GL-Backend per Patch entfernen;
- der Bildschirm „Lizenzen“ aus M1, erweitert um die Komponenten aus `docs/adr/0001/kern-komponenten.md` und MoltenVK;
- in `Scripts/build-core.sh` eine feste Liste der 25 libretro-Funktionen statt `_retro_*` (PPSSPP exportiert sonst 21 `retro_vfs_*_impl` mit) und ein Rezept-Haken für die nötigen Unter-Submodule, damit `bootstrap.sh` nicht alle 23 von PPSSPP holt (allein FFmpeg rund 800 MB). Zusammen mit dem Haken liest auch die CI die Kerne und ihre Submodule aus `project.yml` und den Rezepten, statt sie in `.github/workflows/ci.yml` zu wiederholen.

**Abnahme:** volle Geschwindigkeit in einer anspruchsvollen Homebrew-Demo, 30 Minuten ohne thermische Drosselung auf dem Duo.

### PS2 · JIT-Build (nach M3, parallel zu M4 und M5)

Play!-Kern nur im Scheme `JIT`, JIT-Aktivierung gemäß ADR 0002, PS2-Layouts, Anleitung zum Sideloading im README.

Vorher kommt der Gerätetest aus ADR 0002 (Tests A und D). Dazu gehören:
- ein Patch für Play!s JIT-Speicher unter TXM (CodeGen-PR #34, Play!-PR #1622);
- die JIT-Prüfung in `App/JIT/`, nur im JIT-Build, mit einem neutralen Haken in LibretroKit;
- Play! per `EXCLUDED_SOURCE_FILE_NAMES` aus Debug und Release herausnehmen;
- die Entscheidung, wo der OpenGL-ES-3-Kontext für Play! entsteht (LibretroKit, `App/JIT` oder ein eigenes Paket) oder ob eine Vulkan-Anbindung für Play!s `GSH_Vulkan` lohnt.

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
| PSP-Grafik im eigenen Host | M3 verzögert sich stark | Spike in M0 bestanden: OpenGL ES, Vulkan und Software laufen im Simulator (ADR 0001). Restrisiko: Leistung und Wärme am Gerät |
| Gleiche Funktionsnamen aller Kerne | Kerne lassen sich nicht zusammen linken | Jeder Kern als eigenes Framework, zur Laufzeit geladen |
| Delta und PPSSPP decken schon viel ab | Weniger Nutzer als erhofft | Fokus auf PSP und DS gemeinsam plus Tabletop. Als Lern- und Portfolio-Projekt lohnt es sich so oder so |
| Kein JIT im Store | Schwere Systeme zu langsam, PS2 gar nicht | Store-Build nur mit Systemen, die per Interpreter flüssig laufen. PS2 nur im JIT-Build, Gerätetest aus ADR 0002 (steht aus) |
| JIT unter iOS 27 unzuverlässig | PS2 startet nicht | ADR 0002 vor jeder PS2-Arbeit, Play! als Kern ohne BIOS-Zwang |
| Play!s JIT-Speicher passt nicht zu TXM | PS2 startet auf dem Duo nicht | Patch nach CodeGen-PR #34 und Play!-PR #1622, geprüft im Gerätetest D (ADR 0002) |
| StikDebug muss während des Spielens verbunden bleiben | Umständliche Bedienung im JIT-Build | Klärt Gerätetest A (ADR 0002) |
| GPL und App Store | Keine Store-Veröffentlichung | Erst eigene Geräte, vor einer Einreichung die Kern-Entwickler fragen |
| Neue Duo-APIs, lückenhafte Doku | Verhalten weicht ab | Hinter `#available(iOS 27.1, *)` kapseln, früh auf dem Duo testen |
| Knacken im Ton, unruhiger Takt bei 120 Hz | Spielgefühl leidet | Eigener Takt je Kern, der der Tonuhr folgt statt Resampling (ADR 0005), Messwerte im Debug-Overlay |
| Wärme und Akku | Lange Sessions brechen ein | Messung in jedem Meilenstein, Bildraten-Begrenzer |
| Markenrecht | Abmahnung oder Ablehnung | Neutraler Name, eigene Skins, keine Logos |
| Der Umfang wächst | Nichts wird fertig | Abnahme pro Meilenstein, das nächste System erst danach |

## 12. Offene Punkte

- [x] Projektname festlegen (englisch), danach App Store und GitHub auf Konflikte prüfen. Ergebnis: Arcfold, geprüft am 6. November 2026.
- [x] Sichtbarkeit des Repos: Es bleibt privat, bis die App an andere geht (Fatih, 6. November 2026).
- [x] ADR 0001 angenommen: Vulkan über MoltenVK für PSP (Fatih, mit der M0-Abnahme am 6. November 2026).
- [ ] Store-Build: Darf PPSSPPs nie ausgeführter ARM64-JIT-Code im Kern bleiben (der Host meldet kein JIT, der Kern nutzt den IR-Interpreter), oder wird er herausgepatcht? Harte Regel JIT, ADR 0001 Folgen; vor M3 (Fatih).
- [ ] Tests auf dem Duo schon ab M0 mit kostenloser Apple-ID? Davon hängt der Gerätetest aus ADR 0002 ab.
- [ ] Lizenzvariante festlegen: GPL-3.0-only oder GPL-3.0-or-later. Die eigenen Testprogramme sind derzeit gemischt (`gu-test` or-later, `gs_sprites` und `selftest` only).
- [ ] ADR 0005 (Laufzeit für Software-Kerne) annehmen. Darin offen: Controller-Belegung nach Position oder Beschriftung, 60 oder 120 Hz nach dem Gerätetest, Ton im Lautlos-Modus.
- [ ] Vor M2 auf dem Gerät prüfen: Der Duo-Simulator meldet das Innendisplay mit 2007 × 2853 px statt 1878 × 2670 (Abschnitt 3), und zugeklappt nimmt eine Systemspalte von 84 pt den rechten Rand ein. Davon hängen die Platzierung (ADR 0005) und die Falz-Layouts ab.
- [ ] Libretro-Schnittstelle von Mesen 2 prüfen (M5).
- [ ] Vor dem Öffentlichschalten die Quellen in Abschnitt 13 (Emulations-Ratgeber) auf ROM- und BIOS-Download-Links prüfen und notfalls durch Primärquellen ersetzen.

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
