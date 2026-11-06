---
name: app
description: Aufbau der App in M1 (Bibliothek, Import, Spielansicht, Lebenszyklus, Eingabe, Debug-Overlay, Lizenzen, Debug-Start), Belege, Offenes und Stolperfallen
---

# App

Stand 7. November 2026 (M1, Spur A). Target `Arcfold` mit `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`; was abseits des Main Actors läuft, ist ausdrücklich `nonisolated` oder `@concurrent`. Die Entscheidungen dahinter stehen in ADR 0005, Abschnitte 7 und 9.

## Aufbau

```
App/Sources/
  ArcfoldApp.swift      WindowGroup mit LibraryView, eine GameLibrary für alle Fenster
  Library/              GameSystem, Game und LibraryLocation, GameImporter, GameLibrary, LibraryView
  Play/                 PlaySession, GameView, TouchLayout, TouchControls, ControllerInput, DebugOverlay
  Info/                 LicenseCatalog, LicensesView, CoreListView, CoreCatalog
  Debug/                DebugLaunch, PreviewContent, TestPatternView (nur im Debug-Build)
```

- **Ablage** in Application Support: `Games/<SHA-256>/game.gba`, `game.json`, `battery.sav`, dazu `System/`. Ein Ordner zählt erst als Spiel, wenn `game.json` und die Kopie existieren und die ID zum Ordnernamen passt. Das Dateisystem ist die einzige Quelle.
- **`GameSystem.gba`**: Kern `mgba_libretro`, Endung `gba`, Typ `com.faentiver.arcfold.gba-rom` (in `App/Info.plist`), Kernoptionen `["mgba_use_bios": "OFF"]`.
- **Import** (`GameImporter.importGame`, `@concurrent`): Security-Scope öffnen, Größe 192 Byte bis 32 MiB, Byte 3 = 0xEA und Byte 0xB2 = 0x96, SHA-256 mit CryptoKit, Kopie und dann `game.json` mit `.atomic`. Ein zweiter Import derselben Datei ändert nichts und meldet `wasAlreadyInLibrary`. Fehler mit Dateinamen als `ImportError`, die Bibliothek zeigt sie gesammelt in einem Alert.
- **`PlaySession`** (`@Observable`) besitzt `EmulationSession`, `FrameMailbox`, `AudioRing`, `AudioOutput`, `PresentationStats` und `ControllerInput`.
  - Alle Übergänge laufen über eine Warteschlange von Lebenszyklus-Schritten (jeder Schritt wartet auf den vorigen), damit inaktiv, Hintergrund, aktiv in schneller Folge sich nicht überholen.
  - Start: `load()`, `connect`, `AudioOutput.start()`, dann `resume()`. Startet der Ton nicht, läuft das Spiel ohne ihn, mit Hinweis.
  - Pausengründe: von Hand (Menü, oder abgezogene Kopfhörer), Szene (`.inactive`, `.background`), Unterbrechung der Audiositzung. Beim Pausieren erst `AudioOutput.suspend()`, dann `pause()`; beim Fortsetzen erst `AudioOutput.resume()`, dann `resume()`.
  - Hintergrund: zusätzlich `saveBatteryNow()` innerhalb von `beginBackgroundTask` und `AudioOutput.stop()`; zurück in `.active` erst `AudioOutput.start()`.
  - `resumptionRecommended(false)` macht aus der Unterbrechung eine Pause von Hand.
  - Ein Spiel zur Zeit: Läuft schon eine Sitzung im Prozess, zeigt eine zweite Spielansicht einen Hinweis statt eines Spiels. `.anotherSessionActive` aus `load()` ergibt denselben Hinweis.
  - Alle 10 s eine Zeile über `Logger(subsystem: "com.faentiver.arcfold", category: "stats")` mit denselben Werten wie das Overlay, solange das Spiel läuft.
- **`GameView`**: hochkant Bild oben (volle Breite, Seitenverhältnis des Kerns) und Tasten darunter, quer Bild mittig und Tasten seitlich darüber. `.persistentSystemOverlays(.hidden)`, `.statusBarHidden()`, `.defersSystemGestures(on: .all)`, `isIdleTimerDisabled` während des Spiels. Pausentaste oben rechts öffnet ein Menü mit Fortsetzen, Debug-Overlay ein/aus und Beenden.
- **Touch**: `TouchLayout` ist ein reiner Wert und rechnet aus Punkten die Maske (Steuerkreuz mit acht Sektoren zu 45°, Totzone 30 % des Radius, Reichweite 140 %; Tasten mit 25 % Zugabe, bei Überlappung die nächste Mitte). `TouchControls` zeichnet und meldet die Maske aus einer `SpatialEventGesture`; Beschriftungen A, B, L, R, Start, Select als Text.
- **Controller**: `ControllerInput` beobachtet Verbindungen auf dem Main Actor; `InputRouter` (`nonisolated`) hängt `GCControllerLiveInput` an eine eigene serielle Queue (`inputStateQueueDepth = 16`, `nextInputState()`-Schleife) und vereint die Masken aller Controller. Belegung nach Position: Ost A, Süd B, West Y, Nord X, Schultern und Trigger L und R, Steuerkreuz und linker Stick ab halbem Weg, Menü Start, Optionen Select. Die Tastatur (`GCKeyboard`) folgt RetroArchs Standard für Spieler 1 (`config.def.keybinds.h`, Commit 6ebf66b vom 30. Oktober 2026): Pfeile, X = A, Z = B, S = X, A = Y, Q = L, W = R, Return = Start, rechte Umschalttaste = Select. Mit verbundenem Controller verschwinden die Touch-Tasten.
- **Debug-Overlay**: `TimelineView(.periodic(from: .now, by: 0.25))` liest nur Schnappschüsse (`DebugReadings`): Emulation, Anzeige, Postfach, Ton, `thermalState`, Stromsparmodus. Technischer Text, nicht lokalisiert. Im Debug-Build an, im Release-Build aus.
- **Lizenzen**: `LicenseCatalog` mit Arcfold (GPL-3.0), mGBA 0.10.5 (MPL-2.0, Hinweis auf den Quelltext github.com/mgba-emu/mgba, Tag 0.10.5), blip_buf 1.1.0 (LGPL-2.1-or-later), inih (BSD-3-Clause) und `libretro.h` (MIT, nur der Kopfkommentar). Die Texte kommen aus `Arcfold.app/Licenses/<Komponente>/`, die Ansicht teilt sie in Absätze für ein faules Layout.
- **Info-Menü** links oben in der Bibliothek: „Licenses“ und „Cores“ (die frühere `CoreListView`).
- **Debug-Start** (nur `#if DEBUG`, einmal pro Prozess): `-ArcfoldAutorun <Pfad>` importiert wie der Datei-Import und startet, `-ArcfoldImport <Pfad>` importiert nur, `-ArcfoldTestPattern YES` zeigt die Spielansicht mit dem Testmuster aus `PreviewContent` ohne Kern.
- **Previews** erzeugen keine `EmulationSession` und kein `InputState`: Testmuster im `FrameMailbox`, feste `SessionStats.Snapshot`, `SystemInfo(...)`, `GameLibrary(previewing:)`.

## Belege

Simulator „iPhone Duo“ mit iOS 27.1, 7. November 2026:

- `ArcfoldTests/App`: Import im temporären Ordner (gültig, Duplikat, zu klein, falscher Kopf an Byte 3 und 0xB2, Obergrenze), `GameLibrary.reload` mit unvollständigen Ordnern, Touch-Maske, Tastaturbelegung und Stick, Lizenzkatalog gegen das App-Bundle, Version von mGBA gegen den eingebetteten Kern.
- UI-Tests: Start mit der Bibliothek, „Licenses“ mit fünf Einträgen und ihren Texten, Debug-Import von `selftest.gba` aus dem UI-Test-Bundle, Testmuster auf dem Bildschirm (Lage, ganzzahliger Faktor, acht Farbbalken im Bildschirmfoto). Der Test „Spiel läuft, Overlay zeigt eine Bildrate über 0“ ist geschrieben und übersprungen, bis Spur K die Sitzung liefert.

## Offen

- Alles, was eine laufende `EmulationSession` braucht (Spur K): Spielansicht mit Kern, Debug-Overlay mit echten Werten, Lebenszyklus mit Batteriespeicher, Tastatur und Controller im Spiel.
- Mehrfachberührung mit `SpatialEventGesture` und `GCControllerLiveInput` mit echtem Controller sind noch nicht auf dem Gerät geprüft; im Simulator gehen zwei Finger nur mit der Wahltaste.
- Bildrate, Wärme und Tonlatenz zählen nur auf dem Duo.

## Stolperfallen

- **Sicherer Bereich des Außendisplays.** Zugeklappt (466 × 678 pt) legt iOS 27.1 im Duo-Simulator Statusleiste und Toolbar-Tasten in eine Spalte am rechten Rand; der sichere Bereich endet 84 pt davor, Inhalte sind 382 pt breit. Mit `.statusBarHidden()` bleibt der Rand. **Warum:** Das Bild wird in diesem Bereich ganzzahlig skaliert, auf dem Außendisplay also mit Faktor 4 statt 5 wie für das ganze Panel (ADR 0005). **Anwenden:** Rechnungen und UI-Tests nehmen den Rahmen der Ansicht, nicht die Bildschirmgröße; ob die Spielansicht die Spalte überdecken darf, klärt M2.
- **Zurück-Taste unter iOS 27.** **Warum:** Sie steht nicht mehr in der `NavigationBar`, sondern in einer eigenen Toolbar; `app.navigationBars.buttons` findet sie nicht. **Anwenden:** In UI-Tests `app.buttons["BackButton"]`.
- **`UIViewRepresentable` und Bedienungshilfen.** **Warum:** Ohne eigenes Element taucht die Metal-Ansicht im Baum der Bedienungshilfen nicht auf, UI-Tests finden sie nicht. **Anwenden:** `.accessibilityElement(children: .ignore)` mit Label und Kennung (`game-screen`, `test-pattern-screen`).
- **Datum in `game.json`.** **Warum:** ISO 8601 speichert keine Sekundenbruchteile; ein ungerundetes `Date` ist nach dem Einlesen ein anderes, und das gelesene `Game` gleicht dem importierten nicht. **Anwenden:** Das Importdatum wird vor dem Schreiben auf ganze Sekunden gerundet.
- **Benachrichtigungen von GameController.** **Warum:** Für `GCController` gibt es unter iOS keine typisierten Nachrichten, und ein Objekt aus der `Notification` in `MainActor.assumeIsolated` zu reichen, meldet Swift 6 als Datenrennen. **Anwenden:** Die Benachrichtigung löst nur einen Abgleich mit `GCController.controllers()` aus; für `GCKeyboard` gibt es `didConnect` und `didDisconnect` als `MainActorMessage`.
- **Handler für fremde Queues.** **Warum:** Eine Closure aus einem MainActor-Kontext gilt als MainActor-isoliert und bricht zur Laufzeit ab, wenn GameController sie auf seiner Queue ruft. **Anwenden:** Die Handler entstehen in `InputRouter`, einer `nonisolated` Klasse.
- **`throw XCTSkip` mit nachfolgendem Code.** **Warum:** Der Compiler warnt „will never be executed“, und das Projekt duldet keine Warnungen. **Anwenden:** `try XCTSkipIf(true, "Requires the emulation session from track K")`; die Integration löscht die Zeile.
- **Bildschirmfotos vom Duo-Simulator.** **Warum:** Das Gerät hat zwei Displays; `xcrun simctl io <UDID> screenshot` bricht ohne Auswahl mit „Cannot choose between 2 displays“ ab. Gemeldet werden `--display=1` (außen, 1398 × 2034) und `--display=3` (innen, 2007 × 2853, also nicht die 1878 × 2670 aus dem Plan, Abschnitt 3; Stand iOS 27.1 im Simulator). **Anwenden:** `--display=1` bzw. `--display=3` angeben; die Pixelmaße des Innendisplays vor den Falz-Layouts in M2 auf dem Gerät prüfen.
- **Debug-Start im Simulator.** **Warum:** Dort darf die App Dateien aus dem Bundle der UI-Tests über ihren Pfad lesen, auf dem Gerät nicht. **Anwenden:** `-ArcfoldAutorun` und `-ArcfoldImport` nur im Simulator und in UI-Tests benutzen; auf dem Gerät führt der Weg über die Dateien-App.
