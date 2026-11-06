# Spike PS2-JIT

Wegwerf-Prototyp für [ADR 0002](../../docs/adr/0002-ps2-jit.md). Die App lädt den Play!-Kern per `dlopen`, liest `retro_get_system_info`, startet ein Test-ELF mit einem OpenGL-ES-3-Kontext und prüft, ob JIT verfügbar ist. Sie gehört nicht zur Arcfold-App und wird nach der Entscheidung nicht weiterentwickelt.

## Inhalt

| Datei | Zweck |
| --- | --- |
| `project.yml` | XcodeGen-Projekt `JITSpike` (Bundle-ID `com.faentiver.arcfold.spike.jit`, iOS 27.0, Swift 6) |
| `Sources/Host/PS2SpikeHost.m` | Minimaler libretro-Host: Callbacks, `RETRO_ENVIRONMENT_GET_JIT_CAPABLE`, EAGL-Kontext mit Framebuffer, Bild auslesen |
| `Sources/Host/ArcJIT.c` | `csops`-Flags, `P_TRACED`, TXM-Annahme, Haltepunkt-Protokoll von `universal.js`, Ausführungsprobe mit wählbarer Seite und wählbarem Rückgabewert |
| `Sources/App/` | SwiftUI-Oberfläche und Ablauf; `ResultStore.swift` legt je App-Start einen Ordner unter `Documents/SpikeResults/` an |
| `run-simulator.sh` | Bauen, im Simulator starten, Bericht und Screenshots einsammeln |
| `try-codegen-pr34.sh` | Kern-Variante mit Play--CodeGen PR #34 und Begleitpatch aus einer Kopie des Submoduls bauen (Version `0.77-pr34`), ohne Netz |
| `patches/codegen-pr34-23b29221.patch` | Diff von Play--CodeGen PR #34 am geprüften Head `23b29221`, mit Herkunft und Lizenz im Kopf |
| `patches/play-basicblock-writable-alias.patch` | Begleitpatch: Block-Verknüpfungen über den beschreibbaren Alias der JIT-Arena schreiben |

Testprogramme kommen aus `Tests/Fixtures/ps2/`: `alu.elf` (CPU-Test, Ausgabe muss `alu.expected` entsprechen) und `gs_sprites.elf` (Bild und Bildrate).

## Bauen und im Simulator ausführen

Vor dem Bau des Kerns `Cores/play` und nur die Unter-Submodule holen, die der Kern braucht (Liste im Kopf von `Scripts/cores/play.sh`):

```bash
git submodule update --init Cores/play
git -C Cores/play submodule update --init deps/CodeGen deps/Dependencies deps/Framework deps/libchdr
git -C Cores/play/deps/Dependencies submodule update --init ghc_filesystem xxHash zstd
Scripts/build-core.sh play
Spikes/PS2JIT/run-simulator.sh <simulator-udid> <ausgabeordner> -program alu
Spikes/PS2JIT/run-simulator.sh <simulator-udid> <ausgabeordner> -program gs_sprites -maxFrames 600
Spikes/PS2JIT/run-simulator.sh <simulator-udid> <ausgabeordner> -program alu -jitCapable NO
```

Der letzte Aufruf meldet dem Kern „kein JIT“. Play! lehnt dann mit „Cannot run without JIT“ ab, statt abzustürzen.

Jeder App-Start schreibt in einen eigenen Ordner `Documents/SpikeResults/<name>/`: `probes.json` nach jeder Probe (eine Probe, die gerade läuft, steht dort mit „läuft“, falls sie die App beendet), am Ende eines Laufs `report.json`, `ps2_stdout.txt` und, nur wenn ein Bild entstand, `frame.png`. `run-simulator.sh` gibt den Namen mit `-resultsName` vor. Auf dem Gerät hält die App die Region aus der ersten Probe fest und prüft sie nach einem Detach noch einmal mit neuem Code; im Simulator läuft dieselbe Nachprobe auf dem lokalen Dual-Mapping.

Im Simulator gelten die Regeln des Macs für ausführbaren Speicher. Ein Erfolg dort sagt nichts über JIT auf dem iPhone. Den Gerätetest beschreibt [docs/wissen/ps2-jit.md](../../docs/wissen/ps2-jit.md).

## Grenzen

- libretro erlaubt einen Kern pro Prozess; pro App-Start läuft ein Test.
- Kein Ton, keine Eingabe, keine Anzeige im Vollbild. Das letzte Bild wird aus dem Framebuffer gelesen und als PNG gespeichert.
- Der Standard-Kern ist unverändert (Play! 0.77). Seine JIT-Speicherverwaltung passt nicht zu Geräten mit TXM, siehe ADR 0002. Die Variante aus `try-codegen-pr34.sh` ist ein Experiment und kein Teil des Rezepts.
