# 0007 · Oberfläche mit Liquid Glass

Status: Vorgeschlagen · 7. November 2026 (aus M4 vorgezogen, umgesetzt am selben Tag; am 10. November 2026 auf den bereinigten Verlauf von M2 gelegt, Abschnitt „Zusammenführung mit M2“; seit der Abnahme von M2 am 10. November 2026 liegt der Branch `m4/liquid-glass` auf `main` und kommt als eigener Pull Request gegen `main`; Abnahme durch Fatih und Gerätetest ausstehend)

## Kontext

- Der Plan sieht die Liquid-Glass-Oberfläche in M4 · Feinschliff vor (Abschnitt 10). M1 hat die Laufzeit gebaut und die Oberfläche bewusst schlicht gelassen: eine Listenzeile in der Bibliothek, flache graue Tasten, ein Materialkasten als Pausenmenü, eine schwarze Kapsel für Hinweise.
- Am 7. November 2026 hat Fatih die Oberfläche vorgezogen („iOS 27 bitte mit Liquid Glass Elementen“). Die App soll wie eine echte iOS-27-App wirken. Wo das System eine Lösung hat, gilt sie (native first).
- M2 (DS am Falz) läuft parallel und baut `GameView`, `TouchControls`, `TouchLayout`, `GameSystem`, `Game`, `GameLibrary`, `DebugLaunch` und `LicenseCatalog` um. Lage und Trefferlogik der Tasten, Modell, Import, LibretroKit, Renderer und `PlaySession` bleiben deshalb unverändert. `GameView` und `TouchControls` werden nur örtlich geändert.
- Das SDK setzt die Grenzen (iOS-SDK 27.2, `.swiftinterface` und `.swiftdoc` von SwiftUI und SwiftUICore):
  - Glas gibt es seit iOS 26: `glassEffect(_:in:)`, `Glass.regular`, `.clear`, `.identity`, `GlassEffectContainer`, `glassEffectID`, die Knopfstile `.glass`, `.glass(_:)` (26.1) und `.glassProminent`. iOS 27 bringt keine neuen Glas-APIs.
  - Neu und hier wichtig sind `systemPrefersReducedResourceUsage` und `.crossFade` (27.0) sowie die senkrechte Systemleiste mit `toolbarVerticalBehavior` (27.1).
  - Laut Doku passt `.regular` seinen Inhalt an die Helligkeit darunter an. `.clear` tut das nicht und verlangt eine Abdunklung unter dem Glas. `.identity` zeichnet den Inhalt, als gäbe es kein Glas.
  - `interactiveDismissDisabled(_:)` ist nur für Popover, Sheets und Inspektoren dokumentiert, nicht für den Zoom einer `fullScreenCover`.
- Messungen am Simulator „Arcfold Glass Duo“ (zugeklappt, iOS 27.1, Probe-App außerhalb des Repos):
  - Zwei Toolbar-Einträge in `.primaryAction` werden in der Systemspalte eine gemeinsame Glaskapsel. `.searchable` mit `.minimize` liegt unten in der Spalte.
  - Ein Sheet mit `.medium` bekommt Systemglas und wächst per Zoom aus dem Knopf. Dabei erscheint die Statusleiste in der Spalte.
  - Weiße Schrift auf `.regular` und auf ungedämpftem `.clear` ist über hellen Spielbildern kaum lesbar. Mit Abdunklung bleibt sie lesbar.
  - `toolbarVerticalBehavior(.disabled)` macht die Spielansicht 466 statt 382 pt breit (GBA 5× statt 4×).
  - Eine Icon-Composer-Datei `.icon` und ein `AccentColor` mit Systemreferenz bauen mit XcodeGen 2.45.4 und Xcode 27.2 ohne Warnung.
- Zwei Fehler aus M1 kamen dabei ans Licht. Quer überdeckt der Pause-Knopf die Taste R. Hochkant liegt der Hinweis über Select und Start und nimmt dort Berührungen an.

## Optionen

1. **Apple-nah:** Systemkomponenten liefern das Glas, auch das Pausenmenü als Sheet. Eigenes Glas gibt es nur an Tasten, Pause und Hinweisen. Über Schwarz liegt `.regular`, über dem Bild „Rauchglas“ (`.clear` mit schwarzer Tönung). Die Kacheln sind Monogramme auf einer Systemfarbe.
   - Vorteil: am nächsten am System, die Kernannahmen sind gemessen.
   - Nachteil: Die Tasten über Schwarz sehen kaum anders aus als in M1. Die Kacheln sind schlicht.
2. **Spielgefühl:** Die Spielansicht steht im Mittelpunkt. Hochkant liegt ein Gehäuse in der Spielfarbe mit Lichtern, im Steuerkreuz wandert ein Lichtpunkt, und Tasten federn beim Loslassen. Das Pausenmenü ist ein eigenes Glaspanel, das per `glassEffectID` aus dem Pause-Knopf wächst. Ein Zoom führt von der Kachel ins Spiel, der Akzent ist ein eigenes Violett.
   - Vorteil: am auffälligsten.
   - Nachteil: am meisten Eigenbau, darunter Modalität, Fokus und Escape des Panels. Der Morph eines Knopfstils ist nicht dokumentiert, der Zoom ins Cover kann sich mit den Tasten ins Gehege kommen, und Federn erzeugen bei jedem Druck Phasen mit 120 Hz.
3. **Gestaltungssystem:** Es gibt zwei Gläser mit festen Rollen. Systemglas gilt außerhalb des Spiels, Spielglas (`.clear` über einer Dimmplatte) im Spiel. Die Spielansicht ist in Zonen geteilt (Bild, Deck, Spalte, Falz), der Druck kommt ohne Animation aus der Maske. Kacheln entstehen aus der SHA-256 der Datei, es gibt einen flachen Rückfall über `Glass.identity` und Tokens je Breitenklasse.
   - Vorteil: klare, prüfbare Regeln und leichter Merge.
   - Nachteil: Das Pausen-Panel ist ebenfalls Eigenbau, und für den Rückfall gibt es eine eigene Regel mit Wärme- und Stromsparschwellen, obwohl das System dafür eine API hat.
4. **Nichts vorziehen:** Die Oberfläche bleibt bis M4, wie sie ist. Das widerspricht Fatihs Auftrag.

## Entscheidung

Option 3 ist die Grundlage. Aus Option 1 kommen das System-Sheet und die Toolbar dazu, aus Option 2 die iOS-27-APIs und die Fehlerbehebungen. Regeln, Bausteine, Maße und Abweichungen stehen in `docs/wissen/oberflaeche.md`.

Die Punkte 1, 3, 4 und 8 beschreiben Glastasten, Deck und Platten im laufenden Spiel; das ist der Stand vom 7. November 2026 und seit dem 11. November 2026 durch den Abschnitt „Konsole statt Glastasten“ abgelöst: Glas liegt im Spiel nur noch über dem Bild, die Tasten sind Kappen eines Gehäuses.

1. **Zwei Gläser.**
   - *Systemglas:* Toolbar, Menüs, Suche, Zurück, Alerts, Dateiauswahl und Pausen-Sheet tragen ihr Glas vom System. Eigener Code setzt dort kein `glassEffect`.
   - *Spielglas:* Touch-Tasten, Pause-Knopf, Hinweis und Ton-Chip (seit dem 11. November 2026 nur noch, was über dem Bild liegt) sind `Glass.clear` mit einer Dimmplatte darunter (Grau `Color(white: 0.15)` mit 70 %, bei kleiner Schrift 80 %; IC 80/90 %). So bestimmt das Spielbild nie, wie eine Taste aussieht. Geplant waren 60/70 % (IC 75/85 %); die Tour hat über Weiß 2,9 : 1 und 3,8 : 1 gemessen, deshalb liegen beide Platten 0,1 höher (siehe „Umsetzung“).
2. **Kein Glas auf Inhalt** (Spielbild, Kacheln, Listen, Lizenztexte, Debug-Overlay) und kein Glas auf Glas. Im Sheet stehen deshalb `.borderedProminent` und `.bordered`. Das Debug-Overlay bleibt ohne Glas, damit es die Werte nicht verfälscht, die es misst.
3. **Touch-Tasten:** Sie werden aus dem unveränderten `TouchLayout` gezeichnet, auf einer Ebene ohne Treffer in einem `GlassEffectContainer(spacing: 0)`. Darüber liegt eine durchsichtige Eingabeschicht mit der unveränderten `SpatialEventGesture`. Der Druck kommt nur aus der Maske, die an die Sitzung geht, sofort und ohne Animation. Das Steuerkreuz zeigt ihn als Sektor in der Spielfarbe unter dem Glas. `.interactive()` wird nicht benutzt. Seit dem Merge mit M2: das `TouchLayout` aus den Zonen von `GameLayout`, die Eingabe über `TouchSurface` und `TouchRouter` von M2, die Platte je Taste nach dem, was darunter liegt. Seit dem 11. November 2026 sind die Tasten neben und unter den Bildschirmen Kappen des Gehäuses ohne Glas; die Eingabe bleibt, wie sie war.
4. **Deck:** Hochkant liegt hinter den Tasten ein ruhender Schimmer in der Spielfarbe. Quer liegen die Tasten vor dem Merge über dem Bild. Seit dem Merge mit M2 liegt das Deck hinter jeder Tastenzone, die keinen Bildschirm deckt, in jeder Pose (`DeckLayout`). Seit dem 11. November 2026 ersetzt das Gehäuse das Deck (`ControlDeck` und `DeckLayout` sind entfallen).
5. **Pausenmenü:** Es ist ein System-Sheet mit `.medium`, das per `matchedTransitionSource` und `.zoom` aus dem Glas-Pause-Knopf wächst, bei Bewegung reduzieren mit `.crossFade`. Ein eigener `@State` steuert es, weil `setUserPaused` über die Warteschlange der Sitzung läuft. Wegwischen setzt fort. „Quit Game“ schloss in der ersten Fassung erst das Sheet und dann das Cover (seit M2 gibt es kein Cover mehr, siehe unten). „Show/Hide Debug Overlay“ wird ein Toggle. Seit dem Merge mit M2 folgt das Sheet `showsPauseMenu` (von Hand pausiert oder zugeklappt), steht auch außen nach dem Zuklappen und schließt sich beim Aufklappen; „Resume“ ruft `resumeFromMenu()`, „Quit Game“ beendet über `quit()`, und `RootView` bringt die Bibliothek zurück.
6. **Lage:** Eine reine Funktion `OverlayPlacement` legt fest, wo Pause, Hinweis und Debug sitzen. Quer liegt Pause oben in der Mitte, das behebt die überdeckte Taste R. Hinweise stehen im Bildbereich und nehmen keine Treffer an, das behebt den Hinweis über Select und Start. Seit dem Merge mit M2 ist sie eine Funktion von `GameLayout`: Pause, wo `GameLayout` ihn hinlegt, Hinweise und Chip auf dem oberen oder einzigen Bildschirm.
7. **Bibliothek:**
   - Ein Raster aus Kacheln ohne Cover: `GameStyle` aus der SHA-256 (zehn Paare aus Systemfarben, vier Muster, Monogramm), gezeichnet als `MeshGradient`.
   - In der Toolbar liegen „More“ (Sortierung, Licenses, Cores) und Import als eine Glaskapsel. Die Suche gibt es nur, wenn Spiele da sind. Sortieren und Suchen sind reine Ansichtslogik.
   - Dieselbe Spielfarbe färbt Ladebild, Deck, gedrückte Tasten und den Kopf des Pausen-Sheets.
8. **Rückfall:** Ist `systemPrefersReducedResourceUsage` wahr, wird das Spielglas `Glass.identity` und sieht aus wie in M1, ohne anderen View-Baum. Im Debug-Build schaltet `-ArcfoldControlSurface flat|glass` für A/B-Messungen um (seit dem 11. November 2026 nur noch für das, was über dem Bild liegt).
9. **Akzent und Icon:** Der Akzent ist `systemIndigo` als `AccentColor` mit Systemreferenz im Asset-Katalog. Das App-Icon ist eine Icon-Composer-Datei `App/Resources/AppIcon.icon` mit eigenem Motiv (Bogen mit Falz-Fuge, ein Pixel springt darüber), ohne Eintrag in `project.yml`.
10. **Bedienungshilfen:**
    - `accessibilityDirectTouch(options: .silentOnTouch)` macht die Tastenfläche mit VoiceOver spielbar.
    - Hinweise werden per `AccessibilityNotification.Announcement` angesagt.
    - Das Spielbild und die Kachelkunst sind mit `accessibilityIgnoresInvertColors()` vor dem intelligenten Umkehren geschützt.
    - Bei Kontrast erhöhen, Rahmen anzeigen und Transparenz reduzieren werden Platten und Ränder angepasst. Die Bibliothek zeigt ab den großen Schriftgrößen eine Spalte.
11. **Zoom von der Kachel ins Spiel:** Er kommt nur, wenn ein UI-Test belegt, dass ein Zug nach unten über die Tasten das Spiel nicht schließt. Geändert mit dem Merge mit M2 (E3): Er entfällt. Ein Spiel ersetzt die Bibliothek im Fenster (`RootView`), es gibt keine Präsentation und damit keinen Zoom des Systems; ein eigener Morph ersetzt ihn nicht, weil er Modalität und Übergänge selbst bauen müsste und eine Präsentation über der Bibliothek die Ursache des Fehlers mit verschluckten Berührungen oben war (ADR 0006).
12. **Abnahme über eine ScreenshotTour:**
    - Ein UI-Test fuhr in der ersten Fassung 18 Zustände an (heute 22, dazu 30, 31, 98 und 99; `docs/wissen/oberflaeche.md`), echte Abläufe und Seiten einer Galerie (nur Debug), und legt die Bildschirmfotos als Anhänge mit `.keepAlways` ab.
    - `Scripts/screenshot-tour.sh` fährt die Varianten hell, dunkel, Kontrast und große Schrift und exportiert die Bilder mit `xcresulttool`. Seit M2 stellt es dazu jede echte Pose des Duo mit dem privaten Posen-Werkzeug ein (Teil `poses`) und führt darin in allen vier Varianten Spiel, Bibliothek, Menü, Suche, Lizenzen, Hinweise und Fehleransicht aus.
    - Messwerte: Kontrast der Beschriftungen aus Pixeln (≥ 3 : 1, Select/Start ≥ 4,5 : 1), Schnitt von Pause und R gleich 0, Spaltenzahl der Bibliothek und ein Audit der Bedienungshilfen.

Nicht übernommen wurden:

- das eigene Morph-Panel (das System hat das Sheet),
- das eigene Violett (`systemIndigo` passt sich selbst an),
- die Wärme- und Stromsparregel (dafür gibt es `systemPrefersReducedResourceUsage`),
- Federn, Skalierung und Lichtpunkt beim Druck (Latenz, 120-Hz-Phasen),
- `.regular` über Schwarz (kaum Unterschied zu M1),
- animierte Hintergründe sowie Parallaxe und Randeffekte im Raster,
- `GCVirtualController` und `TouchController` (nicht falzfähig, sie ersetzten `TouchLayout`).

## Umsetzung (7. November 2026)

Die Abschnitte „Umsetzung“, „Nachbesserungen“ und „Zusammenführung mit M2“ sind der Verlauf bis zum 10. November 2026 und beschreiben Glastasten auf einem Deck; was davon im Spiel noch gilt, steht im Abschnitt „Konsole statt Glastasten“.

Erste Fassung auf dem Stand von `main` vor M2, 15 Commits (die Zahlen dieses Abschnitts und der „Nachbesserungen“ sind die von damals; sie gelten für diesen Branch nur, soweit der Abschnitt „Zusammenführung mit M2“ sie nicht ersetzt); geprüft im Simulator „Arcfold Glass Duo“ (zugeklappt, iOS 27.1) mit Xcode 27.2.

- **Builds:** Store und JIT für den Simulator, Store für `generic/platform=iOS` ohne Signatur, alle ohne Warnung (nur die bekannte Zeile von `appintentsmetadataprocessor`). Jeder Commit hat Store und JIT gebaut und den ganzen Store-Testlauf bestanden; nur `fix(design): meet the measured contrast …` ist allein nicht geprüft, sondern zusammen mit dem folgenden Test-Commit. Ein Echtzeit-Test der Kernsitzung fiel einmal unter Last des Macs (über 200) mit 2,6 Bildern/s durch und war beim Wiederholen grün.
- **Tests:** Store 180 (159 bestanden, 21 übersprungen, 0 fehlgeschlagen; M1: 136), JIT 148 bestanden (M1: 130). Neu sind 44 im Store, davon 18 auch im JIT: `DesignAssetsTests` 2, `GameStyleTests` 6, `LibraryArrangementTests` 6, `OverlayPlacementTests` 4, `GlassUITests` 6, `ScreenshotTour` 20. Übersprungen werden die 20 Zustände der Tour (sie laufen über `Scripts/screenshot-tour.sh`) und `testSidewaysTheRButtonIsFree`, weil das Fenster des zugeklappten Duo im Simulator nicht dreht.
- **Tour** (`Scripts/screenshot-tour.sh`, Varianten hell, dunkel, Kontrast, große Schrift): alle Zustände außer 12 (Sheet quer, Fenster dreht nicht); Zustand 11 ist eine Galerie-Seite mit den Teilen der Spielansicht, um 90° gedreht.
  - Pause hochkant 47 × 47 pt (Layout 48); auf der gedrehten Galerie-Seite 45 pt, weil sie auf 0,95 verkleinert ist. Pause ∩ R quer = 0 belegt `OverlayPlacementTests`.
  - Bibliothek außen 2 Spalten (große Schrift 1), innen 3.
  - Kontrast der Beschriftungen in Pixeln (Seite 14, Mindestwert über Weiß und Testmuster): in Ruhe A, B, R 3,84, L 3,81, Steuerkreuz 3,25, Select und Start 5,10; gedrückt A, B, R 4,00, L 3,95, Steuerkreuz 4,40, Select und Start 6,13. Mit Kontrast erhöhen liegt jeder Wert über 10 : 1. Mit den geplanten Platten (0,60 / 0,70) waren es 2,9 und 3,8 : 1; deshalb wurden sie um 0,1 angehoben, gedrückt auf 0,95 gesetzt und die ruhenden Pfeile auf Weiß 0,85.
  - Audit der Bedienungshilfen ohne unbegründeten Befund (Ausnahmen in `docs/wissen/oberflaeche.md`).
  - Zwei Läufe hintereinander: 15 von 18 hellen Bildern pixelgleich und dieselben Messwerte; nur die Bilder mit laufendem Spiel (08, 09, 10) unterscheiden sich im Bild und in den Zahlen des Overlays.
- **Glas gegen flach** (Simulator, hochkant, je 60 s, drei Läufe): Anzeige im Mittel 49,3 gegen 49,7 Hz (Grenze ≤ 2 Hz erfüllt), übersprungen 27,7 % gegen 26,1 % (+1,6 Prozentpunkte, Grenze ≤ 1 verfehlt), „late“ der Anzeige, „GPU busy“ und `resync` 0. Ein Versuch mit flachem Pause-Knopf und Tasten aus Glas lag auf dem Niveau von flach: Es kostet das Glas des Pause-Knopfs über dem `CAMetalLayer`. Die Grenze ist für den Simulator begründet abgeschwächt (dort rendert der Mac, die Anzeige läuft nur mit 46–51 Hz); der Gerätetest entscheidet, und fällt er durch, wird der Pause-Knopf über dem Bild flach (`docs/wissen/oberflaeche.md`).
- **Messung wie in M1** (`selftest.gba`, 60 s, Debug-Build, Werte nach 60 s): vorher (M1) Emulation 59,72 Bilder/s, resync 0, Display 47 Hz, 2676 gezeigt und 936 übersprungen (25,9 %), Display-late 0, Emulation-late 2107; nachher (Glas) 59,58 Bilder/s im letzten Fenster (59,71–59,81 davor), resync 0, Display 47 Hz, 2642 gezeigt und 959 übersprungen (26,6 %), Display-late 0, Emulation-late 2230. Die Last des Macs lag vorher bei über 200, nachher bei 5 bis 140 (parallele Builds und Tests von M2); „late“ der Emulation zählt verspätetes Aufwachen des Emulations-Threads und ist im Simulator schon in M1 hoch.
- **Zoom von der Kachel ins Spiel** ist umgesetzt, weil `testDraggingDownOverTheControlsKeepsTheGame` mit dem Zoom grün ist; ein Zug über das Bild schließt das Spiel ebenfalls nicht.
- **Abweichungen** vom Entwurf stehen mit Grund in `docs/wissen/oberflaeche.md`, Abschnitt „Abweichungen vom Entwurf“.
- **Offen:** Kontrast von Weiß auf dem Indigo des „Resume“-Knopfs im dunklen Sheet: 3,5 : 1, mit Kontrast erhöhen nur 2,1 : 1, weil `systemIndigo` dann heller wird (Frage an Fatih: Systemfarbe behalten oder Akzent mit eigener dunkler Variante im Asset). Nach der Prüfung umgesetzt, siehe unten.

## Nachbesserungen nach der Prüfung

Die 15 Commits wurden am 7. November 2026 unter drei Gesichtspunkten geprüft (Gestaltung, Regeln, Funktion). Bestätigt und behoben:

- **Rand bei Kontrast erhöhen:** Im `GlassEffectContainer` lag das `.overlay` nach `.glassEffect` unter dem Glas; Tasten und Hinweise hatten keinen Rand, nur der Pause-Knopf ohne Container. Rand und der Ring für „Ohne Farbe unterscheiden“ sind jetzt Inhalt des Glases, wie die Beschriftung. Der Ring ist reines Weiß wie die Beschriftung, mit Weiß 0,9 lag er über der Spielfarbe von selftest einmal bei 2,96 : 1. Neue Galerie-Seite `touch-differentiate`.
- **Hinweis bei großer Schrift:** ab den Bedienungshilfe-Größen ohne Zeilengrenze und mit eigener Höhe, er wächst vom unteren Anker nach oben. Der Ton-Chip hält wie der Hinweis bei accessibility2 an und ist ein abgerundetes Rechteck, damit umbrochener Text im Glas bleibt.
- **Weiß auf Indigo:** `AccentColor` bleibt hell die Systemreferenz `systemIndigo`. Dunkel gelten dessen helle Werte, `#6155F5`, mit Kontrast erhöhen `#564ADE`. Das betrifft „Resume“, „Close“ und „Import Games“. `DesignAssetsTests` prüft Weiß darauf in allen vier Erscheinungen auf mindestens 4,5 : 1.
- **Pausen-Sheet mittig:** Bei `.medium` hochkant ignoriert der Inhalt den Einzug der Systemspalte; über ihm steht die Statusleiste, darunter hält die Spalte nichts. Bei `.large` bleibt der Einzug. Ausnahme von R6, begründet in `docs/wissen/oberflaeche.md`.
- **Tasten unter dem Sheet:** Solange das Sheet offen ist, blendet die Tastenkunst aus, das Deck bleibt. Ihr Glas schien sonst als Flecken durch das Glas des Sheets.
- **Raster am Titel:** Der Rand folgt der Breite mit Systemspalte (466 pt, also 20 pt), Spalten und Kacheln weiter der Breite des Rasters.
- **Fehleransicht:** Die Kachelkunst als Hintergrund ist mit Schwarz 0,65 statt 0,45 abgedunkelt, für die Fehlermeldung in sekundärer Systemschrift und das Ladebild.
- **Ton-Chip quer:** eigener Anker `chipAnchor` über den Hinweisen unten in der Mitte, frei von allen Tasten samt Zugabe und Reichweite des Steuerkreuzes (`OverlayPlacementTests`). Hochkant bleibt er unter dem Debug-Overlay. Dabei fiel auf: Das Debug-Overlay nahm Treffer an und hätte quer Berührungen auf L geschluckt; jetzt `.allowsHitTesting(false)` wie jede Überlagerung (R6).
- **Glas über dem Deck:** Platte 0,35 bzw. 0,45 bei kleiner Schrift statt 0,70 / 0,80; über dem Bild, mit Kontrast erhöhen und mit Transparenz reduzieren bleibt sie, wie sie war. Das Glas bricht jetzt den Schimmer der Spielfarbe.
- **Deck-Schimmer:** blendet oben über 8 % der Höhe ein, statt hart anzusetzen.
- **Merge mit M2:** Die Überlagerungen stehen in `Play/GameOverlays.swift` und nehmen einfache Werte. `GameView` ruft sie einmal auf, die Galerie zeigt dieselben ohne Sitzung. `GameView` hat jetzt 144 statt 210 Zeilen wie auf `main` (Diff +53 / −119, vorher +59 / −96).
- **Doku:** `docs/wissen/app.md` beschreibt `TouchControls` als meldend, gezeichnet wird in `TouchControlsArt`.
- **Tests:** Das Audit läuft zusätzlich auf den Seiten `notices` und `failure` und in der Tour mit dunkel und mit Kontrast erhöhen. „Contrast nearly passed“ gilt nicht mehr für Weiß auf dem Akzent, ein Kontrastbefund nur noch, wenn die Pixel des Elements mindestens 4,5 : 1 ergeben. Neue Messwerte der Tour stehen in der Tabelle.

**Belege** (Simulator „Arcfold Glass Duo“, zugeklappt, iOS 27.1, Xcode 27.2)

| Prüfung | Ergebnis |
| --- | --- |
| Builds | Store und JIT für den Simulator, Store für `generic/platform=iOS` ohne Signatur: ohne Warnung (nur die bekannte Zeile von `appintentsmetadataprocessor`) |
| Tests | Store 186 (163 bestanden, 23 übersprungen, 0 fehlgeschlagen), JIT 152 bestanden; vor der Prüfung Store 180 mit 21 übersprungenen, JIT 148. Neu sind `GamePlateTests` (2), `DesignAssetsTests.whiteReadsOnTheAccent` und `OverlayPlacementTests.theStatusChipCoversNoButton` (heute `theStatusChipStaysOnThePictureAboveTheNotices`); die Tour hat 22 statt 20 Tests und überspringt sich im normalen Lauf |
| Tour | alle vier Varianten grün, das Audit auch mit dunkel und mit Kontrast erhöhen; die Messwerte stehen in `docs/wissen/oberflaeche.md`, „Nachbesserungen nach der Prüfung“ |
| Messung wie in M1 | Glas 59,65 und 59,79 Bilder/s, übersprungen 28,0 und 26,2 %; flach 59,82 Bilder/s und 24,7 %; resync, „late“ der Anzeige und „GPU busy“ überall 0, kein Rückschritt gegenüber der Messung oben |
| Commits | neun, geprüft im Ganzen (Builds, Tests, Tour), nicht jeder einzeln |

Nicht geändert, weil es kein Mangel ist: die Messung wie in M1 (kein Rückschritt, siehe Tabelle) und die grünen UI-Tests für Pause, Fortsetzen, Debug-Overlay und Beenden. Offen blieben damals Querformat und Mehrfachberührung mit Glas: Das Fenster des zugeklappten Duo drehte im Simulator nicht (seit E8 erreichbar), zwei Finger gehen dort nur von Hand. Beides steht als G1 bis G5 im Gerätetest (`docs/wissen/geraetetest.md`, Teil 1b), ebenso Glas gegen flach (seit dem 11. November 2026 ersetzt der Gerätetest der Konsole diesen Vergleich). `CLAUDE.md` und `docs/wissen/app.md` wurden mit M2 zusammengeführt.

## Nachbesserungen nach der Prüfung der Gestaltung

Am 10. November 2026 wurden die Befunde der Prüfung der Gestaltung auf dem Stand dieses Branches behoben, als zwei Pakete (Spielansicht, Bibliothek), je mit Unit-Test über alle Geometrien des Duo und UI-Test in den echten Posen (Einzelheiten und Tests: `docs/wissen/oberflaeche.md`, Abweichungen 30 bis 33):

- **Spielansicht:** Fehleransicht auf einem Bildschirm außerhalb des Falzes; Hinweis und Ton-Chip als ein Stapel in einem Glascontainer, bei großer Schrift mit der größten passenden Schriftgröße; Debug-Overlay aus freien Rechtecken, nie auf einer Taste; Pausen-Sheet mit gleichen Rändern; Glas des Pause-Knopfs im Container der Tasten.
- **Bibliothek:** Raster an den Systemrändern in jeder Pose (20 / 20 pt, zu quer 84 / 84 pt), Spaltenzahl nach der Breite, die Kachelkunst niedriger, wo das Fenster für 4 : 3 zu niedrig ist, im Buch zwei Seiten links und rechts des Falzes, Lizenzen mit Liste und Text nebeneinander.
- **Nach der Gegenprüfung:** Die Spaltenzahl der Bibliothek folgt allein der Breite; zugeklappt quer hatte die Höhenregel bei den größten Schriften drei Kacheln zu 181 pt mit gekürzten Namen ergeben. Mit Kontrast erhöhen ist der Rand einer Taste über dem Spielbild Weiß 0,90 statt 0,35 (Kante 12,4 bis 12,7 statt 2,9 : 1), über dem Deck blieb damals 0,35 (seit der zweiten Runde 0,90 für alle Tasten, siehe „Nachbesserungen nach der Gegenprüfung“).
- **Tour:** läuft jetzt in jeder echten Pose und jeder Variante über alle Zustände, auch Bibliothek, Menü, Suche, Lizenzen, langer Hinweis mit Ton-Chip und Fehleransicht (24 Läufe, Ergebnis und offene Befunde in `oberflaeche.md`, „Tour in jeder Pose“).
- **Entfallen:** Der Test mit dem Debug-Overlay über L, weil das Overlay keine Taste mehr deckt.

## Zusammenführung mit M2

Stand 10. November 2026. Die Oberfläche (Stand vom 7. November 2026, zusammengeführt mit dem damaligen Stand von M2) wurde ohne ihren früheren Verlauf auf `m2/ds-falz` gelegt (M2 · DS am Falz, ADR 0006, im Duo-Simulator geprüft): Branch `m4/liquid-glass`, wenige Commits nach Thema, kein Merge-Commit. Am selben Tag nahm Fatih M2 anhand des Pull Requests ab, M2 liegt auf `main`; der Branch liegt seitdem direkt auf `main` und geht als eigener Pull Request gegen `main`, die Abnahme der Oberfläche steht aus; die Konflikte sind nach E1 bis E5 gelöst. „Zusammenführung“ heißt in diesem Abschnitt, dass Glas auf der Architektur von M2 sitzt. Der bereinigte Verlauf von M2 brachte Änderungen, die hier einflossen: die Lizenztexte, das private Posen-Werkzeug nur über `POSE_CHECK_POSTURE_TOOL` und die fensterbezogenen Test-Helfer für das Innendisplay (`app.gameWindow`, `app.viewOrigin`, `app.displayScreenshot()`, `XCUIScreenshot.uprightImage`), die auch die Glas-Tests und die Tour nutzen. Geprüft auf einem Duo-Simulator (iPhone Duo, iOS 27.1) mit Xcode 27.2 auf dem Mac mini M4 Pro; die Messwerte der Tour in den echten Posen stammen vom Stand vor dem Auflegen (der Code der Oberfläche ist derselbe, geändert sind Test-Helfer und Skripte), dazu eine Stichprobe nach dem Auflegen in den Belegen. Einzelheiten, was übernommen, geändert und entfallen ist, und die Messwerte stehen in `docs/wissen/oberflaeche.md`, Abschnitt „Mit M2 zusammengeführt“.

**Entscheidungen**

- **E1 · Die Architektur von M2 gewinnt:** `RootView` statt Vollbild, `GameStage`, `GameLayout` und `FoldGeometry`, `TouchSurface` und `TouchRouter` für die Eingabe, die Pausen-API von `PlaySession` (`showsPauseMenu`, `resumeFromMenu()`, `quit()`, `hingeChanged`), der Schutzrand oben, die Lage der Pausentaste aus `GameLayout`, `DebugRemote`, `LayoutTestPatternView` und alle Kennungen von M2 (`resume`, `quit`, `game-<System>-<Name>`, `touch-pad`, `touch-button-<Taste>`). Die Tests von M2 bleiben, wie sie sind; auch `DSTouchUITests.testEveryTapHitsItsDSPixel` läuft mit den Helfern von M2 in den echten Posen (E7).
- **E2 · Glas liefert das Aussehen** (die Glastasten und das Deck gelten seit dem 11. November 2026 nicht mehr, Abschnitt „Konsole statt Glastasten“): die Bibliothek als Raster mit More-Menü, Import und Suche, App-Icon und Akzent; die Glastasten auf den Zonen von `GameLayout` in jeder Pose und für jedes System, beim DS mit X und Y; Druck nur aus der Maske, die an die Sitzung geht (R5); die Platte je Hintergrund, über einem Bildschirm die Bildplatte, sonst das Deck mit dem Schimmer in der Spielfarbe; kein Glas über dem Touchscreen oder der Division-Region; der Pause-Knopf aus Glas an der Stelle aus `GameLayout`; das Pausenmenü als System-Sheet über `showsPauseMenu`, auch nach dem Zuklappen außen, das sich schließt, wenn die Sitzung von selbst fortsetzt; „Resume“ ruft `resumeFromMenu()`, „Quit Game“ beendet über `quit()`; das Debug-Overlay als Schalter; Hinweise und Ton-Chip ohne Treffer auf dem Bild; Ladebild, Fehleransicht, Galerie. Die Lage von Pause, Hinweis, Chip und Debug-Overlay kommt aus `OverlayPlacement`, einer reinen Funktion von `GameLayout`, getestet über alle Systeme und die Geometrien von `LayoutInvariantTests`.
- **E3 · Kein Zoom von der Kachel ins Spiel** (Entscheidung 11 geändert): `RootView` tauscht die Ansicht, es gibt keine Präsentation, also keinen Zoom des Systems, und kein eigener Morph ersetzt ihn. `testDraggingDownOverTheControlsKeepsTheGame` prüfte nur diesen Zoom und ist entfernt; die Tests der Oberkante nach dem Sheet treten an seine Stelle.
- **E4 · Der Zoom des Sheets aus dem Pause-Knopf bleibt;** er funktioniert mit M2. Ein UI-Test tippt nach Pause über den Knopf, Sheet und Resume an die Oberkante und trifft danach L, R und beim DS den Touchscreen, auch dessen oberste Zeile, damit der Fehler aus M2 nicht über das Sheet zurückkommt.
- **E5 · String Catalog und `project.yml` vereinigt** (der Catalog als Drei-Wege-Abgleich, die Lizenztexte von M2 gelten); ADR 0006 bleibt M2, dieses ADR bleibt Glas.
- **E6 · Doku:** dieser Abschnitt und die aktualisierten „Folgen“; in `oberflaeche.md` wurde „Empfehlungen an M2“ zu „Mit M2 zusammengeführt“; dazu `app.md`, der Plan (M4, Liquid Glass vorgezogen und auf M2 zusammengeführt, danach auf `main` gelegt), `CLAUDE.md` und die Statuszeile im README. Was M2 offen lässt, bleibt offen.
- **E7 · Echte Posen:** Die Tour stellt jede Pose mit dem privaten Posen-Werkzeug außerhalb des Repos ein, das `POSE_CHECK_POSTURE_TOOL` benennt (zu hochkant, zu quer, offen, Buch, Tabletop, flach hochkant), hell und dunkel, und zeigt darin DS und GBA mit Pausen-Sheet, dazu das Sheet nach dem Zuklappen außen. `DSTouchUITests.testEveryTapHitsItsDSPixel` läuft in jeder echten Pose, `Scripts/pose-check.sh ds` und `gba` mit der Glas-Oberfläche.
- **E8 · Querformat außen ist erreichbar:** `testSidewaysTheRButtonIsFree` und Zustand 12 (Sheet quer) laufen, nachdem das Skript die Pose quer gestellt hat; sie überspringen sich nur noch, wenn das Fenster wirklich hochkant bleibt.
- **E9 · Leistung:** je 60 s GBA und DS, Glas gegen flach (`-ArcfoldControlSurface`), außen hochkant und innen offen, im selben Zeitfenster, verglichen mit M2 (DS 59,8, GBA 59,7 Bilder/s).

**Umsetzung**

- Spielansicht und Bibliothek: `GameView` von M2 mit dem Sheet statt des eingebetteten Menüs, `TouchControls` von M2, `LibraryView` als Raster mit `open` von `RootView` statt Vollbild, `RootView` setzt Spielfarbe, Glas oder flach und das dunkle Erscheinungsbild.
- Tasten: `TouchControlsArt` in den Zonen von `GameLayout`, Platte je Taste (`GlassBackdrop.under`), `DeckLayout`, `TouchSurface` als Fläche mit Direktberührung für VoiceOver.
- Pause-Knopf: ein Spielglas-Kreis in der Größe seines Platzes (36 pt in der Menüzeile, sonst 44 pt), interaktiv, Ziel ≥ 44 pt, Quelle des Zooms ins Sheet; Tests der Oberkante, des Sheets beim Zuklappen und des Wegwischens.
- Hinweise: `OverlayPlacement` als Funktion von `GameLayout`, `GameOverlays` in den Koordinaten der Bühne, Ladebild auf den Bildschirmen, Galerie aus `GameLayout`; das Debug-Overlay bricht vor dem Touchscreen um.
- Tests und Tour: Die UI-Tests der Glas-Oberfläche und die Tour nutzen die Test-Helfer von M2 für das Innendisplay (`UITestSupport`); die Tour stellt die echten Posen mit dem privaten Posen-Werkzeug ein (`Scripts/screenshot-tour.sh`, Teil `poses`).

**Belege**

| Prüfung | Ergebnis |
| --- | --- |
| Builds | Store und JIT für den Simulator, Store für `generic/platform=iOS` mit `CODE_SIGNING_ALLOWED=NO` und Store mit den Test-Bundles, frisch in einem leeren Build-Ordner: ohne Warnung, die einzigen Warnzeilen stammen von `appintentsmetadataprocessor`. `Scripts/bootstrap.sh` holte nach dem Merge die Submodule von melonDS DS und baute den Kern (27 s) und mGBA neu (6 s, das Rezept von M2 ändert den Stempel) |
| Tests | (Stand vor den Nachbesserungen der Gegenprüfung, neue Zahlen im Abschnitt „Nachbesserungen nach der Gegenprüfung“) Store 365 (333 bestanden, 32 übersprungen, 0 fehlgeschlagen: ArcfoldTests 159, LibretroKitTests 64, FoldLayoutTests 31, RendererTests 39, ArcfoldUITests 72 mit 40 bestanden), JIT 293 bestanden, je ein voller Lauf auf einem eigenen Duo-Gerät, zugeklappt hochkant gestartet, ohne anderes parallel (parallel gestartete Läufe ließen die zeitabhängigen Tests des DS-Touchscreens scheitern). Übersprungen sind die 30 Zustände der Tour (sie laufen über `Scripts/screenshot-tour.sh`) und je ein Test, der eine bestimmte Pose braucht. Seit M2 neu sind die Tests der Nachbesserungen (Hinweis-Stapel, Fehleransicht, Debug-Overlay, Pause-Sheet, Titelkante, Spalten, Falz im Buch) und `GameOverlayUITests`, `LibraryLayoutUITests` |
| Tour, Varianten | hell, dunkel, Kontrast und große Schrift grün, das Audit dunkel und mit Kontrast erhöhen bestanden; die Messwerte stehen in `docs/wissen/oberflaeche.md` („Mit M2 zusammengeführt“): unter anderem Pause 44 × 44 pt, Beschriftungen über dem Deck 8,87 bis 13,20 : 1, quer über Weiß 3,25 bis 5,10 : 1, Weiß auf dem Akzent 4,65 bis 6,25 : 1 |
| Tour, Posen | 24 Läufe (sechs Posen, vier Varianten): Spiel DS und GBA mit Pausen-Sheet, Bibliothek, Menü, Suche, Lizenzen, langer Hinweis mit Ton-Chip und Fehleransicht in jeder Pose; vier Läufe mit Befunden (hell zugeklappt quer und im Buch, Kontrast erhöhen zugeklappt und zugeklappt quer), siehe `docs/wissen/oberflaeche.md`, „Tour in jeder Pose“. Nach der Gegenprüfung behoben und in den betroffenen Posen neu gefahren: Kontrast erhöhen (30, 31) in allen sechs Posen und die Bibliothek hell zugeklappt quer grün; das Audit im Buch lief damals noch in die Zeitgrenze (behoben, siehe „Nachbesserungen nach der Gegenprüfung“). Pause 44 × 44 pt ohne Taste darunter, Ränder des Sheets gleich, Titelkante 20 / 20 pt (zu quer 84 / 84 pt) in jeder Pose |
| Touch in den echten Posen | `DSTouchUITests.testEveryTapHitsItsDSPixel` offen, Buch, Tabletop und flach hochkant je 32 von 32 Taps im Overlay und im Fadenkreuz, kein Tastendruck |
| Posenprüfung | `Scripts/pose-check.sh gba` und `ds` mit dem Build dieses Branches: dritter Lauf des DS und Lauf des GBA ohne Lücke in einem Fenster eines Wechsels, eine Szene über alle Wechsel, „Paused: folded“ mit dem Sheet außen, „Resumed“ beim Aufklappen; DS 59,78 bis 60,00 Bilder/s. Bei fremder Last von 20 bis 35 zeigte der DS Lücken von 57 bis 66 ms |
| Leistung | `test98MeasureGlassAgainstFlat`, je 60 s, Glas / flach: Emulation überall 59,95 bis 59,96 Bilder/s, `resync`, Aussetzer und „GPU busy“ 0; übersprungene Bilder mit Glas 0,6 bis 3,7 Prozentpunkte über flach, Anzeige 46 bis 52 Hz; Tabelle in `oberflaeche.md` |

## Nachbesserungen nach der Gegenprüfung

Am 10. November 2026 folgte eine zweite Runde auf demselben Branch, wieder als zwei Pakete (Spielansicht, Bibliothek), danach ein voller Lauf in der Reihenfolge Builds, Tests Store und JIT, ganze Tour, Posenprüfung. Neue Commits obenauf, kein Umschreiben des Verlaufs. Einzelheiten stehen mit Messwerten in `docs/wissen/oberflaeche.md` (Abweichungen 33 bis 38, „Tour in jeder Pose“, Stolperfallen):

- **Debug-Overlay und Hinweis:** Die Karte gibt nach, nicht der Hinweis. Sie endet 6 pt vor Ton-Chip und Hinweis, nimmt kleinere Schrift, dann weniger Zeilen und zeichnet nichts, wenn keine Zeile passt (`OverlayPlacement.debugArea(besideStackOf:)`; vorher 5437 Überschneidungen im Unit-Test, nachher keine über 172 Geometrien mal 12 Schriftgrößen).
- **Pausen-Sheet:** so hoch wie sein Inhalt (269 statt 390 pt zugeklappt hochkant, 269 statt 458 pt quer, auch im Buch und im Tabletop); im Tabletop bleibt es unter dem Falz, bei großer Schrift wächst es bis zum Fenster und scrollt dann.
- **Kontrast erhöhen:** Alle Tasten tragen den Rand 0,90, die Kanten messen 12,4 bis 17,3 : 1 (über dem Deck vorher 3,6 bis 4,2).
- **Galerie und Tour:** `GalleryScene.sidewaysGBA` hat den gemessenen sicheren Bereich, der ungünstigste Fall ist die eigene Szene `sidewaysGBAOverThePicture`. Die Tour hat den Zustand 38 (Spiel ohne Debug-Overlay in jeder Pose, hell und dunkel) und startet in jeder Pose beide Testprogramme über ihre Kacheln.
- **Bibliothek im Buch:** Jede Seite hält 20 pt zur Division-Region (Kacheln 168,67 statt 178,67 pt, rechte Seite ab 515,67 statt 495,67 pt); der Lizenztext beginnt ebenfalls 20 pt dahinter.
- **Raster beim Zuklappen:** Nach jedem Zuklappen blieb das Raster mit den vier Spalten des Innendisplays außen stehen und war an beiden Seiten abgeschnitten. Ursache war eine `ScrollView`, die mit ihrem Inhalt wuchs; behoben, nachher zwei Kacheln zu 174 pt.
- **Audit im Buch:** Die Zeitgrenze kam aus der Kontrast-Prüfung auf der Lizenzseite, nicht aus dem Raster; sie ist dort ausgenommen, der Kontrast wird in Pixeln gemessen (21,00 : 1, Hinweis 3,44 : 1).
- **Fotos der Bibliothek:** `LibraryLayoutUITests` fotografiert die Anzeige, die die Bibliothek zeigt (`app.displayScreenshot()`), statt schwarzer Bilder im Buch; Kerne, leere Bibliothek und Suche ohne Treffer laufen ohne künstlichen Falz.
- **Entscheidung ohne Änderung:** Der kleine Titel nach Buch → Tabletop ist Systemverhalten (alle Systemlisten im selben Wechsel, 52 pt Unterschied) und bleibt.

**Belege** (Duo-Simulator, iOS 27.1, Xcode 27.2, je ein voller Lauf nacheinander auf einem eigenen Gerät, zugeklappt hochkant gestartet)

| Prüfung | Ergebnis |
| --- | --- |
| Builds | Store und JIT für den Simulator und Store für `generic/platform=iOS` mit `CODE_SIGNING_ALLOWED=NO` (Xcode, Build-Ordner des Laufs): erfolgreich, ohne Warnung im eigenen Code, die einzige Warnzeile stammt von `appintentsmetadataprocessor` |
| Tests | Store 380 (348 bestanden, 32 übersprungen, 0 fehlgeschlagen: ArcfoldTests 171, LibretroKitTests 64, FoldLayoutTests 31, RendererTests 39, ArcfoldUITests 75 mit 43 bestanden), JIT 305 bestanden (ArcfoldTests 171, LibretroKitTests 64, FoldLayoutTests 31, RendererTests 39). Vorher Store 365 (333 bestanden), JIT 293; neu sind `PauseSheetHeightTests`, die Tests von `DebugPlacementTests` zum Stapel, `LibraryColumnsTests` zu Falz und Breite, `GameOverlayUITests.testThePauseSheetIsAsHighAsItsContent`, `ScreenshotTour.test38CleanGamesInThePose` und `LibraryLayoutUITests.testTheScreensBesideTheGridShowWholeInTheWindow`; übersprungen sind die 31 Zustände der Tour und ein Test, der quer braucht. Kein Fehlschlag, keine Wiederholung nötig |
| Tour | alle vier Varianten und alle 24 Läufe in den echten Posen grün (sechs Posen mal hell, dunkel, Kontrast, große Schrift), dazu die Schließen-Fotos hell und dunkel; Zustand 38 und der Start beider Testprogramme aus der Bibliothek in jeder Pose; `LibraryLayoutUITests` auch im Buch ganz grün. Beim Durchsehen der Fotos kein Überschneiden, kein abgeschnittener Text, kein Glas auf dem Falz oder über dem Touchscreen, kein schwarzes Foto |
| Posenprüfung | `Scripts/pose-check.sh ds` und `gba`: je sieben Schritte, keine Lücke und keine Neusynchronisation in einem Fenster eines Wechsels, eine Szene über alle Wechsel, „Paused: folded“ beim Zuklappen, „Resumed“ beim Aufklappen; DS 59,75 bis 59,87 Bilder/s, GBA 59,67 bis 59,78 |
| Kanten, Sheet, Raster | Kanten mit Kontrast erhöhen 12,37 bis 17,30 : 1 in allen Posen; Sheet 269 pt hoch und 34,33 pt unter „Quit Game“ in jeder Pose und Variante; Titelkante gegen Kachel gleich in jeder Pose; Kacheln im Buch bei 20 / 202,67 / 515,67 / 698,33 pt |

## Lage der Tasten (11. November 2026)

Fatih hat an den Bildern des Pull Requests zwei Dinge bemängelt: In manchen Ansichten von GBA und DS lagen Steuerkreuz und Aktionstasten nicht auf einer Höhe, und Select und Start standen direkt unter den Aktionstasten, wo ein Daumen sie aus Versehen trifft. Beides hatte eine Ursache. In allen Vorlagen mit Spalten stand das Menü (Select, Pause, Start) am Fuß der rechten Spalte und schob die Aktionstasten über das Steuerkreuz: um 22 pt beim DS offen und im Buch, um 66 pt beim DS zugeklappt quer, im Tabletop und flach hochkant und beim GBA zugeklappt quer, offen und im Buch.

Entschieden:

- **Steuerkreuz und Aktionstasten liegen in jeder Pose auf einer Höhe**, ebenso L und R.
- **Select, Pause und Start sitzen mittig direkt unter dem Bild**, als Reihe oder, wo es eng ist, als Spalte. Sie liegen nie unter den Aktionstasten oder dem Steuerkreuz und halten zu beiden mindestens 24 pt Abstand.
- Läuft ein senkrechter Falz durch diese Mitte (offen und im Buch), teilt sich das Menü: Select und Pause vor dem Falz, Start dahinter.
- Wo unter dem Bild kein Platz war, rückt das Bild nach oben (`raised`). Das Bild wird dafür nicht kleiner, außer ohne Falz quer, wo ein Handgerät den größten Faktor nimmt, bei dem alle Tasten im Gehäuse Platz haben (Abschnitt „Konsole statt Glastasten“).

| Pose | GBA | DS |
| --- | --- | --- |
| zugeklappt | Leiste unter dem Bild mit L, Select, Pause, Start, R; darunter Steuerkreuz und A, B | Menü als Spalte zwischen Steuerkreuz und Raute (Select, Start, Pause) |
| zugeklappt quer | Menü unter dem Bild, Steuerkreuz und A, B in den Spalten | Menü unter den Bildschirmen, Steuerkreuz und Raute in den Spalten |
| offen und Buch | Menü unter dem Bild beiderseits des Falzes | Leiste unter den Bildschirmen mit L, Select, Pause, dem Falz, Start, R; darunter Steuerkreuz links und Raute rechts |
| Tabletop und flach hochkant | Leiste unter dem Falz mit L, Select, Pause, Start, R; darunter Steuerkreuz und A, B | Menü unter dem Touchscreen, Steuerkreuz und Raute in den Spalten |

Umgesetzt in `Packages/FoldLayout` (`ControlZones.menuTrailing` für das geteilte Menü, die Bausteine `bandZones`, `sideZones`, `pageZones`, `raised`, `divided`; `finished` gleicht die Zeilen von Steuerkreuz und Aktionstasten an) und in `TouchLayout.menu(in:trailing:)`. Die Bausteine stehen in `docs/wissen/falz.md`. `LayoutInvariantTests` prüft beide Regeln über viele Geometrien, darunter die sechs Posen mit den Maßen, die der Simulator meldet (seit der Konsole auch fünf iPhones hochkant und quer und den Falz am Rand); `MenuPlacementTests` hält die Zonen je Pose fest, `TouchLayoutTests` die Tasten je Pose (Höhe, Abstand, Teilung am Falz).

Belegt am 11. November 2026 im Duo-Simulator (iOS 27.1, Xcode 27.2), Stand vor der Konsole: Store 391 Tests, davon 359 bestanden und 32 übersprungen (ArcfoldTests 174, LibretroKitTests 64, FoldLayoutTests 39, RendererTests 39, ArcfoldUITests 75 mit 43 bestanden), JIT 316 bestanden, kein Fehlschlag; DS und GBA in allen sechs echten Posen fotografiert (Zustand 38 der Tour). Die ganze Tour in allen Varianten und die Posenprüfung sind nach dieser Änderung noch nicht neu gelaufen.

Größe und Aussehen der Tasten sind davon unberührt. Fatih wünschte sich die Spielansicht insgesamt anders, mit einem Gehäuse und größeren Tasten; das ist der folgende Abschnitt, „Konsole statt Glastasten“. Die Zahlen aus diesem Abschnitt gelten dort weiter, soweit der Code sie nicht ändert (Größen und Faktoren stehen in ADR 0006, Abschnitt 8).

## Konsole statt Glastasten (11. November 2026)

Dieser Abschnitt löst die Aussagen der älteren Abschnitte zu Glastasten, Deck und Platten im laufenden Spiel ab. Die älteren Abschnitte bleiben als Verlauf stehen. Bibliothek, Pausen-Sheet, Hinweise, Akzent, Icon und Bedienungshilfen gelten weiter.

### Kontext

- Fatih hat die Spielansicht nach der Lage der Tasten (Abschnitt „Lage der Tasten“) noch einmal anders gewünscht: mit einem Gehäuse und größeren Tasten. Die Glastasten auf einem Deck neben und unter den Bildschirmen wirkten wie lose Bedienelemente. Keine Taste hatte einen festen Ort, und die Bildschirme sahen aus wie Bilder auf einer Fläche, nicht wie Bildschirme.
- Glas über dem laufenden Bild kostet den Render-Server Arbeit (Abschnitt „Folgen“). Glas auf einem ruhenden Gehäuse hat nichts zu brechen und gäbe den Tasten nur einen Look, den ein Gehäuse besser trägt.
- Die Lage der Tasten (Steuerkreuz und Aktionstasten auf einer Höhe, das Menü mittig unter dem Bild) bleibt; sie wird jetzt über mehr Geometrien geprüft.
- Die harte Regel Marken gilt: kein Original-Logo, kein geschütztes Tastensymbol, kein Gerät als Kopie.

### Optionen

1. **Glastasten behalten, nur Maße ändern:** größere Tasten auf dem Deck. Vorteil: wenig Änderung. Nachteil: Die Tasten bleiben lose Flächen; ein Deck gibt ihnen keinen Ort.
2. **Konsole je System:** ein Gehäuse in der Farbe des Systems, Bildschirme in dunklen Blenden, ein Scharnier am Falz, Tasten als Kappen in Mulden mit eingeprägten Buchstaben. Glas nur dort, wo etwas über dem Bild liegt. Vorteil: Jede Taste hat einen festen Ort, die Bildschirme sehen wie Bildschirme aus, das Gehäuse zeichnet sich nur bei einem neuen Layout neu. Nachteil: mehr Eigenbau (Gehäuse, Kappen, Steuerkreuz), mehr Maße, die zu den Layouts passen müssen.
3. **Konsole mit Glaskappen:** das Gehäuse wie in Option 2, die Kappen aber aus Glas. Vorteil: nah am Rest der Oberfläche. Nachteil: Glas auf Gehäuse hat nichts zu brechen und kostet trotzdem Arbeit; die Beschriftung bräuchte wieder eine Platte.

### Entscheidung

Option 2.

1. **Eine Konsole je System.** Der DS steht in „Kreide“ (hell, mit indigofarbener Beschriftung), seine zweite Farbe ist Graphit. Der GBA steht in Indigo (dunkel, mit hellen Tasten), seine zweite Farbe ist Petrol. Dazu gehören Blenden um die Bildschirme, ein Scharnier am Falz, Kappen in Mulden und das Steuerkreuz als Kreuz in einer Schale. Alles sind eigene Entwürfe ohne Original-Logos und ohne geschützte Tastensymbole; die Tasten tragen Buchstaben, Wörter und einfache Pfeile.
   - Maße (Punkte, in jeder Pose gleich): Blende 8, Ecke der Blende 13, Mulde um eine Taste 2, Kappe steht 2,5 heraus und sinkt beim Drücken um 1,5, Knopf von Select, Menu und Start 24 mit der Beschriftung 11,5 in SF Rounded halbfett. Das Gehäuse umrahmt die Kamera des Außendisplays mit einer Mulde und spiegelt sie als Lautsprecher.
   - Die zweite Farbe wählt die Nutzer-Voreinstellung `CaseFinish` (`chalk`, `graphite`, `indigo`, `petrol`; ein System nimmt nur seine eigenen). Eine Oberfläche dafür gibt es noch nicht; sie kommt mit den Einstellungen in M4.
2. **Tasten sind kein Glas mehr.** Glas liegt nur noch über dem Bild:
   - die Menu-Taste mit Controller, wo keine Ecke des Gehäuses frei ist,
   - die Hinweise und der Ton-Chip,
   - Tasten über dem Bild, aber nur auf Anzeigen ohne Platz für das Gehäuse (ein Layout, in dem nicht einmal der kleinste Faktor mit Spalten passt).
   Alles neben oder unter den Bildschirmen ist eine Taste des Gehäuses. Die hellere Platte über dem Deck ist entfallen, ebenso das Deck mit dem Schimmer.
   - **Flach** (das System spart Ressourcen, `systemPrefersReducedResourceUsage`) ist dieselbe dunkle Platte ohne Glas. Vorher war sie weiß mit 0,10 und ließ die Menu-Taste und die Hinweise über einem weißen Bild bei 1,0 : 1 verschwinden.
   - `-ArcfoldControlSurface flat|glass` schaltet nur noch, was über einem Bild liegt.
3. **DS zugeklappt:** Die Voreinstellung ist 3-fach mit Gehäuse und einem eigenen Scharnier zwischen den Bildschirmen. L und R sind die Enden dieses Scharniers. Die schlanke Fassung ist 4-fach, die Leiste des Systems bleibt neben dem Spiel, das Scharnier ist niedriger, und L und R nehmen Berührungen etwas über ihm an. Sie gilt für die Nutzer-Voreinstellung `LargerScreens` (`-LargerScreens YES`). Beide haben noch keine Oberfläche; sie kommt mit den Einstellungen.
4. **L und R sind in jeder Pose 40 pt hoch.** Select, Menu und Start sind kleine Knöpfe mit ihrem Namen darunter oder daneben; ihre Zelle misst höchstens 60 × 44 pt, die Menu-Taste behält ein Ziel von 44 pt.
5. **Ohne Falz quer** (iPhone, Duo zugeklappt quer) gilt ein Handgerät: der größte ganzzahlige Faktor, bei dem alle Tasten im Gehäuse Platz haben. Hochkant auf schmalen Anzeigen läuft das Bild von Rand zu Rand, und die Blende ist ein Band über die ganze Breite mit eckigen Enden.
6. **Bekannte Grenze:** Der DS quer auf iPhones ohne Falz bleibt mit 2-fach klein. Das folgt aus der ganzzahligen Skalierung (ADR 0006) und aus der Regel, dass die Tasten im Gehäuse stehen. Offen ist, ob Geräte ohne Falz dafür später eine eigene Regel bekommen.
7. **Trefferflächen:** Die Toleranz um eine Taste und die Reichweite des Steuerkreuzes enden am Schutzrand oben und am aktiven Falz.
8. **Falz am Rand:** Liegt der Falz so am Rand der Fläche, dass eine Seite leer oder quer zum Falz schmaler als eine Spalte von 134 pt ist, gilt die Vorlage ohne Falz in der größeren Seite. Die Pose bleibt die der Geometrie, und das Gehäuse zeichnet das eigene Scharnier statt des Falzes. Läuft ein Falz von oben nach unten in einer Ansicht, die höher als breit ist (nur eingespeist, nur Debug), gilt beim GBA die Vorlage hochkant ohne Falz mit am Falz geteiltem Menü (`docs/wissen/falz.md`).
9. **Menu-Taste mit Controller:** Sie steht in der ersten freien Ecke des Gehäuses (unten rechts, unten links, oben rechts, oben links), sonst als Glas ganz im Bild, nie quer über einer Blende. Ihre Eingabenamen sind „Menu“ und „Pause“, damit die Sprachsteuerung sie findet.
10. **Die Regeln zur Lage der Tasten vom 11. November gelten weiter** und werden jetzt über alle Geometrien geprüft: den Duo in allen Posen, fünf iPhones hochkant und quer und den Falz am Rand. Dazu kommen: Select, Menu und Start halten 24 pt zu Steuerkreuz und Aktionstasten; die Menüzelle nimmt Select und Start nie Berührungen weg; keine Taste liegt auf einem Bildschirm, außer in einer ausdrücklichen Liste (der schlanke DS); die Mulde einer Taste berührt keinen Bildschirm; jeder Bildschirm sitzt in einer Blende, auf der keine Taste steht.
11. **Die Tour misst die Konsole:** Buchstaben und Pfeile gegen die Kappe, die Namen der kleinen Knöpfe gegen das Gehäuse, die Ränder im Kontrast, den Ring bei „Differenzieren ohne Farbe“ und die Menu-Taste als Zelle mit Ziel und Abstand (`docs/wissen/oberflaeche.md`). Nach der Konsole laufen die vier Varianten zugeklappt und alle sechs Posen in hell und Kontrast. Die Messung Glas gegen flach entfällt, weil im laufenden Spiel keine Taste mehr aus Glas ist, die sie vergleichen könnte.

### Folgen

- Die Bildschirme sehen wie Bildschirme aus, und jede Taste hat einen festen Ort. Die Regel „Kein Glas auf Inhalt“ bleibt; das Spielbild bestimmt weiter nie, wie eine Taste aussieht.
- Glas über dem Spielbild beschränkt sich auf die Menu-Taste mit Controller, die Hinweise, den Chip und Tasten auf Anzeigen ohne Platz für das Gehäuse. Das Gehäuse und seine Tasten zeichnen sich nur bei einem neuen Layout neu; ein Druck zeichnet nur die gedrückte Taste neu. Der Gerätetest prüft deshalb die Konsole, nicht mehr Glas gegen flach (`docs/wissen/geraetetest.md`, Teil 1b).
- Flach liegt unter Menu-Taste und Hinweisen dieselbe dunkle Platte wie mit Glas, mit einem Rand; so bleiben sie über einem weißen Bild lesbar. Die Tour misst die Menu-Taste flach im Zustand 15: 5,66 : 1 über Weiß, 5,89 über dem Testmuster und 17,22 über Schwarz (Schranke 3 über Weiß und dem Testmuster).
- Ein neues System bekommt eine Konsole, sobald FoldLayout es kennt und `ConsoleSkin` Farben für es hat; die Tests von `ConsoleCaseTests` laufen dann über alle Geometrien mit.
- Der DS quer auf iPhones ohne Falz bleibt klein (Entscheidung 6).
- Die Farben und die Wahl zwischen 3-fach und 4-fach beim DS zugeklappt haben noch keine Oberfläche (Entscheidung 1 und 3).
- Belege nach der Konsole, 11. November 2026 (Duo-Simulator, iOS 27.1, Xcode 27.2, eigene Geräte; Einzelheiten in `docs/wissen/oberflaeche.md` und `docs/wissen/falz.md`):

| Beleg | Ergebnis |
| --- | --- |
| Builds | Store und JIT für den Simulator und Store für ein Gerät ohne Signatur: je Exit 0, keine Warnung im eigenen Code (vor und nach den Nachbesserungen) |
| Tests Store, Duo, erster Lauf | 377 bestanden, 1 fehlgeschlagen, 33 übersprungen, 411 gesamt (ArcfoldTests 186 mit 1 Fehlschlag, LibretroKitTests 64, FoldLayoutTests 43, RendererTests 39, ArcfoldUITests 79 mit 46 bestanden); der Fehlschlag war eine Tonlücke in `loadRunPauseResumeStopInRealTime` unter Last, einzeln zweimal grün |
| Tests JIT, Duo | 332 bestanden, 0 Fehlschläge (ArcfoldTests 186, LibretroKitTests 64, FoldLayoutTests 43, RendererTests 39), vor den Nachbesserungen; danach gebaut, der Testlauf steht aus |
| Tests Store, iPhone 18 Pro, iOS 27.2, erster Lauf | 376 bestanden, 4 fehlgeschlagen, 31 übersprungen (UI-Tests: Audit, Select im Buch des GBA, schlanker DS, Chip gegen Hinweis); alle vier geklärt, zwei davon waren Fehler der App (Menü im eingespeisten Buch, Rahmen von Chip und Hinweis), zwei der Tests; einzeln grün; der volle Lauf dort steht nach den Nachbesserungen aus |
| Tests Store, Duo, nach den Nachbesserungen | 413 Tests, 0 Fehlschläge (ArcfoldTests 187, LibretroKitTests 64, FoldLayoutTests 44, RendererTests 39, ArcfoldUITests 79 mit 46 bestanden und 33 übersprungen) |
| Tour, vier Varianten zugeklappt | hell, dunkel, Kontrast und groß: je 31 Tests, kein Fehlschlag (20, 9, 13 und 6 bestanden, die übrigen übersprungen), zusammen 11,5 Minuten |
| Tour, sechs Posen | 16 Teile in hell und Kontrast (zugeklappt und zugeklappt quer auch schlank): 15 grün, 1 Fehlschlag (hell zugeklappt, Zustand 36, Messfehler der Zeit, behoben; danach in allen sechs Posen grün), etwa 85 Minuten |
| Messwerte der Tour | schwächste Werte je Pose in hell: Buchstaben und Pfeile 4,57 bis 4,74 (Schranke 3), Namen 5,17 bis 5,46 (Schranke 4,5), Abstand der Menu-Taste 25,67 bis 169,98 pt (Schranke 24); im Kontrast Rand der Kappen 6,14 bis 6,35 (Schranke 3) |
| Posenprüfung | `gba`: keine Lücke, keine Neusynchronisation. `ds`: ebenso im Lauf ohne andere Last auf dem Mac (vor den Nachbesserungen); in zwei Läufen neben weiteren Testläufen Lücken von 51,9 bis 66,0 ms und Neusynchronisationen. `ds-slim`: bisher nur neben weiteren Testläufen gelaufen, mit Lücken von 52,5 bis 61,5 ms; ein Lauf ohne Last steht aus. Pause und Fortsetzen in jedem Lauf wie gefordert (`docs/wissen/falz.md`, „Nach der Konsole“) |

Offen bleiben nach den Nachbesserungen der Testlauf des JIT-Builds, der volle Lauf auf dem iPhone 18 Pro und die Posenprüfung des DS in der schlanken Fassung ohne andere Last. Die Ausnahme im Audit für das skalierte Pausen-Sheet unter iOS 27.2 bleibt, bis der Gerätetest zeigt, wie ein Gerät das Sheet zeichnet (`docs/wissen/oberflaeche.md`, „Nachbesserungen nach dem Lauf“; `docs/wissen/geraetetest.md`, G15).

## Bilder

Bildschirmfotos aus der Tour, aufrecht gedreht und verkleinert, Außendisplay 466 × 678 pt (quer 678 × 466), Innendisplay 700 × 492 (Tabletop und flach hochkant 492 × 700). Die Spielbilder zeigen die Konsole (Abschnitt „Konsole statt Glastasten“). Bibliothek und Lizenzen stammen vom Stand vor der Konsole und gelten weiter.

![Alle Posen im Überblick](0007/konsole-alle-posen.jpg)

Alle Posen im Überblick, DS und GBA.

![DS zugeklappt](0007/konsole-ds-zugeklappt.jpg)

DS zugeklappt: Gehäuse in Kreide, die Bildschirme in Blenden, dazwischen das Scharnier mit L und R an seinen Enden, darunter Steuerkreuz, Select, Menu und Start in einer Spalte, Aktionstasten als Raute.

![DS zugeklappt, schlank](0007/konsole-ds-zugeklappt-schlank.jpg)

DS zugeklappt in der schlanken Fassung (`-LargerScreens YES`): 4-fach, niedrigeres Scharnier. Die Bildschirme beginnen an der Oberkante, wo die Blende gerade endet; links stehen 12 pt Gehäuse, rechts steht die Leiste des Systems mit der Kamera.

![DS zugeklappt quer](0007/konsole-ds-zugeklappt-quer.jpg)

DS zugeklappt quer: beide Bildschirme nebeneinander, das Scharnier darunter.

![DS offen](0007/konsole-ds-offen.jpg)

DS offen: ein Bildschirm links, der Touchscreen rechts des Falzes, darunter die Leiste mit L, Menü und R, darunter Steuerkreuz und Raute.

![DS im Buch](0007/konsole-ds-buch.jpg)

DS im Buch: wie offen, mit dem aktiven Falz in der Mitte; das Menü teilt sich vor und hinter ihm.

![DS im Tabletop](0007/konsole-ds-tabletop.jpg)

DS im Tabletop: Bild oben, der Touchscreen unter dem Falz, Steuerkreuz und Raute daneben.

![DS flach hochkant](0007/konsole-ds-flach-hochkant.jpg)

DS flach hochkant: beide Bildschirme über und unter dem Falz.

![GBA zugeklappt](0007/konsole-gba-zugeklappt.jpg)

GBA zugeklappt: Gehäuse in Indigo, das Bild in seiner Blende, darunter die Leiste mit L, Select, Menu, Start und R, darunter Steuerkreuz und A, B.

![GBA zugeklappt quer](0007/konsole-gba-zugeklappt-quer.jpg)

GBA zugeklappt quer: ein Handgerät, Steuerkreuz und A, B in den Griffen, L und R oben darüber, die Menüreihe unter dem Bild.

![GBA offen](0007/konsole-gba-offen.jpg)

GBA offen: das Bild über den Falz hinweg zwischen zwei Griffen.

![GBA im Buch](0007/konsole-gba-buch.jpg)

GBA im Buch: wie offen, das Menü beiderseits des Falzes.

![GBA im Tabletop](0007/konsole-gba-tabletop.jpg)

GBA im Tabletop: das Bild in der oberen Hälfte, die Tasten unter dem Falz.

![GBA flach hochkant](0007/konsole-gba-flach-hochkant.jpg)

GBA flach hochkant: wie im Tabletop, ohne aktiven Falz.

![Pausen-Sheet zugeklappt](0007/konsole-pause-sheet-zugeklappt.jpg)

Pausen-Sheet zugeklappt: so hoch wie sein Inhalt; die Tasten des Gehäuses bleiben darunter stehen. Die Karte des Debug-Overlays ist zu sehen, weil der Zustand 30 der Tour es immer zeigt.

![Pausen-Sheet im Buch](0007/konsole-pause-sheet-buch.jpg)

Pausen-Sheet im Buch: links vom Falz, ebenso hoch; die Karte des Debug-Overlays endet links vor dem Falz.

![Hinweis-Stapel zugeklappt](0007/konsole-hinweis-stapel-zugeklappt.jpg)

Hinweis-Stapel (Ton-Chip und Hinweis) zugeklappt: Glas über dem Bild, darüber die Debug-Karte, die vor dem Stapel endet.

![Zustände der Tasten](0007/konsole-tasten-zustaende.jpg)

Zustände der Tasten am GBA: in Ruhe; Hoch und A gedrückt; eine Diagonale des Steuerkreuzes, B und Start gedrückt.

![Glas über dem Bild](0007/konsole-glas-ueber-dem-bild.jpg)

Glas über dem Bild: die Menu-Taste mit Controller auf einer Anzeige ohne freie Ecke im Gehäuse, über Weiß, dem Testmuster und Schwarz.

Bibliothek und Lizenzen (Stand vor der Konsole):

![Bibliothek zugeklappt, hell](0007/glass-bibliothek-zugeklappt-hell.jpg)

Bibliothek zugeklappt, hell: zwei Spalten, Kanten von Titel und erster Kachel bei 20 pt.

![Dieselbe Bibliothek dunkel.](0007/glass-bibliothek-zugeklappt-dunkel.jpg)

Dieselbe Bibliothek dunkel.

![Bibliothek zugeklappt mit der Schriftgröße accessibility-large](0007/glass-bibliothek-grosse-schrift.jpg)

Bibliothek zugeklappt mit der Schriftgröße accessibility-large: eine Spalte, Kunst und Namen wachsen mit.

![Bibliothek im Buch](0007/glass-bibliothek-buch.jpg)

Bibliothek im Buch: zwei Seiten links und rechts des Falzes, jede mit 20 pt Abstand zur Division-Region.

![Bibliothek offen, dunkel](0007/glass-bibliothek-offen-dunkel.jpg)

Bibliothek offen, dunkel: vier Spalten über die ganze Breite.

![Lizenzen im Buch](0007/glass-lizenzen-buch.png)

Lizenzen im Buch: Liste links, Text rechts des Falzes.

Wie die Bilder entstehen (Tour, Posen, Aufrichten der Fotos), steht in `docs/wissen/oberflaeche.md`, Abschnitt „Konsole“ und „Stolperfallen“.

## Folgen

- Die Oberfläche wirkt wie iOS 27: Leisten, Menüs, Suche und Sheet sind Systemglas, eigenes Glas gibt es nur dort, wo das System nichts anbietet. Jeder Eigenbau ist in `docs/wissen/oberflaeche.md` mit Grund aufgeführt.
- Glas über dem `CAMetalLayer` kostet den Render-Server Arbeit, und zwar mit der Bildrate des Spiels (≈ 60 Hz), nicht mit der Rate des Displays. Seit dem 11. November 2026 liegt Glas im Spiel nur noch über dem Bild: die Menu-Taste mit Controller, wo keine Ecke des Gehäuses frei ist, die Hinweise, der Chip und Tasten auf Anzeigen ohne Platz für das Gehäuse. Die Tasten des Gehäuses kosten dafür nichts. Der Simulator misst nur relativ; `docs/wissen/geraetetest.md` prüft am Gerät die Konsole (Teil 1b), den Vergleich von Glas und flach an den Tasten gibt es nicht mehr.
- Ab M3 (PPSSPP, GPU stark belastet) zählt jede Glasfläche. Der flache Rückfall ist dafür vorbereitet und bleibt für das, was über dem Bild liegt.
- Die Lesbarkeit über beliebigen Spielbildern hängt für Hinweise, Chip und die Menu-Taste über dem Bild an der Dimmplatte. Die Tasten des Gehäuses brauchen sie nicht; ihre Beschriftung steht auf der Kappe und wird gegen die Kappe gemessen. Eine Einstellung für die Farbe des Gehäuses gehört zu den Skins in M4 (Abschnitt „Konsole statt Glastasten“).
- Mit M2 zusammengeführt (Abschnitt „Zusammenführung mit M2“): Die Oberfläche hängt an `GameLayout`. Ein neues System bekommt Gehäuse, Tasten, Menu-Taste und die Lage der Hinweise, sobald FoldLayout es kennt; die Tests von `OverlayPlacement` und `ConsoleCaseTests` laufen dann mit.
- Die Fragen an M2 sind beantwortet: `toolbarVerticalBehavior(.disabled)` je System (GBA ab, DS nicht, ADR 0006, Abschnitt 7), der Pause-Knopf liegt nie in der Systemspalte, kein Glas über der Division-Region und dem DS-Touchscreen.
- Kein Zoom ins Spiel, solange ein Spiel die Bibliothek ersetzt. Käme er zurück, bräuchte er eine Präsentation über der Bibliothek, und vor der stünde wieder der Test der Oberkante (ADR 0006, „Nachbesserungen nach der Prüfung“).
- Der Teil `poses` der Tour hängt am privaten Posen-Werkzeug außerhalb des Repos und damit an privaten Schnittstellen des Simulators (ADR 0006, `docs/wissen/falz.md`); ohne `POSE_CHECK_POSTURE_TOOL` oder wenn ein Update von Xcode es bricht, laufen die Varianten weiter, nur der Teil `poses` überspringt sich mit einem Hinweis.
- Offen für Fatih:
  - Statusleiste im Pausen-Sheet bei größter Schrift: Zugeklappt hochkant (DS) reicht das Sheet dann bis y 136, der Statusring der Systemspalte liegt über seiner oberen rechten Ecke; der Inhalt ist frei davon (Abweichung 35). Hängt an der Frage „Statusleiste im Pausen-Sheet“ unten,
  - Titel nach dem Wechsel von breit nach hoch: Nach Buch → Tabletop steht der große Titel klein in der Leiste, wie bei jeder Systemliste. Will Fatih ihn trotzdem groß, wäre das ein eigener Eingriff gegen das Systemverhalten (an den Anfang rollen, wenn die Ansicht vorher am Anfang stand),
  - Audit auf dem Innendisplay: Die Kontrast-Prüfung kann dort je nach Lage der Zeilen in die Zeitgrenze laufen; sie ist für die Lizenzseite im Buch ausgenommen und in Pixeln gemessen. Tritt es bei anderem Text, anderer Sprache oder Schriftgröße auf einer anderen Seite auf, entfällt sie auf dem Innendisplay ganz,
  - Abstände am Falz auf dem Gerät: Die Zahlen gelten für den Simulator (Division-Region 121 px mit je 20 pt Rand); auf dem Gerät können Region und Ränder anders sein (`FoldDivision.pageMargin` ist eine Konstante). Gehört in den Gerätetest,
  - Icon-Motiv (umgesetzt: Pixel springt über den gefalteten Bogen; Alternative „Bogen am Falz“),
  - Akzent im dunklen Modus: umgesetzt sind die hellen Werte von `systemIndigo` (siehe „Nachbesserungen nach der Prüfung“); zurück zur reinen Systemfarbe ginge mit dem Colorset allein, Weiß läge dann wieder bei 3,5 : 1, mit Kontrast erhöhen bei 2,1 : 1,
  - Statusleiste im Pausen-Sheet,
  - Haptik jetzt oder erst mit den Einstellungen in M4,
  - eigenes Icon für den JIT-Build.
- Verschoben nach M4: Haptik, Kontextmenü und Details an Kacheln, eigene Bilder, Löschen und Umbenennen (das alles braucht das Modell).
- Kein JIT-Pfad, keine Marken, keine Cover, keine neuen Abhängigkeiten. Das neue Skript trägt den SPDX-Kopf `GPL-3.0-or-later`.
