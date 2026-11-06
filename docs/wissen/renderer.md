---
name: renderer
description: Aufbau des Renderer-Pakets in M1 (Bildpostfach, Metal-Ansicht, Tonring in C, Audioausgabe), Belege und Stolperfallen
---

# Renderer

Stand 7. November 2026 (M1, Spur A). Paket unter `Packages/Renderer`, swift-tools-version 6.4, iOS 27, Swift 6. Die Entscheidungen dahinter stehen in ADR 0005, Abschnitte 5 und 6.

## Aufbau

- **`FrameMailbox`** (`VideoSink`): vier Plätze zu `maxWidth × maxHeight × Bytes pro Pixel`, einmal angelegt.
  - Zustand je Platz in einem `Atomic<UInt64>`: `Generation << 2 | Phase` mit den Phasen frei, schreiben, bereit, lesen. Die Generation zählt veröffentlichte Bilder. Ein Compare-Exchange auf einen bereiten Platz scheitert deshalb, wenn der Erzeuger ihn inzwischen überschrieben hat.
  - `submit` kopiert zeilenweise ohne den Rand des Kern-Pitch. Ist kein Platz frei, überschreibt es das älteste ungezeigte Bild und zählt es.
  - Konsument (Paketzugriff): `takeFrame(presentationTime:latency:)` wählt das neueste Bild mit `nominalTime + L ≤ Zeitpunkt` und gibt ältere bereite Plätze frei (übersprungen). „Spät“ heißt: Nichts Neueres ist bereit, obwohl nach der Bildperiode schon das nächste Bild fällig war. `release(_:)` gibt den Platz zurück.
- **`GameScreen`**: `UIViewRepresentable` über `GameScreenView`.
  - `CAMetalLayer` mit `bgra8Unorm` und sRGB-Farbraum, Größe in nativen Pixeln (`nativeScale`).
  - `CAMetalDisplayLink` am Main-Run-Loop, 60 bis 120 Hz, bevorzugt 120, `preferredFrameLatency` 1.
  - `L` ist der geglättete Vorlauf (`targetPresentationTimestamp − CACurrentMediaTime()`) plus 8 ms, umgerechnet in `mach_absolute_time`-Einheiten.
  - Drei Upload-Texturen (`.shared`, `replace(region:)`). Jede hat einen Zähler „in Arbeit“, den der Completion-Handler zurücksetzt. Ist die nächste Textur belegt, zählt `gpuBusy`, und das vorige Bild bleibt stehen.
  - Kein neues Bild fällig: kein Present, `framesRepeated` zählt.
  - Pausiert hält der Link an, das letzte Bild bleibt stehen. Nach einer Größenänderung läuft genau ein Update, das es neu zeichnet.
  - `GCEventInteraction` mit `.gamepad` an der View.
- **`PictureRenderer`** (Paketzugriff): Pipelines für RGB565 (`r16Uint`, Dekodierung im Shader mit `read()`) und XRGB8888 (`bgra8Unorm`). Der Viewport ist der sichtbare Teil des skalierten Bildes. `GameScreen` und die Offscreen-Tests benutzen denselben Code.
- **`ScreenPlacement.fitting`**: größter ganzzahliger Faktor, zentriert, ein ungerader Rest geht nach rechts bzw. unten. Ist die Quelle größer als das Ziel, gilt Faktor 1 mit negativem Ursprung.
- **`CRendererAudio`** (C und Objective-C mit ARC):
  - SPSC-Ring mit C11-Atomics, ein Stereo-Frame als `uint32_t`; Erzeuger-, Verbraucher- und Steuerfelder auf getrennten Cache-Zeilen.
  - `ARCAudioRingRender` mit den Zuständen Auffüllen, Spielen und Ausgesetzt. Bei Unterlauf eine Rampe über 64 Frames vom letzten Wert, auch über Aufrufgrenzen hinweg; dann Auffüllen. Eine Flush-Anforderung verwirft beim nächsten Aufruf alles Gepufferte.
  - `ARCAudioRingWrite` (Erzeuger) ist ebenfalls `CA_REALTIME_API` und damit compilergeprüft. Die Zeit (`mach_absolute_time()`) kommt als Parameter aus Swift.
  - `ARCAudioMakeSourceNode`: `initWithFormat:realtimeSafeRenderBlock:`, Blockformat Int16 verschachtelt mit der Kern-Rate, die Render-Funktion kopiert nur.
- **`AudioRing`** (`AudioSink`): Swift-Hülle. `isConsuming` heißt: Zustand Spielen, und der Render-Block lief in den letzten 100 ms. Gemessen wird das am Zähler der Render-Aufrufe aus Sicht des Erzeugers, nicht an `mHostTime`.
- **`AudioOutput`** (`@MainActor`):
  - `.ambient`, `setPreferredIOBufferDuration(0.005)`, asynchrones `activate(options:)`.
  - Engine mit `connectNode(_:to:format:)` und `standardFormatWithSampleRate: <Hardware-Rate>, channels: 2`; Sollfüllstand `max(35 ms, IO-Puffer + 20 ms)`.
  - Beobachtet `didBecomeInactive` und `resumptionRecommendation` als typisierte `MainActorMessage`s, dazu `routeChangeNotification`, `AVAudioEngineConfigurationChange` (neu verbinden und starten) und `mediaServicesWereResetNotification` (alles neu bauen).
  - `resume()` verwirft alten Ton und startet eine vom System angehaltene Engine im Hintergrund neu, danach folgt `.restarted`. `stop()` hält die Engine an und deaktiviert die Sitzung mit `deactivate(options: .notifyOthersOnDeactivation)`.

## Belege

Simulator „iPhone Duo“ mit iOS 27.1, Xcode 27.2, 7. November 2026:

- `.metal` im Paket landet als `default.metallib` in `Arcfold.app/Renderer_Renderer.bundle` und lädt über `makeDefaultLibrary(bundle: .module)`.
- `r16Uint` mit `.shared` und `replace(region:)` funktioniert im Simulator. Offscreen-Render (`PictureRenderTests`): alle 65 536 RGB565-Werte und XRGB8888 pixelgenau gegen die CPU-Rechnung; die Duo-Größen 1878 × 2670, 2670 × 1878 und 1398 × 2034 mit Faktor 7, 11 und 5 und den Ursprüngen aus ADR 0005, schwarzer Rand.
- Testmuster über Postfach, Display-Link und Shader auf dem Bildschirm: UI-Test `testTheGameScreenShowsTheTestPattern` prüft die acht Farbbalken im Bildschirmfoto.
- `AudioOutput` startet im Simulator, der Render-Block läuft, `isConsuming` wird wahr; Aussetzen und Fortsetzen zählen keine Aussetzer.
- Gegenprobe der Compilerprüfung: `malloc` und `free` in `ARCAudioRingRender`, `pthread_mutex_lock` in `ARCAudioRingWrite` und eine Objective-C-Nachricht im Render-Block brechen den Build mit `-Wfunction-effects` als Fehler ab, etwa „function with 'nonblocking' attribute must not call non-'nonblocking' function 'malloc'“ und „block with 'nonblocking' attribute must not access ObjC methods or properties“. Danach entfernt.
- Stresstests mit zwei Threads: Postfach ohne zerrissene oder vertauschte Bilder, auch während der Erzeuger überschreibt; Ring ohne Sprung, Rampen werden an ihrer Formel erkannt.
- Maschinencode des Release-Builds für das Gerät (`otool -tV`, alle Sprünge mit Rückkehr): `FrameMailbox.submit` ruft nur zweimal `memmove` (Zeilenkopie) und die Platzsuche, die selbst nichts aufruft; `AudioRing.write` ruft `mach_absolute_time`, `ARCAudioRingWrite` und den Stub der Stack-Prüfung; `ARCAudioRingWrite` nur `memcpy`, `ARCAudioRingRender` nur `memcpy` und `bzero`. Kein `malloc`, kein Lock, kein `swift_retain` oder `swift_release`, keine Objective-C-Nachricht.

## Stolperfallen

- **Metal-Toolchain fehlt.** Xcode 27 liefert den Metal-Compiler als eigene Komponente; ohne sie bricht der Build mit „cannot execute tool 'metal' due to missing Metal Toolchain“ ab. **Warum:** Der Shader wird beim Bauen übersetzt, nicht zur Laufzeit. **Anwenden:** `xcodebuild -downloadComponent metaltoolchain` (838,9 MB, ohne sudo, Version 27B47), entfernen mit `xcodebuild -deleteComponent metaltoolchain`; die CI braucht denselben Schritt, falls ihr Image die Komponente nicht hat.
- **`any MTLTexture` ist nicht `Sendable`.** **Warum:** Der Completion-Handler läuft auf einem Thread von Metal, Swift 6 verbietet dort das Fangen der Textur. **Anwenden:** Der Zähler „in Arbeit“ steckt in einer eigenen `Sendable`-Klasse, die Textur bleibt auf dem Main Thread.
- **Closures für Objective-C-Handler.** **Warum:** Eine Closure aus einem `@MainActor`-Kontext gilt als MainActor-isoliert; ruft eine API sie auf einer anderen Queue, bricht die dynamische Isolationsprüfung von Swift 6 zur Laufzeit ab. **Anwenden:** solche Closures ausdrücklich `@Sendable` schreiben, etwa bei `deactivate(options:completionHandler:)`, oder in einem `nonisolated` Typ bilden.
- **Statische Logger in `@MainActor`-Klassen.** **Warum:** Sie sind selbst MainActor-isoliert, ein `@Sendable`-Handler darf sie nicht benutzen. **Anwenden:** `nonisolated static let` für den `Logger`.
- **Audio-Tests gleichzeitig.** **Warum:** Alle `AudioOutput` teilen die eine Audiositzung; `stop()` des einen deaktiviert sie für den anderen. **Anwenden:** Die Suite `AudioOutputTests` läuft mit `.serialized`.
- **`-Wfunction-effects` ist sonst aus**, auch mit `-Wall`. **Warum:** Ohne die Warnung prüft der Compiler `CA_REALTIME_API` nicht, und eine Allokation im Render-Block fiele nicht auf. **Anwenden:** Das Pragma steht in `CRendererAudio.m` vor allen Includes; neue Echtzeitfunktionen bekommen `CA_REALTIME_API`, und eine Gegenprobe mit `malloc` muss den Build brechen.
