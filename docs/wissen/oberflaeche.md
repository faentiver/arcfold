---
name: oberflaeche
description: Die Liquid-Glass-Oberfläche (ADR 0007) auf der Architektur von M2: Regeln, Bausteine, Tokens, Messwerte aus der Bildschirmfoto-Tour auch in den echten Posen, Abweichungen vom Entwurf, was beim Auflegen auf M2 übernommen, geändert und entfallen ist, und Stolperfallen
---

# Oberfläche mit Liquid Glass

Stand 10. November 2026, Branch `m4/liquid-glass` auf `main`, auf der Architektur von M2 (ADR 0006, seit dem 10. November 2026 abgenommen und auf `main`); die Oberfläche kommt als eigener Pull Request gegen `main` und wartet auf ihre Abnahme durch Fatih. Die Entscheidung steht in ADR 0007, die Zusammenführung mit M2 in deren Abschnitt „Zusammenführung mit M2“ („zusammengeführt“ und „Merge“ heißen hier: Glas sitzt auf der Architektur von M2; der Branch hat keinen Merge-Commit). Die Bausteine liegen in `App/Sources/Design/`, das Pausenmenü in `App/Sources/Play/PauseMenu.swift`, die Spielansicht von M2 mit Bühne, Tasten und Eingabefläche in `App/Sources/Play/` (`GameView`, `GameStage`, `TouchControls`).

## Zwei Gläser

- **Systemglas** gilt überall außerhalb des laufenden Spiels: Toolbar, Menüs, Suche, Zurück, Alerts, Dateiauswahl und das Pausen-Sheet. Eigener Code setzt dort kein `glassEffect`.
- **Spielglas** liegt über und neben dem Spielbild: `Glass.clear` mit einer Dimmplatte darunter, für Touch-Tasten, Pause-Knopf, Hinweis und Ton-Chip. Laut SDK verlangt `.clear` „a dimming layer or other treatment beneath the glass“; `.regular` passt seinen Inhalt der Helligkeit darunter an, und das Spielbild soll nie bestimmen, wie eine Taste aussieht.

## Regeln

- **R1 · Inhalt trägt kein Glas.** Spielbild, Kacheln, Listen, Lizenztexte und Debug-Overlay. **Warum:** Glas ist eine Ebene über dem Inhalt; das Debug-Overlay würde sonst die Werte verfälschen, die es misst. **Anwenden:** Kachelkunst und Debug-Karte sind flache Formen.
- **R2 · Systemglas kommt vom System.** **Warum:** native first, Fatih erkennt Eigenbau sofort. **Anwenden:** `ToolbarItem`, `Menu`, `.searchable`, `.sheet`, Knopfstile; kein eigenes `glassEffect` außerhalb des Spiels.
- **R3 · Spielglas immer mit Platte und Form.** **Warum:** Ohne Platte ist weiße Schrift über hellen Spielen kaum lesbar (gemessen). Ohne Form ragen die Ecken des Rechtecks aus dem Kreis. **Anwenden:** `.gameGlass(in:isPressed:isSmallLabel:backdrop:)`, beim Pause-Knopf mit `isInteractive: true`. Die Platte folgt dem, was darunter liegt: über einem Bildschirm die Bildplatte, sonst die Deckplatte (`GlassBackdrop.under`).
- **R4 · Kein Glas auf Glas.** **Warum:** Das Sheet ist schon Glas. **Anwenden:** im Sheet `.borderedProminent` und `.bordered`; mehrere eigene Glasformen immer in einem `GlassEffectContainer`.
- **R5 · Sichtbarer Druck ist die gemeldete Maske.** **Warum:** Eine Glasreaktion oder Feder hinkt dem Spiel hinterher und hebt den Compositor bei jedem Druck auf 120 Hz. **Anwenden:** kein `.interactive()` auf Tastenglas, keine Animation beim Drücken und Loslassen.
- **R6 · Nichts Eigenes in die Systemspalte, nichts Trefferfähiges über den Tasten.** **Warum:** M1 hatte zwei Fehler: quer lag der Pause-Knopf auf R, hochkant nahm der Hinweis Select und Start die Berührungen weg. **Anwenden:** jede Überlagerung im Spiel mit `.allowsHitTesting(false)`, außer dem Pause-Knopf; Lage aus `OverlayPlacement`, einer reinen Funktion von `GameLayout`. Kein Glas über dem Touchscreen des DS und der Division-Region.
- **R7 · Glas ist Komfort.** **Warum:** Ab M3 (PSP) zählt jede GPU-Arbeit. **Anwenden:** `Glass.identity` statt `.clear` für den flachen Modus, derselbe View-Baum.
- **R8 · Eigenbau nur, wo das System nichts hat:** Touch-Tasten, Pause-Knopf (der Glas-Knopfstil passt nicht in die Menüzeile, Abweichung 22), Hinweis-Kapsel, Kachelkunst, Deck-Schimmer.
- **R9 · Harte Regeln:** keine Logos, keine geschützten Tastensymbole (nur Buchstaben und `arrowtriangle.*`), keine Marken in Name oder Icon, keine Cover, kein JIT-Pfad, GPL-3.0-or-later, SPDX-Kopf in neuen Skripten.

## Bausteine

| Datei | Inhalt |
| --- | --- |
| `Design/Theme.swift` | `DisplayClass` (compact < 430, regular bis 799, wide ab 800 pt Breite des Containers), `Metrics`, `Motion`, `Color.gamePlate(_:)`, `EnvironmentValues.prefersFades` |
| `Design/GameStyle.swift` | `GameStyle` aus der SHA-256 der Datei: Byte 0 Farbpaar (zehn Paare aus Systemfarben, ohne Gelb), Byte 1 Muster, Byte 2 Ecke, Bytes 3–10 Seed; Monogramm; `pressedFill`; Umgebung `gameStyle` |
| `Design/GameArtwork.swift` | `MeshGradient` 3 × 3 mit Muster per `Canvas` und Monogramm; Varianten `.tile(corner:)`, `.thumbnail`, `.backdrop` |
| `Design/GameTile.swift` | `GameTile`, `TileButtonStyle` (0,96 bzw. Deckkraft bei Bewegung reduzieren), `GameGrid` für Bibliothek und Galerie, Kennung `game-<System>-<Name>` |
| `Design/LibraryArrangement.swift` | `LibrarySort` (`@AppStorage("LibrarySort")`), Sortieren und Suchen als reine Funktion |
| `Design/GameGlass.swift` | `ControlSurface`, `GlassBackdrop` (Bild oder Deck, `under(_:screens:)` je Taste), `gameGlass` (interaktiv nur für den Pause-Knopf), `GamePlate`, `resolvesControlSurface()` |
| `Design/GlassControls.swift` | `TouchControlsArt` (die Tasten eines `TouchLayout` aus den Zonen von `GameLayout`, Platte je Taste), `GlassKey` und `GlassPad` mit den Kennungen `touch-button-<Taste>` und `touch-pad`, `PadSector`, Previews für GBA und DS zugeklappt, im Tabletop und im Buch |
| `Design/ControlDeck.swift` | `ControlDeck(areas:)`, der Schimmer in der Spielfarbe, ein Verlauf über alle Flächen; `DeckLayout`: die Flächen hinter den Zonen, die keinen Bildschirm decken, seitlich und dann nach oben und unten gewachsen, bis ein Bildschirm, der Falz oder der Rand sie aufhält |
| `Design/StatusToast.swift` | `StatusToast` (Hinweis, VoiceOver sagt ihn an, wächst bei großer Schrift nach oben), `StatusChip` (Ton fehlt) |
| `Design/OverlayPlacement.swift` | Lage von Pause-Knopf (mit Ziel ≥ 44 pt), Debug-Overlay, Hinweis und Ton-Chip als reine Funktion von `GameLayout`, `FoldGeometry` und den Touch-Tasten, in Punkten des ganzen Views |
| `Design/LoadingBackdrop.swift` | Kachelkunst unscharf auf jedem Bildschirm, der Spinner auf dem ersten, solange der Kern lädt |
| `Play/GameStage.swift`, `Play/TouchControls.swift` (aus M2) | die Bühne: Bildschirme, Deck, `TouchControls` über `TouchControlsArt`, `TouchSurface` für alle Finger (für VoiceOver eine Fläche mit Direktberührung), Pause-Knopf |
| `Play/GameOverlays.swift` | Debug-Overlay, Ton-Chip, Hinweis und Fehler aus einfachen Werten in den Koordinaten von `GameStage`; `GameView` ruft sie einmal auf, die Galerie zeigt dieselben |
| `Play/PauseMenu.swift` | `PauseButton` (Spielglas-Kreis in der Größe seines Platzes, interaktiv, Ziel ≥ 44 pt, Quelle des Zooms ins Sheet) und `PauseMenu` (Sheet-Inhalt) |
| `Play/GameFailureView.swift` | `ContentUnavailableView` über der Kachelkunst, „Close“ als `.glassProminent` |
| `Debug/GlassGallery.swift` | Galerie-Seiten aus `GameLayout` in Geometrien des Duo-Simulators, für reproduzierbare Bildschirmfotos (nur Debug) |

## Tokens

| Token | compact | regular | wide |
| --- | --- | --- | --- |
| `margin` | 16 | 20 | 24 |
| `gridSpacing` waagerecht / senkrecht | 14 / 20 | 16 / 22 | 20 / 24 |
| `tileMinWidth` | 150 | 170 | 180 |
| `tileCorner` | 14 | 16 | 18 |
| `overlayInset` | 8 | 12 | 16 |
| `toastMaxWidth` | 320 | 400 | 460 |

Der Pause-Knopf hat seit dem Merge keine eigene Größe mehr: ein Kreis in der Größe seines Platzes, mit Touch-Tasten 36 pt (die Menüzeile von M2, eng auch kleiner), ohne sie 44 pt (`GameLayout.pauseButton`); er nimmt Berührungen immer auf mindestens 44 × 44 pt.

Dimmplatte `Color(white: 0.15)` mit dieser Deckkraft (nach der Messung, siehe unten):

| Zustand | große Beschriftung und Symbole | kleine Beschriftung (Kapsel ≤ 40 pt, Hinweise) |
| --- | --- | --- |
| Ruhe über dem Bild | 0,70 | 0,80 |
| Ruhe über dem Deck (hochkant) | 0,35 | 0,45 |
| Kontrast erhöhen | 0,80, Rand 1 pt als Inhalt des Glases: Weiß 0,90 über dem Bild, 0,35 über dem Deck | 0,90, Rand ebenso |
| Transparenz reduzieren | 0,85 | 0,90 |
| Rahmen anzeigen | wie Lage, Rand 1 pt Weiß 0,35 | ebenso |
| gedrückt | `pressedFill` mit 0,95 | `pressedFill` mit Schwarz 0,25 gemischt, 0,95 |
| flach | Weiß 0,15, gedrückt 0,45, Rand 1,5 pt Weiß 0,4 (M1) | ebenso |

Tastenschrift: SF Rounded halbfett (fett bei Fettschrift), Kreis `min(∅ × 0,38, 34)`, Kapsel `min(h × 0,42, 22)`. Pfeile des Steuerkreuzes in Ruhe Weiß 0,85, gedrückt Weiß 1,0 über einem Sektor in der Spielfarbe. Gedrückt mit „Ohne Farbe unterscheiden“: ein Ring 3 pt innen, 1,5 pt Weiß wie die Beschriftung, ebenfalls Inhalt des Glases.

Weitere Maße:

- **Deck-Schimmer:** Spielfarbe mit 0 (oben) → 0,30 (bei 8 % der Höhe) → 0,12 (45 %) → 0 (75 %), mit Kontrast erhöhen × 0,6; ein Verlauf über die Flächen aus `DeckLayout`, von deren oberer Kante bis zur unteren.
- **Ton-Chip:** in jeder Pose 6 pt über dem Hinweis, höchstens 320 pt breit, 40 pt hoch. In einem Bild, das für beide zu niedrig ist (unter 138 pt bei 8 pt Abstand, etwa der DS quer auf einem iPhone mit 128 pt), oben im Bild und der Hinweis darunter. Abgerundetes Rechteck mit 12,5 pt, einzeilig also eine Kapsel. Wie der Hinweis bis höchstens accessibility2.
- **Hinweis:** auf dem oberen oder einzigen Bildschirm, nie auf dem Touchscreen, 12 pt über dessen Unterkante, frei von jeder Taste samt Zugabe, von der Reichweite des Steuerkreuzes, vom Pause-Knopf und vom Falz, aktiv oder nicht. Er nimmt das breiteste freie Stück; ist es unter 240 pt, rückt er über die Tasten im Weg nach oben (DS zugeklappt: über L und R). Bis zu den großen Schriftgrößen drei Zeilen, ab den Bedienungshilfe-Größen ohne Grenze; er wächst vom unteren Anker nach oben.
- **Debug-Overlay:** oben links im sicheren Bereich mit dem Abstand der Breitenklasse; die Zeilen brechen vor einem Pause-Knopf in der oberen Hälfte daneben um und vor einem Touchscreen, der daneben beginnt (Buch und offen, DS), damit die Karte ihn nie abdunkelt.
- **Kachelkunst als Hintergrund** (`.backdrop`, Laden und Fehler): unscharf, Schwarz 0,65 darüber.
- **Rand des Rasters:** aus der Breite mit Systemspalte (außen 466 pt, also 20 pt wie der große Titel); Spalten, Abstände und Ecken aus der Breite des Rasters.
- **Pausen-Sheet:** bei `.medium` hochkant ohne den Einzug der Systemspalte, Ränder 20 pt links und rechts; bei `.large` mit Einzug.

## Abläufe

- **Pause:** Der Knopf ruft `setUserPaused(true)`. `GameView` zeigt das Sheet, solange `showsPauseMenu && phase == .running` gilt, also von Hand pausiert oder zugeklappt (ADR 0006, Abschnitt 10), auch außen nach dem Zuklappen; setzt die Sitzung von selbst fort, wie beim Aufklappen, schließt es sich. Das Sheet hängt an einem eigenen `@State`, weil das Fortsetzen über die Warteschlange der Sitzung läuft; ein Binding auf `showsPauseMenu` würde nach dem Wegwischen noch eine Pause melden, und SwiftUI zeigte das Sheet erneut. „Resume“ ruft `resumeFromMenu()`, Wegwischen und Escape ebenso in `onDismiss`. „Quit Game“ setzt `isQuitting`, schließt das Sheet und beendet in `onDismiss` über `quit()`; danach bringt `RootView` die Bibliothek zurück. Solange das Sheet offen ist, blenden die Tasten aus, Deck und Pause-Knopf bleiben.
- **Zoom:** Nur das Sheet wächst aus dem Pause-Knopf (`matchedTransitionSource` + `.zoom`), bei Bewegung reduzieren oder `accessibilityPrefersCrossFadeTransitions` mit `.crossFade` (iOS 27.0). Der Zoom von der Kachel ins Spiel ist mit dem Merge entfallen: Seit M2 ersetzt ein Spiel die Bibliothek im Fenster (`RootView`), es gibt keine Präsentation, also keinen Zoom des Systems, und kein eigener Morph ersetzt ihn (ADR 0007, Entscheidung 11).
- **Flach:** `resolvesControlSurface()` in `RootView` am Spiel liest `systemPrefersReducedResourceUsage` (iOS 27.0) und im Debug-Build `-ArcfoldControlSurface flat|glass`. Jeder Wechsel kommt ins Log (Kategorie `ui`). Flach hat eine Taste über einem Bildschirm die schwächere Füllung von M2 (Weiß 0,10 statt 0,15).
- **Galerie:** `-ArcfoldGallery <Seite>` zeigt eine Seite statt der Bibliothek, jede aus `GameLayout` in einer Geometrie des Duo-Simulators: `library-empty`, `library-shelf`, `library-inner`, `touch-upright` (das Band des zugeklappten GBA unter dem Bild), `touch-landscape` (der GBA zugeklappt quer, alle Tasten über dem Bild; mit `-ArcfoldGalleryPressed YES` gedrückt), `touch-inner` (der DS im Tabletop unter dem Falz, mit X und Y), `touch-differentiate` (gedrückt mit „Ohne Farbe unterscheiden“), `notices` (das Bild des zugeklappten GBA mit Chip und Hinweis an ihrer Stelle), `failure`, `loading`, `game-landscape` (der GBA quer mit allen Überlagerungen, um 90° gedreht). Jede Taste trägt eine unsichtbare Kennung `gallery-key-<Taste>-<Reihe>` mit ihrem Rahmen.

## Abnahme und Messwerte

Bildschirmfoto-Tour: `Scripts/screenshot-tour.sh <UDID> <Ordner> [light dark contrast large poses]`. Sie stellt Erscheinungsbild, Kontrast und Schriftgröße des Simulators um, führt `ScreenshotTour` aus und exportiert die Anhänge als `<Variante>-<nn>-<Zustand>.png` und `<Variante>-metrics.txt`. Ohne Variante überspringt `ScreenshotTour` jeden Zustand, damit der normale Testlauf schnell bleibt. Seit M2 hat sie einen Teil `poses`: Das Skript stellt jede echte Pose des Duo mit dem privaten Posen-Werkzeug außerhalb des Repos ein, das `POSE_CHECK_POSTURE_TOOL` benennt wie bei `Scripts/pose-check.sh` (zu hochkant, zu quer, offen, Buch, Tabletop, flach hochkant), in allen vier Varianten (jede Pose einmal eingestellt, darin Variante für Variante), und führt darin die Zustände 30 (DS) und 31 (GBA) mit Pausen-Sheet, 32 (Bibliothek), 33 (Menü), 34 (Suche), 35 (Lizenzen), 36 (langer Hinweis mit Ton-Chip über einem laufenden Spiel) und 37 (Fehleransicht) aus, quer dazu 12 (Sheet quer) und `GlassUITests/testSidewaysTheRButtonIsFree`, in hell zusätzlich `GameOverlayUITests` und `LibraryLayoutUITests` (im Buch mit dem Falz von 455,5 bis 495,5 pt über `ARCFOLD_LIBRARY_FOLD`); danach startet es den DS offen, klappt zu, fotografiert das Sheet außen und klappt wieder auf (40 bis 42). Ohne Argumente laufen alle vier Varianten und die Posen; ohne `POSE_CHECK_POSTURE_TOOL` überspringt sich der Teil `poses` mit einem Hinweis (Exit 0), die Varianten laufen.

Ergebnisse vom 7. November 2026 vor dem Merge mit M2 (Simulator „Arcfold Glass Duo“, zugeklappt, iOS 27.1, die feste Tastenlage aus M1); die Messwerte nach dem Merge stehen im Abschnitt „Mit M2 zusammengeführt“:

| Messwert | Grenze | Ergebnis |
| --- | --- | --- |
| Pause hochkant | 44–52 pt | 47 × 47 (Layout 48) |
| Pause quer | 44–52 pt | Fenster dreht nicht; Galerie-Seite gedreht und auf 0,95 verkleinert: 45 |
| Pause ∩ R quer | 0 | 0 laut `OverlayPlacementTests` (678 × 382, 678 × 466, 951 × 669, 874 × 402) |
| Spalten `library-shelf` | hell/dunkel 2, große Schrift 1 | 2 / 2 / 1 |
| Spalten `library-inner` | 3 | 3 |
| Kontrast A, B, L, R, Steuerkreuz über Weiß und Testmuster | ≥ 3,0 : 1 | Ruhe min. 3,25 (Steuerkreuz), A/B/R 3,84, L 3,81; gedrückt min. 3,95 |
| Kontrast Select, Start | ≥ 4,5 : 1 | Ruhe 5,10, gedrückt 6,13 |
| dieselben mit Kontrast erhöhen | ≥ hell | alle über 10 : 1 |
| Audit (Bibliothek, Lizenzen, Hinweise, Fehler, Spiel, Sheet; hell im normalen Testlauf, dunkel und Kontrast in der Tour) | keine Befunde | keine außer den begründeten Ausnahmen (siehe Stolperfallen) |
| Sheet hochkant | notieren | 450 × 390 pt ab y 280 (Detent `.medium`) |
| Sicherer Bereich quer | notieren | nicht messbar, Fenster dreht nicht |
| Zwei Läufe hell | gleiche Bilder | 15 von 18 Bildern pixelgleich, ebenso alle Messwerte; anders nur 08, 09, 10 (laufendes Spiel und Zahlen im Debug-Overlay, 0,4–1,5 % der Pixel) |

Kontrast mit den geplanten Platten (0,60 / 0,70, gedrückt 0,85): A/B/R 2,92, L 2,90, Select/Start 3,84, gedrückt Select/Start 3,31. Die Pfeile mit Weiß 0,55 kamen schon auf der Platte 0,70 nur auf 2,27. Über Schwarz (nicht bewertet) liegen alle Werte über 4,6 : 1.

Weiß auf dem Akzent lag mit `systemIndigo` im dunklen Modus bei 3,5 : 1 („Resume“), mit Kontrast erhöhen bei 2,1 : 1 (`systemIndigo` wird dann heller), „Close“ über der Kachelkunst bei 3,1 : 1 und „Import Games“ dunkel bei 3,6 : 1. Seit der Prüfung gilt dunkel das helle `systemIndigo` (siehe „Nachbesserungen nach der Prüfung“).

**Messung wie in M1** (`selftest.gba` per `-ArcfoldAutorun`, 60 s, Zeilen der Kategorie `stats`): vorher 59,72 Bilder/s, resync 0, Display 47 Hz, übersprungen 25,9 %, „late“ der Emulation 2107; nachher 59,58 Bilder/s im letzten Fenster (59,71–59,81 davor), resync 0, Display 47 Hz, übersprungen 26,6 %, „late“ der Emulation 2230. „late“ der Anzeige in beiden 0.

Nach den Nachbesserungen (Last des Macs 4 bis 5): zwei Läufe mit Glas 59,65 und 59,79 Bilder/s, Display 48 und 49 Hz, übersprungen 28,0 % und 26,2 %; ein Lauf flach 59,82 Bilder/s, 51 Hz, 24,7 %. In allen drei resync 0, „late“ der Anzeige 0, „GPU busy“ 0, keine Aussetzer im Ton. Der Abstand Glas gegen flach (+1,5 bis +3,3 Prozentpunkte) liegt im Rahmen der Messung oben; die Läufe streuen um etwa 2 Prozentpunkte.

**Glas gegen flach** (`ScreenshotTour.test98MeasureGlassAgainstFlat`, `ARCFOLD_TOUR_MEASURE=1`, hochkant, weil das Fenster nicht dreht; je 60 s `selftest.gba`, erst Glas, dann flach; Last des Macs 20 bis 260 durch parallele Builds und Tests von M2):

| Lauf | Glas: Hz / übersprungen | flach: Hz / übersprungen | Unterschied übersprungen |
| --- | --- | --- | --- |
| 1 | 50 / 27,4 % | 51 / 25,9 % | +1,5 Pp. |
| 2 | 48 / 28,4 % | 50 / 26,3 % | +2,1 Pp. |
| 3 | 50 / 27,2 % | 48 / 26,0 % | +1,2 Pp. |
| Versuch: Pause flach, Tasten Glas | 46 / 25,8 % | 49 / 26,5 % | −0,7 Pp. |

In allen Läufen: Emulation 59,4–59,7 Bilder/s, „late“ der Anzeige 0 (einmal 2 im Versuch), „GPU busy“ 0, `resync` 0 außer einmal 2 im flachen Lauf bei Last 258. Grenzen des Entwurfs: Hz-Unterschied ≤ 2 (erfüllt, im Mittel 0,3), übersprungen ≤ 1 Prozentpunkt über flach (verfehlt, im Mittel +1,6).

Ursache: Der Versuch mit flachem Pause-Knopf und Tasten aus Glas liegt auf dem Niveau von flach. Es kostet also das Glas des Pause-Knopfs über dem `CAMetalLayer`, nicht das Glas der Tasten über dem ruhenden Deck. Glas über einer Ebene, die sich mit jedem Bild ändert, muss der Compositor bei jedem Bild neu abtasten.

Entscheidung (begründet abgeschwächt): Der Pause-Knopf bleibt aus Glas. Im Simulator rendert der Mac die Ebenen, und die Anzeige läuft dort ohnehin nur mit 46–51 Hz; auf dem Gerät entscheidet der Gerätetest (`geraetetest.md`, Teil 1b) mit denselben Grenzen. Fällt er durch, wird der Pause-Knopf über dem Bild flach (`Glass.identity`, eine Zeile in `PauseButton`), quer zusätzlich die Tasten. Bis dahin schaltet `systemPrefersReducedResourceUsage` alles auf flach.

## Nachbesserungen nach der Prüfung

Die Umsetzung wurde am 7. November 2026 unter drei Gesichtspunkten geprüft (Gestaltung, Regeln, Funktion). Gemessen danach mit der Tour (Varianten hell, dunkel, Kontrast, große Schrift):

| Messwert | Grenze | vorher | nachher |
| --- | --- | --- | --- |
| Kante der Tasten mit Kontrast erhöhen, Seite 08 (Spiel hochkant, volle Größe, über dem Deck) | ≥ 3 : 1 | Rand fehlte, Fläche gegen Deck 1,1 : 1 | A 3,85, B 3,94, L und R 3,51, Steuerkreuz 3,74, Select und Start 4,12 |
| Ring bei „Ohne Farbe unterscheiden“ gegen die gedrückte Farbe, Seite 19 | ≥ 3 : 1 | nicht gemessen, lag wie der Rand hinter dem Glas | hell 3,28 bis 7,42, Kontrast 7,83 bis 15,34 (mit Weiß 0,9 wie im Entwurf lag R hell bei 2,96) |
| Beschriftungen über dem Deck, Seite 13 (Platte 0,35 / 0,45) | ≥ 3 bzw. 4,5 : 1 | Platte 0,70 / 0,80 | in Ruhe A 12,0, B 12,7, L und R 10,3, Steuerkreuz 9,1, Select und Start 13,2; gedrückt A 4,6, Steuerkreuz 5,3; im Spiel (Seite 08) mindestens 9,0 |
| Weiß auf dem Akzent: Import Games, Resume (im immer dunklen Sheet), Close (über der Kachelkunst) | ≥ 4,5 : 1 | Import Games dunkel 3,6, Resume 3,5 (mit Kontrast 2,1), Close 3,1 | Import Games 5,14 (hell, dunkel, große Schrift), 6,25 (Kontrast); Resume 5,09, 6,12 (Kontrast); Close 4,69, 6,19 (Kontrast) |
| Fehlermeldung über der Kachelkunst | ≥ 4,5 : 1 | 3,8 | 5,09 (große Schrift 5,08, Kontrast 6,13) |
| Ränder von „Resume“ im Sheet, links / rechts | gleich | 20 / 96 pt | 20 / 20 pt (hell, Kontrast, große Schrift) |
| Linke Kante der ersten Kachel gegen den großen Titel | gleich | 16 / 20 pt | 20,0 / 20,0 pt (hell, dunkel, große Schrift) |
| Hinweis mit accessibility-large | ganzer Text | abgeschnitten nach drei Zeilen | ganzer Text in 149 pt Höhe, ganz im Bildbereich |

Die Kanten auf den verkleinerten Galerie-Seiten 13 (0,58) und 14 (0,69) werden nur notiert: Dort ist der Rand 0,6 bzw. 0,7 pt breit und misst mit Kontrast erhöhen 1,6 bis 3,9 : 1 (über Weiß zählt die Platte, 14 : 1).

## Abweichungen vom Entwurf

Gegenüber dem Entwurf vom 7. November 2026, aus dem ADR 0007 hervorging, jeweils mit Grund:

1. **Platten 0,1 dunkler.** Entwurf 0,60 / 0,70 (IC 0,75 / 0,85), umgesetzt 0,70 / 0,80 (IC 0,80 / 0,90). Gemessen über Weiß: 2,9 : 1 und 3,8 : 1, also unter 3 bzw. 4,5. Der Entwurf sah dafür selbst vor, die Platte um 0,1 anzuheben statt die Schrift zu verkleinern.
2. **Gedrückt fast deckend.** `pressedFill` mit 0,95 statt 0,85, bei kleiner Schrift zusätzlich mit Schwarz 0,25 gemischt. Mit 0,85 kamen Select und Start gedrückt über Weiß auf 3,3 : 1.
3. **Pfeile in Ruhe Weiß 0,85 statt 0,55.** Mit 0,55 maß der Pfeil über Weiß 2,3 : 1, auch auf der dunkleren Platte. Gedrückt unterscheidet sie der Sektor in der Spielfarbe.
4. **`debugMaxWidth` = linke Kante des Pause-Knopfs − 2 × Abstand** statt `w / 2 − 32`. Beide sind bei 8 pt Abstand gleich; mit den 12 und 16 pt der breiteren Klassen hätte `w / 2 − 32` den Pause-Knopf überdeckt (`OverlayPlacementTests`).
5. **Querformat im Simulator nicht erreichbar** (bis zum Zusammenführen mit M2; seitdem dreht die Pose „zu, quer“ des privaten Posen-Werkzeugs das Außendisplay, siehe Abweichung 28). Das Fenster des zugeklappten Duo drehte mit `XCUIDevice.orientation` nicht. Zustand 11 ist deshalb die Galerie-Seite `game-landscape` (dieselben Teile, um 90° gedreht), Zustand 12 (Sheet quer) und `testSidewaysTheRButtonIsFree` überspringen sich. Pause ∩ R = 0 und die Lage quer belegen `OverlayPlacementTests` für 678 × 382, 678 × 466, 951 × 669 und 874 × 402; der sichere Bereich quer (`landscape-safe-area`) ist nicht gemessen.
6. **Glas gegen flach hochkant statt quer** (in der ersten Fassung, weil quer im Simulator nicht ging, siehe 5; seit Abweichung 28 misst der Abschnitt „Mit M2 zusammengeführt“ auch offen). Hochkant liegt nur der Pause-Knopf über dem Bild, die Messung sagt also wenig über quer; das entscheidet der Gerätetest (`geraetetest.md`, Teil 1b). Die Grenze „übersprungen ≤ 1 Prozentpunkt über flach“ verfehlt der Simulator mit +1,6; sie ist für den Simulator abgeschwächt (Messwerte und Ursache oben).
7. **Seite 14 mit einem Zustand je Start.** `-ArcfoldGalleryPressed YES` zeigt gedrückt; so passen die drei Hintergründe groß genug für die Pixelmessung auf eine Seite. Dazu kamen die Seiten `loading` und `game-landscape`.
8. **Audit mit begründeten Ausnahmen.** Zulässig sind „Contrast nearly passed“ bei Systemfarben (sekundäre Labels, Weiß auf Indigo), Befunde auf `touch-controls` und `debug-overlay` (der Entwurf lässt sie zu) sowie im Sheet ein „Contrast failed“, wenn die Pixel des Elements ≥ 4,5 : 1 ergeben (gemessen 5,5 : 1 für „Quit Game“).
9. **Monogramm im `Canvas`, Spielname ohne Obergrenze für Dynamic Type, Spielname im Sheet primär statt sekundär, Sheet-Inhalt in einer `ScrollView`.** Alles aus dem Audit (siehe Stolperfallen).
10. **`GameArtwork(style:variant:)` mit `.tile(corner:)`.** Die Ecke kommt aus der Breitenklasse des Rasters; ohne `style` liest die Kunst `gameStyle` aus der Umgebung (Kopf des Sheets, Ladebild, Fehler).
11. **Pause-Menü schließt auch, wenn die Sitzung von selbst fortsetzt** (`isPauseMenuShown = paused` statt nur bei `true`).
12. **Zwei Commits mehr.** `fix(design): meet the measured contrast and the accessibility audit` trennt die Korrekturen aus der Messung vom Test-Commit; `test(ui): make the screenshot tour repeatable` friert die Statusleiste ein und findet die Kacheln auch bei großer Schrift.
13. **`CLAUDE.md` erst mit dem Merge von M2.** Status und Wissensliste kamen mit dem Merge dazu, damit sie zum Stand beider Meilensteine passen.
14. **`ScreenshotTour` überspringt sich ohne Variante.** So bleibt `xcodebuild test` schnell; die Tour läuft über das Skript. Die Tests zählen trotzdem mit (20 übersprungen).
15. **Rauchglas-Rückfall des Pause-Knopfs nicht nötig.** Auf den Bildern 08 und 10 zeigt der Knopf keine „Mondsichel“; die Platte bleibt. Der Gerätetest schaut noch einmal hin.
16. **Platte über dem Deck 0,35 / 0,45** (Prüfung): Der Entwurf kennt eine Platte für Bild und Deck. Über dem dunklen, ruhigen Deck machte sie jede Taste zu einer fast deckenden grauen Scheibe; Weiß liest sich dort auf der leichten Platte mit 9 bis 13 : 1. Kontrast erhöhen und Transparenz reduzieren behalten ihre Werte.
17. **Akzent dunkel mit den hellen Werten von `systemIndigo`** (Prüfung): `#6155F5`, mit Kontrast erhöhen `#564ADE`, beides die Werte, die das System hell zeigt; hell bleibt die Systemreferenz. Mit `systemIndigo` dunkel lag Weiß darauf unter 4,5 : 1, mit Kontrast erhöhen bei 2,1 : 1.
18. **Pausen-Sheet über der Spalte** (Prüfung, Ausnahme von R6): Bei `.medium` hochkant reicht das System-Sheet über die Spalte, die Statusleiste steht darüber, und die Spalte hält dort nichts. Der Inhalt nutzt die Breite des Sheets; bei `.large` bleibt der Einzug.
19. **Ton-Chip quer über den Hinweisen** (Prüfung): Der Entwurf stapelt ihn unter dem Debug-Overlay; quer lag er dort auf L. Das Debug-Overlay nimmt keine Treffer an (R6).
20. **Ton-Chip als abgerundetes Rechteck mit Grenze accessibility2** (Prüfung): Als Kapsel schnitten die runden Enden umbrochenen Text ab; ohne Grenze wuchs er hochkant aus dem Bildbereich.
21. **Ring bei „Ohne Farbe unterscheiden“ in reinem Weiß** statt Weiß 0,9 (Prüfung): Mit 0,9 lag der Ring von R über der Spielfarbe von selftest bei 2,96 : 1. Weiß wie die Beschriftung erreicht auf jeder gedrückten Farbe mindestens 3 : 1 (`GameStyleTests`).
22. **Pause-Knopf ohne den Glas-Knopfstil** (Merge): Der Stil `.glass(.clear)` bemisst das Glas nach der Steuergröße, mit `.large` 47 pt, die Menüzeile von M2 ist 36 pt hoch. Der Knopf ist jetzt ein Kreis aus Spielglas in der Größe seines Platzes, `Glass.clear.interactive()` über der Platte, mit einem Ziel von mindestens 44 × 44 pt wie in M2; er reagiert wie die Glasknöpfe des Systems.
23. **Kein Zoom von der Kachel ins Spiel** (Merge, Entscheidung 11): Das Spiel ersetzt die Bibliothek (`RootView`), es gibt keine Präsentation, aus der das System zoomen könnte. Kein eigener Morph als Ersatz, weil er Modalität und Übergänge selbst bauen müsste, die Ursache des Fehlers von M2 war eine Präsentation über der Bibliothek.
24. **Deck wo keine Bildschirme sind** (Merge): Statt „hochkant unter dem Bild“ liegt das Deck hinter jeder Tastenzone, die keinen Bildschirm deckt, in jeder Pose (`DeckLayout`), und über einem Bildschirm trägt eine Taste die Bildplatte. Quer zugeklappt liegen die Tasten des GBA über dem Bild (kein Deck), beim DS daneben (Deck).
25. **Hinweise auf dem oberen oder einzigen Bildschirm** (Merge): statt „hochkant unten im Bildbereich, quer unten mittig“. Die Lage folgt `GameLayout`; ein Hinweis meidet Tasten, Touchscreen, Pause-Knopf und Falz und rückt nach oben, wenn ihm kein Stück von 240 pt bleibt.
26. **Ton-Chip in jeder Pose über dem Hinweis** (Merge): Vorher hochkant unter dem Debug-Overlay. Mit einer Regel für alle Posen bleibt er auf dem Bild und frei von Tasten; in einem Bild unter 138 pt Höhe (bei 8 pt Abstand) kommt er oben ins Bild.
27. **Debug-Overlay bricht vor dem Touchscreen um** (Merge; seit den Nachbesserungen der Gestaltung ersetzt durch Abweichung 33): Im Buch und offen beginnt der Touchscreen des DS neben der Ecke des Overlays; dessen Karte lag über der oberen Zeile des Touchscreens und über dem Fadenkreuz des Touch-Tests. Sonst bleibt die Lage von M2: oben links im sicheren Bereich, quer zugeklappt über L (nur sichtbar, es nimmt keine Treffer an).
28. **Querformat und Innendisplay im Simulator erreichbar** (Merge): Mit dem privaten Posen-Werkzeug stellt die Tour jede echte Pose ein (Abschnitt „Mit M2 zusammengeführt“). `testSidewaysTheRButtonIsFree` und Zustand 12 laufen quer; sie überspringen sich nur noch, wenn das Fenster wirklich hochkant bleibt. Zustand 11 bleibt die gedrehte Galerie-Seite, weil sie alle Teile auf einer Seite zeigt.
29. **Tastenmaße aus `GameLayout`** (Merge): Die Tour misst den Kontrast der Tasten im Spiel an deren eigenen Rahmen (`touch-button-<Taste>`, `touch-pad`) statt an den Formeln von M1, die Galerie zeigt die Tasten in den Zonen von `GameLayout`.

30. **Rand der Bibliothek vom System** (Gestaltung): Das Raster beginnt an der Kante des großen Titels und endet am Rand auf der anderen Seite. Der Rand kommt von `systemMinimumLayoutMargins` des Hosting-Controllers (`SystemMarginsReader`), nicht aus `scenePadding`, das in jeder Pose 16 pt misst. Gemessen: 20 / 20 pt, zu quer 84 / 84 pt; auf einer Seite mit Einzug 0.
31. **Raster nach der Breite, Kachelkunst nach der Höhe** (Gestaltung, nach der Gegenprüfung geändert): Die Spaltenzahl folgt allein der Breite (`LibraryColumns`, reine Funktion, Tests über alle Geometrien des Duo, vier Randsätze und alle Schriftgrößen): Mindestbreite der Breitenklasse mal `tileScale` der Schriftgröße. Wäre eine Reihe mit zweizeiligem Namen höher als das Fenster, wird die Kachelkunst niedriger (`artworkHeight`: sichtbare Höhe minus 8 pt minus Höhe der Beschriftung, mindestens 60 pt), die Kachel nie schmaler. Zuerst nahm das Raster dafür eine Spalte mehr; zugeklappt quer (594 × 350 pt im sicheren Bereich) entstanden so bei den größten Schriften drei Kacheln zu 181 pt mit gekürzten Namen („Arc-Li…“). Jetzt dort: Standard 3 Spalten, accessibility-medium bis -extra-large 2 zu 279 pt, die zwei größten Stufen 1 Kachel zu 574 pt mit flacher Kunst. Bei Standardgröße zu hochkant, zu quer, offen, Buch, Tabletop und flach hochkant: 2, 3, 4, 2 + 2, 3, 3 Spalten. Tests: `LibraryColumnsTests` (Kachel mindestens so breit, wie die Schriftgröße verlangt; kein Name der Galerie gekürzt oder im Wort getrennt, mit den Schriften der Kachel gemessen), `LibraryLayoutUITests.testNoNameOfATileIsCutShortAtAnyTextSize` (Audit „Text clipped“ für die Namen bei fünf Schriftgrößen in der Pose, wie sie ist).
32. **Bibliothek im Buch in zwei Seiten** (Gestaltung): Bei aktivem Falz von oben nach unten teilt das Raster sich links und rechts des Falzes (2 + 2 Spalten, bei großer Schrift 1 + 1), keine Kachel auf der Division-Region. Lizenzen zeigen Liste und Text nebeneinander über `ArrangementView`, wie die Einstellungen. Kerne, leere Bibliothek, Suche ohne Treffer und ein geschobener Lizenztext bleiben auf der ersten Seite. Offen flach und im Tabletop teilt auch das System nicht, dort bleibt es eine Seite. Im Buch ist die Lücke links vom Falz größer als rechts: die linke Seite ist 64 pt breiter, rechts nimmt die Systemspalte 84 pt, die Kacheln sind auf beiden Seiten gleich breit.
33. **Hinweise, Chip, Debug-Overlay und Fehleransicht aus freien Rechtecken** (Gestaltung): `OverlayPlacement` sucht die freien Rechtecke zwischen allen Hindernissen (Tasten samt Zugabe, Reichweite des Steuerkreuzes, Pause-Ziel, Touchscreen, Falz). Hinweis und Ton-Chip sind ein Stapel in einem `GlassEffectContainer`; bei großer Schrift nimmt er die größte Schriftgröße, bei der Chip und ganzer Hinweis in die Spalte passen. Das Debug-Overlay wählt eine von fünf Schriftgrößen (10 bis 6 pt) und liegt in keiner Pose auf einer Taste (`DebugPlacementTests`, `GameOverlayUITests.testTheDebugOverlayCoversNoControl`). Die Fehleransicht (`OverlayPlacement.failureArea`) zentriert Text und „Close“ im sicheren Bereich, mit Falz im Teil darüber bzw. links davon, und scrollt bei großer Schrift; die Kachelkunst füllt weiter die ganze Ansicht (`FailurePlacementTests`, `GameOverlayUITests.testTheFailureMessageStaysOnOneScreen` in sechs Posen). Der Pause-Knopf zeichnet sein Glas im Container der Tasten; das Pausen-Sheet gleicht seine Ränder aus dem gemessenen sicheren Bereich aus (`PauseSheetMarginsTests`, `PauseGlassTests`).
34. **Rand über dem Bild mit Kontrast erhöhen Weiß 0,90** (Gegenprüfung): Der Rand war überall Weiß 0,35. Über dem dunklen Bild der Testprogramme maß die Kante von L und R 2,84 bis 2,96 : 1, über einem mitteldunklen Bild fiele sie gerechnet auf 1,7 : 1, weil dort weder der Rand noch die Platte gegen das Bild steht. Mit Kontrast erhöhen zeichnet eine Taste, die über einem Bildschirm liegt (`GlassBackdrop.picture`), den Rand deshalb mit 0,90 (`GamePlate.pictureBorderOpacity`): Gerechnet über jedes graue Bild hält dann der Rand oder die Platte mindestens 3,1 : 1 (`GamePlateTests.theEdgeOverThePictureStandsOutFromAnyPicture`; mit 0,75 wären es 2,7, mit 0,85 knapp 3,0). Über dem Deck und bei „Rahmen anzeigen“ allein bleibt 0,35.

## Mit M2 zusammengeführt

Am 7. November 2026 wurde die Oberfläche mit dem damaligen Stand von M2 zusammengeführt; am 10. November 2026 wurde sie ohne ihren früheren Verlauf auf den bereinigten Verlauf von M2 gelegt (Branch `m4/liquid-glass`, kein Merge-Commit); nach der Abnahme von M2 am selben Tag liegt der Branch auf `main`. Dabei fielen die doppelten Test-Helfer für das Innendisplay weg: Glass-Tests und Tour nutzen die Helfer von M2 (`app.gameWindow`, `app.viewOrigin`, `app.displayScreenshot()`, `XCUIScreenshot.uprightImage`), die Kontrastmessung ist eine Erweiterung von `Pixels`. Die Architektur von M2 gewinnt, Glas liefert das Aussehen (ADR 0007, Abschnitt „Zusammenführung mit M2“, Entscheidungen E1 bis E9).

**Übernommen aus den Empfehlungen an M2**

- `toolbarVerticalBehavior(.disabled)` für die Spielansicht außen: M2 hat es je System entschieden, der GBA schaltet die Leiste ab (466 × 562 pt, 5×), der DS behält sie (382 × 644 pt, 4×) (ADR 0006, Abschnitt 7).
- Neue Tasten bekommen das Glas über `TouchLayout.buttons`: X und Y des DS sind `GlassKey`s wie A und B.
- Kein Glas über der Division-Region und über dem Touchscreen des DS: Tasten und Pause-Knopf meiden beide nach den Regeln von `GameLayout`, Hinweise und Chip nach `OverlayPlacement`. Das Deck ist kein Glas; es bleibt neben dem Falz.
- `OverlayPlacement` wird aus FoldLayout gespeist, die Tests laufen gegen `GameLayout` für GBA und DS in allen 41 Geometrien von `LayoutInvariantTests`, mit Touch-Tasten und mit Controller (`OverlayPlacementTests`, `ControlDeckTests`).
- Bei Konflikten gewann die Struktur von M2 (`GameView`, `GameStage`, `TouchControls`, `TouchSurface`, `RootView`), die Bausteine aus `Design/` sind eingesetzt; `GameOverlays` nimmt die Werte der Spielansicht von M2 (Debug-Werte mit Falz, Hinweis, Ton, Fehler). Die Tastenkunst trägt die Kennungen der Tests von M2, die Platte kommt aus `GlassBackdrop` je Taste. Strings und `project.yml` sind vereinigt.

**Geändert**

- Der Pause-Knopf sitzt, wo `GameLayout` ihn hinlegt (Menüzeile zwischen Select und Start, ohne Touch-Tasten eine Ecke), nie in der Systemspalte; die Empfehlung „nur mit gemeldeter Verdeckungsregion in die Spalte“ ist damit gegenstandslos. Er ist ein Spielglas-Kreis statt des Glas-Knopfstils (Abweichung 22).
- Hinweise und Chip liegen auf dem oberen oder einzigen Bildschirm (Abweichungen 25 und 26), das Debug-Overlay bricht vor einem Touchscreen daneben um (Abweichung 27).
- Das Pausenmenü ist das Sheet von ADR 0007, gesteuert von `showsPauseMenu` statt `isUserPaused`; es steht auch nach dem Zuklappen außen und schließt sich beim Aufklappen. Die Kennungen sind die von M2: `resume`, `quit` (vorher `quit-game`), `game-<System>-<Name>` (vorher `game-<Name>`).
- Die Tour stellt die echten Posen ein (Abweichung 28) und misst die Tasten an ihren Rahmen (Abweichung 29).

**Entfallen**

- Der Zoom von der Kachel ins Spiel und sein Test `testDraggingDownOverTheControlsKeepsTheGame` (Abweichung 23); an seine Stelle treten die Tests der Oberkante nach dem Sheet.
- Die feste Tastenlage aus M1 (`TouchLayout(size:isLandscape:)`) und mit ihr die Formeln in Tour und Galerie. `PadShape` und `ButtonShape`, die M2 mitbrachte, sind wieder entfernt.
- Der Hinweis „Quer überdeckt das Debug-Overlay die Taste L, die Lage gehört M2“: Die Lage von M2 bleibt (Abweichung 27).

**Messwerte nach dem Merge**

Tour in den vier Varianten am 7. November 2026 (Simulator „Arcfold Glass Duo“, zugeklappt hochkant, iOS 27.1), alle vier Läufe grün:

| Messwert | Grenze | Ergebnis |
| --- | --- | --- |
| Pause zugeklappt hochkant (GBA, Menüzeile) | Ziel 44–52 pt | 44 × 44 bei (211, 596), gezeichnet 36 pt |
| Spalten `library-shelf`, `library-inner` | 2 (große Schrift 1), 3 | 2 / 2 / 1, 3 |
| Linke Kante der ersten Kachel gegen den großen Titel | gleich | 20,0 / 20,0 pt |
| Beschriftungen im Spiel über dem Deck (Seite 08, volle Größe) | ≥ 3 bzw. 4,5 : 1 | A 12,02, B 12,74, L und R 10,29, Steuerkreuz 8,87, Select und Start 13,20; mit Kontrast erhöhen 17,26 / 17,26 / 17,10 / 12,60 / 17,04 |
| Kante der Tasten mit Kontrast erhöhen (Seite 08) | ≥ 3 : 1 | A 3,92, B 4,02, L und R 3,62, Steuerkreuz 3,81, Select 4,06, Start 4,18 |
| Beschriftungen quer über Weiß (Seite 14, GBA zugeklappt quer, alle Tasten über dem Bild) | ≥ 3 bzw. 4,5 : 1 | Ruhe A und B 5,10, L und R 3,84, Steuerkreuz 3,25, Select und Start 5,10; gedrückt 6,13 / 4,00 / 4,38 / 6,13; über dem Testmuster in Ruhe mindestens 3,25 (Steuerkreuz), Select und Start 5,31 |
| Weiß auf dem Akzent | ≥ 4,5 : 1 | Import Games 5,14 (hell, dunkel, große Schrift), 6,25 (Kontrast); Resume 5,09, 6,12; Close 4,68 (hell), 4,65 (große Schrift), 6,19 (Kontrast) |
| Fehlermeldung über der Kachelkunst | ≥ 4,5 : 1 | 5,00 (hell), 5,03 (große Schrift), 6,00 (Kontrast) |
| Pausen-Sheet hochkant | Ränder gleich | 450 × 390 pt ab y 280, 20 / 20 pt (hell, Kontrast, große Schrift) |
| Ring bei „Ohne Farbe unterscheiden“ (Seite 19) | ≥ 3 : 1 | hell 4,10 bis 7,52, Kontrast 12,55 bis 15,35 |
| Hinweis mit accessibility-large (Seite 17) | ganzer Text im Bild | 149 pt hoch, ganz auf dem Bild |
| Audit dunkel und mit Kontrast erhöhen | keine unbegründeten Befunde | bestanden |

Teil `poses` der Tour am 7. November 2026, hell und dunkel, jede Pose mit dem privaten Posen-Werkzeug eingestellt: 12 Läufe, 40 Tests, alle grün (Zustände 30, 31 und 99 in jeder Pose, quer dazu 12 und `testSidewaysTheRButtonIsFree`). Rahmen in Pixeln des Views, das Sheet in Punkten:

| Pose | View, sicherer Bereich, Falz | DS | GBA | Pausen-Sheet |
| --- | --- | --- | --- | --- |
| zu hochkant | 1398 × 2034, Leiste rechts (DS) bzw. oben (GBA) | je 4× bei (61, 0) und (61, 768) | 5× bei (99, 246) | 450 × 390 ab (8, 280) |
| zu quer (`closed --orientation landscape-left`) | 2034 × 1398, DS Leiste links 252 px, GBA oben 246 px | je 3× bei (759, 72) und (759, 648), Spalten daneben | 6× bei (297, 291), Tasten über dem Bild | 662 × 458 ab (8, 8) |
| offen | 2853 × 2007, unten 102 px, Falz 121 px bei x 1366, inaktiv | je 5× bei (73, 192) und (1530, 192) | 9× bei (346, 232) über den Falz | 653 × 385 ab (149, 276), mittig |
| Buch | wie offen, Falz aktiv | je 5× wie offen | 9× wie offen | 460 × 385 ab (8, 276), links vom Falz |
| Tabletop | 2007 × 2853, Falz 121 px bei y 1366, aktiv | oben 7× bei (107, 41), Touchscreen 5× bei (363, 1639) | 8× bei (43, 73) | 653 × 456 ab y 488, unter dem Falz |
| flach hochkant (`open --orientation landscape-left`) | wie Tabletop, Falz inaktiv | je 5× bei (363, 233) und (363, 1639) | 8× bei (43, 73) | wie Tabletop |

- **Quer zugeklappt:** Der Pause-Knopf nimmt 44 × 44 pt bei (600, 384) und schneidet R nicht; R drückt (`testSidewaysTheRButtonIsFree`, „last R“, kein Sheet). Das Sheet quer reicht über die ganze Breite, sein Inhalt hat links rund 100 pt und rechts rund 30 pt Abstand (Einzug des Systems, gemessen im Bild); „Resume“ 5,09 : 1. Die GBA-Tasten liegen über dem Bild (Bildplatte), die DS-Tasten in den Spalten neben den Bildschirmen (Deck). Gerechnet hatte ADR 0006 den GBA quer mit 8× ohne Rand; gemessen ist die Leiste auch quer oben und der Faktor 6×.
- **Innendisplay:** Die Tasten liegen in jeder Pose auf dem Deck neben oder unter den Bildschirmen, beim GBA im Buch und offen in Spalten links und rechts des Bildes, das über dem Falz liegt; Glas liegt nie auf dem Touchscreen oder der Division-Region. Das System legt das Sheet im Buch links vom Falz und im Tabletop unter den Falz, offen mittig.
- **Sheet nach dem Zuklappen** (Zustände 40 bis 42, hell und dunkel): DS offen gestartet, zugeklappt steht das Sheet außen über dem pausierten Spiel, aufgeklappt ist es zu und das Spiel läuft.
- **Touch in den echten Posen:** `DSTouchUITests.testEveryTapHitsItsDSPixel` offen, im Buch, im Tabletop und flach hochkant je 32 von 32 Taps im Overlay und im Fadenkreuz, kein Tastendruck (gegen ein Foto des Innendisplays, Zellmitten, siehe Stolperfallen); zugeklappt im vollen Lauf ebenso.
- **Posenprüfung** (`Scripts/pose-check.sh ds` und `gba` mit dem Build dieses Branches, eigenes Gerät, danach gelöscht): je sieben Schritte (zu, offen, Buch, Tabletop, flach hochkant, zu, offen), keine Lücke und keine Neusynchronisation in keinem Fenster, eine einzige „Game view appeared“ ohne „disappeared“, also dieselbe Szene über alle Wechsel; beim Zuklappen „Paused: folded“ mit dem Sheet außen, beim Aufklappen „Resumed“. Messzeilen DS 59,76 bis 59,92 Bilder/s, GBA 59,66 bis 59,81, 0 Aussetzer, Ton zweimal aufgefüllt (Start und Fortsetzen).

**Glas gegen flach nach dem Merge** (E9; Simulator „Arcfold Glass Duo“, Mac mini M4 Pro, Last 3 bis 4; je System erst Glas, dann flach, im selben Zeitfenster). Zwei Wege: die Messzeilen der Kategorie `stats` (alle 10 s, 7 Zeilen in rund 70 s, gestartet mit `-ArcfoldAutorun` und `-ArcfoldControlSurface glass|flat`), wie M2 gemessen hat, und `ScreenshotTour.test98MeasureGlassAgainstFlat` (60 s nach dem Anlauf, Zähler des Overlays):

| Pose | System | Messzeilen Glas: Bilder/s, Hz, übersprungen | Messzeilen flach | Tour (test98) Glas / flach: Hz, übersprungen |
| --- | --- | --- | --- | --- |
| zu hochkant | DS | 59,83 (59,71–59,93), 45–50 Hz, 28,8 % | 59,85 (59,80–59,94), 49–51 Hz, 24,3 % | 51 / 49 Hz, 27,7 / 25,4 % |
| zu hochkant | GBA | 59,77 (59,66–59,86), 44–50 Hz, 30,4 % | 59,71 (59,59–59,77), 48–51 Hz, 27,1 % | 49 / 50 Hz, 28,0 / 26,2 % |
| offen | DS | 59,82 (59,75–59,87), 48–52 Hz, 28,4 % | 59,83 (59,65–59,96), 49–51 Hz, 26,0 % | 49 / 49 Hz, 25,8 / 24,9 % |
| offen | GBA | 59,71 (59,61–59,76), 45–49 Hz, 32,0 % | 59,77 (59,65–59,90), 45–48 Hz, 30,1 % | 49 / 47 Hz, 31,2 / 28,9 % |

In allen Läufen `resync` 0, Aussetzer 0, „GPU busy“ 0, „late“ der Anzeige beim GBA 0, beim DS 4 bis 22 mit und ohne Glas. Die Emulation hält die Rate von M2 (DS 59,8, GBA 59,7 Bilder/s) mit Glas wie flach. Übersprungen liegt Glas 0,9 bis 4,5 Prozentpunkte über flach, wie vor dem Merge (+1,6 im Mittel) über der Grenze von einem Prozentpunkt; die Anzeige läuft im Simulator mit 44 bis 52 Hz und streut zwischen zwei Läufen um bis zu 2,5 Prozentpunkte. Ein erster Lauf zugeklappt unmittelbar nach der Posenprüfung, bei Last 31 bis 42, ergab für den GBA mit Glas 58,93 Bilder/s und 28,9 % gegen flach 59,92 und 26,3 %; bei Last 3 bis 4 wiederholt, lag Glas bei 59,92. Die Entscheidung bleibt beim Gerätetest (`geraetetest.md`, Teil 1b).

## Tour in jeder Pose (10. November 2026)

Nach den Nachbesserungen an Spielansicht und Bibliothek (Hinweis-Stapel, Fehleransicht, Debug-Overlay, Pause-Sheet, Titelkante, Spalten, Falz im Buch) zeigt die Tour in jeder echten Pose und jeder Variante (hell, dunkel, Kontrast erhöhen, große Schrift) den ganzen Umfang: Spiel DS und GBA mit Pausen-Sheet (30, 31), Bibliothek (32), Menü (33), Suche (34), Lizenzen (35), langer Hinweis mit Ton-Chip (36) und Fehleransicht (37). 24 Läufe (sechs Posen mal vier Varianten) auf dem Duo-Simulator, iOS 27.1, jede Pose mit dem privaten Posen-Werkzeug eingestellt. Auslöser für Hinweis, Chip und Fehleransicht sind `DebugRemote` (`notice.long`, `chip.show`) und `-ArcfoldFailStart YES` (Debug-Build). Gemessen in jeder Pose, wo es Sinn hat: Kante des großen Titels gegen die erste Kachel, Ränder des Sheets, Größe des Pause-Knopfs und seine Lage zu den Tasten, Kontrast der Beschriftungen und Kanten der Tasten, Weiß auf dem Akzent, Hinweis und Chip im Fenster, ohne Überschneidung und ohne Taste darunter.

| Pose | Fenster (pt) | Bibliothek | Titelkante, Kachel | Ränder des Sheets | Pause-Knopf | „Resume“ / „Close“ |
| --- | --- | --- | --- | --- | --- | --- |
| zu hochkant | 466 × 678 | 2 Spalten | 20 / 20 pt | 20 / 20 pt | 44 × 44, keine Taste darunter | 5,09 / 4,68–4,73 : 1 |
| zu quer | 678 × 466 | 3 Spalten | 84 / 84 pt | 96 / 96 pt | 44 × 44, keine Taste darunter | 5,09 / 4,68–4,69 : 1 |
| offen | 951 × 669 | 4 Spalten | 20 / 20 pt | 20 / 20 pt | 44 × 44, keine Taste darunter | 5,09 / 4,74 : 1 |
| Buch | 951 × 669 | 2 + 2 Spalten (Falz 455,5 bis 495,5 pt) | 20 / 20 pt | 20 / 20,3 pt | 44 × 44, keine Taste darunter | 5,09 / 4,74 : 1 |
| Tabletop | 669 × 951 | 3 Spalten | 20 / 20 pt | 20 / 20 pt | 44 × 44, keine Taste darunter | 5,09 / 4,73–4,74 : 1 |
| flach hochkant | 669 × 951 | 3 Spalten | 20 / 20 pt | 20 / 20 pt | 44 × 44, keine Taste darunter | 5,09 / 4,73–4,74 : 1 |

Hinweis und Chip stehen in jeder Pose, DS und GBA, im Fenster, ohne Überschneidung und ohne Taste darunter (Rahmen in `*-metrics.txt`). Zu hochkant: Chip (42, 104, 297 × 26) über dem Hinweis (31, 135, 320 × 52) beim DS.

**Kante der Tasten mit Kontrast erhöhen** (Grenze 3 : 1), kleinster Wert je Pose und System, nach der Gegenprüfung: zu hochkant DS 3,68, GBA 3,62; zu quer DS 3,71, GBA 4,00; offen und Buch DS 3,71, GBA 3,50; Tabletop und flach hochkant DS 3,61, GBA 3,74. Die Tasten über dem Spielbild (L und R des DS zugeklappt; L, R und Steuerkreuz des GBA zugeklappt quer) tragen dort den Rand Weiß 0,90 und messen 12,37 bzw. 12,70 : 1; mit dem Rand 0,35 waren es 2,90 bis 2,96. Die Messung tastet die Umgebung 1 bis 2 pt neben der Kante ab (zuvor 2,5 bis 4 pt): B des GBA zugeklappt quer liegt 2,7 pt neben dem Bild und zählt jetzt gegen das Deck (4,00 statt 2,96). In den vier Posen des Innendisplays ändert das keinen Wert.

**Behoben nach der Gegenprüfung** (Abweichungen 31 und 34):

1. Zugeklappt hochkant, DS, und zugeklappt quer, GBA, mit Kontrast erhöhen: Die Kante der Tasten über dem Spielbild lag bei 2,90 bis 2,96 : 1. Der Rand über dem Bild ist jetzt Weiß 0,90; `test30DSInThePose` und `test31GBAInThePose` bestehen mit Kontrast erhöhen in allen sechs Posen.
2. Zugeklappt quer, Bibliothek: Das Audit meldete „Text clipped“ für die Namen der ersten Reihe, auch bei der Standardgröße, weil es die Schrift selbst vergrößert und das Raster bei den größten Schriften drei Kacheln zu 181 pt bildete („Arc-Li…“, „fold_run-/ner“). Die Spaltenzahl folgt jetzt allein der Breite, die Kachelkunst wird niedriger. `LibraryLayoutUITests` besteht zugeklappt quer ganz, mit dem Audit und dem neuen Test der Namen bei fünf Schriftgrößen.

**Offener Befund:**

1. Im Buch läuft das Audit der Bibliothek in `LibraryLayoutUITests` in die Zeitgrenze („Audit failed to complete in time“, Code −56): in der Tour und in einem Einzellauf, auf zwei Geräten. Die übrigen 20 Tests im Buch bestehen; auf einem früheren Stand bestand das Audit im Buch in 35 s.

Die Fotos der Tour sind die Bitmaps der Anzeige; zugeklappt quer liegen sie im Bild um 90° gedreht.

**Leistung, Glas gegen flach** (`test98MeasureGlassAgainstFlat`, je 60 s nach dem Anlauf, nacheinander auf einem ruhigen Mac, eigenes Duo-Gerät): Emulation überall 59,95 bis 59,96 Bilder/s, `resync` 0, Aussetzer 0, „GPU busy“ 0, „late“ der Anzeige 0.

| Pose | System | Glas: Hz, übersprungen | flach: Hz, übersprungen |
| --- | --- | --- | --- |
| zu hochkant | DS | 50 Hz, 25,2 % | 52 Hz, 24,6 % |
| zu hochkant | GBA | 51 Hz, 24,3 % | 51 Hz, 22,4 % |
| offen | DS | 52 Hz, 24,5 % | 49 Hz, 23,6 % |
| offen | GBA | 46 Hz, 28,0 % | 51 Hz, 24,3 % |

Übersprungen liegt Glas 0,6 bis 3,7 Prozentpunkte über flach, die Emulation hält die Rate wie flach.

**Tests und Posenprüfung:** Store 365 (333 bestanden, 32 übersprungen, 0 fehlgeschlagen: ArcfoldTests 159, LibretroKitTests 64, FoldLayoutTests 31, RendererTests 39, ArcfoldUITests 72 mit 40 bestanden), JIT 293 bestanden (Stand nach der Gegenprüfung). `Scripts/pose-check.sh gba` ohne Lücke in einem Fenster eines Wechsels, nur eine Neusynchronisation nach einem Bildschirmfoto; `ds` beim dritten Lauf ohne Lücke und ohne Neusynchronisation (59,78 bis 60,00 Bilder/s, Zuklappen „Paused: folded“, Aufklappen „Resumed“). Zwei frühere Läufe des DS bei fremder Last von 20 bis 35 zeigten Lücken von 57 bis 66 ms in den Fenstern von Wechseln.

## Stolperfallen

- **`accessibilityIdentifier` auf einem Container.** **Warum:** Ohne `.accessibilityElement(children: .contain)` ersetzt die Kennung die Kennungen aller Kinder; im Sheet fand der UI-Test `resume` nicht mehr, nur noch `pause-menu`. **Anwenden:** Container-Kennung immer nach `.accessibilityElement(children: .contain)`.
- **Das Außendisplay dreht nur über die Pose.** **Warum:** Im Simulator „Arcfold Glass Duo“ (zugeklappt, iOS 27.1) meldet `XCUIDevice.shared.orientation` nach dem Setzen `.landscapeLeft`, das Fenster bleibt aber hochkant 466 × 678 pt (gemessen am 7. November 2026). Die Pose „zu, quer“ des privaten Posen-Werkzeugs dreht es, danach „zu“ wieder hochkant. **Anwenden:** Querformat über die Tour (Teil `poses`); `testSidewaysTheRButtonIsFree` und Zustand 12 überspringen sich nur, wenn das Fenster hochkant bleibt.
- **XCUITest auf dem Innendisplay.** **Warum:** Offen, im Buch und im Tabletop meldet die App ihren Rahmen in der aufrechten Lage des Innendisplays (669 × 951 pt für ein Fenster von 951 × 669), und Taps relativ zur App kamen nie an; `XCUIScreen.main` ist das Außendisplay, das Innendisplay ein zweiter Eintrag in `XCUIScreen.screens`, und dessen Bildschirmfoto hat die Pixel des Displays aufrecht mit der Drehung als Ausrichtung und ist mit 2852 × 2006 einen Pixel kleiner als der View (2853 × 2007), also nachgerechnet (gemessen am 7. November 2026). **Anwenden:** Tippen relativ zum Fenster (`app.viewOrigin`), fotografieren mit `app.displayScreenshot()`, Pixel mit `XCUIScreenshot.uprightImage` lesen und in einem nachgerechneten Foto Zellmitten statt Zellkanten prüfen (`UITestSupport`, `DSTouchUITests`).
- **Debug-Overlay über dem Touchscreen.** **Warum:** Im Buch und offen beginnt der Touchscreen des DS neben der Ecke des Overlays; dessen Karte mit Schwarz 0,6 dunkelte die obere Zeile ab, das Fadenkreuz des Touch-Tests las Rot als (100, 0, 0). **Anwenden:** `OverlayPlacement` lässt die Zeilen vor einem Touchscreen umbrechen, der daneben beginnt (`theDebugOverlayStaysOffTheTouchScreen`).
- **`CFBundleIconName` liegt verschachtelt.** **Warum:** Mit einer `.icon`-Datei schreibt der Asset-Compiler den Schlüssel unter `CFBundleIcons` → `CFBundlePrimaryIcon`. **Anwenden:** `DesignAssetsTests` liest ihn dort.
- **Negative Rahmen beim ersten Layout.** **Warum:** Beim ersten Durchlauf meldet `GeometryReader` die Größe 0; `debugMaxWidth` wurde negativ, und XCTest meldete „Invalid frame dimension (negative or non-finite)“. **Anwenden:** Breiten aus `OverlayPlacement` sind auf 0 begrenzt.
- **Monogramm als Text.** **Warum:** Auch mit `.accessibilityHidden(true)` blieb das Monogramm im Button der Kachel ein Textelement, und das Audit meldete „Dynamic Type font sizes are partially unsupported“. **Anwenden:** Das Monogramm wird im `Canvas` gezeichnet.
- **Texte in Glas und das Audit.** **Warum:** `performAccessibilityAudit` sieht die Beschriftungen der Touch-Tasten trotz `.accessibilityElement(children: .ignore)` und `.accessibilityHidden(true)` als Texte und meldet ihren Kontrast über Glas als „failed“, obwohl die Pixel 3,8 : 1 und mehr zeigen. Im Sheet meldete es „Quit Game“ in manchen Läufen als „failed“ (Pixel 5,5 : 1). **Anwenden:** Der Kontrast der Tasten wird in Pixeln gemessen (Tour, Seite 14); im Audit-Test gelten Befunde auf den Tasten (`touch-button-<Taste>`, `touch-pad`, Kennungen mit `touch-`) und auf `debug-overlay` als zulässig, seit dem Merge nicht mehr alles in `touch-controls`, das bei M2 die ganze Bühne deckt; im Sheet ein „failed“ nur, wenn die Pixel ≥ 4,5 : 1 ergeben, und „nearly passed“ bei Systemfarben (sekundäre Labels, Weiß auf Indigo im dunklen Modus).
- **Sheet mit `.medium` und großer Schrift.** **Warum:** Das Audit vergrößert die Schrift; ohne Scrollen wurden „Debug Overlay“ und „Quit Game“ abgeschnitten gemeldet. **Anwenden:** Der Inhalt des Sheets steht in einer `ScrollView` mit `.scrollBounceBehavior(.basedOnSize)`.
- **Sekundäre Schrift im Sheet über dem Spiel.** **Warum:** Das Sheet-Glas lässt das Spiel durch; der Spielname in `.secondary` fiel im Audit durch. **Anwenden:** Spielname in Primärfarbe, `.subheadline.weight(.medium)`.
- **Schalter im UI-Test.** **Warum:** Ein kurzer Tipp schaltet einen Schalter im Simulator oft nicht um (Fatihs Notiz). **Anwenden:** `GlassUITestCase.flip(_:)` drückt 0,15 s auf das rechte Ende der Zeile und wartet auf den neuen Wert.
- **Rand nach `.glassEffect` im Container.** **Warum:** In einem `GlassEffectContainer` liegt ein `.overlay`, das nach `.glassEffect` kommt, unter dem Glas; der Rand von Kontrast erhöhen fehlte an Tasten und Hinweisen, am Pause-Knopf ohne Container war er da (gemessen). **Anwenden:** Rand und Ring als Inhalt des Glases zeichnen, also das Overlay vor `.glassEffect`, wie die Beschriftung.
- **Glas unter einem Sheet.** **Warum:** Das Glas des Sheets zeichnet die Lichtkanten der Tasten darunter als helle Flecken. **Anwenden:** Solange das Pausen-Sheet offen ist, sind die Tasten ausgeblendet, das Deck bleibt.
- **Text in einem festen Rahmen.** **Warum:** `Text` kürzt auf die angebotene Höhe; der Anker des Hinweises ist 72 pt hoch. **Anwenden:** Hinweis und Chip mit `.fixedSize(horizontal: false, vertical: true)`, der Anker richtet nur die Unterkante aus.
- **Breite mit Systemspalte.** **Warum:** Neben der Spalte ist die `ScrollView` der Bibliothek 382 pt breit, ihr `GeometryProxy` meldet die Spalte als `safeAreaInsets.trailing` 84; ein Hintergrund mit `.ignoresSafeArea()` reicht nicht in die Spalte (gemessen 382). **Anwenden:** Breite plus Unterschied der seitlichen Einzüge; gleiche Einzüge auf beiden Seiten (quer) ändern nichts.
- **`ContentUnavailableView` im Audit.** **Warum:** Das Audit meldet für Titel, Text und Knopf „Dynamic Type font sizes are partially unsupported“; bis accessibility-large wächst der Text sichtbar mit. **Anwenden:** Auf der Fehlerseite gilt der Befund als Grenze des Systems; Hinweis und Chip begrenzen ihre Größe selbst (accessibility2).
- **Hinweis und Chip bei großer Schrift.** **Warum:** In der ersten Fassung deckte der nach oben wachsende Hinweis ab accessibility-large einen dreizeiligen Ton-Chip oben links zum Teil zu (Seite 17). Seit Abweichung 26 liegt der Chip in jeder Pose über dem Hinweis auf dem Bild, frei von Tasten, und in einem Bild unter 138 pt Höhe oben (`OverlayPlacement`). **Anwenden:** Hinweise, Chip und Debug-Overlay nur über `OverlayPlacement` legen, nie mit festen Ankern; große Schrift in der Tour (Variante `large`, Seite 17) ansehen.
- **Messungen unter Last.** **Warum:** Während der Messungen liefen weitere Builds und Tests auf demselben Mac; die Last des Macs lag zeitweise über 200, und ein Echtzeit-Test der Kernsitzung fiel einmal mit 2,6 Bildern/s durch (beim Wiederholen grün). **Anwenden:** Glas gegen flach immer im selben Zeitfenster und nur relativ vergleichen; die Entscheidung fällt auf dem Duo.
