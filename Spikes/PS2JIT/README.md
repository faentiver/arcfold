# Spike PS2-JIT

Wegwerf-Prototyp für [ADR 0002](../../docs/adr/0002-ps2-jit.md). Die App lädt den Play!-Kern per `dlopen`, liest `retro_get_system_info`, startet ein Test-ELF mit einem OpenGL-ES-3-Kontext und prüft, ob JIT verfügbar ist. Sie gehört nicht zur Arcfold-App und wird nach der Entscheidung nicht weiterentwickelt.

## Inhalt

| Datei | Zweck |
| --- | --- |
| `project.yml` | XcodeGen-Projekt `JITSpike` (Bundle-ID `com.faentiver.arcfold.spike.jit`, iOS 27.0, Swift 6) |
| `Sources/Host/PS2SpikeHost.m` | Minimaler libretro-Host: Callbacks, `RETRO_ENVIRONMENT_GET_JIT_CAPABLE`, EAGL-Kontext mit Framebuffer, Bild auslesen |
| `Sources/Host/ArcJIT.c` | `csops`-Flags, `P_TRACED`, TXM-Annahme, Haltepunkt-Protokoll von `universal.js`, Ausführungsprobe |
| `Sources/App/` | SwiftUI-Oberfläche und Ablauf, Ergebnis nach `Documents/SpikeResults/` |
| `run-simulator.sh` | Bauen, im Simulator starten, Bericht und Screenshots einsammeln |

Testprogramme kommen aus `Tests/Fixtures/ps2/`: `alu.elf` (CPU-Test, Ausgabe muss `alu.expected` entsprechen) und `gs_sprites.elf` (Bild und Bildrate).

## Bauen und im Simulator ausführen

```bash
Scripts/build-core.sh play
Spikes/PS2JIT/run-simulator.sh <simulator-udid> <ausgabeordner> -program alu
Spikes/PS2JIT/run-simulator.sh <simulator-udid> <ausgabeordner> -program gs_sprites -maxFrames 600
Spikes/PS2JIT/run-simulator.sh <simulator-udid> <ausgabeordner> -program alu -jitCapable NO
```

Der letzte Aufruf meldet dem Kern „kein JIT“. Play! lehnt dann mit „Cannot run without JIT“ ab, statt abzustürzen.

Im Simulator gelten die Regeln des Macs für ausführbaren Speicher. Ein Erfolg dort sagt nichts über JIT auf dem iPhone. Den Gerätetest beschreibt [docs/wissen/ps2-jit.md](../../docs/wissen/ps2-jit.md).

## Grenzen

- libretro erlaubt einen Kern pro Prozess; pro App-Start läuft ein Test.
- Kein Ton, keine Eingabe, keine Anzeige im Vollbild. Das letzte Bild wird aus dem Framebuffer gelesen und als PNG gespeichert.
- Der Kern ist unverändert (Play! 0.77). Seine JIT-Speicherverwaltung passt nicht zu Geräten mit TXM, siehe ADR 0002.
