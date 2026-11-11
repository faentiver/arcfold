---
name: falz
description: Duo-APIs im iOS-SDK 27.2 (Scharnier, reservierte Regionen, vertikale Leiste), Duo-Simulator mit Device Hub und Displays, gemessene Maße, FoldLayout (Leser, Vorlagen, Regeln mit Schutzrand oben, Touch-Abbildung), echte Posen per Software (privates Werkzeug außerhalb des Repos, eingebunden über POSE_CHECK_POSTURE_TOOL), Posen ohne den Weg des Systems (DebugRemote) und Stolperfallen, darunter das Vollbild, das oben Berührungen verschluckte; Grundlage der Falz-Layouts in ADR 0006
---

# Falz

Stand 7. November 2026, Xcode 27.2 (27B52), iOS-SDK 27.2, Simulator-Runtime iOS 27.1 (24A94425). Quellen: die Erkundung zu M2 mit dem Prototyp FalzProbe (nicht im Repo), die Umsetzung in Spur L (Paket `Packages/FoldLayout`, Belege in `docs/adr/0006/falz-simulator.txt`), die Integration (`docs/adr/0006/m2-abnahme-simulator.txt`) und die Nachbesserungen nach der Prüfung (ADR 0006, gleichnamiger Abschnitt; Sonden-App nicht im Repo). Die Entscheidungen stehen in ADR 0006; hier stehen Fakten, der Aufbau von FoldLayout und Stolperfallen. Kennzeichnung: **belegt** (gemessen oder im SDK gelesen), **Annahme**, **offen**.

## APIs (belegt im SDK)

| API | Signatur und Werte |
| --- | --- |
| `onHingeChange` (SwiftUI, 27.1) | `func onHingeChange(isEnabled: Bool = true, _ action: @escaping (_ oldContext: DeviceHingeContext, _ newContext: DeviceHingeContext) -> Void) -> some View` |
| `DeviceHingeContext` | `hinge: DeviceHinge?`, `nil` ohne Scharnier |
| `DeviceHinge` | `status: Status`, `angle: Angle`. `Status` ist ein Struct mit `static var` `.closed`, `.partiallyOpen`, `.fullyOpen`, kein Enum: ein `switch` braucht `default` |
| `GeometryProxy.reservedRegions` (27.1) | `func reservedRegions(kind: ReservedRegion.Kind, options: ReservedRegion.QueryOptions = [], layoutDirectionBehavior: LayoutDirectionBehavior = .mirrors) -> [ReservedRegion]`; eine Methode des Proxys, kein Modifier |
| `ReservedRegion` | `id`, `kind` (`.division` Falz, `.occlusion` etwa die Kamera), `frame`, `margins: EdgeInsets`, `isActive`; `CustomStringConvertible` erst ab 27.2 |
| `ReservedRegion.QueryOptions` | `.includeInactive` |
| `ArrangementView` | `init(primary:secondary:)`, Stile `.automatic`, `.split`, `.overlay` |
| Vertikale Leiste | `View.toolbarVerticalBehavior(_:)` mit `.automatic` und `.disabled`; Umgebung `toolbarVerticalEdge` |
| UIKit | `UIHingeInteraction(updateHandler:)` mit `UIHinge.status` (unknown 0, closed 1, partiallyOpen 2, fullyOpen 3) und `angle` in Radiant; `UIView.reservedRegions(kind:options:)`; `preferredVerticalBarBehavior` |

- Es gibt keine API, die eine Pose wie „Tabletop“ oder „Buch“ oder ein Display als „innen“ oder „außen“ benennt. Die Pose folgt aus der Division-Region: flach aufgeklappt inaktiv mit Breite 0, nur geknickt aktiv; außen gibt es keine (belegt außen, Apple Tech Talk 111463 für innen).
- Laut UIKit-Header bestimmt das System Rate und Auflösung des Winkels; für offen, zu und halb soll man den Status nehmen.
- Szenen: nichts Duo-Spezifisches. `windowScene(_:didUpdateEffectiveGeometry:)` trägt den Kommentar „Always called when a `UIWindowScene` moves between screens.“ Auf dem Außendisplay lassen sich keine neuen Fenster anlegen (Tech Talk 111464).

## Duo-Simulator

- Eigenes Gerät: `xcrun simctl create "<Name>" com.apple.CoreSimulator.SimDeviceType.iPhone-Duo com.apple.CoreSimulator.SimRuntime.iOS-27-1`, am Ende `shutdown` und `delete`. Das vorhandene Gerät „iPhone Duo“ bleibt unberührt.
- Displays: 1 außen „primary“ 1398 × 2034 px, 3 innen „primary-1“ 2007 × 2853 px, beide Faktor 3 und 460 ppi. Das Innendisplay hat `nativeOrientation 270`: hochkant gehalten meldet es `rot90`, aufgeklappt wie ein Buch ist es quer, 951 × 669 pt, mit senkrechtem Falz. Bildschirmfotos mit `xcrun simctl io <UDID> screenshot --display=1` bzw. `--display=3`.
- Nach dem Booten ist das Gerät zugeklappt: Display 1 aktiv, Display 3 aus. `xcrun devicectl device info displays --device <UDID> --json-output <Datei>` zeigt, welches Display aktiv ist.
- **Posen über Device Hub oder per Software.** Device Hub hat die Knöpfe Closed, Partially Open, Open und Drehen, mit gedrückter Wahltaste und dem Schieberegler jeden Winkel. `simctl`, `devicectl` und XCUIAutomation haben nichts dafür (belegt). Per Software geht es nur über private Schnittstellen des Simulators, mit einem privaten Werkzeug außerhalb des Repos (Abschnitt „Posen per Software“).

## Maße (belegt, zugeklappt)

- Außendisplay 466 × 678 pt, `nativeScale` 3, `maximumFramesPerSecond` 60 im Simulator.
- Sicherer Bereich trotz `.statusBarHidden()` und `.persistentSystemOverlays(.hidden)`: oben 0, links 0, unten 34, rechts 84 pt (Statusleiste und Toolbar in einer Spalte rechts, `verticalBarEdge` trailing), also 382 × 644 pt. Mit `.toolbarVerticalBehavior(.disabled)`: oben 82, unten 34, seitlich 0 pt, also 466 × 562 pt.
- `.occlusion` außen, aktiv, Ränder 0: Kamera (399,67 | 29,33, 37 × 37 pt) und (382 | 0, 84 × 82 pt), direkt nach dem Start kurz 84 × 174 pt.
- `onHingeChange` meldet beim Erscheinen `nil → closed 0.0°`, ohne Posenwechsel.
- Display-Link im Simulator 48 bis 52 Hz, Lücken bis 150 ms bei Start und Bildschirmfotos, bis 383 ms während `simctl io screenshot` und `devicectl`.

## FoldLayout

Paket `Packages/FoldLayout`, reine Werttypen (`swift test` läuft auf dem Mac), dazu zwei SwiftUI-Modifikatoren nur für iOS in `FoldReaders.swift`.

**Leser.** `onFoldGeometryChange(scale:perform:)` hängt `onGeometryChange(for: FoldGeometry.self)` an einen View, der den sicheren Bereich füllt. Die Transform-Closure (`@Sendable`, außerhalb des Main Actors) liest `size`, `safeAreaInsets` und `reservedRegions(kind: .division, options: .includeInactive, layoutDirectionBehavior: .fixed)` und rechnet:

- `container` = Größe plus Insets, in Pixeln gerundet; `safeArea` = Insets, nach außen gerundet (`PixelInsets.covering`).
- `fold` = Rahmen der ersten Division-Region, um die Insets oben und links verschoben, nach außen gerundet (`PixelRect.covering`) und auf den View begrenzt; `foldMargins` = ihre `margins`, aufgerundet; `isFoldActive` = `isActive`.
- `leading` und `trailing` folgen der Leserichtung; die Spielansicht erzwingt links nach rechts (Spieltasten spiegeln nicht), der Leser wertet sie trotzdem aus.
- `occlusions` = die aktiven Regionen der Art `.occlusion` (Kamera), ebenso verschoben und gerundet; seit der Prüfung. Das Overlay zeigt sie, die Pausentaste ohne Touch-Tasten meidet sie, die Tasten noch nicht (ADR 0006, Abschnitt 7).
- Vor iOS 27.1 ist `fold` nil und `occlusions` leer. `onHingeStateChange(perform:)` übersetzt `onHingeChange` in `HingeState` (`.closed`, `.partiallyOpen`, `.fullyOpen`); ein unbekannter Status gilt als nil.

**Pose.** `FoldGeometry.posture`: keine Region `single`, inaktiv `flat`, aktiv und breiter als hoch `tabletop`, aktiv und senkrecht (Buch) `flat`.

**Vorlagen** (`GameLayout(system:geometry:showsTouchControls:metrics:)`, Maße in Punkt: Spalte 112, Band 128, Abstand 8, Schutzrand oben 64, L/R 44 hoch, Start/Select 36 hoch):

| Pose | Ein Bildschirm | Zwei Bildschirme (DS) |
| --- | --- | --- |
| zu, hochkant | oben, volle Breite, Band darunter | gestapelt oben, Band darunter; L und R über den unteren Ecken des oberen Bildschirms, wenn das Band dafür zu niedrig ist |
| zu, quer | so groß wie möglich und nach oben gerückt, Spalten an den Seiten, über dem Bild, wenn sie einen Faktor kosten, Menü unter dem Bild | gestapelt und nach oben gerückt, Spalten daneben, Menü unter den Bildschirmen |
| flach mit senkrechtem Falz, Buch | über den Falz, Spalten ≥ 112 pt daneben, Menü unter dem Bild beiderseits des Falzes | links vom Falz, Touchscreen rechts, beide am Schutzrand, darunter die Leiste und die Tasten |
| flach mit waagerechtem Falz | in der oberen Hälfte, Band unten | gleicher Faktor über und unter dem Falz, Spalten neben dem Touchscreen, Menü darunter |
| Tabletop | in der oberen Hälfte, Band unten | oben so groß wie möglich, Touchscreen mit Spalten unten, Menü darunter |

Zwei Regeln gelten in jeder Vorlage (seit dem 11. November 2026, nach Fatihs Rückmeldung zu den Bildern; `MenuPlacementTests`, `LayoutInvariantTests`):

- **Steuerkreuz und Aktionstasten liegen auf einer Höhe.** Ihre Zonen decken dieselben Zeilen (`finished` gleicht sie an), die Tasten sitzen in der Mitte ihrer Zone.
- **Das Menü (Select, Pause, Start) sitzt mittig direkt unter dem Bild, nie unter den Aktionstasten oder dem Steuerkreuz**, wo ein Daumen es aus Versehen trifft. Vorher stand es in den Spalten unter den Aktionstasten und schob sie 22 bis 66 pt über das Steuerkreuz.

Die Bausteine:

- **Band:** direkt unter dem Bild eine Leiste mit L, dem Menü in der Mitte und R (44 pt hoch, das Menü bis 240 pt breit, L und R mindestens 64 pt), darunter Steuerkreuz links und Aktionstasten rechts über dieselbe Höhe. Ist das Band zu niedrig für die Leiste (unter 164 pt), liegen L und R über den unteren Ecken des oberen Bildschirms, 8 pt über dem Touchscreen (bis zur Prüfung über den oberen Ecken), und das Menü steht als Spalte zwischen Steuerkreuz und Aktionstasten: Select, Start, Pause untereinander, mit niedrigeren Zeilen (ab 28 pt), bevor sie nebeneinander an die Tasten rücken. Das ist der DS zugeklappt: Band 132 pt, L und R bei y = 204 bis 248 pt, das Menü 34 pt von den Aktionstasten.
- **Spalten** (`sideZones`): links L und das Steuerkreuz, rechts R und die Aktionstasten; die Spalten beginnen am Schutzrand. Das Menü liegt zwischen den Spalten unter dem Bild. Lässt das Bild darunter weniger als 48 pt, rückt es nach oben (`raised`): der DS zugeklappt quer bis an die Oberkante (48 pt frei), der GBA zugeklappt quer bis an die Leiste (30 pt frei, Menüzeile 28 pt). Bleiben unter einem Bild ohne Touch weniger als 28 pt, liegt das Menü über seinem unteren Rand; unter einem Touchscreen ohne Platz gehen seine zwei Teile an den Fuß der Spalten (kommt in keiner Pose des Duo vor).
- **Seiten** (`pageZones`, DS offen und im Buch): unter den Bildschirmen eine Leiste mit L ganz links, dem Menü beiderseits des Falzes und R ganz rechts; darunter das Steuerkreuz auf der linken und die Aktionstasten auf der rechten Seite.
- **Geteiltes Menü** (`ControlZones.menuTrailing`): Läuft ein senkrechter Falz durch die Mitte unter dem Bild, aktiv oder nicht, steht Select mit der Pausentaste 8 pt vor ihm und Start 8 pt dahinter (je 124 pt breit). So sehen offen und Buch gleich aus.
- **Schutzrand oben** (seit der Prüfung, `LayoutMetrics.topEdgeGuard`): In den obersten 64 pt liegt nichts, was Berührungen nimmt, also keine Taste, kein Touchscreen und keine Pausentaste; ein sicherer Bereich oben zählt mit (`GameLayout.firstInputRow`). Bilder ohne Touch dürfen hinein. Gründe: die Randgesten des Systems an der Oberkante und die Reichweite der Daumen; der Streifen ohne Touch im Simulator war ein Fehler der App (Stolperfallen).
- **Pausentaste ohne Touch-Tasten** (`GameLayout.pauseButton`): 44 pt in der ersten Ecke des sicheren Bereichs unter dem Schutzrand, die weder Touchscreen noch aktiven Falz noch eine Verdeckungsregion berührt, in der Reihenfolge unten rechts, unten links, oben rechts, oben links. DS zugeklappt mit Controller: unten rechts unter dem Touchscreen; DS flach hochkant mit Controller (7×): oben rechts über dem oberen Bildschirm. Mit Touch-Tasten liegt sie in der Menüzone und nimmt Berührungen auf mindestens 44 × 44 pt, auch wo sie mit 36 pt gezeichnet ist.
- **Die Menüzone** (`ControlZones.menu`) nimmt Start, Select und die Pausentaste der App auf.
- **Regeln,** am Ende jeder Vorlage noch einmal durchgesetzt (`Templates.finished`): Tasten im sicheren Bereich unter dem Schutzrand, nie auf dem Touchscreen, nie auf einem aktiven Falz samt Rändern. Bildschirme ganzzahlig, im sicheren Bereich, nie auf dem Kern des Falzes (Falz ohne Ränder), außer einem einzelnen Bild im Buch. Der Touchscreen nimmt Eingaben wie die Tasten und bleibt deshalb auch aus den Rändern heraus; ein Bild ohne Touch darf hineinreichen.
- Ohne Touch-Tasten (Controller in Benutzung) werden die Bildschirme größer oder bleiben gleich, nie kleiner (Test `aControllerNeverShrinksAScreen`).

**Zahlen** mit den Maßen des Simulators, alle aus `GameLayoutTests` (Spalte „belegt“: auch im Simulator gemessen):

| System | Pose | Bild(er) | belegt |
| --- | --- | --- | --- |
| GBA | zu, Leiste oben (466 × 562 pt) | 5× 1200 × 800 px bei (99, 246) | UI-Test, Bildschirmfoto |
| GBA | zu, Leiste rechts | 4× 960 × 640 px bei (93, 0) | Test |
| GBA | zu, quer | 8×, Tasten über dem Bild | Test |
| GBA | flach quer, Buch 16 pt | 9× bei (346, 283), mit Controller 11× | Test |
| GBA | flach hochkant / Tabletop 16 pt | 8× bei (43, 73) / (43, 61) | Test |
| DS | zu, Leiste rechts (382 × 644 pt) | je 4× bei (61, 0) und (61, 768) | UI-Test, Bildschirmfoto |
| DS | zu, Leiste oben | 3×, mit Controller 4× | Test |
| DS | flach hochkant | 5× bei (363, 233) und (363, 1659), mit Controller 7× | Test |
| DS | flach quer / Buch 16 pt | 5× bei (73, 192) und (1499, 192) / (61, 192) und (1511, 192), am Schutzrand | Test |
| DS | Tabletop 16 pt | oben 7× bei (107, 29), Touchscreen 5× bei (363, 1671) | Test |
| DS | Tabletop, Plan 1878 × 2670 px | oben 6× bei (171, 91) | Test |

Mit 2007 × 2853 px bleibt der obere DS-Bildschirm im Tabletop 7-fach bis 55 pt Falzband, ab 56 pt 6-fach; mit 8 pt Rändern hält er 7-fach bei 55 pt nur, weil er in den Rand reicht (Test `screensReachIntoTheMarginsAndTheTouchScreenDoesNot`).

**Touch.** `TouchMapping` rechnet einen Punkt zuerst in den Gerätepixel um, der ihn enthält (`floor(p · s + 10⁻⁶)`), dann ganzzahlig in die Zelle (`floor((d − x₀) / k)`). Die Toleranz von einem Millionstel Pixel hält Punkte wie 121,333… pt auf ihrem Pixel, deren Produkt mit 3 knapp darunter fällt. `clampedPixel` klemmt auf den Rand, `framePixel` addiert die Lage im Kernbild (DS unten: y + 192), `center` liefert die Pixelmitte in Punkten. Belegt: alle 49 152 Pixelmitten bei Faktor 1 bis 7 und Ursprüngen, die kein Vielfaches von 3 sind, und jeder Gerätepixel einer Diagonale, einer Zeile und einer Spalte landet in seiner Zelle.

## Posen per Software (privates Werkzeug, nicht im Repo)

Stand 7. November 2026, geprüft mit Xcode 27.2 (27B52), Runtime iOS 27.1 (24A94425) und macOS 27.2. Ein Posen-Werkzeug setzt Winkel und Ausrichtung eines gebooteten Duo-Simulators per Software, wie die Knöpfe von Device Hub, aber ohne Klick und ohne sudo. Es nutzt private Schnittstellen des Simulators und ist deshalb nicht Teil des Repos: ein privates Werkzeug, nur für den Simulator und nur zur Entwicklung, nie in der App (ADR 0006, Abschnitt 15 und „Entscheidungen bei der Annahme“).

**Einbinden.** `Scripts/pose-check.sh` nimmt das Werkzeug über die Umgebungsvariable `POSE_CHECK_POSTURE_TOOL`: ein ausführbares Programm, das `<UDID> <Pose> [--orientation landscape-left] --quiet` versteht und erst zurückkehrt, wenn die Pose steht; scheitert es, bricht die Prüfung ab. Ohne die Variable, oder mit `POSE_CHECK_HUB=1`, fragt das Skript je Schritt nach dem Wechsel in Device Hub.

```bash
POSE_CHECK_POSTURE_TOOL=<Werkzeug> Scripts/pose-check.sh ds    # danach gba
```

| Pose | Winkel | Ausrichtung | Ergebnis (belegt) |
| --- | --- | --- | --- |
| `closed` | 0° | Hochformat | Außendisplay an, innen aus |
| `book` | 130° | Hochformat | innen an, Falz senkrecht; entspricht „Partially Open“ in Device Hub |
| `open` | 180° | Hochformat | innen an, flach, Falz senkrecht |
| `tabletop` | 90° | `landscape-left` | innen an, Falz waagerecht |

`--orientation landscape-left` ersetzt die Ausrichtung einer Pose: `open --orientation landscape-left` ist flach hochkant mit waagerechtem Falz, `closed --orientation landscape-left` das Querformat außen.

**Was es belegt:** den Weg des Systems mit echten Posen, also den Wechsel des Displays, die Layouts des Innendisplays mit der gemessenen Division-Region, Drawable und Display-Link dort (Abschnitt „Mit echten Posen belegt“, ADR 0006, Abschnitt „Posenprüfung per Software“). **Was nicht:** das Gerät. Dort kommt der Winkel vom Sensor, und Leistungszahlen zählen nur dort.

**Stolperfallen:**

- **Updates.** Private Schnittstellen können sich mit jedem Update von Xcode, der Simulator-Runtime oder macOS ändern. **Anwenden:** nach jedem Update mit dem Werkzeug `closed`, `open`, `book` und wieder `closed` einstellen und jedes Mal mit `xcrun devicectl device info displays` prüfen, welches Display aktiv ist; geht es nicht mehr, bleibt Device Hub.
- **Nie springen.** Ein Sprung von offen (180°) auf zu (0°) in einem Schritt ließ den Falzübergang des Simulators hängen; danach wechselten die Displays erst nach einem Neustart des Simulators wieder. **Anwenden:** den Winkel wie Device Hub in kleinen Schritten bewegen; ein Wechsel dauert so 3 bis 4 s.
- **Eine Quelle für den Winkel.** Zwei Quellen zugleich kämpfen gegeneinander. **Anwenden:** keinen zweiten Wechsel starten, solange einer läuft, und Device Hub nicht gleichzeitig am selben Simulator benutzen.
- **Nur eigene, gebootete Duo-Simulatoren.** `Scripts/pose-check.sh` legt dafür ein eigenes Gerät an und löscht es am Ende; fremde Geräte bleiben unberührt.
- `devicectl device orientation set` meldet für den Duo Erfolg, kommt im Simulator aber nicht an; die Ausrichtung geht nur mit `--orientation` oder in Device Hub.

## Mit echten Posen belegt

Am 7. November 2026 mit `Scripts/pose-check.sh ds` und `gba` (Posen per Software: zu, offen, Buch, Tabletop, flach hochkant, zu, offen; Rohwerte und Fotos in ADR 0006, Abschnitt „Posenprüfung per Software“):

- **Eine Szene für beide Displays.** „Scene shown“ steht einmal, danach nur „Screen changed“: außen 466 × 678 pt, innen 951 × 669 pt, im Tabletop und flach hochkant 669 × 951 pt. Beim Wechsel zwischen außen und innen startet der Display-Link neu, beim Drehen innen nicht; die Drawable folgt (1398 × 2034 → 2853 × 2007 → 2007 × 2853 px). Kein Wechsel ging durch eine andere Szenenphase. `PlaySession` bleibt damit bei `GameView` (ADR 0006, Abschnitt 9).
- **Division-Region innen:** ein Band von 121 px (40,3 pt), senkrecht bei x = 1366 px, wenn das Gerät hochkant steht (offen, Buch), waagerecht bei y = 1366 px, wenn es quer steht (Tabletop, flach hochkant); aktiv im Buch und im Tabletop, inaktiv flach. Außen gibt es keine.
- **Layouts:** DS offen und im Buch beide Bildschirme 5× links und rechts vom Falz, die Tasten darunter; im Tabletop oben 7×, unten der Touchscreen 5× mit den Tasten daneben; flach hochkant beide 5× über und unter dem Falz. GBA offen und im Buch 9× über den Falz hinweg (das Buch zählt in Version 1 als flach, Plan Abschnitt 7); im Tabletop und flach hochkant 8× über dem Falz, die Tasten darunter. Zugeklappt außen DS 4×, GBA 5× ohne senkrechte Leiste.
- **Übergänge:** Beim Drehen innen und beim Zuklappen entsteht 3 bis 15 ms lang ein Layout, in dem die Division-Region noch zur alten Lage gehört (Faktor 1 bis 2); danach kommt das richtige. Zu sehen wäre das höchstens ein Bild lang, beim Zuklappen pausiert das Spiel ohnehin.
- **Emulation:** keine Lücke über 50 ms und keine Neusynchronisation im Fenster eines Wechsels; beim Zuklappen „Paused: folded“ mit dem Pausenmenü außen, beim Aufklappen „Resumed“; DS 59,8 Bilder/s, GBA 59,7 bis 59,8 Bilder/s.

## Posen ohne den Weg des Systems (`DebugRemote`, seit der Integration von M2)

`DebugRemote` (nur Debug-Build, `App/Sources/Debug/DebugRemote.swift`) nimmt Darwin-Benachrichtigungen an und ändert damit die Pose eines laufenden Spiels, ohne Neustart:

| Benachrichtigung | Wirkung |
| --- | --- |
| `com.faentiver.arcfold.debug.fold.flat`, `.tabletop`, `.book` | ersetzt den gemessenen Falz wie `-ArcfoldFoldOverride` (flach: inaktive Linie über die Mitte; Tabletop und Buch: aktives Band von 16 pt) |
| `com.faentiver.arcfold.debug.fold.measured` | zurück zum gemessenen Falz |
| `com.faentiver.arcfold.debug.hinge.closed`, `.open` | übergibt `PlaySession.hingeChanged(from:to:)` einen Scharnierwechsel wie `onHingeChange`, vom zuletzt gesehenen Zustand aus |
| `com.faentiver.arcfold.debug.overlay.hide`, `.show` | blendet das Debug-Overlay aus und wieder ein, für Bildschirmfotos des ganzen Bildes |

- Senden aus einem Skript: `xcrun simctl spawn <UDID> notifyutil -p <Name>`; aus einem UI-Test: `notify_post` (Testprozess und App teilen das Benachrichtigungszentrum des Simulators). Jede Änderung steht im Log (Kategorie `fold`, „Simulated fold“, „Simulated hinge“).
- **Was es belegt:** Layoutwechsel, Viewports, Touch-Abbildung, Emulation, Ton und Pause beim Wechsel der Pose, in der echten App mit echtem Kern. **Was nicht:** den Weg des Systems, also den Wechsel des Displays, ob dieselbe Szene wandert, die Layouts des Innendisplays, die Größe der Drawable dort und den Display-Link dort. Die Geometrie bleibt die des Außendisplays; flach, Buch und Tabletop ergeben dort entartete Layouts (Faktor 1 bis 4). Den Weg des Systems belegen echte Posen, per Software (Abschnitt „Posen per Software“) oder mit Device Hub.
- UI-Tests: `PoseUITests` (Posenwechsel bei laufendem DS und GBA ohne Pause, auch keine kurze, Zuklappen und Fortsetzen außen, L und R in jeder Pose nach einem Tipp an die Oberkante, beide Testprogramme aus der Bibliothek) und `DSTouchUITests.testTapsHitTheirPixelsInEveryPose` (Touch in jeder Pose an allen 19 Stellen, nach einem Tipp an die Oberkante).

## Stolperfallen

- **Rahmen sind lokal.** `reservedRegions` liefert Rahmen im Koordinatenraum des lesenden Views: Ein Reader im sicheren Bereich meldete die Kamera bei y = −52,67, einer im Vollbild bei 29,33. **Anwenden:** um die Insets oben und links ins Vollbild verschieben.
- **`.ignoresSafeArea()` verschluckt die Insets.** Ein GeometryReader damit meldet `safeAreaInsets` 0. **Anwenden:** den sicheren Bereich mit einem View innerhalb davon messen.
- **`onGeometryChange` feuert auch ohne Größenänderung,** wenn sich nur eine reservierte Region ändert (84 × 174 → 84 × 82). **Anwenden:** die Regionen im selben Transform lesen; die Closure ist `@Sendable`, die Region lässt sich dort nonisolated lesen.
- **Touch auf ganze Gerätepixel gerundet.** Der Simulator liefert Positionen in Vielfachen von 1/3 pt; halbe Pixel kippen je nach Rundung (73,833 pt kam als 74 pt an). **Anwenden:** UI-Tests tippen auf Pixelmitten oder ganze Gerätepixel.
- **`screenConfig power off` schwärzt das Außendisplay** bis zum Neustart des Geräts, auch den Home-Bildschirm. **Anwenden:** `simctl io <UDID> screenConfig --display=1 power …` nie in Skripten.
- **Querformat außen nur per Software oder Device Hub:** `devicectl device orientation set` meldet Erfolg, `orientation get` bleibt `portrait`, die App dreht nicht; auch `XCUIDevice.shared.orientation` dreht das Fenster des zugeklappten Duo nicht. Das Posen-Werkzeug mit `closed --orientation landscape-left` dreht es (belegt am 7. November 2026: Außendisplay `rot270`, die Bibliothek quer mit der Systemspalte links; Abschnitt „Posen per Software“). **Anwenden:** Querformat außen vor dem Test mit dem Werkzeug oder in Device Hub einstellen, danach `closed` für hochkant.
- **XCTest auf dem Innendisplay.** **Warum:** Läuft die App innen (offen, Buch, Tabletop, flach hochkant), meldet XCTest den Rahmen des Anwendungselements in der eigenen Ausrichtung des Displays (669 × 951 pt, obwohl das Fenster 951 × 669 pt hat); Tipps relativ zur Anwendung (`app.coordinate(withNormalizedOffset:)`) gehen daneben, und `XCUIScreen.main` bleibt das ausgeschaltete Außendisplay (Foto 1398 × 2034 px, schwarz). Tipps relativ zu Elementen und zum Fenster kommen an; `XCUIScreen.screens` hat zwei Displays. Dem Foto des Fensters fehlen innen die letzte Zeile und die letzte Spalte der Bitmap in der eigenen Ausrichtung des Displays (2006 × 2852 statt 2007 × 2853 px). Offen und im Buch (Gerät hochkant, Innendisplay `rot90`) kommt die Bitmap gedreht mit der Ausrichtung `.right`; aufgerichtet fehlt dann die erste Spalte des Views, und jeder Pixel liegt einen Pixel weiter links (gegen `simctl io screenshot` gemessen: aufgerichtet und um einen Pixel nach rechts verschoben stimmen beide überein, mittlere Abweichung 0,03). Im Tabletop, flach hochkant und außen (`.up`) fehlen Spalte und Zeile rechts und unten, nichts verschiebt sich. Belegt am 7. November 2026 mit einer Sonde in offener und zugeklappter Pose und mit den UI-Tests in jeder Pose. **Anwenden:** UI-Tests tippen über `app.viewOrigin` und fotografieren mit `app.displayScreenshot()` (beide über das Fenster), Pixel lesen sie aus `uprightImage` (`UITestSupport.swift`), nie über `app.coordinate`, `XCUIScreen.main` oder `image.cgImage`; Größenvergleiche lassen einen Pixel zu.
- **StandBy:** `devicectl device settings standby --show` lehnt in dieser Pose ab.
- **Der lesende View darf seine Größe nicht von der Bühne bekommen.** Lag die Spielbühne mit fester Größe (der ganze View) und `.ignoresSafeArea()` als Geschwister im selben `ZStack`, wuchs der `ZStack` auf das Vollbild, der Leser maß 466 × 678 pt statt 382 × 644 pt, addierte die Insets ein zweites Mal und meldete 1649 × 2136 px (belegt im ersten Lauf der UI-Tests). **Warum:** Ein Kind mit fester Größe bestimmt die Größe des `ZStack` mit; die Messung wird so zur Rückkopplung. **Anwenden:** Die Bühne hängt als `.background(alignment: .topLeading)` am lesenden View; ein Hintergrund nimmt an der Größe seines Views nicht teil.
- **Vollbild über einem `NavigationStack` verschluckt Berührungen oben.** Lag das Spiel als `fullScreenCover` über dem `NavigationStack` der Bibliothek, kamen im Duo-Simulator (iOS 27.1, Außendisplay) nach einer einzigen Berührung der Oberkante alle späteren Berührungen in den obersten 60 bis 70 pt nicht mehr beim Spiel an, mindestens 20 s lang; tiefere kamen an. Unabhängig von `defersSystemGestures`, versteckter Statusleiste und `persistentSystemOverlays`. Eine Sonden-App zeigt dasselbe mit einer Liste im `NavigationStack` mit großem Titel, auch ohne Toolbar-Knöpfe; ohne `NavigationStack` darunter oder mit Wurzeltausch statt Vollbild kam jede Berührung an, auch an der Kante (belegt am 7. November 2026). Vermutlich nimmt die Navigationsleiste der verdeckten Bibliothek die Berührungen. SpringBoard hat oben immer ein Element von 466 × 100 pt, auch wenn alles ankommt; es ist nicht die Ursache. Vorher galt der Effekt als Streifen von 56 pt, den der Simulator nie an die App gibt; die Grenze hing an der Reihenfolge der Taps (eine Messung, die bei y = 5 pt beginnt, löst ihn selbst aus). **Warum:** L und R lagen zugeklappt in den oberen Ecken, der Touchscreen im Buch am oberen Rand; nach einem Griff an die Kante wären sie tot gewesen, vielleicht auch auf dem Gerät. **Anwenden:** Ein Spiel ersetzt die Bibliothek im Fenster (`RootView`), statt sie zu überdecken; keine Vollbild-Präsentation über einem `NavigationStack` für Ansichten, die oben Berührungen brauchen. UI-Tests tippen vor Touch-Prüfungen einmal an die Kante, damit eine Rückkehr des Fehlers auffällt.
- **`SpatialEventCollection.Event.ID` ist nicht `Sendable`.** **Warum:** Ein generischer Typ mit `Sendable`-Anforderung an die Kennung lässt sich damit nicht bilden. **Anwenden:** `TouchRouter<TouchID: Hashable>` ist nur bedingt `Sendable` (`where TouchID: Sendable`); Tests nehmen `Int` als Kennung.

## Offen

- Höhe und Ränder der `.division`-Region innen und Pixelmaße des Innendisplays auf dem Gerät (im Simulator 2007 × 2853 px und ein Band von 121 px, im Plan 1878 × 2670). Das Debug-Overlay zeigt beides (Zeile „Fold“).
- Ob ein Wechsel auf dem Gerät durch `scenePhase` `.inactive` läuft; im Simulator tat es keiner (Abschnitt „Mit echten Posen belegt“), die App pausiert ohnehin erst nach 300 ms (`docs/wissen/app.md`).
- Wie sich Berührungen an der Oberkante auf dem Gerät mit den Randgesten des Systems vertragen (Gerätetest, Punkt 25), und wo innen die Verdeckungsregionen liegen (Punkt 21).
