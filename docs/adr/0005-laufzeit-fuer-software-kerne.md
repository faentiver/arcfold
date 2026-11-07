# 0005 · Laufzeit für Software-Kerne

Status: Angenommen · 7. November 2026 (vorgeschlagen am 6. November 2026, umgesetzt in M1, Belege im Abschnitt „Umsetzung in M1“, Entscheidungen im Abschnitt „Entscheidungen bei der Annahme“)

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

Der Code steht in `Packages/LibretroKit/Sources/LibretroKit/` (`Media.swift`, `Sinks.swift`, `Input.swift`, `EmulationSession.swift`, `SessionStats.swift`) und `Packages/Renderer/Sources/Renderer/`. Seit der Integration ist alles umgesetzt; die Platzhalter `fatalError("M1 track K")` und `fatalError("M1 track A")` aus dem Entwurf gibt es nicht mehr.

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
  - Fehler `e = (bufferedFrames − geschriebene Frames − targetFrames) / sampleRate` in Sekunden. `bufferedFrames` stammt aus dem `AudioBufferStatus` des letzten Schreibens im Bild, abgezogen werden alle Frames, die das Bild geschrieben hat. Geregelt wird also der Füllstand vor dem Ton des Bildes, der Tiefpunkt kurz vor dem nächsten Schreiben, auf die Reserve `targetFrames` (Abschnitt 6).
  - Geändert bei der Integration: Der Vertrag in `Sinks.swift` meinte zuerst den Pegel direkt nach einem Schreiben, `AudioRing` meldet aber den Füllstand zum Auffüllen. Damit hielt der Regler nach dem Schreiben 35 ms und vor dem nächsten Bild nur etwa 18 ms. In der Simulation von Spur K gab das bei +500 ppm 2 Aussetzer in 10 Minuten und einen Tiefstwert von 2,1 ms, mit dem Füllstand vor dem Ton 0 Aussetzer und 18,6 ms. Die geschriebenen Frames abzuziehen, statt ein Bild Ton auf den Sollwert aufzuschlagen, hält die Regel auch für Kerne richtig, die mehrmals pro Bild schreiben.
  - `I = clamp(I + e · P, ±0,5)` und `trim = clamp(0,05 · e + 0,005 · I, ±0,005)`, die Periode wird zu `P · (1 + trim)`.
  - Nur solange `isConsuming` gilt, sonst klingt `trim` gegen 0 ab.
  - Belegt in der Simulation des Entwurfs „Echtzeit“: 0 Aussetzer bei ±100 und ±500 ppm Drift, Ausreißern bis 12 ms und einem Stillstand von 30 ms, und `trim` stellt sich genau auf die Drift ein.
  - Im Echtzeitlauf des Entwurfs „Nativ“ (2 × 40 s am Mac) lag die nötige Korrektur bei 0 bis −0,14 %, ohne Aussetzer. Ohne Regelung wäre der Puffer dort nach etwa einer Minute leer gewesen.
  - Gegen den P-Regler aus Entwurf „Nativ“: Ein P-Regler hält bei Drift einen bleibenden Abstand zum Sollfüllstand, der PI-Regler nicht.
- **Abweichung von Leitplanke 6:** Es gibt kein dynamisches Resampling. Die Tonhöhe bleibt exakt, die Wandlung macht AVAudioEngine mit fester Rate, und der Render-Block bleibt eine reine Kopie. Das Bild ist ohnehin nicht an den Display-Takt gekoppelt. Der Plan ist angepasst.
- **Startreihenfolge:** `load()`, `connect(video:audio:)`, `AudioOutput.start()`, `resume()`. Belegt im Prototyp: Liefen Bilder schon vor dem Start der Engine, füllte sich der Puffer auf über 7 000 Frames, und 1 616 Frames gingen verloren. Mit dem Ton zuerst blieb der Füllstand stabil.
- **Messwerte** schreibt der Emulations-Thread etwa einmal pro Sekunde und bei jedem Zustandswechsel mit relaxed Stores in `SessionStats`: Laufzeit von `retro_run`, Verspätung, späte Bilder (über 2 ms), Neusynchronisationen, `trim` und die Bildrate. Dazu kommen Signposts (Subsystem `com.faentiver.arcfold`, Kategorie `emulation`): das Intervall „retro_run“ und das Ereignis „resync“. Umgesetzt in C mit den `os_signpost`-Makros (`CLibretro/arcfold_signpost.h`) statt mit `OSSignposter`, weil `OSSignposter.beginInterval` in der Messung von Spur K pro Bild ein Objekt und zwei Puffer anlegte, auch ohne Instruments.

### 4. Callbacks (Leitplanke 3)

- **Trampoline:** sechs `@convention(c)`-Funktionen als `static let`. Sie leiten an den aktiven Kontext weiter, der als `Unmanaged`-Zeiger in einem globalen `Atomic<UInt>` steht (0 heißt kein Kern). Belegung per `compareExchange` vor `retro_set_environment`, weil mGBA dort schon das Environment ruft. Freigabe nach `retro_deinit`. Ein zweites `load()` endet mit `.anotherSessionActive`. Zugriff mit `takeUnretainedValue()`, ohne unterstrichene API.
- Gegen Entwurf „Nativ“ (`Atomic<Bool>` plus `nonisolated(unsafe)`): Belegung und Zeiger stecken in einem einzigen Atomic, ein unsicherer globaler Zustand entfällt. Belegt im Prototyp: kompiliert unter Swift 6.4.2 mit den Features des Projekts.
- **Log:** `retro_log_printf_t` ist variadisch, Swift sieht ihn nur als `OpaquePointer?`. Ein C-Shim in `CLibretro` (`arcfold_log.c`) prüft zuerst eine atomare Mindeststufe (darunter wird nur gezählt), formatiert sonst mit `vsnprintf` in einen Stack-Puffer und ruft eine nicht-variadische Senke. Die Senke schreibt mit Ratenbegrenzung über `os.Logger`. `CLibretro` hat dafür den Umbrella-Header `include/CLibretro.h`: Ohne ihn baut SwiftPM die Module-Map über das Verzeichnis, und ein neuer Header fehlte im schon gebauten Modul für das Gerät.
- **Spiel übergeben:** mGBA hat `need_fullpath = false`. Der Host liest die Datei mit `NSData(contentsOf:options: .alwaysMapped)` und übergibt `data`, `size` und `path`. `NSData` statt `Data`, weil `bytes` dokumentiert so lange gilt wie das Objekt (`docs/wissen/libretrokit.md`). Die Daten bleiben bis `retro_unload_game` gültig. Pfad und Daten ergeben dieselben Bilder (belegt).
- **Environment in M1:**

| Befehl | Antwort |
| --- | --- |
| `GET_CORE_OPTIONS_VERSION` | `false`. mGBA meldet seine 13 Optionen dann über `SET_VARIABLES` (belegt), der Host kopiert die Standardwerte sofort, weil mGBA die Zeichenketten danach freigibt |
| `SET_VARIABLES` | `true`, Standardwert ist der erste Wert der Liste |
| `GET_VARIABLE` | Wert aus `SessionConfiguration.coreOptions`, sonst der Standardwert; C-Strings mit stabiler Adresse für die ganze Sitzung, unbekannte Schlüssel `false` |
| `GET_VARIABLE_UPDATE` | `*data = false`, `true`; einmal pro Bild, ohne Allokation |
| `SET_PIXEL_FORMAT` | `true` für RGB565 und XRGB8888, `false` für 0RGB1555 (zählt als unbehandelt); nach dem Laden nur noch dasselbe Format |
| `GET_INPUT_BITMASKS` | `true`, `data` ist bei mGBA `NULL` und bleibt unberührt |
| `SET_INPUT_DESCRIPTORS` | `true`, ignoriert; die Beschriftungen kommen aus der App |
| `GET_LOG_INTERFACE` | C-Shim |
| `GET_SYSTEM_DIRECTORY`, `GET_SAVE_DIRECTORY` | Ordner aus der Konfiguration; der Systemordner bleibt leer |
| `GET_CAN_DUPE` | `true`; ein `NULL`-Bild erreicht die Senke nicht |
| `SET_GEOMETRY` | `true`, Größe bis zum Maximum; vor dem Laden `false` |
| `SET_SYSTEM_AV_INFO` | `false` und protokollieren; mGBA ruft es nicht, M2 klärt den Bedarf |
| `SHUTDOWN` | `true`, Ereignis `coreRequestedShutdown` |
| `SET_MESSAGE`, `SET_MESSAGE_EXT` | `true`, Ereignis `coreMessage` |
| `GET_JIT_CAPABLE` | Rückgabe `true` mit `*data = false`: Laut libretro.h heißt die Rückgabe `true` „Aufruf verfügbar“, und ein Kern ohne Antwort kann abstürzen (ADR 0002). Der JIT-Build bekommt später einen neutralen Haken |
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
  - In der App zählt der sichere Bereich: Zugeklappt legt iOS 27.1 im Duo-Simulator Statusleiste und Toolbar in eine 84 pt breite Spalte am rechten Rand. Die Spielansicht ist dort 382 pt breit, das Bild also 960 × 640 px (Faktor 4) bei (93, 62) statt Faktor 5 auf dem ganzen Panel (belegt in den Bildschirmfotos der Abnahme).
  - Der Duo-Simulator meldet das Innendisplay mit 2007 × 2853 px, nicht mit den 1878 × 2670 aus dem Plan (Abschnitt 3). Welche Zahl auf dem Gerät gilt, klärt der Gerätetest vor M2.

### 6. Ton

- **`AudioRing`:** lock-freier SPSC-Ring in C (`CRendererAudio`, C11-Atomics mit Acquire und Release). Er fasst 8 192 Stereo-Frames Int16 (250 ms bei 32 768 Hz), ein Frame als `uint32_t`, sodass nie ein halbes Stereopaar entsteht. Der Erzeuger schreibt höchstens den freien Platz, der Rest wird verworfen und gezählt. Belegt im Prototyp: 3,17 Mrd. Frames unter Volllast ohne Sprung.
- **Render-Funktion** `CA_REALTIME_API` mit den Zuständen Auffüllen (Stille, bis der Sollwert erreicht ist), Spielen und Ausgesetzt (Stille ohne Zählung). Nach dem Auffüllen blendet sie über 64 Frames ein, damit das Signal nicht von Stille auf seinen Wert springt. Läuft der Ring beim Spielen leer, füllt sie den Rest mit Nullen und blendet über 64 Frames vom letzten Wert aus. Dann zählt sie einen Aussetzer und füllt neu auf.
- **Compilerprüfung:** In der Umsetzungsdatei steht `#pragma clang diagnostic error "-Wfunction-effects"`. Belegt im Prototyp: `malloc`, `free`, `NSLog` oder eine Objective-C-Nachricht im Block brechen den Build ab, `memcpy` und Atomics nicht. Die Warnung ist sonst aus, auch mit `-Wall`. In M1 ist auch der Erzeuger `ARCAudioRingWrite` `CA_REALTIME_API` und damit geprüft; die Gegenprobe von Spur A (Allokation und Lock eingebaut, Build bricht ab) steht in `docs/wissen/renderer.md`.
- **`isConsuming`** heißt: Zustand Spielen, und der Render-Block lief in den letzten 100 ms. Gemessen am Zähler der Render-Aufrufe aus Sicht des Erzeugers, nicht an `mHostTime`.
- **Knoten:** Eine Objective-C-Fabrik erzeugt `AVAudioSourceNode` mit `initWithFormat:realtimeSafeRenderBlock:`. Das Blockformat ist das Kernformat, Int16 verschachtelt mit 32 768 Hz, die Render-Funktion kopiert also nur. Verbunden wird mit `connectNode(_:to:format:)` und dem Format `standardFormatWithSampleRate: <Hardware-Rate>, channels: 2`. Damit wandelt nur der Quellknoten, und das einmal; laut Header kann er Abtastrate, Bittiefe und Verschachtelung wandeln. Belegt im Prototyp: Ohne Format stand der Knoten auf 44,1 kHz, und der Mischer wandelte ein zweites Mal.
- **Sollfüllstand** `max(35 ms, ioBufferDuration + 20 ms)`, neu berechnet nach jeder Routenänderung. Mit 5 ms IO-Puffer sind das 35 ms, mit 21 ms 41 ms. Gegen die festen 50 ms aus Entwurf „Nativ“: Die Simulation zeigte schon mit 35 ms keine Aussetzer, solange der IO-Puffer klein ist.
  - Der Sollfüllstand ist der Füllstand, auf den das Auffüllen wartet, und zugleich die Reserve, die der Takt vor dem Ton jedes Bildes hält (`AudioBufferStatus.targetFrames`, Abschnitt 3). Direkt nach dem Schreiben liegt der Füllstand damit etwa ein Bild Ton höher, bei mGBA rund 17 ms.
- **Audiositzung:** Kategorie `.ambient`, also stumm im Lautlos-Modus und mischbar mit Musik. `setPreferredIOBufferDuration(0.005)`, Aktivierung mit dem asynchronen `activate(options:)`. Beobachtet werden `didBecomeInactiveNotification` (Spiel pausieren), `resumptionRecommendationNotification` (fortsetzen bei `.shouldResume`), `routeChangeNotification` (Sollwert neu, bei `.oldDeviceUnavailable` pausieren), `AVAudioEngineConfigurationChange` (Engine neu starten) und `mediaServicesWereResetNotification` (Engine und Knoten neu bauen). Neustarts und Auffüllen zählen nicht als Aussetzer.

### 7. Eingabe

- **`InputState`:** ein `Atomic<UInt32>` je Quelle und ein gemeinsames Latch. `set(_:from:)` speichert die Maske der Quelle und setzt neu gedrückte Tasten per `bitwiseOr` im Latch. `retro_input_poll` bildet einmal pro Bild die Vereinigung aller Quellen plus `latch.exchange(0)`, `input_state` liest nur diesen Schnappschuss: Maske für `RETRO_DEVICE_ID_JOYPAD_MASK`, sonst das Bit, nur Port 0 und `RETRO_DEVICE_JOYPAD`. Ein Tipp zwischen zwei Abfragen geht so nicht verloren.
- **Touch:** eine SwiftUI-Ansicht mit `SpatialEventGesture` (iOS 18 und neuer), die alle Finger sieht. Aus allen aktiven Berührungen entsteht eine Maske, ein Finger kann von Taste zu Taste gleiten. Das Steuerkreuz ist ein Kreis mit acht Sektoren und Totzone. Beschriftungen A, B, L, R, Start und Select, ohne Original-Symbole. Ausweg, falls Mehrfachberührung so nicht zuverlässig ist: eine `UIView` mit Touch-Methoden.
- **Controller:** Verbindungsmeldungen und `GCController.controllers()`. Pro Controller `GCControllerLiveInput` (`controller.input`) auf einer eigenen seriellen Queue mit `inputStateQueueDepth = 16`; `inputStateAvailableHandler` holt mit `nextInputState()` jeden Zwischenzustand ab.
  - Gegen `valueChangedHandler` auf dem Main Thread (Entwurf „Nativ“): unabhängig von Hängern im Main Thread.
  - An der Spielansicht hängt `GCEventInteraction` für Gamepad-Ereignisse.
  - Belegung nach RetroPad-Position: Ost-Taste A, Süd-Taste B, West Y, Nord X, Schultertasten und Trigger L und R, Steuerkreuz und linker Stick (Schwelle 0,5) für die Richtungen, Menü Start, Optionen Select.
  - `GCKeyboard` mit derselben Logik für Tests im Simulator, Belegung wie die Standard-Tastatur von RetroArch.
  - Hat ein verbundener Controller eine Taste gedrückt, blendet die App das Touch-Overlay aus; trennt er sich, kommt es zurück. Geändert bei der Integration, zuvor genügte die Verbindung: Der Duo-Simulator meldet ohne angeschlossene Hardware immer einen Controller („MFi“/„Gamepad“), mit der ursprünglichen Regel blieben die Touch-Tasten dort unsichtbar. Auf dem Gerät nimmt so auch ein gekoppelter, aber beiseitegelegter Controller die Touch-Tasten nicht weg.

### 8. Batteriespeicher

- **Laden** nach `retro_load_game` und vor dem ersten `retro_run`: `min(Dateigröße, retro_get_memory_size)` Byte in den Puffer kopieren. Fehlt die Hauptdatei, ist sie leer, unlesbar oder kürzer als die Sicherung, kommt `battery.sav.bak` zum Zug; fehlen beide, bleibt der Puffer bei 0xFF. „Kürzer als erwartet“ aus dem Entwurf ist so umgesetzt, weil mGBA vor der Erkennung des Speichertyps 131 072 Byte meldet: Eine richtige SRAM-Datei mit 32 768 Byte wäre sonst immer zu kurz.
- **Prüfen** alle 30 Bilder per `memcmp` gegen eine einmal angelegte Kopie des zuletzt gesehenen Stands. Geschrieben wird, wenn sich der Inhalt geändert hat und seit einer Prüfung gleich geblieben ist. Grund: Spiele schreiben oft über mehrere Bilder, ein Abzug mitten darin wäre inkonsistent.
- **Übergabe** in einen von zwei vorab angelegten Puffern an eine serielle Queue mit QoS `.utility`, je Puffer über ein einmal angelegtes `DispatchWorkItem`. Ein Dispatch-Block darf beliebig oft laufen, solange niemand auf ihn wartet (`dispatch/block.h`); `queue.async` mit einer Closure legte pro Übergabe zwei Blöcke an. Pro Bild gibt es keine Allokation (gemessen von Spur K, `docs/wissen/libretrokit.md`).
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
- **Import** über `.fileImporter` mit Mehrfachauswahl und dem Typ `com.faentiver.arcfold.gba-rom`, deklariert in `App/Info.plist` (Endung `gba`, konform zu `public.data`). Dazu kommt der Typ, den das System der Endung gerade zuordnet (`GameSystem.importTypes`): Arcfold importiert seinen Typ nur, exportiert eine andere installierte App einen eigenen für `.gba`, bevorzugt das System diesen, und ohne ihn grauten die Spiele in der Auswahl aus. Pro Datei in einer `@concurrent`-Funktion:
  1. `startAccessingSecurityScopedResource()`.
  2. Lesen über `NSFileCoordinator`, damit iCloud Drive und andere Anbieter die Datei vorher laden; ohne Mapping, die Kopie ändert sich danach nicht mehr.
  3. Prüfen: 192 Byte bis 32 MiB, Byte 3 ist 0xEA und Byte 0xB2 ist 0x96, wie in mGBAs `GBAIsROM`.
  4. SHA-256 mit CryptoKit, dann atomar kopieren.
- **Systemtabelle** `GameSystem.gba`: Kern `mgba_libretro`, Endung `gba`, Typ wie oben, Kernoptionen `mgba_use_bios = OFF`.
- **`PlaySession`** (`@MainActor @Observable`) besitzt `EmulationSession`, `FrameMailbox`, `AudioRing`, `AudioOutput` und `PresentationStats`.

| Übergang | Aktion |
| --- | --- |
| Spiel öffnen | `load()`, `connect`, `AudioOutput.start()`, `resume()` |
| `scenePhase` → `.inactive` | `AudioOutput.suspend()`, dann `pause()` |
| → `.background` | zuerst `beginBackgroundTask`, darin wie `.inactive`, dazu `saveBatteryNow()` und `AudioOutput.stop()` |
| → `.active` | nach dem Hintergrund zuerst `AudioOutput.start()`; dann `AudioOutput.resume()` und `resume()`, sofern nicht von Hand pausiert |
| `interrupted` | pausieren |
| `outputDeviceLost`, `resumptionRecommended(false)` | Pause von Hand, Fortsetzen über das Menü |
| `resumptionRecommended(true)` | fortsetzen, sofern nicht von Hand pausiert |
| Spielansicht schließen | `stop()`, `AudioOutput.stop()` |

- Alle Übergänge laufen über eine Warteschlange von Lebenszyklus-Schritten, die aufeinander warten. Inaktiv, Hintergrund und aktiv in schneller Folge überholen sich so nicht.
- Beim Pausieren kommt der Ton zuerst (umgesetzt von Spur A, abweichend von der ersten Fassung dieser Tabelle): Hielte zuerst der Emulations-Thread an, liefe der Ring leer, und das zählte als Aussetzer.

- **Spielansicht:** `GameScreen` hochkant oben und quer mittig, Touch-Tasten darunter bzw. seitlich, dazu ein Menü mit Fortsetzen, Overlay und Beenden. `.persistentSystemOverlays(.hidden)`, `.statusBarHidden()`, `.defersSystemGestures(on: .all)`, während des Spiels `isIdleTimerDisabled`. Die Oberfläche bleibt in M1 schlicht, Liquid Glass und Skins kommen in M4.
- **Ein Spiel zur Zeit:** Das generierte Scene-Manifest erlaubt mehrere Szenen. Eine zweite Spielansicht würde mit `.anotherSessionActive` scheitern, die App zeigt dann einen Hinweis statt eines zweiten Spiels.
- **Debug-Overlay:** `TimelineView(.periodic(from: .now, by: 0.25))` liest nur Schnappschüsse.
  - Emulation: Bildrate, Laufzeit, `trim`, späte Bilder, Neusynchronisationen.
  - Anzeige: Rate des Display-Links, gezeigte, wiederholte und übersprungene Bilder, späte Auswahl, GPU belegt.
  - Ton: Füllstand in ms, Sollwert, Aussetzer, verworfene Frames, Auffüllen, IO-Puffer.
  - Eingabe: gehaltene Tasten, letzter Tastendruck und Zahl der Tastendrücke aus `InputState`. Der Zähler hält fest, was eine kurze Berührung bewirkt hat; der UI-Test der Touch-Tasten liest ihn.
  - Dazu `ProcessInfo.thermalState` und `isLowPowerModeEnabled`.
  - Alle 10 s schreibt die App eine Zeile über `Logger(subsystem: "com.faentiver.arcfold", category: "stats")` als Beleg für Abnahmeläufe. Im Debug-Build ist das Overlay an.
- **Lizenzen:** Liste und Textansicht für Arcfold (GPL-3.0, `LICENSE`), mGBA 0.10.5 (MPL-2.0, mit dem Hinweis auf den Quelltext: github.com/mgba-emu/mgba, Tag 0.10.5), blip_buf 1.1.0 (LGPL-2.1-or-later), inih (BSD-3-Clause) und `libretro.h` (MIT, der Kopfkommentar der Datei). blip_buf und inih stecken im gebauten Kern (belegt in `build.ninja`). Die Texte kopiert `project.yml` aus den Originalen nach `Arcfold.app/Licenses/<Komponente>/`, im Repo gibt es keine Doppel. M3 ergänzt PPSSPP und MoltenVK.
- **Info.plist:** `INFOPLIST_KEY_LSApplicationCategoryType = public.app-category.games`, dazu in `App/Info.plist` `LSSupportsGameMode`, `CADisableMinimumFrameDurationOnPhone` und die Typ-Deklaration. Xcode führt die Datei mit den generierten Schlüsseln zusammen (belegt im Build).
- **Debug-Start:** Nur im Debug-Build importiert und startet das Startargument `-ArcfoldAutorun <Pfad>` eine Datei auf demselben Weg wie `.fileImporter`, für UI-Tests und die Abnahme im Simulator. Dazu kamen in Spur A `-ArcfoldImport <Pfad>` (nur importieren) und `-ArcfoldTestPattern YES` (Spielansicht mit Testmuster ohne Kern); beide bleiben, weil UI-Tests sie nutzen. Den Pfad darf die App nur im Simulator lesen; auf dem Gerät führt der Weg über die Dateien-App.

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
  - Kurzer Lauf mit echtem Takt: laden, 120 Bilder, Pause, zweite Pause (die Bildrate bleibt stehen), Fortsetzen, Stopp, Spielstand geschrieben; die Bildrate nur als Plausibilitätswert.
- **App-Tests** (`Tests/ArcfoldTests/App`): Import im temporären Ordner (Duplikat, zu klein, falscher Kopf), Bibliothek, Inhalt des App-Bundles.
- **UI-Tests** (`ArcfoldUITests`, nur im Scheme Store): Start, Spiel per Debug-Start mit Bildrate im Overlay, Bildschirm „Lizenzen“, dazu aus Spur A der Debug-Import und das Testmuster ohne Kern, nach der Prüfung die Touch-Tasten (A halten, von A nach B gleiten, Tastenzähler im Overlay).
- **Abnahme im Simulator:** eigenes Gerät „iPhone Duo“ mit iOS 27.1. Zehn Minuten `selftest.gba`: Bildrate etwa 59,7, keine Aussetzer nach dem Auffüllen, keine Neusynchronisation. Neustart per `simctl terminate` und erneutem Start: Boot-Zähler plus 1. Wechsel in den Hintergrund und zurück. Leistungszahlen gelten dort nur als Plausibilitätswerte. Ergebnis im Abschnitt „Umsetzung in M1“.
- **Abnahme auf dem Duo** (offen, bis das Gerät eingerichtet ist): zehn Minuten `selftest.gba` und zehn Minuten eines Homebrews mit DirectSound-Ton. Erwartet: 59,73 ± 0,05 Bilder/s, keine Aussetzer, `thermalState` höchstens `.fair`.

### 11. Testprogramm

- **`Tests/Fixtures/gba/selftest.gba`** aus dem eigenen Generator `Tests/Fixtures/gba/selftest/make_gba_selftest.py`. Er vereint beide Entwürfe: den festen Ton (440 bzw. 880 Hz) und die ablesbaren Zähler aus „Nativ“, dazu den Herzschlag im SRAM aus „Echtzeit“, der das Sichern während des Spiels prüfbar macht. 864 Byte, reproduzierbar, ohne Logo und ohne BIOS-Aufrufe. Lizenz und Prüfsumme stehen in `Tests/Fixtures/LICENSES.md`.
- **Belegt in mGBA 0.10.5** (macOS-Build, Legacy-Optionen, `mgba_use_bios = OFF`, `0005/selftest-mgba-macos.txt` und `0005/selftest-frame-0300-boot2.png`):
  - RGB565, 240 × 160, Pitch 512, Ton 439,9 Hz und mit A 879,7 Hz.
  - SRAM erkannt (32 768 Byte), Boot-Zähler 1 → 2 → 3, Herzschlag 4 nach 300 Bildern.
  - Bildzähler 294 bei Bild 300, deterministisch über Läufe und bei Übergabe als Pfad.
  - Belegt in Spur K mit dem iOS-Kern im Simulator: Die SHA-256 der Bilder 1, 60 und 300 stimmen mit den macOS-Werten überein (`CoreSessionTests`, Suite `Determinism`).
- **Nicht im Repo:**
  - jsmolka/gba-tests (MIT): `sram.gba` meldet unter mGBA 0.10.5 „Failed test 006“, der Kopf enthält das Nintendo-Logo.
  - µCity Advance: Grafik unter CC-BY-NC-SA-4.0, also nicht frei.
  - Grimlight (MIT laut GitHub): Repo vom 16. Oktober 2026, Konto vom 30. September 2026, keine Sterne. Für die Tests nicht nötig.
  - Für Hör- und Scrolltests auf dem Gerät eignet sich die 160p Test Suite v0.23 (`240pee_mb.gba`, 61 104 Byte, github.com/pinobatch/240p-test-mini). Laut README steht sie unter „GNU General Public License, version 2 or later“, GitHub erkennt GPL-2.0 (geprüft am 6. November 2026). Sie bringt Sinustöne, PCM über DirectSound und Scrolltests mit. Fatih importiert sie selbst, ins Repo kommt sie nicht.

## Folgen

- **Plan:** Leitplanke 6 beschreibt jetzt die Trimmung der Emulationsperiode statt Resampling. M1 nennt im Lizenzbildschirm zusätzlich blip_buf und inih, Abschnitt 9 nennt die Fixture und die Testarten.
- **Neue Targets:** `RendererTests` (beide Schemes) und `ArcfoldUITests` (nur Store) sind angelegt. Mit den Spuren kamen dazu: Log-Shim, Signposts und Umbrella-Header in `CLibretro` (K) und das C/ObjC-Target `CRendererAudio` im Renderer (A).
- **Neue Build-Voraussetzung:** die Metal-Toolchain als Komponente von Xcode (`xcodebuild -downloadComponent metaltoolchain`), weil der Renderer einen Shader übersetzt. Die CI lädt sie, wenn das Image sie nicht hat.
- **Abhängigkeit:** Renderer hängt von LibretroKit ab, nie umgekehrt.
- **Ein Kern pro Prozess:** Tests mit Sitzung laufen serialisiert, und die App verhindert eine zweite Spielansicht.
- **Vor M3:** Der Environment-Callback und der Log-Weg müssen threadsicher werden, weil PPSSPP aus eigenen Threads ruft. Dazu kommt der HW-Render-Weg (ADR 0001). Ein `actor` mit eigenem `SerialExecutor` auf dem Emulations-Thread wäre dann einen Blick wert, weil er den Kern zur Übersetzungszeit an den Thread bindet.
- **Annahmen, die die Spuren prüfen sollten,** Stand nach der Integration:
  - Ein ObjC-Target im Swift-Paket baut mit Xcode für iOS: belegt für Simulator und Gerät (Spur A).
  - `.metal`-Dateien im Paket landen als `default.metallib` in `Bundle.module`: belegt, sofern die Metal-Toolchain installiert ist (Spur A).
  - `MTLTexture.replace` mit `.shared` und `r16Uint` funktioniert im Simulator: belegt, pixelgenau für alle 65 536 RGB565-Werte (Spur A).
  - `SpatialEventGesture` liefert Mehrfachberührung zuverlässig: offen. Im Simulator ist nur die einzelne Berührung prüfbar (Abschnitt „Umsetzung in M1“), Mehrfachberührung braucht das Gerät.
  - `GCControllerLiveInput` und `GCKeyboard` funktionieren im Simulator: offen. Der Simulator meldet einen Controller („MFi“/„Gamepad“) und eine Tastatur („Generic Keyboard“), Eingaben darüber sind ungeprüft; ein echter Controller braucht das Gerät.
  - Das Verhalten von `CAMetalDisplayLink` beim Wechsel zwischen Innen- und Außendisplay gehört zu M2.
- **Offen bei der Vorlage** (inzwischen entschieden, Abschnitt „Entscheidungen bei der Annahme“):
  - die Leistungszahlen auf dem Duo: Bildrate, Wärme, Tonlatenz, 60 oder 120 Hz;
  - die Controller-Belegung nach Position oder nach Beschriftung, solange der Controller unbekannt ist;
  - die Lizenzvariante des Generators (Plan, Abschnitt 12);
  - Ton im Lautlos-Modus: `.ambient` als Standard, ein Schalter für `.playback` erst in M4;
  - ob die 160p Test Suite für den Gerätetest genügt;
  - aus der Integration: ob `mach_wait_until` auf dem Duo ähnlich spät aufwacht wie im Simulator (bis etwa 2 ms, dort zählten in der Abnahme rund 58 % der Bilder als „spät“). Dann wären die Grenze für späte Bilder oder die Latenz-QoS des Emulations-Threads (`THREAD_LATENCY_QOS_POLICY`) zu prüfen;
  - aus der Integration: ob die Spielansicht zugeklappt die Systemspalte rechts überdecken darf (Faktor 5 statt 4) und welche Pixelmaße das Innendisplay auf dem Gerät hat. Beides gehört zu M2;
  - aus der Integration: die neue Regel für das Touch-Overlay (ausblenden erst nach dem ersten Tastendruck eines Controllers, Abschnitt 7).

## Umsetzung in M1

Stand 7. November 2026, Branch `m1/gba`: Spur K (`m1/kern-laufzeit`) und Spur A (`m1/ausgabe-app`) per Merge zusammengeführt, dazu die Korrekturen der Integration. Geprüft auf einem eigenen Simulatorgerät „Arcfold M1 Integration“ (iPhone Duo, iOS 27.1, 24A94425) mit Xcode 27.2 auf dem Mac mini M4 Pro. Zahlen aus dem Simulator sind Plausibilitätswerte, Bildrate, Wärme und Ton zählen erst auf dem Duo. Rohwerte in `0005/m1-abnahme-simulator.txt`.

**Korrekturen der Integration**

- Takt: Regelgröße ist der Füllstand vor dem Ton des Bildes, `targetFrames` die Reserve (Abschnitte 3 und 6).
- Touch-Overlay: ausblenden erst nach dem ersten Tastendruck eines Controllers (Abschnitt 7).
- Messwerte: Ein Intervall ohne Bilder, etwa eine zweite Pause, behält die Bildrate. Vorher zeigte das Overlay nach dem Hintergrund bis zur nächsten Messung 0 Bilder/s.
- Der UI-Test „Spiel läuft“ läuft ohne Überspringen; die CI lädt die Metal-Toolchain, wenn sie fehlt.

**Nachbesserungen nach der Prüfung**

Die Prüfung von `m1/gba` fand keine Fehler, aber acht kleinere Befunde. Sieben davon sind behoben, einer wartet auf das Gerät:

- Ton: Nach dem Auffüllen blendet die Render-Funktion über 64 Frames ein (Abschnitt 6). Vorher sprang das Signal beim Start, beim Fortsetzen und nach einem Aussetzer von Stille auf seinen Wert, was knacken kann.
- Hintergrund: Die Hintergrundaufgabe beginnt vor der Pause und endet nach dem Sichern und dem Anhalten des Tons (Abschnitt 10). Vorher lief die Pause mit ihrer Sicherung ungeschützt, wenn `.inactive` fehlte.
- Debug-Overlay: Seine Zeilen brechen vor der Pausentaste um, auf dem Außendisplay lief der Text sonst durch das Pausensymbol.
- Import: Lesen über `NSFileCoordinator` und zusätzlich der Typ, den das System `.gba` zuordnet (Abschnitt 9).
- Touch: fester UI-Test über den neuen Tastenzähler im Overlay (`InputState.pressCount`, `lastPressedButtons`). Der Testmuster-Test schlägt fehl, statt zu überspringen, wenn sich das Bildschirmfoto nicht lesen lässt. Den Import über die Dateiauswahl prüft weiterhin kein fester Test: Die Auswahl folgt Sprache und Layout des Simulators, ein solcher Test wäre brüchig.
- Doku: Die Ursache der niedrigen Anzeigerate im Simulator ist eine offene Frage, keine Erklärung (Zeile „Anzeige“ unten).
- Offen bis zum Gerätetest: Sicherungen ohne Mindestabstand. Ändert ein Spiel seinen Spielstand laufend, schreibt die App etwa jede Sekunde 32 KiB mit `fsync`. selftest.gba tut das mit Absicht (Herzschlag). Was das auf dem Duo an Strom und Flash kostet, wird dort gemessen; bei Bedarf kommt ein Mindestabstand von 5 bis 10 s für periodische Sicherungen dazu, das sofortige Sichern bei Pause, Hintergrund und Ende bleibt.

**Belege**

| Prüfung | Ergebnis |
| --- | --- |
| Builds | Store und JIT für den Simulator, Store für `generic/platform=iOS` mit `CODE_SIGNING_ALLOWED=NO`, auch in einem frischen Build-Ordner: ohne Warnung im eigenen Code; die einzige Warnzeile stammt von `appintentsmetadataprocessor` (`docs/wissen/bauen-und-ci.md`) |
| Tests | Store 136 grün (ArcfoldTests 42, LibretroKitTests 54, RendererTests 34, ArcfoldUITests 6, keiner übersprungen), JIT 130 grün; Stand nach den Nachbesserungen auf einem frischen Gerät „Arcfold M1 Nachbesserung“, vorher 132 und 127 |
| Bildrate, zehn Minuten `selftest.gba` | Bildzähler des Programms: 36 370 Bilder in 608,85 s, also 59,735 Bilder/s (Soll 59,7275, Unsicherheit etwa ±0,05). Messzeilen alle 10 s: Mittel 59,72, 59,59 bis 59,89; `trim` −0,08 bis +0,03 %; 0 Neusynchronisationen |
| Ton im selben Zeitraum | 0 Aussetzer, 0 verworfene Frames, einmal aufgefüllt; Füllstand 31 bis 57 ms bei 35 ms Reserve, IO-Puffer 2,7 ms bei 48 kHz |
| Wärme | `thermalState` durchgehend `nominal`, Stromsparmodus aus; im Simulator ohne Aussagekraft |
| Anzeige | Display-Link 47 bis 54 Hz, deshalb rund 25 % übersprungene Bilder; 0 späte Auswahlen, 0 „GPU belegt“, 11 überschriebene Bilder beim Start. Die Ursache ist offen: Das Testmuster lief im selben Simulator ohne Fenster mit 60 Hz, der Rückgang kommt also erst mit dem Spiel (ein Present pro Bild, Kern, Ton oder Overlay), nicht schon durch das fehlende Fenster. Auf dem Duo messen; bleibt die Anzeige dort unter der Bildrate, `preferredFrameLatency` 2 statt 1 und die Zahl der Drawables prüfen |
| Späte Bilder | rund 58 % mehr als 2 ms nach der Frist; `mach_wait_until` wacht im Simulator spät auf (`docs/wissen/libretrokit.md`) |
| Hintergrund und zurück | 10 s Einstellungen im Vordergrund: Das Spiel pausierte (in 26,5 s Uhrzeit liefen 16,2 s Emulation), danach 59,7 Bilder/s, 0 Aussetzer, 0 Neusynchronisationen, ein weiteres Auffüllen |
| Speicherstand über einen Neustart | `battery.sav` vor `simctl terminate`: 32 768 Byte, „ARCF“, Boot-Zähler 1. Nach dem Neustart zeigt das Spiel Boot-Zähler 2, die Datei beginnt mit „ARCF“ und 0x02, `battery.sav.bak` hält die vorige Fassung |
| Touch | Halten von A setzt im Spiel Bit 0 der Tastenzeile, Gleiten von A nach B wechselt auf Bit 1, Loslassen löscht beide; vorübergehender UI-Test mit Bildschirmfotos, nur Einzelberührung. Seit der Nachbesserung prüft der feste UI-Test `testTouchButtonsReachTheSession` denselben Weg bis in die Sitzung über den Tastenzähler im Overlay |
| Import über `.fileImporter` | Dateiauswahl, Durchsuchen, „Auf meinem iPhone“, `selftest.gba`, Öffnen: Das Spiel steht in der Bibliothek (vorübergehender UI-Test) |
| Lizenzen | UI-Test: fünf Einträge (Arcfold GPL-3.0, mGBA 0.10.5 MPL-2.0 mit Quelltext-Hinweis, blip_buf 1.1.0 LGPL-2.1-or-later, inih BSD-3-Clause, libretro.h MIT) mit ihren Texten |

Ein erster Lauf derselben Art vor der Korrektur der Messwerte ergab 59,728 Bilder/s, ebenfalls ohne Aussetzer und Neusynchronisation.

Bildschirmfotos: `0005/m1-selftest-simulator.png` (laufendes Spiel mit Debug-Overlay und Touch-Tasten, zugeklappt, Faktor 4) und `0005/m1-lizenzen.png`.

**Offen, braucht das Duo:** 59,73 ± 0,05 Bilder/s, Wärme, Tonlatenz, 60 oder 120 Hz, Mehrfachberührung, echter Controller und Tastatur, ein Homebrew mit DirectSound-Ton (160p Test Suite), der Import aus der Dateien-App auf dem Gerät, auch aus iCloud Drive und mit einem zweiten installierten Emulator, die Anzeigerate mit den übersprungenen Bildern, Strom und Flash bei Sicherungen im Sekundentakt.

## Entscheidungen bei der Annahme

Angenommen am 7. November 2026 mit der Abnahme von M1.

- **Takt folgt der Tonuhr** per Trimmung um höchstens ±0,5 % statt Resampling (Abschnitt 3). In der Abnahme blieb `trim` zwischen −0,08 und +0,03 %, ohne Aussetzer. Die Tonhöhe stimmt dabei genau, weil der Ton mit der Abtastrate des Kerns läuft; nur die Bildrate weicht um den Gangunterschied der Uhren ab.
- **Controller nach Position:** Ost = A, Süd = B, West = Y, Nord = X, wie das RetroPad von libretro und RetroArch. Auf einem Xbox-Controller liegt GBA-A damit auf der Taste „B“, so wie die Tasten am GBA liegen. Eine eigene Belegung kommt mit den Einstellungen in M4.
- **Bildrate der Anzeige:** bevorzugt 120 Hz, weil ein ausgelassenes oder doppeltes Bild dann 8,3 statt 16,7 ms dauert. Zeigt der Gerätetest bei 120 Hz deutlich mehr Wärme als bei 60 Hz (`thermalState` nach 30 Minuten über „nominal“, bei 60 Hz nicht), gilt 60 Hz.
- **Ton im Lautlos-Modus:** `.ambient`, also stumm mit dem Lautlos-Schalter und gemischt mit anderer Wiedergabe, wie Apple es für Spiele vorsieht. Ein Schalter für `.playback` kommt mit den Einstellungen in M4.
- **Touch-Tasten** verschwinden erst nach dem ersten Tastendruck eines Controllers (Abschnitt 7). Auf dem Gerät nimmt so auch ein gekoppelter, aber beiseitegelegter Controller die Touch-Tasten nicht weg.
- **Außendisplay:** Das Bild bleibt im sicheren Bereich (Faktor 4), die Systemspalte bleibt frei. M2 bewertet das mit den Falz-Layouts neu.
- **Sicherungen ohne Mindestabstand:** Geschrieben wird nur, was sich geändert hat und eine Prüfung lang gleich blieb. Spiele schreiben ihren Spielstand selten, im Sekundentakt schreibt nur selftest.gba mit Absicht. Selbst dann wären es rund 115 MB pro Stunde, ein kleiner Bruchteil dessen, was der Flash-Speicher über seine Lebensdauer verträgt. Ein Mindestabstand kommt nur, wenn ein echtes Spiel laufend schreibt und der Gerätetest das als Stromverbrauch zeigt.
- **Späte Bilder:** Die Grenze bleibt 2 ms. Zählt der Gerätetest mehr als 10 % späte Bilder und ist das als Ruckeln oder im Ton spürbar, bekommt der Emulations-Thread eine Echtzeit-Policy (`THREAD_TIME_CONSTRAINT_POLICY`).
- **Testprogramme:** selftest.gba bleibt die einzige automatische Fixture. Die 160p Test Suite (GPL-2.0-or-later) importiert Fatih für den Gerätetest selbst, sie kommt nicht ins Repo.
- **Lizenz:** App und eigene Testprogramme stehen unter GPL-3.0-or-later (Plan, Abschnitt 12).

Offen bleibt der Gerätetest auf dem Duo, Anleitung in `docs/wissen/geraetetest.md`.
