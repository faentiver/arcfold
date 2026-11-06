---
name: ps2-jit
description: PS2 mit JIT auf iOS 26 und 27 – StikDebug, TXM, Haltepunkt-Protokoll, Play!s JIT-Speicher, Erkennung zur Laufzeit, Stolperfallen und die Anleitung für den Gerätetest auf dem Duo
---

# PS2 mit JIT

Stand 6. November 2026. Entscheidung und Optionen stehen in [ADR 0002](../adr/0002-ps2-jit.md), der Prototyp liegt in `Spikes/PS2JIT/`.

Kennzeichnung: **belegt** heißt im Code, in einer Primärquelle oder im Simulator nachgewiesen. **Annahme** heißt plausibel, aber nicht geprüft. **Gerät** heißt erst auf dem Duo prüfbar.

## Kurzfassung

- Play! hat keinen Interpreter. Ohne ausführbaren Speicher läuft nichts (belegt: CodeGen erzeugt nur x86, AArch32, AArch64 und WASM, `CBasicBlock::Execute` ruft immer kompilierten Code).
- StikDebug behandelt unter iOS 27 jedes iPhone als Gerät mit TXM (belegt: `ProcessInfo+TXM.swift`). Dort reicht ein angehängter Debugger nicht: Jede ausführbare Region muss die App über das Haltepunkt-Protokoll von `universal.js` vorbereiten lassen (belegt: StikJIT `INTEGRATION.md`, StikDebug-Quellcode).
- Play! 0.77 tut das nicht. Es schaltet jeden Block einzeln mit `vm_protect` auf r-x (belegt). Auf dem Duo scheitert das voraussichtlich (Annahme, gestützt auf Play!-Issue #1490 und CodeGen-PR #34; Gerät).
- Upstream gibt es nur einen offenen Pull Request, Play--CodeGen #34 vom 7. September 2026. Allein bringt er Play! zum Absturz. Mit unserem Begleitpatch für `BasicBlock.cpp` (zwei Zeilen) liefert der CPU-Test im Simulator genau die erwartete Ausgabe (belegt im Simulator; Gerät).
- Ohne JIT startet Play! nicht, sondern meldet „Cannot run without JIT“, wenn das Frontend `RETRO_ENVIRONMENT_GET_JIT_CAPABLE` mit „nein“ beantwortet (belegt im Simulator).
- Grafik: Play!s libretro-Kern rendert nur über OpenGL ES 3 (belegt). Vulkan gibt es bei Play! nur in den eigenen Oberflächen, nicht im libretro-Kern.

## Wie StikDebug JIT freischaltet

Voraussetzungen (belegt: StikDebug-README und `PAIRING.md` auf Commit `9d7a917`, SideStore-Doku, Apple-Doku):

- Die App braucht `get-task-allow`. Xcode setzt das Entitlement bei jeder Entwicklungs-Signatur automatisch, also auch mit kostenloser Apple-ID.
- Eine Pairing-Datei des Geräts. Ab iOS 27 erzeugt StikDebug sie selbst (Einstellungen → Pair a Device), sonst mit iloader am Mac.
- LocalDevVPN aus dem App Store. Das VPN leitet die Verbindung zum eigenen Gerät zurück.
- Entwicklermodus. StikDebug lädt und mountet das Developer Disk Image selbst, einmal pro Neustart (laut StikJIT-Doku ab iOS 26.4 als Cryptex-DDI).
- StikDebug selbst ist nicht mehr im App Store. Es gibt eine AltSource, eine IPA und den Quellcode zum Selbstbauen.

Ablauf:

- **Ohne TXM:** Der Debugger hängt sich an und löst sich wieder. Danach ist `CS_DEBUGGED` gesetzt, und der Prozess darf Seiten ausführbar machen.
- **Mit TXM:** Ausführbar werden nur Seiten, die über die Debug-Verbindung beschrieben wurden. StikDebugs `prepare_memory_region` schickt dazu für jede 16-KiB-Seite das GDB-Paket `M<adresse>,1:69`, schreibt also ein Byte 0x69 an den Seitenanfang. Die App muss das Skript selbst rufen:
  - `brk #0xf00d`, Befehl in `x16`: 0 = Detach, 1 = Region vorbereiten (`x0` = Adresse oder NULL, `x1` = Länge, Ergebnis in `x0`), 2 = weiteres Skript nachladen.
  - Mit `x0` = NULL holt das Skript die Region selbst (`_M<länge>,rx`) und bereitet sie vor.
  - Reihenfolge laut INTEGRATION.md: Skript anhängen lassen, auf `CS_DEBUGGED` warten, alle Regionen vorbereiten, beschreibbaren Alias anlegen (`vm_remap`), Detach, erst dann „JIT bereit“. Nach dem Detach lässt sich keine neue Region mehr vorbereiten.
  - Das ältere `legacy.js` (DolphiniOS, UTM, ARMSX2) erwartet genau einen `brk #0x69` mit einer selbst gemappten r-x-Region in `x0`/`x1`.
- Ein `brk` ohne Debugger beendet die App mit SIGTRAP. Vorher muss deshalb `P_TRACED` geprüft werden; `CS_DEBUGGED` bleibt nach dem Detach gesetzt und taugt dafür nicht.
- TXM erkennt StikDebug (wie DolphiniOS) nur über die Modellkennung: unter iOS 26 ab iPhone14,2 (A15) bzw. iPad14,5, ab iOS 27 alle Geräte außer iPad8,11 und iPad8,12. Das Duo (A20 Pro, iOS 27) zählt sicher dazu.
- Die Liste [SUPPORTED_APPS.md](https://github.com/StikDebug/StikDebug/blob/main/SUPPORTED_APPS.md) (15 Apps, darunter MeloNX, DolphiniOS, UTM und ARMSX2, ohne Play!) bedeutet offizielle Unterstützung, keine technische Sperre („Apps not listed here may still work“). Eine App gibt ihr Skript per URL mit: `stikdebug://enable-jit?bundle-id=<id>&pid=<pid>&script-name=universal.js`. Alternativ ordnet man der App in StikDebug ein Skript zu. Für die Liste lehnt das Team Projekte ohne Nutzerbasis und überwiegend KI-generierte Projekte in der Regel ab.

## Play! und JIT

Betroffene Stellen in Play! 0.77 (`Cores/play`, CodeGen `a5009f7`):

| Datei | Zeilen | Inhalt |
| --- | --- | --- |
| `deps/CodeGen/src/MemoryFunction.cpp` | 13–30 | iOS, auch der Simulator, wählt `MEMFUNC_USE_MACHVM` mit `MEMFUNC_MACHVM_STRICT_PROTECTION` |
| ebenda | 101–115 | je Block `vm_allocate`, `memcpy`, `vm_protect` auf r-x |
| ebenda | 212–231 | `BeginModify`/`EndModify` schalten zwischen rw- und r-x |
| `Source/BasicBlock.cpp` | 101 | ein `CMemoryFunction` je kompiliertem Block |
| ebenda | 410–414, 429–432 | Block-Verknüpfungen schreiben direkt in den Code (`GetCode()`) |
| `Source/ee/EeExecutor.cpp` | 83–127, 252–270 | Schreibschutz auf EE-RAM per `mprotect` und Mach-Exception-Port am Thread |
| `Source/ui_libretro/main_libretro.cpp` | 482–493 | Abfrage von `RETRO_ENVIRONMENT_GET_JIT_CAPABLE`, nur wenn `IOS` definiert ist |

Bewertung:

- Unter TXM ist dieser Weg unbrauchbar: Jeder Block bekommt neue Seiten, die nie über den Debugger vorbereitet werden. Laut PR #34 entzieht `vm_protect` auf einem A17 Pro mit iOS 26.4.2 das Ausführrecht still (Annahme für das Duo; Gerät).
- Nötig ist eine Arena: einmal eine r-x-Region über den Debugger, dazu ein rw-Alias per `vm_remap`, darin Unterallokation. Block-Verknüpfungen müssen über den Alias schreiben.
- [Play--CodeGen PR #34](https://github.com/jpd002/Play--CodeGen/pull/34) (Johnzx07, Head `23b29221`, nicht gemergt) setzt das um. Befunde aus Code und Simulator:
  - Die 64-MB-Arena wird erst beim ersten kompilierten Block angefordert, und der PR sendet nie Detach. Das weicht von INTEGRATION.md ab.
  - Vor dem `brk` prüft der PR nur `CS_DEBUGGED`. Hat das Skript schon getrennt, stürzt die App ab.
  - Der Arena-Weg greift auch im arm64-Simulator (Bedingung `TARGET_OS_IPHONE && TARGET_CPU_ARM64`), dort über den Rückfall mmap r-x plus Alias. Die PR-Beschreibung sagt das Gegenteil.
  - Der angekündigte Begleitpatch für `BasicBlock.cpp` fehlt. Ohne ihn stürzt Play! in `CBasicBlock::LinkBlock` ab (`KERN_PROTECTION_FAILURE` beim Schreiben in die r-x-Seite der Arena, Beleg `docs/adr/0002/sim-pr34-only-crash.txt`). Mit `Spikes/PS2JIT/patches/play-basicblock-writable-alias.patch` stimmt die Ausgabe des CPU-Tests.
  - Die Arena wird nie vergrößert; freie Stücke kommen in eine einfache Liste. Ob 64 MB für lange Sitzungen reichen, ist offen (Annahme).
- Play!s eigene iOS-App 0.77 erkennt JIT per `getppid() != 1`, über AltServer (AltKit) oder den Jailbreak-Pfad und ruft beim Start `ptrace(PT_TRACE_ME)`. Einen Weg für TXM hat sie nicht. Die Issues [#1490](https://github.com/jpd002/Play-/issues/1490), [#1558](https://github.com/jpd002/Play-/issues/1558) und [#1585](https://github.com/jpd002/Play-/issues/1585) zu iOS 26 sind offen.

## JIT zur Laufzeit erkennen und den Absturz vermeiden

- `csops(getpid(), CS_OPS_STATUS, …)` liefert `CS_GET_TASK_ALLOW` (0x4) und `CS_DEBUGGED` (0x10000000), definiert in XNU `osfmk/kern/cs_blobs.h`. `csops` ist in libSystem exportiert, steht aber in keinem SDK-Header. Es ist private API und gehört nur in den JIT-Build.
- `sysctl` mit `KERN_PROC_PID` liefert `P_TRACED`: Ein Debugger ist gerade verbunden.
- Unter TXM entscheidet erst eine Probe: Region vorbereiten lassen, über den Alias `mov w0, #42; ret` schreiben, den Schutz mit `vm_region_64` prüfen, dann aufrufen. Der Spike prüft zusätzlich Play!s eigenen `vm_protect`-Weg, damit sich vorhersagen lässt, ob der unveränderte Kern laufen würde.
- Den Absturz verhindert das Frontend: Es beantwortet `RETRO_ENVIRONMENT_GET_JIT_CAPABLE` (74) nur dann mit „ja“, wenn der JIT-Weg des geladenen Kerns geprüft funktioniert. Play! beendet `retro_load_game` sonst mit „Cannot run without JIT“. Das greift nur, wenn das Frontend die Abfrage beantwortet und der Kern mit `IOS` gebaut ist; `Scripts/cores/play.sh` setzt `-DIOS=1`.

## Befunde im Simulator

6. November 2026, eigenes Gerät „Arcfold PS2JIT“ (iPhone 18 Pro, iOS 27.2, 24B8117), Play! 0.77. Im Simulator gelten die Regeln des Macs für ausführbaren Speicher; nichts davon sagt etwas über JIT auf dem Gerät.

| Lauf | Ergebnis | Beleg |
| --- | --- | --- |
| Kern laden, `retro_get_system_info` | Play!, 0.77, `elf\|iso\|cso\|isz\|cue\|chd`, libretro-API 1 | `docs/adr/0002/sim-alu.json` |
| Proben | Dual-Mapping und `vm_protect` auf r-x klappen ohne Debugger | `sim-alu.json` |
| `alu.elf` mit JIT | Ausgabe Byte für Byte gleich `alu.expected` (788 Zeilen), Testende nach 0,55 s | `sim-alu.png`, `sim-alu.json` |
| `alu.elf`, Frontend meldet „kein JIT“ | `retro_load_game` liefert false, Meldung „Cannot run without JIT“, kein Absturz | `sim-nojit.png`, `sim-nojit.json` |
| `gs_sprites.elf` | 600 × `retro_run`, 601 Bilder 640 × 448 in 2,1 s (etwa 290 fps ohne Bildratenbremse), Bild wie erwartet | `sim-gs_sprites.png`, `gs_sprites-frame.png` |
| PR #34 ohne Begleitpatch | Absturz in `CBasicBlock::LinkBlock` | `sim-pr34-only-crash.txt` |
| PR #34 mit Begleitpatch | `alu.elf` korrekt, `gs_sprites.elf` 601 Bilder in 2,1 s | `sim-pr34-companion-*.json` |
| Speicher | etwa 210 MB Footprint während `gs_sprites` | vmmap, 6. November 2026 |

Der Simulator rendert OpenGL ES 3.0 mit dem „Apple Software Renderer“. Bildraten aus dem Simulator sind deshalb nur Plausibilitätswerte.

## Stolperfallen

- `retro_run` blockiert, solange das Programm keine GS-Register schreibt: Play! gibt nur dann ein Bild aus, und `ProcessSingleFrame` wartet auf genau dieses Bild. Der CPU-Test endet deshalb über seine Ausgabe, nicht über die Bildzahl. LibretroKit braucht für Play! einen Wächter.
- Play! schreibt die Konsolenausgabe des PS2-Programms nur mit der Einstellung `iop.fileio.stdlogging` nach `Documents/Play Data Files/ps2_stdout.txt`.
- In einem Submodul ist `.git` eine Datei. Play!s CMake erkennt die Version dann nicht und meldet 0.30. Das Rezept übergibt `PLAY_VERSION` aus `git describe`.
- Das in libchdr gebündelte zlib benennt beim Konfigurieren `zconf.h` im Quellbaum um. Das Rezept nutzt deshalb die zlib des SDK.
- libretro erlaubt einen Kern pro Prozess. Der Spike erlaubt einen Lauf pro App-Start.
- Auf dem Emulations-Thread fehlt ein Autorelease-Pool, der regelmäßig geleert wird. Autoreleaste Objekte pro Bild trieben den Footprint auf fast 3 GB; der Spike legt Bilder deshalb ohne Autorelease an und legt je `retro_run` einen Pool an.
- Die Runtime iOS 27.2 (24B8117) unterstützt den Gerätetyp iPhone Duo nicht: `simctl create` meldet „Incompatible device“. Der Spike lief deshalb auf einem iPhone 18 Pro.

## Gerätetest auf dem Duo

Ziel: in etwa 30 Minuten klären, ob StikDebug mit `universal.js` unserer App auf dem Duo ausführbaren Speicher gibt (Test A), wie sich der unveränderte Kern verhält (Test B und C) und ob die Variante mit PR #34 läuft (Test D).

### Vorbereitung am Mac (einmalig, etwa 10 Minuten)

1. Branch mit dem Spike auschecken und die Submodule holen:
   ```bash
   git submodule update --init --recursive Cores/play
   Scripts/build-core.sh play
   ```
2. Für Test D zusätzlich die Variante mit PR #34 bauen (holt den Diff per `gh`):
   ```bash
   Spikes/PS2JIT/try-codegen-pr34.sh build/experiments/pr34-geraet
   ```
3. Projekt erzeugen und öffnen:
   ```bash
   cd Spikes/PS2JIT && xcodegen generate && open JITSpike.xcodeproj
   ```
4. In Xcode beim Target JITSpike unter Signing & Capabilities die Personal Team der Apple-ID wählen. Ist die Bundle-ID vergeben, eine eigene wählen, etwa `com.<name>.arcfold.spike.jit`.
5. Das Duo per USB anschließen, „Vertrauen“ bestätigen und unter Einstellungen → Datenschutz & Sicherheit → Entwicklermodus einschalten (Neustart).
6. Mit Run (⌘R) auf dem Duo installieren. Beim ersten Mal unter Einstellungen → Allgemein → VPN & Geräteverwaltung dem Entwicklerzertifikat vertrauen. Danach die Debug-Sitzung in Xcode beenden (⌘.): Für alle Tests startet die App vom Home-Bildschirm, sonst hängt LLDB statt StikDebug am Prozess.

Die kostenlose Apple-ID erlaubt drei eigene Apps je Gerät und signiert für sieben Tage (Apple, „Choosing a Membership“). JIT-Spike und StikDebug belegen zwei davon.

### StikDebug einrichten (einmalig, etwa 10 Minuten)

1. StikDebug installieren. Am einfachsten selbst bauen: `git clone https://github.com/StikDebug/StikDebug.git` (gelesen wurde Stand `9d7a917`, aktuelles Release 3.2.0), in Xcode 27 öffnen, Personal Team und eine eigene Bundle-ID wählen, auf dem Duo ausführen. StikDebug nutzt die App Group `group.com.stik.stikdebug`; diese Kennung ist vergeben, also unter Signing & Capabilities eine eigene eintragen. Ob die Personal Team App Groups erlaubt, ist nicht geprüft (Annahme). Klappt das Signieren nicht, bleibt der Weg über SideStore oder AltStore mit der offiziellen AltSource aus dem StikDebug-README.
2. LocalDevVPN aus dem App Store installieren, öffnen und das VPN einschalten.
3. In StikDebug unter Settings → Pair a Device → Pair iPhone or iPad die Pairing-Datei erzeugen. Ersatzweise am Mac mit iloader („Manage Pairing File“ → „Place“ bei StikDebug).
4. StikDebug mit WLAN und VPN einmal öffnen, damit es das Developer Disk Image lädt und mountet. Nach jedem Neustart des Duo wiederholen.

### Test A: Bekommt die App ausführbaren Speicher? (etwa 5 Minuten)

1. JIT-Spike vom Home-Bildschirm starten. Erwartung: „get-task-allow“ an, „CS_DEBUGGED“ aus, „TXM angenommen“ an.
2. „JIT über StikDebug anfordern“ tippen. StikDebug öffnet sich, fragt eventuell nach Bestätigung, hängt sich an, führt `universal.js` aus und kehrt zur App zurück.
3. Die drei Proben ablesen und einen Screenshot machen:

| Probe | Bedeutung bei Erfolg |
| --- | --- |
| universal.js, Region vom Debugger | Der TXM-Weg funktioniert für Arcfold. Das ist die zentrale Frage des Spikes. |
| universal.js, eigene r-x-Region | Klärt den Widerspruch zwischen PR #34 (geht nicht) und Skriptcode (sollte gehen). |
| Play!s Weg (vm_protect auf r-x) | Der unveränderte Kern könnte laufen. Erwartet wird „Seite nicht ausführbar“. |

Mögliche Fehler: „CS_DEBUGGED kam nicht innerhalb von 120 s“ heißt, StikDebug hat sich nicht angehängt (VPN, Pairing-Datei, DDI; Log in StikDebug ansehen). „kein Debugger mehr verbunden“ heißt, StikDebug lief ohne Skript; in StikDebug der App `universal.js` zuordnen und erneut versuchen. Stürzt die App beim Tippen ab, den Absturzbericht sichern (unten).

### Test B: Unveränderter Kern mit JIT (etwa 3 Minuten)

Im selben App-Start nach Test A: Zeigt „JIT an den Kern gemeldet“ „nein“, den Schalter „Kern trotzdem starten“ einschalten und „alu.elf starten“ tippen. Erwartung unter TXM: Absturz beim ersten kompilierten Block. Läuft der Test durch und meldet „Ausgabe = alu.expected“, braucht Play! keinen Patch – das wäre die beste Nachricht.

### Test C: Ohne JIT (etwa 2 Minuten)

App beenden und neu starten, kein JIT anfordern, „alu.elf starten“. Erwartung: „Spiel geladen: nein“, „Cannot run without JIT“ und der Hinweis, kein Absturz.

### Test D: Variante mit PR #34 (etwa 10 Minuten)

1. Am Mac `Cores/Build/play_libretro.xcframework` beiseite schieben, `build/experiments/pr34-geraet/play_libretro.xcframework` an seine Stelle kopieren und JIT-Spike erneut mit Run installieren, danach wieder ⌘. drücken. Die App zeigt dann „JIT-Speicher: Arena vom Debugger (PR #34)“.
2. App vom Home-Bildschirm starten, Test A wiederholen, dann „alu.elf starten“. Erwartung: „Ausgabe = alu.expected“.
3. App neu starten, Test A wiederholen, „Bilder für gs_sprites“ auf 18000 (5 Minuten) stellen und „gs_sprites.elf starten“. Bildrate, Prozent von NTSC und thermalState notieren.
4. Danach am Mac `Scripts/build-core.sh play` laufen lassen, damit wieder der normale Kern in `Cores/Build` liegt.

### Was notiert wird

- Gerät und iOS-Version (stehen in der App), StikDebug-Version.
- Ergebnis jeder Probe mit dem angezeigten Schutz (etwa „r-x“).
- Für jeden Lauf: Spiel geladen, Meldung des Kerns, Ausgabe gleich `alu.expected`, Bildrate, thermalState vorher → nachher.
- Screenshots der App, bei Abstürzen den Bericht aus Einstellungen → Datenschutz & Sicherheit → Analyse & Verbesserungen → Analysedaten (`JITSpike-…`).
- Die App legt jeden Lauf unter `Documents/SpikeResults` ab (`report.json`, `frame.png`, `ps2_stdout.txt`). Im Finder unter dem Duo → Dateien → JIT-Spike lassen sie sich auf den Mac ziehen.

Erfolg im Sinne von ADR 0002: Test A „Region vom Debugger“ bestanden und Test D mit korrekter Ausgabe. Scheitert Test A, ist PS2 über StikDebug auf dem Duo derzeit nicht machbar.

## Quellen

- StikJIT, [INTEGRATION.md](https://github.com/StikDebug/StikJIT/blob/main/INTEGRATION.md), Commit `b3e01a3` (1. November 2026)
- StikDebug, [README](https://github.com/StikDebug/StikDebug), [PAIRING.md](https://github.com/StikDebug/StikDebug/blob/main/PAIRING.md), [SUPPORTED_APPS.md](https://github.com/StikDebug/StikDebug/blob/main/SUPPORTED_APPS.md), `StikDebug/Scripts/universal.js`, `legacy.js`, `JSSupport/JSDebugSupport.swift`, `Support/ProcessInfo+TXM.swift`, `Support/ScriptStore.swift`, `Views/HomeView.swift`, Commit `9d7a917` (6. November 2026)
- SideStore-Doku, [JIT](https://docs.sidestore.io/docs/advanced/jit), abgerufen am 6. November 2026
- Play!, Tag 0.77 (`fa75cea`), Issues [#1490](https://github.com/jpd002/Play-/issues/1490), [#1558](https://github.com/jpd002/Play-/issues/1558), [#1585](https://github.com/jpd002/Play-/issues/1585)
- Play--CodeGen, [PR #34](https://github.com/jpd002/Play--CodeGen/pull/34), Head `23b29221`
- DolphiniOS, `Source/Core/Common/MemoryUtil_iOS_LuckTXM.cpp` und `Source/iOS/App/Common/Jit/JitManager+Debugger.m` ([OatmealDome/dolphin-ios](https://github.com/OatmealDome/dolphin-ios))
- UTM, Commit [`678534e`](https://github.com/utmapp/UTM/commit/678534e6a57e73656bf9a44f2e0189bdaa71a7c6) „new JIT workaround for iOS 26“
- XNU `xnu-12377.121.6`, `osfmk/kern/cs_blobs.h` und `bsd/sys/codesign.h` ([apple-oss-distributions/xnu](https://github.com/apple-oss-distributions/xnu))
- Apple, [Debugging tool entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.cs.debugger) (Xcode setzt `get-task-allow` für Debug-Builds), [Enabling Developer Mode on a device](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device), [Choosing a Membership](https://developer.apple.com/support/compare-memberships/)
- libretro.h aus Play! 0.77 (`Source/ui_libretro/ext/libretro.h`), `RETRO_ENVIRONMENT_GET_JIT_CAPABLE`
