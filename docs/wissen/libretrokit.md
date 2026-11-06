---
name: libretrokit
description: Aufbau von LibretroKit (Laden per dlopen, Emulations-Thread, Takt, Callbacks, Environment, Batteriespeicher, Messwerte), Eigenheiten von mGBA 0.10.5 und Stolperfallen
---

# LibretroKit

Stand 7. November 2026 (M1, Spur K). Paket unter `Packages/LibretroKit`, swift-tools-version 6.4, iOS 27, Swift 6 mit Strict Concurrency. Entscheidungen: ADR 0003 (Kerne als Frameworks) und ADR 0005 (Laufzeit für Software-Kerne).

## Aufbau

| Teil | Rolle |
| --- | --- |
| `CLibretro` | `include/libretro.h` unverändert (Herkunft in `Sources/CLibretro/README.md`), dazu der Log-Shim `arcfold_log.h/.c`, die Signposts `arcfold_signpost.h/.c` und der Umbrella-Header `CLibretro.h`. LibretroKit importiert es mit `internal import`, die öffentliche API ist reines Swift. |
| `LibretroCore` | Öffnet `<name>.framework` aus `Bundle.privateFrameworksURL` per `dlopen(RTLD_NOW \| RTLD_LOCAL)`, löst beim Öffnen alle benutzten `retro_*`-Funktionen per `dlsym` auf (`CoreFunctions`) und schließt in `deinit`. Die Lebenszyklus-Funktionen sind interne Methoden (`LibretroCore+Lifecycle.swift`). |
| `EmulationSession` | Öffentliche Fassade. Hält nur `SessionControl` und leitet Befehle weiter. Ohne `stop()` freigegeben, stoppt sie selbst. |
| `SessionControl` | Das Geteilte: `Mutex`-Postfach mit `Atomic<Bool>`-Merker, `DispatchSemaphore` zum Wecken, Zustand als `Atomic<UInt8>`, `InputState`, `SessionStats`, `AsyncStream` der Ereignisse. |
| `EmulationThread` | Läuft auf dem Thread „Arcfold Emulation“ und besitzt Kern, `CallbackContext`, `FrameClock` und `BatterySaveMonitor`. Nichts davon ist `Sendable`. |
| `CallbackSlot`, `CallbackContext` | Ein globales `Atomic<UInt>` mit den `Unmanaged`-Bits des Kontexts und sechs `@convention(c)`-Trampoline als `static let`. Der Kontext beantwortet Environment, Bild, Ton und Eingabe. |
| `FrameClock` | Werttyp mit eingespeister Zeit: Fristplan und PI-Regler. |
| `BatterySaveFile`, `BatterySaveWriter`, `BatterySaveMonitor` | Dateilogik, Schreiber auf der `.utility`-Queue, Vergleich auf dem Emulations-Thread. |
| `CoreOptions`, `CoreLog`, `InputState`, `SessionStats`, `HostTime` | Kernoptionen, Log-Senke mit Ratenbegrenzung, Eingabe, Messwerte, Mach-Zeit. |

## Lebenszyklus einer Sitzung

1. `load()`: Zustand `.idle` → `.loading`, Postfach offen. Ein `Thread` mit Name „Arcfold Emulation“, QoS `.userInteractive` und 16 MiB Stack startet.
2. Auf dem Thread: System- und Spielstandordner sowie der Ordner des Batteriespeichers werden angelegt, falls sie fehlen. Dann den Callback-Platz belegen (sonst `.anotherSessionActive`), Kern öffnen, API-Version prüfen.
3. Callbacks setzen, `retro_set_environment` zuerst, `retro_init`, Thread-Namen erneut setzen.
4. Spiel als `NSData(contentsOf:options: .alwaysMapped)` lesen und mit `data`, `size` und `path` an `retro_load_game` geben. `NSData` statt `Data`, weil `bytes` dokumentiert so lange gilt wie das Objekt; die Sitzung hält es bis `retro_unload_game`.
5. Pixelformat prüfen (RGB565 oder XRGB8888), AV-Info lesen, Batteriespeicher in den Kern kopieren, Zustand `.ready`, `load()` kehrt zurück.
6. Schleife: pro Bild nur der Merker; Befehle mit `withLockIfAvailable`, im Leerlauf mit `withLock` und Warten an der Semaphore. `runFrames` läuft ohne Takt, `resume()` mit dem `FrameClock`. Jedes Bild läuft in einem `autoreleasepool`.
7. `stop()`: Batteriespeicher sofort sichern und auf die Platte warten, `retro_unload_game`, `retro_deinit`, Platz freigeben, `dlclose`, Zustand `.stopped`, offene Fortsetzungen beantworten, `events` beenden.

Fehler beim Laden enden in `.failed`; alles bis dahin Geladene wird zurückgebaut, der Platz ist wieder frei. `stop()` geht in jedem Zustand und endet in `.stopped`. Befehle an eine Sitzung ohne Thread (vor `load()`, nach dem Ende) werden sofort beantwortet. `SHUTDOWN` vom Kern beendet die Sitzung wie `stop()`.

## Takt (`FrameClock`)

- Absolute Fristen in Mach-Ticks, der Bruchteil eines Ticks wird mitgeführt: Nach 10⁶ Bildern liegt die Frist höchstens einen Tick neben `start + 10⁶ · P` (Test).
- Verspätung bis drei Perioden holt der Plan ohne Wartezeit auf, die Fristen bleiben im Raster. Darüber beginnt der Plan bei „jetzt“, `resyncs` zählt, Signpost „resync“.
- PI-Regler nach ADR 0005 nur bei `isConsuming`, sonst `trim · 0,95` pro Bild. `.unthrottled` wartet nie, `FrameStamp.nominalTime` ist dann die Startzeit.
- Simulation in den Tests (10 min, Gerät mit 256 Frames bei 48 kHz, Laufzeiten 1,5 bis 3,5 ms plus seltene Spitzen bis 15,5 ms, Sollwert 35 ms): bei −500, −100, +100 und +500 ppm Drift 0 Aussetzer, 0 Neusynchronisationen, mittlerer `trim` in der zweiten Hälfte +500,5, +100,3, −99,8 und −499,5 ppm, kleinster Füllstand beim Spielen 18,6 ms.

## Environment

Gezählt wird jeder Aufruf in `SessionSummary.environmentCalls`; `unhandledEnvironmentCommands` enthält jeden mangels Unterstützung abgelehnten Befehl.

| Befehl (Nr.) | Antwort |
| --- | --- |
| `GET_CORE_OPTIONS_VERSION` (52) | `false`, nicht als unbehandelt gezählt |
| `SET_VARIABLES` (16) | `true`; Schlüssel und Standardwert (erster Wert nach `;`) werden sofort kopiert |
| `GET_VARIABLE` (15) | Wert aus `coreOptions`, sonst Standardwert, als C-String mit fester Adresse für die ganze Sitzung; unbekannte Schlüssel `false` und `value = NULL` |
| `GET_VARIABLE_UPDATE` (17) | `*data = false`, `true` |
| `SET_PIXEL_FORMAT` (10) | `true` für RGB565 und XRGB8888, sonst `false` (unbehandelt); nach dem Laden nur noch dasselbe Format |
| `GET_INPUT_BITMASKS` (51 \| EXP) | `true`, `data` bleibt unberührt |
| `SET_INPUT_DESCRIPTORS` (11) | `true`, ignoriert |
| `GET_LOG_INTERFACE` (27) | C-Shim |
| `GET_SYSTEM_DIRECTORY` (9), `GET_SAVE_DIRECTORY` (31) | Pfade aus der Konfiguration |
| `GET_CAN_DUPE` (3) | `true`; `NULL`-Bilder erreichen die Senke nicht |
| `SET_GEOMETRY` (37) | `true`, Größe bis zum Maximum; vor dem Laden `false` |
| `SHUTDOWN` (7) | `true`, Ereignis `coreRequestedShutdown`, die Sitzung endet |
| `SET_MESSAGE` (6), `SET_MESSAGE_EXT` (60) | `true`, Ereignis `coreMessage` |
| `GET_JIT_CAPABLE` (74) | `true` mit `*data = false`, nicht als unbehandelt gezählt |
| `SET_SYSTEM_AV_INFO` (32) | `false`, protokolliert, unbehandelt |
| alle übrigen, etwa `SET_MEMORY_MAPS`, `SET_SUPPORT_ACHIEVEMENTS`, `SET_HW_RENDER` | `false`, unbehandelt |

## Batteriespeicher

- Dateien: `battery.sav`, die vorige Fassung `battery.sav.bak` und während des Schreibens `battery.sav.tmp`.
- **Laden** vor dem ersten `retro_run`: liegengebliebene `.tmp` löschen, dann `min(Datei, Speicher)` Byte kopieren. Die Sicherung kommt zum Zug, wenn die Hauptdatei fehlt, leer, unlesbar oder kürzer als die Sicherung ist. „Kürzer als erwartet“ heißt also „kürzer als die Sicherung“: Eine Hauptdatei kürzer als der Kernspeicher ist bei mGBA normal (32 KiB Datei, 128 KiB Speicher vor der Erkennung).
- **Prüfen** alle 30 Bilder per `memcmp`. Geschrieben wird, wenn sich der Inhalt seit dem letzten Schreiben geändert hat und seit der vorigen Prüfung gleich geblieben ist. Ein geschrumpfter Speicher mit gleichem Inhalt gilt nicht als Änderung.
- **Übergabe:** zwei beim Laden angelegte Puffer, je mit einem einmal angelegten `DispatchWorkItem` für die serielle `.utility`-Queue. Ein Dispatch-Block darf beliebig oft laufen, solange niemand auf ihn wartet (`dispatch/block.h`). Sind beide Puffer unterwegs, wartet eine periodische Sicherung auf die nächste Prüfung.
- **Schreiben:** `createFile` für `.tmp`, `FileHandle.write`, `synchronize()`, `close()`, dann `replaceItemAt(_:withItemAt:backupItemName:options: .withoutDeletingBackupItem)`. Das klappt auch ohne vorhandene Hauptdatei und ersetzt eine alte `.bak` (belegt auf macOS und in den Simulator-Tests). Keine Schutzklasse `.complete`.
- **Sofort** bei `pause()`, `saveBatteryNow()` und `stop()` (vor `retro_unload_game`); `pause()` und `saveBatteryNow()` kehren zurück, wenn die Datei auf der Platte ist. Solange keine Datei existiert und der Speicher nur 0xFF enthält, wird nie geschrieben.
- Ereignisse `batterySaveWritten(bytes:)` und `batterySaveFailed(reason:)` kommen von der Queue.

## Messwerte und Signposts

- `SessionStats`: relaxed Atomics, ein Schreiber. Veröffentlicht etwa einmal pro Sekunde und bei jedem Zustandswechsel. Kürzere Intervalle als 0,25 s behalten Bildrate und Maxima des letzten vollen Intervalls.
- Späte Bilder: Start mehr als 2 ms nach der Frist.
- Signposts (Subsystem `com.faentiver.arcfold`, Kategorie `emulation`): Intervall „retro_run“ und Ereignis „resync“, aus C über `os_signpost_interval_begin/end`.
- Log der Kerne: Kategorie `core`, Mindeststufe WARN im C-Shim, darüber höchstens 20 Zeilen pro Sekunde, danach eine Zeile mit der Zahl der verworfenen.

## Echtzeitpfad ohne Allokation (belegt)

- Pro Bild laufen auf dem Emulations-Thread: Merker-Abfrage, `FrameClock`, `mach_wait_until`, Signposts, `retro_run` mit Video-, Audio- und Eingabe-Trampolin, `GET_VARIABLE_UPDATE`, Senkenaufrufe, Messwerte und alle 30 Bilder der Vergleich des Batteriespeichers. Keiner dieser Schritte nimmt eine Sperre.
- Messung am 7. November 2026: dieselben Quellen für macOS gebaut, mGBA 0.10.5 für macOS, `selftest.gba` mit gedrückter Taste A, Senken ohne eigene Allokation, `malloc` und Verwandte per `DYLD_INSERT_LIBRARIES` auf dem Thread „Arcfold Emulation“ gezählt (Werkzeug im Scratchpad, nicht im Repo):
  - optimiert (`-O`): `runFrames(1)`, `(1000)` und `(2000)` je 0 Allokationen, einschließlich mGBA und der Übergaben an den Schreiber; 3 s Echtzeit mit `resume`/`pause` 1 Allokation (die Fortsetzung von `pause`).
  - unoptimiert (`-Onone`, wie der Debug-Build): 1 Allokation pro Befehl (`removeFirst` im Postfach), keine pro Bild.
- Vorher gefunden und behoben: `OSSignposter.beginInterval` legt pro Intervall ein Objekt und zwei Puffer an, auch ohne Instruments (`isEnabled` war in der Messung auf macOS `true`); ein `Dictionary`-Zähler legte im Debug-Build pro `GET_VARIABLE_UPDATE` Speicher an; `queue.async` mit Closure legte pro Übergabe zwei Blöcke an.

## Eigenheiten von mGBA 0.10.5 (belegt)

- RGB565 240 × 160, Pitch 512, immer derselbe Zeiger, nie ein `NULL`-Bild. 59,7275009155 Bilder/s, 32 768 Hz.
- Ruft `GET_INPUT_BITMASKS` mit `data = NULL`. Pro Bild einmal `input_poll` und `GET_VARIABLE_UPDATE`.
- Ohne Optionen v1/v2 meldet mGBA 13 Optionen über `SET_VARIABLES` und gibt die Zeichenketten gleich danach frei; `GET_VARIABLE` 8-mal beim Laden.
- Lehnt der Host nur `SET_MEMORY_MAPS` und `SET_SUPPORT_ACHIEVEMENTS` ab, ist `unhandledEnvironmentCommands` genau diese Menge.
- Batteriespeicher: ein 128-KiB-Puffer voller 0xFF; `retro_get_memory_size` meldet 131 072 bis zur Erkennung des Speichertyps, dann die echte Größe (SRAM 32 768). mGBA übernimmt den Pufferinhalt erst im ersten `retro_run` („deferred setup“), deshalb muss der Spielstand davor im Puffer stehen. `retro_unload_game` gibt den Puffer frei.
- `retro_load_game` kopiert die Spieldaten; der Host hält sie trotzdem bis zum Entladen (Vertrag von libretro).
- Ton: ein Batch pro Bild, das erste mit 80 Frames, danach 545 bis 552, im Mittel 548,62; dieselbe Verteilung wie auf macOS. `realloc` des Tonpuffers nur, solange er wächst.
- Mit frischem Spielstand stimmen die SHA-256 der Bilder 1, 60 und 300 im iOS-Simulator mit den macOS-Werten überein (`docs/adr/0005/selftest-mgba-macos.txt`); Bildzähler = Bildnummer − 6.
- Loggt „Savedata synced“ und ähnliches auf Stufe INFO; unter WARN wird das nur gezählt.

## Entscheidungen

- **Nicht kopierbar (`~Copyable`)**: Der Wert besitzt das Handle. Genau ein Besitzer, genau ein `dlclose`; `_ = consume core` schließt den Kern, bevor die Sitzung ihr Ende meldet.
- **Nicht `Sendable`** (`@available(*, unavailable) extension LibretroCore: Sendable {}`). **Warum:** Kerne haben globalen Zustand und sind nicht threadsicher. **Anwenden:** Der Kern entsteht auf dem Emulations-Thread und verlässt ihn nie.
- **Typed throws** (`throws(LibretroError)`, `throws(SessionError)`), damit Aufrufer ohne Casts auf die Fälle schalten können.
- **Kein Kernaufruf auf dem Main Thread**: Die App liest die Kern-Infos in einer `@concurrent`-Funktion (`CoreCatalog.load`), Sitzungen laufen auf ihrem Thread.

## Stolperfallen

- Ein `~Copyable`-Struct darf in `init` seine Properties nicht bedingt setzen. Lösung: erst in lokale Konstanten auflösen, dann alle Properties am Ende setzen.
- `do throws(LibretroError) { … } catch { … }` schreiben. Ohne die Angabe ist `error` im `catch` vom Typ `any Error`.
- Mit Member Import Visibility braucht jede Datei, die Member eines Typs aus LibretroKit benutzt, selbst `import LibretroKit`.
- Paket-Test für „Symbol fehlt“: Ein Symlink auf die Binärdatei des Test-Bundles als Framework-Binärdatei ergibt den Fehlerfall ohne echten Kern.
- `Bundle(url:)` merkt sich Bundles pro Pfad. Tests legen deshalb je Fall einen eigenen Ordner mit UUID an.
- `RETRO_DEVICE_MASK` ist ein Makro mit Ausdruck und kommt in Swift nicht an; stattdessen `(1 << RETRO_DEVICE_TYPE_SHIFT) - 1`.
- **Umbrella-Verzeichnis:** Ohne Header mit dem Namen des Targets erzeugt SwiftPM für `CLibretro` die Module-Map `umbrella "include"`. Ein später hinzugefügter Header kam dann nicht in das vorher gebaute Modul für `iphoneos`, und der Geräte-Build scheiterte mit „cannot find 'arcfold_signpost_run_begin' in scope“, während die Simulator-Builds liefen. **Anwenden:** Jeden Header in `include/CLibretro.h` eintragen; die geänderte Module-Map baut das Modul neu, auch in einem vorhandenen DerivedData.
- `retro_log_printf_t` ist variadisch: Swift sieht `retro_log_callback.log` nur als `OpaquePointer?`. Deshalb der C-Shim.
- Die Sitzung eines nie geladenen Kerns hat keinen Thread, der `events` beendet: Das erledigt `stop()` selbst, sonst hängt `for await`.
- Swift Testing: `#expect(menge == [ … ])` mit einem `Set` links verglich in einem Fall mit einem Array-Literal und schlug trotz gleicher Elemente fehl. Erwartete Mengen als `let erwartet: Set<UInt32> = [ … ]` anlegen.
- `#expect` nimmt keine `~Copyable`-Werte; Testhilfen als Klasse schreiben.
- Weckzeiten im Simulator: `mach_wait_until` wacht dort bis etwa 2 ms zu spät auf (Timer-Coalescing des Mac). Im Echtzeit-Test lagen 0 von 182 Bildern mehr als 2,5 ms nach ihrer Frist, aber ein Viertel über der Grenze von 2 ms für „späte Bilder“. Die Zahl ist im Simulator deshalb kein Maßstab; die Bildrate stimmte (59,7). Auf dem Gerät offen.
