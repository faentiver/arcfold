# 0005 · Laufzeit für Software-Kerne

Status: Vorgeschlagen · 6. November 2026

## Kontext

- M1 macht mGBA spielbar: Emulations-Thread mit Takt, Bild, Ton, Eingabe, Batteriespeicher, Import, Debug-Overlay und Lizenzen (Plan, Abschnitt 10). Den Rahmen geben die Leitplanken 3 bis 8 vor (Plan, Abschnitt 5).
- Zwei Entwürfe mit Prototypen liegen vor: „Nativ und schlank“ und „Echtzeit robust“. Die Prototypen liefen gegen mGBA 0.10.5, gebaut für macOS aus `Cores/mgba` mit den Optionen aus `Scripts/cores/mgba.sh`. Sie liegen im Scratchpad und nicht im Repo. Messwerte von dort sind als „Prototyp“ gekennzeichnet, Leistungszahlen vom Mac gelten nur als Plausibilitätswerte.
- Die Umsetzung läuft in zwei parallelen Spuren: K für Kern und Laufzeit, A für Ausgabe und App. Deshalb stehen die öffentlichen Schnittstellen vorab als Code fest.
- mGBA 0.10.5 verhält sich so (belegt im Prototyp und im eigenen Lauf, `0005/selftest-mgba-macos.txt`):
  - RGB565, 240 × 160 Pixel, 512 Byte pro Zeile, immer derselbe Zeiger, nie ein leeres Bild.
  - 59,7275009155 Bilder/s und 32 768 Hz.
  - Pro `retro_run` genau ein `retro_audio_sample_batch` mit 545 bis 552 Frames (erstes Bild 80), nie `retro_audio_sample`.
  - Pro Bild einmal `retro_input_poll` und dreimal `input_state` (Maske, L3, R3).
  - Gebaut mit `DISABLE_THREADING`, also ohne eigene Threads.
  - Der Batteriespeicher meldet nach `retro_load_game` 131 072 Byte und nach der Erkennung des Speichertyps die echte Größe (SRAM: 32 768). mGBA übernimmt den Pufferinhalt erst im ersten `retro_run`. Nach `retro_unload_game` ist der Puffer freigegeben.
  - Viele ROMs erzeugen pro Bild eine Logzeile der Stufe INFO (DMA).
- Das iOS-SDK 27.2 setzt Grenzen (belegt in den Headern):
  - `AVAudioSourceNode(format:realtimeSafeRenderBlock:)` ist `CA_REALTIME_API` (`[[clang::nonblocking]]`) und für Swift gesperrt: „Swift is not supported for use with audio realtime threads“.
  - `AVAudioEngine.connect(_:to:format:)` ist ab iOS 27 veraltet, der Ersatz heißt `connectNode(_:to:format:) throws`.
  - `AVAudioSession.interruptionNotification` ist veraltet, ersetzt durch `didBecomeInactiveNotification` und `resumptionRecommendationNotification`.
- Apples Doku „Developing Metal apps that run in Simulator“ verbietet im Simulator die Pixelformate `b5g6r5Unorm`, `a1bgr5Unorm`, `abgr4Unorm`, `bgr5A1Unorm` und das Schreiben in sRGB-Texturen.

## Optionen

| Thema | Optionen |
| --- | --- |
| Modulgrenzen | (a) Renderer hängt von LibretroKit ab, die Senken-Protokolle stehen in LibretroKit. (b) Beide unabhängig, eigene Typen im Renderer, Adapter in der App |
| Taktabweichung | (a) Die Emulation folgt der Tonuhr über eine Trimmung der Bildperiode. (b) Dynamisches Resampling (Leitplanke 6). (c) Der Display-Link treibt den Kern |
| Regler | (a) P-Regler auf den Füllstand. (b) PI-Regler |
| Ton-Render-Block | (a) C/Objective-C mit `realtimeSafeRenderBlock`. (b) Swift-Block |
| Bildübergabe | (a) Dreifachpuffer, `MTKView` zeigt das neueste Bild. (b) Postfach mit Soll-Zeitstempeln, `CAMetalDisplayLink` wählt nach Zeit |
| Texturformat | (a) `r16Uint`, Dekodierung im Shader. (b) `b5g6r5Unorm` |
| Callback-Platz | (a) `Atomic<Bool>` plus `nonisolated(unsafe) static var`. (b) ein `Atomic<UInt>` mit den Zeiger-Bits des Kontexts |
| Kernoptionen | (a) Legacy-Weg: `GET_CORE_OPTIONS_VERSION` mit `false` beantworten, mGBA meldet über `SET_VARIABLES`. (b) Optionen v2 |
| Controller | (a) `valueChangedHandler` auf dem Main Thread. (b) `GCControllerLiveInput` auf eigener Queue |
| Testprogramm | (a) eigener Generator. (b) fremdes Homebrew |

## Entscheidung

### 1. Modulgrenzen

```
App ──► Renderer ──► LibretroKit ──► CLibretro (libretro.h, Log-Shim)
 │         └──► CRendererAudio (Ring, Render-Funktion, Knoten-Fabrik; C/ObjC)
 └──► LibretroKit
```

- **LibretroKit** lädt den Kern, betreibt den Emulations-Thread mit Takt, beantwortet die Callbacks, hält Eingabezustand und Batteriespeicher. Es kennt weder Metal noch AVFoundation und lässt sich mit eigenen Senken kopflos testen.
- **Renderer** implementiert die Senken (`FrameMailbox: VideoSink`, `AudioRing: AudioSink`), zeichnet mit Metal und spielt den Ton.
- **App** verdrahtet beides und enthält Bibliothek, Import, Spielansicht, Touch, Controller, Overlay und Lizenzen.
- Gegen Entwurf „Echtzeit“ (unabhängige Pakete, Adapter in der App): Zwei Sätze gleichnamiger Typen (`PixelFormat`, `VideoGeometry`) wären in der App mehrdeutig, und die Adapter brächten nur Weiterleitungen. Was der Entwurf schützen wollte, bleibt erhalten: LibretroKit ist frei von Grafik und Ton.

### 2. Öffentliche Schnittstellen

Der Code steht in `Packages/LibretroKit/Sources/LibretroKit/` (`Media.swift`, `Sinks.swift`, `Input.swift`, `EmulationSession.swift`, `SessionStats.swift`) und `Packages/Renderer/Sources/Renderer/`. Fehlende Umsetzungen enthalten nur `fatalError("M1 track K")` bzw. `fatalError("M1 track A")`.

| Typ | Rolle |
| --- | --- |
| `PixelFormat`, `VideoGeometry`, `AVTiming`, `SessionInfo` | Werte aus `retro_get_system_av_info` und `SET_PIXEL_FORMAT`; `SessionInfo` liefert `load()` |
| `FrameStamp` | Sequenznummer und Soll-Startzeit eines Bildes in `mach_absolute_time`-Einheiten |
| `VideoSink.submit(pixels: RawSpan, width:height:bytesPerRow:format:stamp:)` | Bild auf dem Emulations-Thread; `RawSpan` kann den Aufruf nicht überleben |
| `AudioSink.write(_: Span<Int16>) -> AudioBufferStatus` | Ton auf dem Emulations-Thread; der Rückgabewert speist den Regler |
| `JoypadButtons`, `InputState.set(_:from:)` | RetroPad-Bits, eine Maske je Quelle (Touch, Controller, Tastatur) |
| `SessionConfiguration`, `Pacing` | Kern, Spiel, Batteriespeicher, Ordner, Kernoptionen, `.realTime` oder `.unthrottled` |
| `EmulationSession` | `load()`, `connect(video:audio:)`, `resume()`, `pause()`, `runFrames(_:)`, `saveBatteryNow()`, `stop() -> SessionSummary`, dazu `input`, `stats`, `events`, `state` |
| `SessionError`, `SessionEvent`, `SessionState`, `SessionSummary`, `SessionStats` | Fehler, Ereignisse, Zustand, Diagnose, Messwerte |
| `FrameMailbox`, `GameScreen`, `PresentationStats`, `ScreenPlacement` | Bildübergabe, Metal-Ansicht, Zähler, ganzzahlige Platzierung |
| `AudioRing`, `AudioOutput`, `AudioCounters`, `AudioRoute`, `AudioOutputEvent`, `AudioOutputError` | Tonpuffer, Ausgabe über AVAudioEngine, Zähler, Ereignisse |

`LibretroCore` aus M0 bleibt öffentlich und `~Copyable`. Die Lebenszyklus-Funktionen (`retro_init`, `retro_load_game`, `retro_run`, `retro_get_memory_*` und weitere) bekommt der Typ als interne Methoden. Er lebt als lokale Konstante in der Laufschleife und verlässt den Emulations-Thread nie.

### 3. Threading und Takt

- **Ein `Thread` pro Sitzung**, Name „Arcfold Emulation“, QoS `.userInteractive`, 16 MiB Stack, ohne Time-Constraint-Scheduling. Gründe: Der Kern allokiert in `retro_run` (mGBA ruft `realloc` für den Tonpuffer), und Swift ist auf Echtzeit-Threads nicht vorgesehen. Pro Bild ein `autoreleasepool`, weil der Thread keine Run-Loop hat. Den Namen nach `retro_init` erneut setzen, weil manche Kerne ihn ändern (PPSSPP, `docs/wissen/psp-grafik.md`).
- **Befehle** (`resume`, `pause`, `runFrames`, `stop` und weitere) landen in einem `Mutex`-Postfach mit atomarem Merker. Der Emulations-Thread prüft pro Bild nur den Merker und holt das Postfach mit `withLockIfAvailable`, er wartet also nie auf den Main Thread. Antworten gehen über `CheckedContinuation` an der Bildgrenze zurück. Pausiert wartet der Thread an einer `DispatchSemaphore`.
- **Takt mit absoluten Fristen** über `mach_wait_until`. Die Periode ist `1 / framesPerSecond` aus `retro_get_system_av_info`, unabhängig vom Display. Liegt der Thread mehr als drei Perioden zurück (Hintergrund, Debugger), beginnt der Fristplan neu bei „jetzt“, und `resyncs` zählt mit. Kleinere Verspätungen holt der Plan auf, indem die nächsten Bilder ohne Wartezeit laufen; mehr als drei Bilder am Stück entstehen so nie. Belegt im Prototyp: Relatives Schlafen erzeugte 23 % zu wenig Ton und 418 Aussetzer in 10 s, absolute Fristen keinen.
- **Die Emulation folgt der Tonuhr.** Ein PI-Regler trimmt die Periode um höchstens ±0,5 %:
  - Fehler `e = (bufferedFrames − targetFrames) / sampleRate` in Sekunden, aus dem `AudioBufferStatus` des letzten Schreibens im Bild.
  - `I = clamp(I + e · P, ±0,5)` und `trim = clamp(0,05 · e + 0,005 · I, ±0,005)`, die Periode wird zu `P · (1 + trim)`.
  - Nur solange `isConsuming` gilt, sonst klingt `trim` gegen 0 ab.
  - Belegt in der Simulation des Entwurfs „Echtzeit“: 0 Aussetzer bei ±100 und ±500 ppm Drift, Ausreißern bis 12 ms und einem Stillstand von 30 ms, und `trim` stellt sich genau auf die Drift ein.
  - Im Echtzeitlauf des Entwurfs „Nativ“ (2 × 40 s am Mac) lag die nötige Korrektur bei 0 bis −0,14 %, ohne Aussetzer. Ohne Regelung wäre der Puffer dort nach etwa einer Minute leer gewesen.
  - Gegen den P-Regler aus Entwurf „Nativ“: Ein P-Regler hält bei Drift einen bleibenden Abstand zum Sollfüllstand, der PI-Regler nicht.
- **Abweichung von Leitplanke 6:** Es gibt kein dynamisches Resampling. Die Tonhöhe bleibt exakt, die Wandlung macht AVAudioEngine mit fester Rate, und der Render-Block bleibt eine reine Kopie. Das Bild ist ohnehin nicht an den Display-Takt gekoppelt. Der Plan ist angepasst.
- **Startreihenfolge:** `load()`, `connect(video:audio:)`, `AudioOutput.start()`, `resume()`. Belegt im Prototyp: Liefen Bilder schon vor dem Start der Engine, füllte sich der Puffer auf über 7 000 Frames, und 1 616 Frames gingen verloren. Mit dem Ton zuerst blieb der Füllstand stabil.
- **Messwerte** schreibt der Emulations-Thread etwa einmal pro Sekunde mit relaxed Stores in `SessionStats`: Laufzeit von `retro_run`, Verspätung, späte Bilder (über 2 ms), Neusynchronisationen, `trim` und die Bildrate. Dazu kommen `OSSignposter`-Intervalle um `retro_run`.

### 4. Callbacks (Leitplanke 3)

- **Trampoline:** sechs `@convention(c)`-Funktionen als `static let`. Sie leiten an den aktiven Kontext weiter, der als `Unmanaged`-Zeiger in einem globalen `Atomic<UInt>` steht (0 heißt kein Kern). Belegung per `compareExchange` vor `retro_set_environment`, weil mGBA dort schon das Environment ruft. Freigabe nach `retro_deinit`. Ein zweites `load()` endet mit `.anotherSessionActive`. Zugriff mit `takeUnretainedValue()`, ohne unterstrichene API.
- Gegen Entwurf „Nativ“ (`Atomic<Bool>` plus `nonisolated(unsafe)`): Belegung und Zeiger stecken in einem einzigen Atomic, ein unsicherer globaler Zustand entfällt. Belegt im Prototyp: kompiliert unter Swift 6.4.2 mit den Features des Projekts.
- **Log:** `retro_log_printf_t` ist variadisch, Swift sieht ihn nur als `OpaquePointer?`. Ein C-Shim in `CLibretro` prüft zuerst eine atomare Mindeststufe (darunter wird nur gezählt), formatiert sonst mit `vsnprintf` in einen Stack-Puffer und ruft eine nicht-variadische Senke. Die Senke schreibt mit Ratenbegrenzung über `os.Logger`.
- **Spiel übergeben:** mGBA hat `need_fullpath = false`. Der Host liest die Datei mit `Data(contentsOf:options: .alwaysMapped)` und übergibt `data`, `size` und `path`. Die Daten bleiben bis `retro_unload_game` gültig. Pfad und Daten ergeben dieselben Bilder (belegt).
- **Environment in M1:**

| Befehl | Antwort |
| --- | --- |
| `GET_CORE_OPTIONS_VERSION` | `false`. mGBA meldet seine 13 Optionen dann über `SET_VARIABLES` (belegt), der Host kopiert die Standardwerte sofort, weil mGBA die Zeichenketten danach freigibt |
| `SET_VARIABLES` | `true`, Standardwert ist der erste Wert der Liste |
| `GET_VARIABLE` | Wert aus `SessionConfiguration.coreOptions`, sonst der Standardwert; C-Strings mit stabiler Adresse für die ganze Sitzung, unbekannte Schlüssel `false` |
| `GET_VARIABLE_UPDATE` | `*data = false`, `true`; einmal pro Bild, ohne Allokation |
| `SET_PIXEL_FORMAT` | `true` für RGB565 und XRGB8888, `false` für 0RGB1555 |
| `GET_INPUT_BITMASKS` | `true`, `data` ist bei mGBA `NULL` und bleibt unberührt |
| `SET_INPUT_DESCRIPTORS` | `true`, ignoriert; die Beschriftungen kommen aus der App |
| `GET_LOG_INTERFACE` | C-Shim |
| `GET_SYSTEM_DIRECTORY`, `GET_SAVE_DIRECTORY` | Ordner aus der Konfiguration; der Systemordner bleibt leer |
| `GET_CAN_DUPE` | `true`; ein `NULL`-Bild erreicht die Senke nicht |
| `SET_GEOMETRY` | `true`, Größe bis zum Maximum |
| `SET_SYSTEM_AV_INFO` | `false` und protokollieren; mGBA ruft es nicht, M2 klärt den Bedarf |
| `SHUTDOWN` | `true`, Ereignis `coreRequestedShutdown` |
| `SET_MESSAGE`, `SET_MESSAGE_EXT` | `true`, Ereignis `coreMessage` |
| `GET_JIT_CAPABLE` | `false`; der JIT-Build bekommt später einen neutralen Haken (ADR 0002) |
| `SET_MEMORY_MAPS`, `SET_SUPPORT_ACHIEVEMENTS` | `false` (keine Cheats, keine Achievements) |
| `GET_RUMBLE_INTERFACE`, `GET_SENSOR_INTERFACE`, `SET_HW_RENDER` und alle übrigen | `false` |

`SessionSummary.unhandledEnvironmentCommands` sammelt jeden Befehl, den der Host mangels Unterstützung ablehnt: unbekannte Befehle und die oben mit `false` abgelehnten. Abfragen, bei denen `false` die erwartete Antwort ist (`GET_CORE_OPTIONS_VERSION`, `GET_JIT_CAPABLE`), zählen nicht.

Gegen Optionen v2 aus Entwurf „Echtzeit“: Eine Oberfläche für Kernoptionen kommt erst in M4. Der Legacy-Weg liefert alle Schlüssel und Standardwerte und erspart das Auslesen der v2-Strukturen mit Feldern fester Länge. In M1 setzt die App nur `mgba_use_bios = OFF`.

### 5. Bild

- **`FrameMailbox`** mit vier Plätzen der Größe `maxWidth × maxHeight × bytesPerPixel`, einmal angelegt. Jeder Platz hat einen atomaren Zustand (frei, schreiben, bereit, lesen). Der Emulations-Thread kopiert nur zeilenweise und entfernt dabei den Rand des Kern-Pitch. Er ruft weder Metal noch Locks auf. Ist kein Platz frei, überschreibt er das älteste nicht gezeigte Bild und zählt es.
- **`GameScreen`** zeichnet in einen `CAMetalLayer`, getaktet von einem `CAMetalDisplayLink` am Main-Run-Loop. Gezeigt wird das neueste Bild, dessen Soll-Zeit plus `L` vor dem `targetPresentationTimestamp` liegt. `L` ist der gemessene Vorlauf des Display-Links plus 8 ms Reserve. Ist das gewählte Bild noch nicht fertig, wird das neueste fertige gezeigt und als „späte Auswahl“ gezählt.
  - Gegen `MTKView` mit „neuestem Bild“ aus Entwurf „Nativ“: Nur `CAMetalDisplayLink` liefert den Zielzeitpunkt zusammen mit dem Drawable.
  - In der Simulation des Entwurfs „Echtzeit“ verwarf „neuestes Bild“ bei 60 Hz 66 Bilder pro Minute durch Phasenjitter, die Soll-Zeit-Regel keines. Der Preis sind etwa 8 ms mehr Bildlatenz.
- **Bildrate:** `preferredFrameRateRange` von 60 bis 120 Hz, bevorzugt 120 Hz; dafür steht `CADisableMinimumFrameDurationOnPhone` in `App/Info.plist`. Bei 59,7275 Hz Bildinhalt steht unvermeidlich ab und zu ein Bild einen Takt länger: bei 120 Hz etwa alle 1,84 s für 8,3 ms, bei 60 Hz etwa alle 3,67 s für 16,7 ms. Der kleinere Sprung spricht für 120 Hz. Was das an Strom kostet, klärt der Gerätetest, Ausweg sind feste 60 Hz.
- **Texturformat `r16Uint`** für RGB565. Der Fragment-Shader liest mit `read()` an ganzzahligen Texelkoordinaten, das ist ohne Sampler pixelgenau, und dekodiert 5-6-5 selbst. XRGB8888 kommt über `bgra8Unorm`. Drawable `bgra8Unorm` mit sRGB-Farbraum, keine `_srgb`-Formate.
  - Gegen `b5g6r5Unorm` aus Entwurf „Echtzeit“: Apple verbietet das Format im Simulator, und dort laufen die Tests. Belegt ist es nur auf macOS.
- **Drei Upload-Texturen** (`.shared`, `replace(region:)`), je mit einem atomaren Merker „in Arbeit“ bis zum Completion-Handler. Ist die nächste Textur noch in Arbeit, bleibt das vorige Bild stehen und `gpuBusy` zählt. Auf dem Main Thread wartet keine Semaphore.
- **Platzierung:** `ScreenPlacement.fitting` wählt den größten ganzzahligen Faktor und zentriert auf ganze Pixel. Belegt pixelgenau im Prototyp (Offscreen-Render gegen CPU-Rechnung): Duo innen hochkant 1878 × 2670 ergibt Faktor 7 bei (99, 775), quer 2670 × 1878 Faktor 11 bei (15, 59), außen 1398 × 2034 Faktor 5 bei (99, 617). Die Falz-Layouts kommen in M2.

### 6. Ton

- **`AudioRing`:** lock-freier SPSC-Ring in C (`CRendererAudio`, C11-Atomics mit Acquire und Release). Er fasst 8 192 Stereo-Frames Int16 (250 ms bei 32 768 Hz), ein Frame als `uint32_t`, sodass nie ein halbes Stereopaar entsteht. Der Erzeuger schreibt höchstens den freien Platz, der Rest wird verworfen und gezählt. Belegt im Prototyp: 3,17 Mrd. Frames unter Volllast ohne Sprung.
- **Render-Funktion** `CA_REALTIME_API` mit den Zuständen Auffüllen (Stille, bis der Sollwert erreicht ist), Spielen und Ausgesetzt (Stille ohne Zählung). Läuft der Ring beim Spielen leer, füllt sie den Rest mit Nullen und blendet über 64 Frames vom letzten Wert aus. Dann zählt sie einen Aussetzer und füllt neu auf.
- **Compilerprüfung:** In der Umsetzungsdatei steht `#pragma clang diagnostic error "-Wfunction-effects"`. Belegt im Prototyp: `malloc`, `free`, `NSLog` oder eine Objective-C-Nachricht im Block brechen den Build ab, `memcpy` und Atomics nicht. Die Warnung ist sonst aus, auch mit `-Wall`.
- **Knoten:** Eine Objective-C-Fabrik erzeugt `AVAudioSourceNode` mit `initWithFormat:realtimeSafeRenderBlock:`. Das Blockformat ist das Kernformat, Int16 verschachtelt mit 32 768 Hz, die Render-Funktion kopiert also nur. Verbunden wird mit `connectNode(_:to:format:)` und dem Format `standardFormatWithSampleRate: <Hardware-Rate>, channels: 2`. Damit wandelt nur der Quellknoten, und das einmal; laut Header kann er Abtastrate, Bittiefe und Verschachtelung wandeln. Belegt im Prototyp: Ohne Format stand der Knoten auf 44,1 kHz, und der Mischer wandelte ein zweites Mal.
- **Sollfüllstand** `max(35 ms, ioBufferDuration + 20 ms)`, neu berechnet nach jeder Routenänderung. Mit 5 ms IO-Puffer sind das 35 ms, mit 21 ms 41 ms. Gegen die festen 50 ms aus Entwurf „Nativ“: Die Simulation zeigte schon mit 35 ms keine Aussetzer, solange der IO-Puffer klein ist.
- **Audiositzung:** Kategorie `.ambient`, also stumm im Lautlos-Modus und mischbar mit Musik. `setPreferredIOBufferDuration(0.005)`, Aktivierung mit dem asynchronen `activate(options:)`. Beobachtet werden `didBecomeInactiveNotification` (Spiel pausieren), `resumptionRecommendationNotification` (fortsetzen bei `.shouldResume`), `routeChangeNotification` (Sollwert neu, bei `.oldDeviceUnavailable` pausieren), `AVAudioEngineConfigurationChange` (Engine neu starten) und `mediaServicesWereResetNotification` (Engine und Knoten neu bauen). Neustarts und Auffüllen zählen nicht als Aussetzer.

### 7. Eingabe

- **`InputState`:** ein `Atomic<UInt32>` je Quelle und ein gemeinsames Latch. `set(_:from:)` speichert die Maske der Quelle und setzt neu gedrückte Tasten per `bitwiseOr` im Latch. `retro_input_poll` bildet einmal pro Bild die Vereinigung aller Quellen plus `latch.exchange(0)`, `input_state` liest nur diesen Schnappschuss: Maske für `RETRO_DEVICE_ID_JOYPAD_MASK`, sonst das Bit, nur Port 0 und `RETRO_DEVICE_JOYPAD`. Ein Tipp zwischen zwei Abfragen geht so nicht verloren.
- **Touch:** eine SwiftUI-Ansicht mit `SpatialEventGesture` (iOS 18 und neuer), die alle Finger sieht. Aus allen aktiven Berührungen entsteht eine Maske, ein Finger kann von Taste zu Taste gleiten. Das Steuerkreuz ist ein Kreis mit acht Sektoren und Totzone. Beschriftungen A, B, L, R, Start und Select, ohne Original-Symbole. Ausweg, falls Mehrfachberührung so nicht zuverlässig ist: eine `UIView` mit Touch-Methoden.
- **Controller:** Verbindungsmeldungen und `GCController.controllers()`. Pro Controller `GCControllerLiveInput` (`controller.input`) auf einer eigenen seriellen Queue mit `inputStateQueueDepth = 16`; `inputStateAvailableHandler` holt mit `nextInputState()` jeden Zwischenzustand ab.
  - Gegen `valueChangedHandler` auf dem Main Thread (Entwurf „Nativ“): unabhängig von Hängern im Main Thread.
  - An der Spielansicht hängt `GCEventInteraction` für Gamepad-Ereignisse.
  - Belegung nach RetroPad-Position: Ost-Taste A, Süd-Taste B, West Y, Nord X, Schultertasten und Trigger L und R, Steuerkreuz und linker Stick (Schwelle 0,5) für die Richtungen, Menü Start, Optionen Select.
  - `GCKeyboard` mit derselben Logik für Tests im Simulator, Belegung wie die Standard-Tastatur von RetroArch.
  - Ist ein Controller verbunden, blendet die App das Touch-Overlay aus.

### 8. Batteriespeicher

- **Laden** nach `retro_load_game` und vor dem ersten `retro_run`: `min(Dateigröße, retro_get_memory_size)` Byte in den Puffer kopieren. Fehlt die Datei oder ist sie kürzer als erwartet, kommt `battery.sav.bak` zum Zug, sonst bleibt der Puffer bei 0xFF.
- **Prüfen** alle 30 Bilder per `memcmp` gegen eine einmal angelegte Kopie des zuletzt gesehenen Stands. Geschrieben wird, wenn sich der Inhalt geändert hat und seit einer Prüfung gleich geblieben ist. Grund: Spiele schreiben oft über mehrere Bilder, ein Abzug mitten darin wäre inkonsistent.
- **Übergabe** in einen von zwei vorab angelegten Puffern an eine serielle Queue mit QoS `.utility`. Pro Bild gibt es keine Allokation.
- **Schreiben:** temporäre Datei im selben Ordner, `FileHandle.synchronize()`, dann `replaceItemAt(_:withItemAt:backupItemName:options:)` mit `.withoutDeletingBackupItem`, sodass `battery.sav.bak` die vorige Fassung hält. Liegengebliebene temporäre Dateien werden beim Laden gelöscht. Keine Dateischutzklasse `.complete`, sonst scheitert das Schreiben bei gesperrtem Gerät.
- **Sofort** bei `pause()`, `saveBatteryNow()` und `stop()`, dort vor `retro_unload_game`.
- **Nie** schreiben, solange keine Datei existiert und der Puffer nur 0xFF enthält. So entsteht bei Spielen ohne Speicher keine 128-KiB-Datei.
- Gegen Entwurf „Nativ“ (Prüfung alle 60 Bilder, 1 s Ruhe, `Data.write(options: .atomic)`): `fsync` und Sicherungsdatei machen das Schreiben robuster, die vorab angelegten Puffer vermeiden Allokationen auf dem Emulations-Thread.
- Save States (`retro_serialize`, bei mGBA 430 144 Byte) kommen in M4.

### 9. App

- **Ablage** in `Application Support/`:
  - `Games/<SHA-256>/game.gba`: Kopie der importierten Datei.
  - `Games/<SHA-256>/game.json`: Name, System, ursprünglicher Dateiname, Größe, Importdatum.
  - `Games/<SHA-256>/battery.sav`: der Batteriespeicher.
  - `System/`: leer.
  - Das Dateisystem ist die einzige Quelle, SwiftData wäre für eine Handvoll Dateien zu viel. Die ID aus der Prüfsumme macht doppelte Importe zu einem Eintrag, und eine umbenannte Datei behält ihren Spielstand.
  - Gegen die Ordnernamen beider Entwürfe: Der Container hat schon einen Ordner `Library`, deshalb heißt der Ordner `Games`.
- **Import** über `.fileImporter` mit Mehrfachauswahl und dem Typ `com.faentiver.arcfold.gba-rom`, deklariert in `App/Info.plist` (Endung `gba`, konform zu `public.data`). Pro Datei in einer `@concurrent`-Funktion:
  1. `startAccessingSecurityScopedResource()`.
  2. Prüfen: 192 Byte bis 32 MiB, Byte 3 ist 0xEA und Byte 0xB2 ist 0x96, wie in mGBAs `GBAIsROM`.
  3. SHA-256 mit CryptoKit, dann atomar kopieren.
- **Systemtabelle** `GameSystem.gba`: Kern `mgba_libretro`, Endung `gba`, Typ wie oben, Kernoptionen `mgba_use_bios = OFF`.
- **`PlaySession`** (`@MainActor @Observable`) besitzt `EmulationSession`, `FrameMailbox`, `AudioRing`, `AudioOutput` und `PresentationStats`.

| Übergang | Aktion |
| --- | --- |
| Spiel öffnen | `load()`, `connect`, `AudioOutput.start()`, `resume()` |
| `scenePhase` → `.inactive` | `pause()`, `AudioOutput.suspend()` |
| → `.background` | wie `.inactive`, dazu `saveBatteryNow()` in `beginBackgroundTask` und `AudioOutput.stop()` |
| → `.active` | `AudioOutput.resume()`, `resume()`, sofern nicht von Hand pausiert |
| `interrupted`, `outputDeviceLost` | pausieren |
| `resumptionRecommended(true)` | fortsetzen, sofern nicht von Hand pausiert |
| Spielansicht schließen | `stop()`, `AudioOutput.stop()` |

- **Spielansicht:** `GameScreen` hochkant oben und quer mittig, Touch-Tasten darunter bzw. seitlich, dazu ein Menü mit Fortsetzen, Overlay und Beenden. `.persistentSystemOverlays(.hidden)`, `.statusBarHidden()`, `.defersSystemGestures(on: .all)`, während des Spiels `isIdleTimerDisabled`. Die Oberfläche bleibt in M1 schlicht, Liquid Glass und Skins kommen in M4.
- **Ein Spiel zur Zeit:** Das generierte Scene-Manifest erlaubt mehrere Szenen. Eine zweite Spielansicht würde mit `.anotherSessionActive` scheitern, die App zeigt dann einen Hinweis statt eines zweiten Spiels.
- **Debug-Overlay:** `TimelineView(.periodic(from: .now, by: 0.25))` liest nur Schnappschüsse.
  - Emulation: Bildrate, Laufzeit, `trim`, späte Bilder, Neusynchronisationen.
  - Anzeige: Rate des Display-Links, gezeigte, wiederholte und übersprungene Bilder, späte Auswahl, GPU belegt.
  - Ton: Füllstand in ms, Sollwert, Aussetzer, verworfene Frames, Auffüllen, IO-Puffer.
  - Dazu `ProcessInfo.thermalState` und `isLowPowerModeEnabled`.
  - Alle 10 s schreibt die App eine Zeile über `Logger(subsystem: "com.faentiver.arcfold", category: "stats")` als Beleg für Abnahmeläufe. Im Debug-Build ist das Overlay an.
- **Lizenzen:** Liste und Textansicht für Arcfold (GPL-3.0, `LICENSE`), mGBA 0.10.5 (MPL-2.0, mit dem Hinweis auf den Quelltext: github.com/mgba-emu/mgba, Tag 0.10.5), blip_buf 1.1.0 (LGPL-2.1-or-later), inih (BSD-3-Clause) und `libretro.h` (MIT, der Kopfkommentar der Datei). blip_buf und inih stecken im gebauten Kern (belegt in `build.ninja`). Die Texte kopiert `project.yml` aus den Originalen nach `Arcfold.app/Licenses/<Komponente>/`, im Repo gibt es keine Doppel. M3 ergänzt PPSSPP und MoltenVK.
- **Info.plist:** `INFOPLIST_KEY_LSApplicationCategoryType = public.app-category.games`, dazu in `App/Info.plist` `LSSupportsGameMode`, `CADisableMinimumFrameDurationOnPhone` und die Typ-Deklaration. Xcode führt die Datei mit den generierten Schlüsseln zusammen (belegt im Build).
- **Debug-Start:** Nur im Debug-Build importiert und startet das Startargument `-ArcfoldAutorun <Pfad>` eine Datei auf demselben Weg wie `.fileImporter`, für UI-Tests und die Abnahme im Simulator.

### 10. Tests

- **Paket-Tests ohne Kern.**
  - LibretroKitTests: `FrameClock` mit eingespeister Zeit (Fristplan ohne Drift; Aufholen unter drei Perioden; Neusynchronisation darüber; Regler mit ±100 und ±500 ppm über 10 simulierte Minuten ohne Aussetzer; Begrenzung auf ±0,5 %). Dazu `InputState` (Latch, Vereinigung), Environment mit selbst gebauten C-Strukturen (stabile Zeiger, `GET_INPUT_BITMASKS` mit `NULL`, Zählung unbekannter Befehle), der Callback-Platz (zweite Belegung scheitert) und die Dateilogik des Batteriespeichers in einem temporären Ordner.
  - RendererTests: Ring und Postfach einzeln und als Stresstest mit zwei Threads, bei dem jedes Bild seine Sequenznummer trägt. Dazu `ScreenPlacement` für die Duo-Größen und ein Offscreen-Render mit Metal im Simulator, pixelgenau gegen die CPU-Rechnung, für RGB565 und XRGB8888.
- **Mit echtem mGBA** (`Tests/ArcfoldTests/Core`, Kern aus dem App-Bundle, `selftest.gba` aus dem Test-Bundle). Alle Tests, die eine Sitzung laden, stehen unter einer gemeinsamen Suite mit `.serialized`, weil nur ein Kern pro Prozess aktiv sein kann.
  - Start: 240 × 160 RGB565; der Bildzähler im Bild ist Bildnummer − 6.
  - Determinismus: zwei Läufe mit denselben Prüfsummen bei Bild 1, 60 und 300. Die Sollwerte werden auf iOS festgeschrieben.
  - Ton: ein Batch pro Bild mit 545 bis 552 Frames, Mittel 548,63 ± 0,5, Frequenz 440 ± 2 Hz, mit A 880 ± 2 Hz.
  - Eingabe: A in den Bildern 100 bis 300 setzt Bit 0 der Tastenzeile und den hohen Ton.
  - Spielstand: Sitzung 1 schreibt 32 768 Byte, die mit „ARCF“ und 0x01 beginnen; Sitzung 2 zählt 0x02; Byte 5 trägt den Herzschlag.
  - Environment: `SessionSummary.unhandledEnvironmentCommands` enthält bei mGBA genau `SET_MEMORY_MAPS` und `SET_SUPPORT_ACHIEVEMENTS`.
  - Kurzer Lauf mit echtem Takt: laden, 120 Bilder, Pause, Fortsetzen, Stopp, Spielstand geschrieben; die Bildrate nur als Plausibilitätswert.
- **App-Tests** (`Tests/ArcfoldTests/App`): Import im temporären Ordner (Duplikat, zu klein, falscher Kopf), Bibliothek, Inhalt des App-Bundles.
- **UI-Tests** (`ArcfoldUITests`, nur im Scheme Store): Start, Spiel per Debug-Start mit Bildrate im Overlay, Bildschirm „Lizenzen“.
- **Abnahme im Simulator:** eigenes Gerät „iPhone Duo“ mit iOS 27.1. Zehn Minuten `selftest.gba`: Bildrate etwa 59,7, keine Aussetzer nach dem Auffüllen, keine Neusynchronisation. Neustart per `simctl terminate` und erneutem Start: Boot-Zähler plus 1. Wechsel in den Hintergrund und zurück. Leistungszahlen gelten dort nur als Plausibilitätswerte.
- **Abnahme auf dem Duo** (offen, bis das Gerät eingerichtet ist): zehn Minuten `selftest.gba` und zehn Minuten eines Homebrews mit DirectSound-Ton. Erwartet: 59,73 ± 0,05 Bilder/s, keine Aussetzer, `thermalState` höchstens `.fair`.

### 11. Testprogramm

- **`Tests/Fixtures/gba/selftest.gba`** aus dem eigenen Generator `Tests/Fixtures/gba/selftest/make_gba_selftest.py`. Er vereint beide Entwürfe: den festen Ton (440 bzw. 880 Hz) und die ablesbaren Zähler aus „Nativ“, dazu den Herzschlag im SRAM aus „Echtzeit“, der das Sichern während des Spiels prüfbar macht. 864 Byte, reproduzierbar, ohne Logo und ohne BIOS-Aufrufe. Lizenz und Prüfsumme stehen in `Tests/Fixtures/LICENSES.md`.
- **Belegt in mGBA 0.10.5** (macOS-Build, Legacy-Optionen, `mgba_use_bios = OFF`, `0005/selftest-mgba-macos.txt` und `0005/selftest-frame-0300-boot2.png`):
  - RGB565, 240 × 160, Pitch 512, Ton 439,9 Hz und mit A 879,7 Hz.
  - SRAM erkannt (32 768 Byte), Boot-Zähler 1 → 2 → 3, Herzschlag 4 nach 300 Bildern.
  - Bildzähler 294 bei Bild 300, deterministisch über Läufe und bei Übergabe als Pfad.
  - Offen bis zu den Tests der Spur K: der Beleg mit dem iOS-Kern im Simulator.
- **Nicht im Repo:**
  - jsmolka/gba-tests (MIT): `sram.gba` meldet unter mGBA 0.10.5 „Failed test 006“, der Kopf enthält das Nintendo-Logo.
  - µCity Advance: Grafik unter CC-BY-NC-SA-4.0, also nicht frei.
  - Grimlight (MIT laut GitHub): Repo vom 16. Oktober 2026, Konto vom 30. September 2026, keine Sterne. Für die Tests nicht nötig.
  - Für Hör- und Scrolltests auf dem Gerät eignet sich die 160p Test Suite v0.23 (`240pee_mb.gba`, 61 104 Byte, github.com/pinobatch/240p-test-mini). Laut README steht sie unter „GNU General Public License, version 2 or later“, GitHub erkennt GPL-2.0 (geprüft am 6. November 2026). Sie bringt Sinustöne, PCM über DirectSound und Scrolltests mit. Fatih importiert sie selbst, ins Repo kommt sie nicht.

## Folgen

- **Plan:** Leitplanke 6 beschreibt jetzt die Trimmung der Emulationsperiode statt Resampling. M1 nennt im Lizenzbildschirm zusätzlich blip_buf und inih, Abschnitt 9 nennt die Fixture und die Testarten.
- **Neue Targets:** `RendererTests` (beide Schemes) und `ArcfoldUITests` (nur Store) sind angelegt. Mit den Spuren kommen dazu: der Log-Shim in `CLibretro` (K) und das C/ObjC-Target `CRendererAudio` im Renderer (A).
- **Abhängigkeit:** Renderer hängt von LibretroKit ab, nie umgekehrt.
- **Ein Kern pro Prozess:** Tests mit Sitzung laufen serialisiert, und die App verhindert eine zweite Spielansicht.
- **Vor M3:** Der Environment-Callback und der Log-Weg müssen threadsicher werden, weil PPSSPP aus eigenen Threads ruft. Dazu kommt der HW-Render-Weg (ADR 0001). Ein `actor` mit eigenem `SerialExecutor` auf dem Emulations-Thread wäre dann einen Blick wert, weil er den Kern zur Übersetzungszeit an den Thread bindet.
- **Annahmen, die die Spuren prüfen:**
  - Ein ObjC-Target im Swift-Paket baut mit Xcode für iOS; mit `swift build` auf macOS ist das belegt.
  - `.metal`-Dateien im Paket landen als `default.metallib` in `Bundle.module`.
  - `MTLTexture.replace` mit `.shared` und `r16Uint` funktioniert im Simulator.
  - `SpatialEventGesture` liefert Mehrfachberührung zuverlässig.
  - `GCControllerLiveInput` und `GCKeyboard` funktionieren im Simulator.
  - Das Verhalten von `CAMetalDisplayLink` beim Wechsel zwischen Innen- und Außendisplay gehört zu M2.
- **Offen für Fatih:**
  - die Leistungszahlen auf dem Duo: Bildrate, Wärme, Tonlatenz, 60 oder 120 Hz;
  - die Controller-Belegung nach Position oder nach Beschriftung, solange der Controller unbekannt ist;
  - die Lizenzvariante des Generators (Plan, Abschnitt 12);
  - Ton im Lautlos-Modus: `.ambient` als Standard, ein Schalter für `.playback` erst in M4;
  - ob die 160p Test Suite für den Gerätetest genügt.
