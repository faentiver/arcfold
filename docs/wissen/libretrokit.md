---
name: libretrokit
description: Aufbau von LibretroKit (Laden per dlopen, Emulations-Thread, Takt, Callbacks, Environment, Batteriespeicher, Zeiger, Messwerte), Eigenheiten von mGBA 0.10.5 und melonDS DS 1.4.0 und Stolperfallen
---

# LibretroKit

Stand 7. November 2026 (M1, nach der Integration von Spur K und Spur A; dazu M2 mit melonDS DS, belegt im iOS-Simulator). Paket unter `Packages/LibretroKit`, swift-tools-version 6.4, iOS 27, Swift 6 mit Strict Concurrency. Entscheidungen: ADR 0003 (Kerne als Frameworks), ADR 0005 (Laufzeit für Software-Kerne) und ADR 0006 (DS und Falz-Layouts).

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
| `CoreOptions`, `CoreLog`, `InputState`, `SessionStats`, `HostTime` | Kernoptionen, Log-Senke mit Ratenbegrenzung, Eingabe, Messwerte, Mach-Zeit. `InputState` zählt außerdem jeden Tastendruck (`pressCount`) und hält den letzten fest (`lastPressedButtons`), für das Debug-Overlay und den UI-Test der Touch-Tasten. |

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
- Geregelt wird der Füllstand vor dem Ton des Bildes: `bufferedFrames` nach dem letzten Schreiben minus alle Frames, die das Bild geschrieben hat (`CallbackContext.audioFramesWritten`, Batch und Einzelsamples), gegen `targetFrames`, die Reserve der Senke. `AudioRing` meldet als `targetFrames` den Füllstand zum Auffüllen (35 ms).
- Simulation in den Tests (10 min, Gerät mit 256 Frames bei 48 kHz, Laufzeiten 1,5 bis 3,5 ms plus seltene Spitzen bis 15,5 ms, Reserve 35 ms): bei −500, −100, +100 und +500 ppm Drift 0 Aussetzer, 0 Neusynchronisationen, mittlerer `trim` in der zweiten Hälfte +500,6, +100,3, −99,7 und −499,5 ppm, kleinster Füllstand beim Spielen 20,6, 20,6, 18,6 und 18,6 ms. Der Test verlangt mehr als 10 ms.
- Gegenprobe mit derselben Simulation, aber der Reserve als Sollwert für den Pegel direkt nach dem Schreiben (so wirkten der erste Vertrag in `Sinks.swift` und `AudioRing` vor der Integration zusammen): kleinster Füllstand 2,1 bis 3,3 ms, bei +500 ppm 2 Aussetzer (einmaliger Lauf bei der Integration, nicht als Test im Repo). **Warum:** Zwischen zwei Bildern verbraucht die Ausgabe ein Bild Ton (rund 17 ms), die Reserve muss davor liegen. **Anwenden:** Eine neue Senke meldet als `targetFrames` die Reserve, die sie vor neuem Ton braucht, nicht den Pegel nach dem Schreiben.

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
- **Laden** vor dem ersten `retro_run`: liegengebliebene `.tmp` löschen, dann `min(Datei, Speicher)` Byte kopieren; ist `blankSaveMemoryByte` gesetzt, füllt es den Rest dahinter (seit der Prüfung von M2, siehe unten). Die Sicherung kommt zum Zug, wenn die Hauptdatei fehlt, leer, unlesbar oder kürzer als die Sicherung ist. „Kürzer als erwartet“ heißt also „kürzer als die Sicherung“: Eine Hauptdatei kürzer als der Kernspeicher ist bei mGBA normal (32 KiB Datei, 128 KiB Speicher vor der Erkennung).
- **Prüfen** alle 30 Bilder per `memcmp`. Geschrieben wird, wenn sich der Inhalt seit dem letzten Schreiben geändert hat und seit der vorigen Prüfung gleich geblieben ist. Ein geschrumpfter Speicher mit gleichem Inhalt gilt nicht als Änderung.
- **Übergabe:** zwei beim Laden angelegte Puffer, je mit einem einmal angelegten `DispatchWorkItem` für die serielle `.utility`-Queue. Ein Dispatch-Block darf beliebig oft laufen, solange niemand auf ihn wartet (`dispatch/block.h`). Sind beide Puffer unterwegs, wartet eine periodische Sicherung auf die nächste Prüfung.
- **Schreiben:** `createFile` für `.tmp`, `FileHandle.write`, `synchronize()`, `close()`, dann `replaceItemAt(_:withItemAt:backupItemName:options: .withoutDeletingBackupItem)`. Das klappt auch ohne vorhandene Hauptdatei und ersetzt eine alte `.bak` (belegt auf macOS und in den Simulator-Tests). Keine Schutzklasse `.complete`.
- **Sofort** bei `pause()`, `saveBatteryNow()` und `stop()` (vor `retro_unload_game`); `pause()` und `saveBatteryNow()` kehren zurück, wenn die Datei auf der Platte ist. Solange keine Datei existiert und der Speicher nur 0xFF enthält, wird nie geschrieben.
- Ereignisse `batterySaveWritten(bytes:)` und `batterySaveFailed(reason:)` kommen von der Queue.

## Zeiger (seit M2, ADR 0006)

- `PointerPosition` hält x und y in libretro-Koordinaten: −32767 bis 32767 überspannen das ganze Kernbild. `PointerPosition(pixelX:pixelY:frameWidth:frameHeight:)` zielt auf die Pixelmitte, `round((b + 0,5) / W · 65534 − 32767)`; das DS-Pixel (x, y) des unteren Bildschirms ist Pixel (x, 192 + y) im 256 × 384 großen Bild. `PointerPositionTests` prüft alle Pixel für 192, 256, 384 und 512 gegen die Rückrechnung beider melonDS-Kerne.
- `InputState.setPointer(_:)` hat genau einen Schreiber, den Touchscreen der App; `nil` hebt ab, die letzten Koordinaten bleiben. x, y und „gedrückt“ stehen in einem `Atomic<UInt64>`, sodass der Emulations-Thread nie x eines Tipps mit y eines anderen sieht.
- Latch: Ein Druck, der seit der letzten Abfrage begann, steht mit seiner Anfangsposition im Latch. `pollPointer()` nimmt die aktuelle Position, solange gedrückt ist, sonst einmal den Latch; danach ist der Latch leer. Ein Tipp kürzer als ein Bild kommt so genau ein Bild lang an.
- `CallbackContext.inputState` beantwortet `RETRO_DEVICE_POINTER` auf Port 0 und Index 0: X, Y, PRESSED und COUNT (0 oder 1). Andere Indizes (Mehrfachberührung) und Ports sehen 0.
- `pointerPressCount` und `lastPointerPress` halten fest, was ein Tipp bewirkt hat, für das Debug-Overlay und den UI-Test, wie `pressCount` bei den Tasten.
- Belegt mit melonDS DS im Simulator (`CoreSessionTests.DS.Touch`): alle 256 Spalten (y = 100) und alle 192 Zeilen (x = 128), je 3 Bilder gedrückt und 2 los, 448 von 448 richtig (Blöcke, Rohwerte = Pixel · 16, Fadenkreuz mit rotem Kreuzungspunkt genau am Pixel, Stift-Bit nur während des Drückens, Touch-Zähler + 448 mod 256). Ein Tipp mit `setPointer` und `setPointer(nil)` vor `runFrames(1)` kommt an: Position, Zähler 1, Fadenkreuz, `pointerPressCount` 1.

## Leerer Spielstand und Fehlerbild (seit M2, ADR 0006)

- `SessionConfiguration.blankSaveMemoryByte`: Fehlen `battery.sav` und `battery.sav.bak`, füllt `BatterySaveMonitor.load(into:blankByte:)` den Spielstand vor dem ersten `retro_run` mit diesem Byte. Der DS nimmt 0xFF, weil melonDS DS mit 0x00 beginnt; leere EEPROM- und Flash-Bausteine lesen 0xFF. Ein Speicher nur aus 0xFF wird weiterhin nie geschrieben, solange keine Datei existiert. Seit der Prüfung füllt das Byte auch den Rest hinter einer Datei, die kürzer ist als der Spielstand des Kerns, etwa wenn eine neue Version von melonDS die Größe aus ihrer ROM-Datenbank ändert; vorher blieb dort 0x00. Ohne das Byte (mGBA) behält der Rest, was der Kern hineingelegt hat. Tests `aSaveFileWinsOverTheBlankByte` und `withoutABlankByteTheRestKeepsWhatTheCorePutThere`.
- `SessionConfiguration.requiresSystemMemory`: Meldet der Kern nach `retro_load_game` keinen `RETRO_MEMORY_SYSTEM_RAM`, scheitert `load()` mit `SessionError.gameNotRunnable`; das Spiel wird entladen. melonDS DS lädt ein verschlüsseltes Spiel ohne echtes BIOS mit Rückgabe `true` und zeigt dann ein Fehlerbild, bei dem `SYSTEM_RAM` und `SAVE_RAM` 0 melden. Für mGBA aus, weil andere Kerne `SYSTEM_RAM` womöglich gar nicht melden.
- Belegt mit melonDS DS im Simulator (`CoreSessionTests.DS`): Ohne Datei bleiben im Spielstand von `selftest.nds` nach drei Sitzungen die Bytes 6 bis 8191 bei 0xFF, ohne die Füllung bei 0x00. Die verschlüsselte Variante endet in `.gameNotRunnable` und `.failed`, schreibt keinen Spielstand, und eine folgende DS-Sitzung im selben Prozess läuft.

## Messwerte und Signposts

- `SessionStats`: relaxed Atomics, ein Schreiber. Veröffentlicht etwa einmal pro Sekunde und bei jedem Zustandswechsel. Kürzere Intervalle als 0,25 s und Intervalle ohne Bilder behalten Bildrate und Maxima des letzten vollen Intervalls. **Warum:** Die App pausiert auf dem Weg in den Hintergrund zweimal (inaktiv, dann Hintergrund); vor der Korrektur bei der Integration veröffentlichte die zweite Pause 0 Bilder/s, und das Overlay zeigte das nach dem Fortsetzen bis zur nächsten Messung. **Anwenden:** Neue Messwerte, die über ein Intervall gemittelt werden, nur aus Intervallen mit Bildern bilden.
- Späte Bilder: Start mehr als 2 ms nach der Frist.
- Signposts (Subsystem `com.faentiver.arcfold`, Kategorie `emulation`): Intervall „retro_run“ und Ereignis „resync“, aus C über `os_signpost_interval_begin/end`.
- Log der Kerne: Kategorie `core`, Mindeststufe WARN im C-Shim, darüber höchstens 20 Zeilen pro Sekunde, danach eine Zeile mit der Zahl der verworfenen.

## Echtzeitpfad ohne Allokation (belegt)

- Pro Bild laufen auf dem Emulations-Thread: Merker-Abfrage, `FrameClock`, `mach_wait_until`, Signposts, `retro_run` mit Video-, Audio- und Eingabe-Trampolin, `GET_VARIABLE_UPDATE`, Senkenaufrufe, Messwerte und alle 30 Bilder der Vergleich des Batteriespeichers. Keiner dieser Schritte nimmt eine Sperre.
- Messung am 7. November 2026: dieselben Quellen für macOS gebaut, mGBA 0.10.5 für macOS, `selftest.gba` mit gedrückter Taste A, Senken ohne eigene Allokation, `malloc` und Verwandte per `DYLD_INSERT_LIBRARIES` auf dem Thread „Arcfold Emulation“ gezählt (Werkzeug nicht im Repo):
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

## Eigenheiten von melonDS DS 1.4.0 (belegt im iOS-Simulator)

Belegt mit dem Kern aus dem App-Bundle und `selftest.nds` in `Tests/ArcfoldTests/Core/CoreSessionTests+DS.swift`, Duo-Simulator mit iOS 27.1, Optionen aus `GameSystem.dsCoreOptions` mit `melonds_start_time_mode=absolute`. Die Erkundung zu M2 (kopfloser Host auf macOS) ist damit bestätigt; Abweichungen und Ergänzungen stehen dabei.

- **Bild:** XRGB8888 256 × 384, Pitch 1024, ein Bild pro `retro_run` (300 von 300), immer dieselbe Form. Oberer Bildschirm in den Zeilen 0–191, unterer in 192–383. Bytes im Speicher B, G, R, X. Farben: BGR555 pro Kanal `c6 = 2c`, dann `c8 = 4·c6 + c6/16`, 31 ergibt 251; der Decoder der Tests vergleicht exakt, ohne Toleranz.
- **Takt:** genau 33 513 982 / 560 190 Bilder/s (59,8260983) und 33 513 982 / 1024 = 32 728,498046875 Hz, nicht 32 728,5. `retro_get_system_av_info` meldet diese Doubles; `AVTiming.sampleRate` geht unverändert an `AudioOutput`. Erst der Quellknoten wandelt aus der auf ganze Hertz gerundeten Rate, 32 728 Hz, weil seine Wandlung aus der Bruchrate im Simulator nach 80 bis 90 s einbrach (`docs/wissen/renderer.md`); die 15 ppm Gangunterschied gleicht der Takt aus, der der Tonuhr folgt (ADR 0005, Abschnitt 3).
- **AV-Info:** base 256 × 384, max 1024 × 576, Seitenverhältnis 2/3. Im ersten Bild einmal `SET_GEOMETRY` mit denselben Werten, nie `SET_SYSTEM_AV_INFO`.
- **Ton:** ein `audio_sample_batch` pro Bild mit 546 bis 548 Frames, auch im ersten Bild (546); Mittel über 300 Bilder 547,057. Ton des Testprogramms 440,04 Hz, mit A 880,16 Hz (steigende Durchgänge durch den Mittelwert, Bilder 20–95 bzw. 110–300).
- **Bildzähler:** ARM9 = Bildnummer − 7, ARM7 = Bildnummer − 1.
- **Determinismus:** Die SHA-256 der Bilder 1, 60 und 300 (sichtbare Bytes, Zeile für Zeile) sind über Sitzungen gleich und gleich den macOS-Werten der Erkundung (`076545ea…`, `26f92f38…`, `7e908360…`), obwohl der Spielstand dort mit 0x00 und hier mit 0xFF beginnt: In beiden Fällen fehlt die Kennung, und das Bild zeigt sonst nichts aus dem Spielstand.
- **Tasten:** Alle zwölf RetroPad-Tasten erscheinen nach Namen (A, B, Select, Start, Steuerkreuz, R, L als KEYINPUT-Bits 0–9, X und Y aus EXTKEYIN); vier Bilder Halten genügen. Das Stift-Bit steht genau, solange der Zeiger gedrückt ist; das Deckel-Bit bleibt 0.
- **Environment:** Abgelehnt und gezählt sind genau die 20 Befehle aus ADR 0006, Abschnitt 4. `GET_VARIABLE_UPDATE` einmal pro Bild, `SET_VARIABLES` einmal (laut Erkundung 74 Optionen über den Legacy-Weg), `SET_GEOMETRY` einmal.
- **Spielstand:** 8192 Byte EEPROM für den unbekannten Spielcode „ZARC“, Größe gleich nach `retro_load_game`; Puffer anfangs 0x00. Drei Sitzungen in einem Prozess: Boot-Zähler 1 → 2 → 3, Status 0x0E und danach 0x0F (Kennung gefunden), Herzschlag 4 bei Bild 300, `battery.sav.bak` hält die vorige Fassung.
- **Ordner:** Nach einer Sitzung liegt im Systemordner nur `melonDS DS/wfcsettings.bin` (2304 Byte), der Ordner `melonDS DS/` neben den Spielständen bleibt leer. Laut Quelltext schreibt der Kern die Datei beim Entladen (Aufgabe „Firmware Flush“) und nach Änderungen der Firmware durch ein Spiel, nicht pro Bild.
- **WLAN-Einstellungen** (`CoreSessionTests.DS.Firmware`, 7. November 2026): `wfcsettings.bin` hält drei Zugangspunkte zu 256 Byte ab Byte 1536, 1792 und 2048, davor die drei erweiterten des DSi, die die erzeugte DS-Firmware mit 0xFF lässt; die DNS-Server eines Zugangspunkts stehen bei 0xC8 und 0xCC. Mit der Vorgabe von `melonds_firmware_wfc_dns` schreibt der Kern einen Ersatzserver für den eingestellten Online-Dienst als ersten und zweiten DNS-Server in Zugangspunkt 0. Die App setzt `0.0.0.0` („Force Default DNS“); die nächste Sitzung setzt dann alle DNS-Felder auf 0, und die Adresse steht nirgends mehr in der Datei. „Don't Override“ genügt nicht, weil der Kern die Datei lädt, bevor er den DNS setzt (ADR 0006, Abschnitt 3).
- **Fehlerbild und Laden:** Ausnahmen der Art `config_exception` (verschlüsseltes Spiel ohne BIOS, Retail-Titel nur für den DSi im DS-Modus) zeigen das Fehlerbild bei Rückgabe `true` (`.gameNotRunnable`), `invalid_rom_exception` (Einsprung, Logo-Prüfsummenfeld, Lage der Binärteile, Größe) gibt `false` (`.gameRejected`). Wie `NDSHeader` dazu passt, prüft `CoreSessionTests.DS.ImportRules` mit dem Testprogramm und 16 Varianten davon.
- **Render-Thread:** ein Thread mehr im Prozess; alle Callbacks vom aufrufenden Thread (Erkundung).
- **Leistung im Simulator** (Plausibilitätswert, Mac mini M4 Pro, während paralleler Builds): `retro_run` für `selftest.nds` über je 600 Bilder in fünf Läufen im Median 2,6 bis 2,8 ms, im Maximum 3,1 bis 6,3 ms (Test `CoreSessionTests.DS.Performance`, gibt beide Werte aus). Zählt nur auf dem Duo.
- **Allokationen** (macOS-Bau von melonDS DS 1.4.0 mit melonDS `906e9eb` und der LibretroKit-Quellen, Zählbibliothek per `DYLD_INSERT_LIBRARIES` auf dem Thread „Arcfold Emulation“, Werkzeug nicht im Repo): optimiert 0 Allokationen in `runFrames(1)`, `(600)` und `(2000)` mit gehaltener Taste, mit gehaltenem Zeiger und bei 200 Tipps zwischen den Bildern; in 3 s Echtzeit nur beim Befehl `pause()` (Fortsetzung und Abschluss der Sicherung), keine pro Bild. Unoptimiert nur beim Abholen eines Befehls aus dem Postfach (`removeFirst`), keine pro Bild. Die Erkundung zählte im Kern selbst eine Allokation in 600 Bildern, mit 3D etwa eine pro Bild.
- `retro_serialize_size` 19 228 045 Byte; `serialize` 1,1 ms, `unserialize` 3,1 ms (Mac, Erkundung).

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
- Weckzeiten im Simulator: `mach_wait_until` wacht dort bis etwa 2 ms zu spät auf (Timer-Coalescing des Mac). Im Echtzeit-Test lagen 0 von 182 Bildern mehr als 2,5 ms nach ihrer Frist, aber ein Viertel über der Grenze von 2 ms für „späte Bilder“. Die Zahl ist im Simulator deshalb kein Maßstab; die Bildrate stimmte (59,7). In der zehnminütigen Abnahme der App lagen rund 58 % der Bilder über 2 ms, die Bildrate betrug trotzdem 59,73 Bilder/s, ohne Neusynchronisation. Auf dem Gerät offen.
- **Secure Area beim Direktstart:** melonDS „entschlüsselt“ beim Direktstart die ersten 2 KiB jedes ARM9-Teils, der bei 0x4000 bis 0x7FFF liegt, auch bei Homebrew. Ohne die Kennung eines entschlüsselten Abzugs (0xE7FFDEFF am Anfang, nicht 16 Byte später) misslingt das, und dort stehen danach nur 0xE7FFDEFF. **Warum:** Die Homebrew-Variante von `selftest.nds` mit Spielcode „####“ ohne Kennung lädt, läuft aber nicht, weil ihr Einsprung 16 Byte hinter dem Anfang liegt. **Anwenden:** Testprogramme mit ARM9-Teil bei 0x4000 behalten die Kennung oder legen den ARM9-Teil unter 0x4000; die Importprüfung sagt, ob der Kern eine Datei lädt, nicht, ob ihr Programm läuft.
- **DSi im DS-Modus:** melonDS DS 1.4.0 lehnt im DS-Modus nur Retail-Titel ab, die einen DSi brauchen (Unit-Code 3 oder DSiWare, jeweils mit Modcrypt-Flag und einem Spielcode aus vier Großbuchstaben oder Ziffern), und das per Fehlerbild; DSi-Homebrew startet auf dem DS. **Warum:** `NDSHeader` lehnte jede Datei mit Unit-Code 3 und jede DSiWare-Kennung ab, der Kern startete die Homebrew-Varianten. **Anwenden:** `NDSHeader.Fields.needsDSi` folgt `RequiresDSi` und `IsRetailDSiTitle` aus `src/libretro/config/console.cpp`; beim nächsten Kernwechsel die Regeln dort erneut vergleichen, `CoreSessionTests.DS.ImportRules` zeigt Abweichungen.
- **Gepolstertes Abbild:** melonDS füllt die Datei mit Nullen auf die nächste Zweierpotenz auf und prüft Offset plus Größe beider Binärteile gegen dieses Abbild (`ValidateROM`, in 32 Bit). **Warum:** Eine Datei mit zu großem ARM9-Teil ließ der Import durch, der Kern lehnte sie ab; ein ARM7-Teil in der Polsterung startete, der Import lehnte ab. **Anwenden:** `NDSHeader` rechnet mit `paddedSize(of:)` und in 64 Bit, damit die Summe nicht überläuft.
- **Bilder in Tests:** Ein DS-Bild hat 393 KB. Der Touch-Durchlauf liest 896 Bilder; sie alle aufzuheben, kostete über 350 MB. `LatestPicture` hält nur das neueste Bild, die Tests lesen es nach jedem `runFrames`.
- **Pause im Echtzeit-Test:** `ClockedSoundSink` spielt weiter, solange niemand ihn anhält, und zählte die Pause als Aussetzer. Wie die App vor `pause()` den Ton anhält, ruft der Test vorher `suspend()`; danach füllt die Senke neu auf, ohne Aussetzer.
- **Spiele mit großem Spielstand (offen):** melonDS gibt NAND-Spielkarten 8, 16 oder 64 MiB Spielstand (`CartRetail`). `BatterySaveMonitor` hält davon drei Kopien und vergleicht alle 30 Bilder den ganzen Speicher per `memcmp` auf dem Emulations-Thread. Für die üblichen EEPROM- und Flash-Größen bis 1 MiB unkritisch; ob 64 MiB ins Bildbudget passen, zeigt erst ein solches Spiel auf dem Duo.
