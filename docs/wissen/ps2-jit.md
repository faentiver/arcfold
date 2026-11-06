---
name: ps2-jit
description: PS2 mit JIT auf iOS 26 und 27 – StikDebug, TXM, Haltepunkt-Protokoll, Play!s JIT-Speicher, Erkennung zur Laufzeit, Einbau in den JIT-Build, Stolperfallen und die Anleitung für den Gerätetest auf dem Duo
---

# PS2 mit JIT

Stand 6. November 2026. Entscheidung und Optionen stehen in [ADR 0002](../adr/0002-ps2-jit.md), der Prototyp liegt in `Spikes/PS2JIT/`.

Kennzeichnung: **belegt** heißt im Code, in einer Primärquelle, im Simulator oder in einem Build-Experiment nachgewiesen. **Annahme** heißt plausibel, aber nicht geprüft. **Gerät** heißt erst auf dem Duo prüfbar.

## Kurzfassung

- Play! hat keinen Interpreter. Ohne ausführbaren Speicher läuft nichts (belegt: CodeGen erzeugt nur x86, AArch32, AArch64 und WASM, `CBasicBlock::Execute` ruft immer kompilierten Code).
- StikDebug behandelt unter iOS 27 jedes iPhone als Gerät mit TXM (belegt: `ProcessInfo+TXM.swift`). Dort reicht ein angehängter Debugger nicht: Jede ausführbare Region muss die App über das Haltepunkt-Protokoll von `universal.js` vorbereiten lassen (belegt: StikJIT `INTEGRATION.md`, StikDebug-Quellcode).
- Play! 0.77 tut das nicht. Es schaltet jeden Block einzeln mit `vm_protect` auf r-x (belegt). Auf dem Duo scheitert das voraussichtlich (Annahme, gestützt auf Play!-Issue #1490 und CodeGen-PR #34; Gerät).
- Upstream gibt es dafür zwei zusammengehörige, offene Pull Requests desselben Autors: Play--CodeGen #34 (7. September 2026) und Play! #1622 (27. September 2026). CodeGen #34 allein bringt Play! zum Absturz. Zusammen mit der zweizeiligen Änderung an `BasicBlock.cpp` aus #1622 (bei uns als Patch nachgebaut, identisch) liefert der CPU-Test im Simulator genau die erwartete Ausgabe (belegt im Simulator; Gerät).
- Ob der Debugger nach der Vorbereitung getrennt werden darf, ist offen: INTEGRATION.md trennt, PR #34 nicht. Test A prüft das (Gerät).
- Ohne JIT startet Play! nicht, sondern meldet „Cannot run without JIT“, wenn das Frontend `RETRO_ENVIRONMENT_GET_JIT_CAPABLE` mit „nein“ beantwortet (belegt im Simulator).
- Die JIT-Prüfung gehört in Quellen des App-Targets, die nur der JIT-Build übersetzt, nicht in LibretroKit: Pakete sehen `JIT_BUILD` nicht (belegt, Build-Experiment).
- Grafik: Play!s libretro-Kern rendert nur über OpenGL ES 3 (belegt). Vulkan gibt es bei Play! nur in den eigenen Oberflächen, nicht im libretro-Kern.

## Wie StikDebug JIT freischaltet

Voraussetzungen (belegt: StikDebug-README und `PAIRING.md` auf Commit `9d7a917`, SideStore-Doku, Apple-Doku):

- Die App braucht `get-task-allow`. Entwicklungsprofile erlauben es, auch das der kostenlosen Apple-ID: Mit ihr lässt sich in Xcode auf dem Gerät debuggen, und das setzt `get-task-allow` voraus. Für Debug-Builds trägt Xcode es selbst ein (Apple-Doku), der JIT-Build auf `m0/fundament` setzt es zusätzlich in `App/Arcfold-JIT.entitlements`, damit es auch in Release-JIT sicher drin ist.
- Eine Pairing-Datei des Geräts. Ab iOS 27 erzeugt StikDebug sie selbst (in StikDebug unter Settings → Pair a Device), sonst mit iloader am Mac.
- LocalDevVPN aus dem App Store. Das VPN leitet die Verbindung zum eigenen Gerät zurück.
- Entwicklermodus. StikDebug lädt und mountet das Developer Disk Image selbst, einmal pro Neustart (laut StikJIT-Doku ab iOS 26.4 als Cryptex-DDI).
- StikDebug selbst ist nicht mehr im App Store. Es gibt eine AltSource, eine IPA und den Quellcode zum Selbstbauen.

Ablauf:

- **Ohne TXM:** Der Debugger hängt sich an und löst sich wieder. Danach ist `CS_DEBUGGED` gesetzt, und der Prozess darf Seiten ausführbar machen.
- **Mit TXM:** Ausführbar werden nur Seiten, die über die Debug-Verbindung beschrieben wurden. StikDebugs `prepare_memory_region` schickt dazu für jede 16-KiB-Seite das GDB-Paket `M<adresse>,1:69`, schreibt also ein Byte 0x69 an den Seitenanfang. Die App muss das Skript selbst rufen:
  - `brk #0xf00d`, Befehl in `x16`: 0 = Detach, 1 = Region vorbereiten (`x0` = Adresse oder NULL, `x1` = Länge, Ergebnis in `x0`), 2 = weiteres Skript nachladen.
  - Mit `x0` = NULL holt das Skript die Region selbst (`_M<länge>,rx`) und bereitet sie vor.
  - Reihenfolge laut INTEGRATION.md: Skript anhängen lassen, auf `CS_DEBUGGED` warten, alle Regionen vorbereiten, beschreibbaren Alias anlegen (`vm_remap`), Detach, erst dann „JIT bereit“. Nach dem Detach lässt sich keine neue Region mehr vorbereiten. Dass die vorbereiteten Seiten danach ausführbar bleiben, setzt die Doku voraus, sagt es aber nicht ausdrücklich.
  - CodeGen-PR #34 widerspricht: Er sendet nie ein Detach, weil das Ausführrecht am verbundenen Debugger hänge (PR-Beschreibung und Kommentar in `MemoryFunction.cpp`). Einen Beleg nennt der PR nicht. Welche Seite recht hat, zeigt Test A mit den Proben „Nach Detach“ (Gerät).
  - Das ältere `legacy.js` (DolphiniOS, UTM, ARMSX2) erwartet genau einen `brk #0x69` mit einer selbst gemappten r-x-Region in `x0`/`x1`.
- Ein `brk` ohne Debugger beendet die App mit SIGTRAP. Vorher muss deshalb `P_TRACED` geprüft werden; `CS_DEBUGGED` bleibt nach dem Detach gesetzt und taugt dafür nicht.
- TXM erkennt StikDebug (wie DolphiniOS) nur über die Modellkennung: unter iOS 26 ab iPhone14,2 (A15) bzw. iPad14,5, ab iOS 27 alle Geräte außer iPad8,11 und iPad8,12. Das Duo (A20 Pro, iOS 27) zählt sicher dazu.
- Die Liste [SUPPORTED_APPS.md](https://github.com/StikDebug/StikDebug/blob/main/SUPPORTED_APPS.md) (15 Apps, darunter MeloNX, DolphiniOS, UTM und ARMSX2, ohne Play!) bedeutet offizielle Unterstützung, keine technische Sperre („Apps not listed here may still work“). Eine App gibt ihr Skript per URL mit: `stikdebug://enable-jit?bundle-id=<id>&pid=<pid>&script-name=universal.js`. Alternativ ordnet man der App in StikDebug ein Skript zu. Für die Liste lehnt das Team in der Regel Projekte ohne etablierte Nutzerbasis ab, außerdem minderwertige Projekte, die zum großen Teil KI-generiert sind, und Forks schon unterstützter Apps. Für eine spätere Aufnahme von Arcfold zählen also Nutzerbasis und Qualität.

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
- [Play--CodeGen PR #34](https://github.com/jpd002/Play--CodeGen/pull/34) (Johnzx07, Commits `f2d99e5` und `23b29221`, nicht gemergt) setzt das um. Der geprüfte Stand liegt als `Spikes/PS2JIT/patches/codegen-pr34-23b29221.patch` im Repo (Diff gegen `a5009f7`, byte-gleich mit `gh pr diff` vom 6. November 2026). Befunde aus Code und Simulator:
  - Die 64-MB-Arena holt `MemFunc_InitJitArena()`, das nur Play!s eigene App beim Start ruft (PR #1622). Im libretro-Kern ruft es niemand, dort fordert CodeGen die Arena erst beim ersten kompilierten Block an. Detach sendet der PR nie, mit der Begründung, das Ausführrecht hänge am verbundenen Debugger. Beides weicht von INTEGRATION.md ab; ob das Detach wirklich schadet, ist offen (Test A).
  - Vor dem `brk` prüft der PR nur `CS_DEBUGGED`. Hat das Skript schon getrennt, stürzt die App ab.
  - Der Arena-Weg greift auch im arm64-Simulator (Bedingung `TARGET_OS_IPHONE && TARGET_CPU_ARM64`), dort über den Rückfall mmap r-x plus Alias. Die PR-Beschreibung sagt das Gegenteil.
  - Der Begleitpatch für `BasicBlock.cpp` steckt nicht im PR, sondern in [Play! PR #1622](https://github.com/jpd002/Play-/pull/1622) (gleicher Autor, offen seit 27. September 2026, von einem Dritten freigegeben, nicht gemergt). Dessen Änderung an `BasicBlock.cpp` ist identisch mit `Spikes/PS2JIT/patches/play-basicblock-writable-alias.patch`; der dort eingetragene CodeGen-Stand `318f273c` hat dieselbe `MemoryFunction.cpp` wie der PR-Head (belegt). Ohne den Begleitpatch stürzt Play! in `CBasicBlock::LinkBlock` ab (`KERN_PROTECTION_FAILURE` beim Schreiben in die r-x-Seite der Arena, Beleg `docs/adr/0002/sim-pr34-only-crash.txt`). Mit ihm stimmt die Ausgabe des CPU-Tests (belegt im Simulator).
  - PR #1622 meldet Erfolg auf iOS 26.4.2 und 26.6.2 (iPhone 15 Pro Max), 26.7 und iOS 27 (dort mit LiveContainer 3.8.0). Das sind Angaben des Autors für Play!s eigene iOS-App mit Vulkan, nicht für den libretro-Kern; geprüft ist davon nichts (Annahme). Der PR trägt außerdem `dynamic-codesigning` in die Entitlements ein. Laut PR #34 bräuchte erst `mmap` mit `MAP_JIT` dieses Entitlement. In Xcode 27.2 kommt der Schlüssel in keiner Konfigurationsdatei vor (plist, xcspec, json), als Capability bietet Xcode ihn also nicht an; mit Entwicklungs-Signatur wäre er vermutlich ein Signaturfehler (Annahme, nicht geprüft). Arcfold trägt ihn nicht ein.
  - Die Arena wird nie vergrößert; freie Stücke kommen in eine einfache Liste. Ob 64 MB für lange Sitzungen reichen, ist offen (Annahme).
- Ein zweiter Ansatz, [Play--CodeGen PR #32](https://github.com/jpd002/Play--CodeGen/pull/32) (offen seit 4. Januar 2026), überträgt DolphiniOS' `MemoryUtil_iOS_*` samt lwmem nach CodeGen. DolphiniOS steht unter GPL-2.0-or-later, CodeGen unter BSD; upstream kann das so kaum übernehmen. Nicht weiter geprüft.
- Play!s eigene iOS-App 0.77 erkennt JIT per `getppid() != 1`, über AltServer (AltKit) oder den Jailbreak-Pfad und ruft beim Start `ptrace(PT_TRACE_ME)`. Einen Weg für TXM hat sie nicht. Die Issues [#1490](https://github.com/jpd002/Play-/issues/1490), [#1558](https://github.com/jpd002/Play-/issues/1558) und [#1585](https://github.com/jpd002/Play-/issues/1585) zu iOS 26 sind offen.

## JIT zur Laufzeit erkennen und den Absturz vermeiden

- `csops(getpid(), CS_OPS_STATUS, …)` liefert `CS_GET_TASK_ALLOW` (0x4) und `CS_DEBUGGED` (0x10000000), definiert in XNU `osfmk/kern/cs_blobs.h`. `csops` ist in libSystem exportiert, steht aber in keinem SDK-Header. Es ist private API und gehört nur in den JIT-Build.
- `sysctl` mit `KERN_PROC_PID` liefert `P_TRACED`: Ein Debugger ist gerade verbunden.
- Unter TXM entscheidet erst eine Probe: Region vorbereiten lassen, über den Alias `mov w0, #42; ret` schreiben, den Schutz mit `vm_region_64` prüfen, dann aufrufen. Der Spike prüft zusätzlich Play!s eigenen `vm_protect`-Weg, damit sich vorhersagen lässt, ob der unveränderte Kern laufen würde, und nach einem Detach dieselbe Region noch einmal mit neuem Code.
- Den Absturz verhindert das Frontend: Es beantwortet `RETRO_ENVIRONMENT_GET_JIT_CAPABLE` (74) nur dann mit „ja“, wenn der JIT-Weg des geladenen Kerns geprüft funktioniert. Play! beendet `retro_load_game` sonst mit „Cannot run without JIT“. Das greift nur, wenn das Frontend die Abfrage beantwortet und der Kern mit `IOS` gebaut ist; `Scripts/cores/play.sh` setzt `-DIOS=1`.

### Wo die Prüfung im Projekt hingehört

- Lokale Swift-Pakete sehen weder `SWIFT_ACTIVE_COMPILATION_CONDITIONS` noch `GCC_PREPROCESSOR_DEFINITIONS` des App-Targets, und SwiftPM unterscheidet nur debug und release. Ein `#if JIT_BUILD` in LibretroKit ist deshalb auch im JIT-Build falsch (belegt, Build-Experiment vom 6. November 2026).
- LibretroKit bekommt nur einen neutralen Haken, etwa `JITCapability` mit einer Closure und dem Standard „nein“. Die Prüfung selbst liegt in `App/JIT/` (C-Teil wie `Spikes/PS2JIT/Sources/Host/ArcJIT.c`, Swift-Hülle). Debug und Release schließen den Ordner mit `EXCLUDED_SOURCE_FILE_NAMES: JIT/*` aus, den Bridging-Header setzen nur Debug-JIT und Release-JIT.
- Mit einer Kopie von `m0/fundament` gebaut (belegt, `docs/adr/0002/jit-build-gating.txt`): Store-Builds ohne `csops`, ohne `brk #0xf00d` und ohne Play!, Debug-JIT mit allen dreien (Release-JIT ohne `brk`, weil das Experiment die Funktionen dafür nicht aufruft und der Optimierer sie entfernt); keine Warnung im eigenen Code. Der JIT-Build listet „Play! 0.77“ in der Kernliste.

## Befunde im Simulator

6. November 2026, eigenes Gerät „Arcfold PS2JIT“ (iPhone 18 Pro, iOS 27.2, 24B8117), Play! 0.77, Spike in `Spikes/PS2JIT/`, Stand wie auf `m0/fundament`, nach dem Merge auf `main`. Im Simulator gelten die Regeln des Macs für ausführbaren Speicher; nichts davon sagt etwas über JIT auf dem Gerät.

| Lauf | Ergebnis | Beleg |
| --- | --- | --- |
| Kern laden, `retro_get_system_info` | Play!, 0.77, `elf\|iso\|cso\|isz\|cue\|chd`, libretro-API 1 | `docs/adr/0002/sim-alu.json` |
| Proben | Dual-Mapping, zweite Seite (Wert 43), überschriebene erste Seite (Wert 44) und `vm_protect` auf r-x klappen ohne Debugger | `sim-alu.json` |
| `alu.elf` mit JIT | Ausgabe Byte für Byte gleich `alu.expected` (787 Zeilen), Testende nach 0,54 s | `sim-alu.png`, `sim-alu.json` |
| `alu.elf`, Frontend meldet „kein JIT“ | `retro_load_game` liefert false, Meldung „Cannot run without JIT“, kein Absturz, kein Bild | `sim-nojit.png`, `sim-nojit.json` |
| `gs_sprites.elf` | 600 × `retro_run`, 601 Bilder 640 × 448 in 2,0 s (etwa 300 fps ohne Bildratenbremse), Bild wie erwartet | `sim-gs_sprites.png`, `gs_sprites-frame.png` |
| PR #34 ohne Begleitpatch | Absturz in `CBasicBlock::LinkBlock` | `sim-pr34-only-crash.txt` |
| PR #34 mit Begleitpatch | `alu.elf` korrekt, `gs_sprites.elf` 601 Bilder in 2,0 s | `sim-pr34-companion-*.json` |
| Speicher | etwa 210 MB Footprint während `gs_sprites` | vmmap, 6. November 2026 |
| JIT-Build aus `m0/fundament` mit Play! | „Play! 0.77“ in der Kernliste, JIT-Zeile aus `App/JIT` | `jit-build-corelist.png` |

Der Simulator rendert OpenGL ES 3.0 mit dem „Apple Software Renderer“. Bildraten aus dem Simulator sind deshalb nur Plausibilitätswerte.

## Stolperfallen

- `retro_run` blockiert, solange das Programm keine GS-Register schreibt: Play! gibt nur dann ein Bild aus, und `ProcessSingleFrame` wartet auf genau dieses Bild. Der CPU-Test endet deshalb über seine Ausgabe, nicht über die Bildzahl. LibretroKit braucht für Play! einen Wächter.
- Play! schreibt die Konsolenausgabe des PS2-Programms nur mit der Einstellung `iop.fileio.stdlogging` nach `Documents/Play Data Files/ps2_stdout.txt`.
- In einem Submodul ist `.git` eine Datei. Play!s CMake erkennt die Version dann nicht und meldet 0.30. Das Rezept übergibt `PLAY_VERSION` aus `git describe`.
- Das in libchdr gebündelte zlib benennt beim Konfigurieren `zconf.h` im Quellbaum um. Das Rezept nutzt deshalb die zlib des SDK.
- `git submodule update --init --recursive` holt bei Play! auch AltKit, Nuanceur, SDWebImage und zlib. Der Kern braucht sie nicht: CMake nutzt sie nur für Play!s iOS-Oberfläche, den Vulkan-GS und als zlib-Ersatz, wenn das SDK keins hat. Das kostet nur Zeit beim Holen; `Scripts/bootstrap.sh` holt rekursiv. Die nötige Liste steht im Kopf von `Scripts/cores/play.sh`.
- libretro erlaubt einen Kern pro Prozess. Der Spike erlaubt einen Lauf pro App-Start.
- Auf dem Emulations-Thread fehlt ein Autorelease-Pool, der regelmäßig geleert wird. Autoreleaste Objekte pro Bild trieben den Footprint auf fast 3 GB; der Spike legt Bilder deshalb ohne Autorelease an und legt je `retro_run` einen Pool an.
- Defines und Swift-Bedingungen des App-Targets erreichen lokale Swift-Pakete nicht (siehe oben). Das gilt auch für `GLES_SILENCE_DEPRECATION`.
- `EXCLUDED_SOURCE_FILE_NAMES` vergleicht relative Muster mit den letzten Pfadteilen einer Datei (swift-build, `Path.matchesFilenamePattern`). `JIT/*` trifft alle Dateien direkt in einem Ordner `JIT`, `play_libretro.framework` die eingebettete Kopie des Kerns; der Name des xcframeworks trifft nichts.
- Die Runtime iOS 27.2 (24B8117) unterstützt den Gerätetyp iPhone Duo nicht: `simctl create` meldet „Incompatible device“. Der Spike lief deshalb auf einem iPhone 18 Pro.

## Gerätetest auf dem Duo

Ziel: in etwa 30 Minuten klären, ob StikDebug mit `universal.js` unserer App auf dem Duo ausführbaren Speicher gibt und ob er nach dem Detach ausführbar bleibt (Test A), wie sich der unveränderte Kern verhält (Test B und C) und ob die Variante mit PR #34 läuft (Test D).

### Vorbereitung am Mac (einmalig, etwa 10 Minuten)

1. `m0/fundament` auschecken, nach dem Merge `main`. Dann nur die nötigen Submodule holen und den Kern bauen:
   ```bash
   git submodule update --init Cores/play
   git -C Cores/play submodule update --init deps/CodeGen deps/Dependencies deps/Framework deps/libchdr
   git -C Cores/play/deps/Dependencies submodule update --init ghc_filesystem xxHash zstd
   Scripts/build-core.sh play
   ```
2. Für Test D zusätzlich die Variante mit PR #34 bauen. Das Skript nimmt den abgelegten Diff des geprüften Stands und braucht kein Netz:
   ```bash
   Spikes/PS2JIT/try-codegen-pr34.sh build/experiments/pr34-geraet
   ```
   Wer wissen will, ob sich der PR seither geändert hat: `gh api repos/jpd002/Play--CodeGen/pulls/34 --jq .head.sha` (geprüft ist `23b29221…`).
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

### Test A: Bekommt die App ausführbaren Speicher, und bleibt er? (etwa 5 Minuten)

1. JIT-Spike vom Home-Bildschirm starten. Erwartung: „get-task-allow“ an, „CS_DEBUGGED“ aus, „TXM angenommen“ an. Den angezeigten Ergebnisordner notieren.
2. „JIT über StikDebug anfordern“ tippen. StikDebug öffnet sich, fragt eventuell nach Bestätigung, hängt sich an, führt `universal.js` aus und kehrt zur App zurück.
3. Die drei Proben ablesen, die nacheinander erscheinen, und einen Screenshot machen.
4. „Detach senden, dann Region erneut prüfen“ tippen und die zwei Proben „Nach Detach“ ablesen, wieder mit Screenshot.

| Probe | Bedeutung bei Erfolg |
| --- | --- |
| universal.js, Region vom Debugger | Der TXM-Weg funktioniert für Arcfold. Das ist die zentrale Frage des Spikes. |
| universal.js, eigene r-x-Region | Klärt den Widerspruch zwischen PR #34 (geht nicht) und Skriptcode (sollte gehen). |
| Play!s Weg (vm_protect auf r-x) | Der unveränderte Kern könnte laufen. Erwartet wird „Seite nicht ausführbar“. |
| Detach (x16 = 0) | `universal.js` hat die Verbindung getrennt; die Probe danach meldet, ob `P_TRACED` aus ist. |
| Nach Detach: Region vom Debugger, unbenutzte Seite | Neuer Code auf einer vorbereiteten, bisher unbenutzten Seite läuft ohne Debugger. So würde eine Arena nach INTEGRATION.md arbeiten. |
| Nach Detach: Region vom Debugger, erste Seite neu beschrieben | Überschriebener Code läuft ohne Debugger, wie bei Play!s Block-Verknüpfungen. |

Bestehen beide Proben „Nach Detach“, darf Arcfold den Debugger nach der Vorbereitung trennen, und PR #34 irrt an dieser Stelle. Scheitern sie („Seite nicht ausführbar“, „falsches Ergebnis“ oder Absturz), hat PR #34 recht: StikDebug muss während der ganzen Spielsitzung verbunden bleiben.

Mögliche Fehler: „CS_DEBUGGED kam nicht innerhalb von 120 s“ heißt, StikDebug hat sich nicht angehängt (VPN, Pairing-Datei, DDI; Log in StikDebug ansehen). „kein Debugger mehr verbunden“ heißt, StikDebug lief ohne Skript; in StikDebug der App `universal.js` zuordnen und erneut versuchen. Stürzt die App während einer Probe ab, steht diese Probe in `probes.json` mit dem Ergebnis „läuft“; zusätzlich den Absturzbericht sichern (unten).

### Test B: Unveränderter Kern mit JIT (etwa 3 Minuten)

Im selben App-Start nach Test A: Zeigt „JIT an den Kern gemeldet“ „nein“, den Schalter „Kern trotzdem starten“ einschalten und „alu.elf starten“ tippen. Erwartung unter TXM: Absturz beim ersten kompilierten Block. Läuft der Test durch und meldet „Ausgabe = alu.expected“, braucht Play! keinen Patch – das wäre die beste Nachricht.

### Test C: Ohne JIT (etwa 2 Minuten)

App beenden und neu starten, kein JIT anfordern, „alu.elf starten“. Erwartung: „Spiel geladen: nein“, „Cannot run without JIT“ und der Hinweis, kein Absturz.

### Test D: Variante mit PR #34 (etwa 10 Minuten)

1. Am Mac `Cores/Build/play_libretro.xcframework` beiseite schieben, `build/experiments/pr34-geraet/play_libretro.xcframework` an seine Stelle kopieren und JIT-Spike erneut mit Run installieren, danach wieder ⌘. drücken. Die App zeigt dann „JIT-Speicher: Arena vom Debugger (PR #34)“.
2. App vom Home-Bildschirm starten, JIT anfordern wie in Test A, aber **kein Detach senden**: Diese Variante fordert ihre Arena erst beim ersten kompilierten Block an. Dann „alu.elf starten“. Erwartung: „Ausgabe = alu.expected“.
3. App neu starten, JIT wieder ohne Detach anfordern, „Bilder für gs_sprites“ auf 18000 (5 Minuten) stellen und „gs_sprites.elf starten“. Bildrate, Prozent von NTSC und thermalState notieren.
4. Danach am Mac `Scripts/build-core.sh play` laufen lassen, damit wieder der normale Kern in `Cores/Build` liegt.

### Was notiert wird

- Gerät und iOS-Version (stehen in der App), StikDebug-Version.
- Ergebnis jeder Probe mit dem angezeigten Schutz (etwa „r-x“), auch der Proben „Nach Detach“.
- Für jeden Lauf: Spiel geladen, Meldung des Kerns, Ausgabe gleich `alu.expected`, Bildrate, thermalState vorher → nachher.
- Screenshots der App, bei Abstürzen den Bericht aus Einstellungen → Datenschutz & Sicherheit → Analyse & Verbesserungen → Analysedaten (`JITSpike-…`).
- Jeder App-Start schreibt in einen eigenen Ordner `Documents/SpikeResults/<Datum-Uhrzeit>/`: `probes.json` sofort nach jeder Probe, am Ende eines Laufs `report.json`, `ps2_stdout.txt` und `frame.png` (nur, wenn ein Bild entstand). Im Finder unter dem Duo → Dateien → JIT-Spike lassen sich die Ordner auf den Mac ziehen.

Erfolg im Sinne von ADR 0002: Test A „Region vom Debugger“ bestanden und Test D mit korrekter Ausgabe. Scheitert Test A, ist PS2 über StikDebug auf dem Duo derzeit nicht machbar. Die Proben „Nach Detach“ entscheiden, ob StikDebug während des Spielens verbunden bleiben muss.

## Quellen

- StikJIT, [INTEGRATION.md](https://github.com/StikDebug/StikJIT/blob/main/INTEGRATION.md), Commit `b3e01a3` (1. November 2026)
- StikDebug, [README](https://github.com/StikDebug/StikDebug), [PAIRING.md](https://github.com/StikDebug/StikDebug/blob/main/PAIRING.md), [SUPPORTED_APPS.md](https://github.com/StikDebug/StikDebug/blob/main/SUPPORTED_APPS.md), `StikDebug/Scripts/universal.js`, `legacy.js`, `JSSupport/JSDebugSupport.swift`, `Support/ProcessInfo+TXM.swift`, `Support/ScriptStore.swift`, `Views/HomeView.swift`, Commit `9d7a917` (6. November 2026)
- SideStore-Doku, [JIT](https://docs.sidestore.io/docs/advanced/jit), abgerufen am 6. November 2026
- Play!, Tag 0.77 (`fa75cea`), Issues [#1490](https://github.com/jpd002/Play-/issues/1490), [#1558](https://github.com/jpd002/Play-/issues/1558), [#1585](https://github.com/jpd002/Play-/issues/1585)
- Play--CodeGen, [PR #34](https://github.com/jpd002/Play--CodeGen/pull/34), Head `23b29221`, Beschreibung und Code abgerufen am 6. November 2026; [PR #32](https://github.com/jpd002/Play--CodeGen/pull/32)
- Play!, [PR #1622](https://github.com/jpd002/Play-/pull/1622) (Begleit-PR zu CodeGen #34), Stand 27. September 2026
- DolphiniOS, `Source/Core/Common/MemoryUtil_iOS_LuckTXM.cpp` und `Source/iOS/App/Common/Jit/JitManager+Debugger.m` ([OatmealDome/dolphin-ios](https://github.com/OatmealDome/dolphin-ios))
- UTM, Commit [`678534e`](https://github.com/utmapp/UTM/commit/678534e6a57e73656bf9a44f2e0189bdaa71a7c6) „new JIT workaround for iOS 26“
- XNU `xnu-12377.121.6`, `osfmk/kern/cs_blobs.h` und `bsd/sys/codesign.h` ([apple-oss-distributions/xnu](https://github.com/apple-oss-distributions/xnu))
- swift-build ([swiftlang/swift-build](https://github.com/swiftlang/swift-build)), Commit `699c510`: `Sources/SWBUtil/Path.swift`, `Sources/SWBCore/BuildFileFilteringContext.swift`
- Apple, [Debugging tool entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.cs.debugger) (Xcode setzt `get-task-allow` für Debug-Builds), [Enabling Developer Mode on a device](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device), [Choosing a Membership](https://developer.apple.com/support/compare-memberships/)
- libretro.h aus Play! 0.77 (`Source/ui_libretro/ext/libretro.h`), `RETRO_ENVIRONMENT_GET_JIT_CAPABLE`
