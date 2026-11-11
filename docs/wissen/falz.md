---
name: falz
description: Duo-APIs im iOS-SDK 27.2 (Scharnier, reservierte Regionen, vertikale Leiste), Duo-Simulator mit Device Hub und Displays, gemessene Maße, FoldLayout (Leser, Vorlagen für die Konsole von ADR 0007 mit Handgerät, Falz am Rand und Schutzrand oben, Tests über alle Geometrien, Touch-Abbildung), echte Posen per Software (privates Werkzeug außerhalb des Repos, eingebunden über POSE_CHECK_POSTURE_TOOL), Posen ohne den Weg des Systems (DebugRemote) und Stolperfallen, darunter das Vollbild, das oben Berührungen verschluckte; Grundlage der Falz-Layouts in ADR 0006
---

# Falz

Stand 7. November 2026 (Abschnitt FoldLayout und Posenprüfung am 11. November 2026 an die Konsole angepasst), Xcode 27.2 (27B52), iOS-SDK 27.2, Simulator-Runtime iOS 27.1 (24A94425). Quellen: die Erkundung zu M2 mit dem Prototyp FalzProbe (nicht im Repo), die Umsetzung in Spur L (Paket `Packages/FoldLayout`, Belege in `docs/adr/0006/falz-simulator.txt`), die Integration (`docs/adr/0006/m2-abnahme-simulator.txt`) und die Nachbesserungen nach der Prüfung (ADR 0006, gleichnamiger Abschnitt; Sonden-App nicht im Repo). Die Entscheidungen stehen in ADR 0006 und, für die Konsole, in ADR 0007; hier stehen Fakten, der Aufbau von FoldLayout und Stolperfallen. Kennzeichnung: **belegt** (gemessen oder im SDK gelesen), **Annahme**, **offen**.

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

**Vorlagen** (`GameLayout(system:geometry:showsTouchControls:metrics:)`, Maße in Punkt, seit dem 11. November 2026 an die Konsole angepasst, ADR 0007, „Konsole statt Glastasten“; vorher Spalte 112, Band 128, L und R 44 hoch): Spalte 134, Abstand 8, Schutzrand oben 64, Blende 8, Steuerkreuz 110 bis 146 (bis 170, wo die Tasten einen Teil der Fläche für sich haben), L und R 40 hoch, Menüzeile 44 hoch (niedrigste 28), Scharnier der Konsole 44 (schlank 20), Menüzelle höchstens 60 × 44, Menü bis 196 breit, Abstand des Menüs zu Steuerkreuz und Aktionstasten 24.

| Pose | Ein Bildschirm | Zwei Bildschirme (DS) |
| --- | --- | --- |
| zu, hochkant | oben, volle Breite, darunter die Leiste mit L, Menü und R, darunter Steuerkreuz und Aktionstasten | beide oben in der Mitte mit dem Scharnier der Konsole dazwischen, L und R an seinen Enden, darunter Steuerkreuz, Menü als Spalte und Raute; schlank: Leiste des Systems daneben, Scharnier 20 pt |
| zu, quer, und jede Anzeige ohne Falz quer | Handgerät (siehe unten) | Handgerät mit dem Stapel, oder beide nebeneinander mit dem Scharnier darunter, wo sie dabei nicht kleiner werden |
| flach mit senkrechtem Falz, Buch | in der Mitte über den Falz zwischen zwei Griffen, Menü unter dem Bild beiderseits des Falzes | links vom Falz der obere, rechts der Touchscreen, beide am Schutzrand, darunter die Leiste und die Tasten |
| flach mit waagerechtem Falz, Tabletop | in der oberen Hälfte mit einem Rand des Gehäuses, Leiste und Tasten unten | oben so groß wie möglich mit Rand, Touchscreen mit Steuerkreuz und Raute unten, Menü darunter |

Zwei Regeln gelten in jeder Vorlage (seit dem 11. November 2026, nach Fatihs Rückmeldung zu den Bildern; `MenuPlacementTests`, `LayoutInvariantTests`):

- **Steuerkreuz und Aktionstasten liegen auf einer Höhe.** Ihre Zonen decken dieselben Zeilen (`finished` gleicht sie an), die Tasten sitzen in der Mitte ihrer Zone.
- **Das Menü (Select, Menu, Start) sitzt mittig direkt unter dem Bild, nie unter den Aktionstasten oder dem Steuerkreuz**, und hält zu beiden 24 pt (`menuKeepOut`). Vorher stand es in den Spalten unter den Aktionstasten und schob sie 22 bis 66 pt über das Steuerkreuz.

Die Bausteine:

- **Band** (`bandZones`): direkt unter dem Bild eine Leiste mit L, dem Menü in der Mitte und R (44 pt hoch, das Menü bis 196 pt breit, L und R mindestens 64 pt), darunter Steuerkreuz links und Aktionstasten rechts über dieselbe Höhe, mittig zwischen Leiste und Unterkante der Anzeige. L, Steuerkreuz und die Blende des Bildes beginnen auf einer Linie, R, Aktionstasten und Blende enden auf einer, wo die Blende das zulässt. Ein Band, das für Leiste und Tasten zu niedrig ist, setzt L und R über die unteren Ecken des Bildschirms darüber und das Menü als Spalte zwischen Steuerkreuz und Aktionstasten (`lowBandZones`).
- **Scharnier der Konsole** (`hingeZones`, DS zugeklappt und DS zugeklappt quer): L und R sind Tasten wie überall und stehen an den Enden des Scharniers, am Scharnier 100 pt breit und 40 pt hoch; L beginnt, wo das Steuerkreuz beginnt, R endet, wo die Raute endet. Darunter stehen Steuerkreuz, Menü und Raute in gleichen Abständen. Das Menü ist eine Reihe, wo die Breite reicht, sonst eine Spalte mit 100 pt, in der engsten mit 80 pt; in der Spalte endet Start genau am Ziel der Menu-Taste. Das schlanke Scharnier (20 pt) ist für eine Taste zu niedrig: L und R sind seine Enden, ihre Trefferflächen reichen etwas über das Scharnier auf die unteren Ecken des oberen Bildschirms, nie auf den Touchscreen, und die Tasten darunter beginnen 2 pt unter dem Touchscreen.
- **Spalten** (`sideZones`, Handgerät, Griffe neben dem Bild): links L und das Steuerkreuz, rechts R und die Aktionstasten; L und R stehen oben in den Griffen auf Höhe der Oberkante der Blende, Steuerkreuz und Aktionstasten auf der Mittellinie des Bildes. Das Menü liegt zwischen den Spalten unter dem Bild; die Lücke dazwischen ist `max(0, min(16, frei − 44), min(10, frei − 28))` pt. Lässt das Bild darunter weniger Platz, rückt es nach oben (`raised`), nie aus dem sicheren Bereich. Bleiben unter einem Bild ohne Touch weniger als 28 pt, liegt das Menü über seinem unteren Rand; unter einem Touchscreen ohne Platz gehen seine zwei Teile an den Fuß der Spalten (kommt in keiner Pose des Duo vor).
- **Seiten** (`pageZones`, DS offen und im Buch): unter den Bildschirmen eine Leiste mit L ganz links, dem Menü beiderseits des Falzes und R ganz rechts; darunter das Steuerkreuz links und die Aktionstasten rechts. Bild, L und Steuerkreuz beginnen auf einer Linie.
- **Geteiltes Menü** (`ControlZones.menuTrailing`): Läuft ein senkrechter Falz durch die Mitte unter dem Bild, aktiv oder nicht, steht Select mit der Menu-Taste 8 pt vor ihm und Start 8 pt dahinter. So sehen offen und Buch gleich aus.
- **Handgerät** (`Templates.handheldScale`): Ohne Falz quer (iPhone, Duo zugeklappt quer) steht ein Bild mit Blende in der Mitte, das Menü darunter, links und rechts eine Spalte von 134 pt. Der Faktor ist der größte, bei dem 240 k (beim gestapelten DS die Breite des Stapels) plus zwei Spalten in die sichere Breite und 160 k plus 2 × 8 pt Blende, 2 pt Haarstrich und 28 pt niedrigste Menüzeile in die sichere Höhe passen. Passt kein k ab 1, liegen die Tasten wie in M1 über dem Bild. Auf iPhones quer: 812 und 852 pt 5-fach, 874, 932 und 956 pt 6-fach (vorher 7-fach auf 874 pt mit Glas über dem Bild); der gestapelte DS auf 932 × 430 pt steht 2-fach nebeneinander statt 3-fach gestapelt, weil das Menü sonst unter Steuerkreuz und Aktionstasten läge. Der DS quer auf iPhones bleibt klein (ADR 0007, Entscheidung 6).
- **Schmale Fläche hochkant:** Wo die Blende seitlich nicht neben das Bild passt (iPhone 402 pt breit, GBA 5-fach, 1 pt Rand), zählt der Faktor mehr als die Blende: Das Bild läuft von Rand zu Rand, und die Blende ist ein Band über die ganze Breite mit eckigen Enden (`endsAtLeftEdge`, `endsAtRightEdge`).
- **Falz am Rand** (`GameLayout.placeable`): Ist eine Seite des Falzes im sicheren Bereich quer zum Falz schmaler als 134 pt oder leer, rechnet die Vorlage ohne Falz in der größeren Seite, mit dem sicheren Bereich bis zum Falz. Die Pose bleibt die der Geometrie, und das Gehäuse zeichnet das eigene Scharnier statt des Falzes. Beispiel: 669 × 475 pt mit einem Falz am unteren Rand, GBA 5-fach, DS 3-fach nebeneinander, der Touchscreen im sichtbaren Teil.
- **Falz von oben nach unten in einer Ansicht, die höher als breit ist** (gibt es nur eingespeist: `-ArcfoldFoldOverride book` oder `fold.book` auf einem Display ohne Falz, nur Debug): Das GBA nimmt die Vorlage hochkant ohne Falz (Bild oben, über dem Falz wie im Buch), die Leiste teilt das Menü am Falz (Select und Menu davor, Start dahinter, je 8 pt daneben, Teile 64 bis 128 pt breit), L und R geben dafür bis auf 64 pt nach, Steuerkreuz und Aktionstasten bleiben auf ihrer Seite. Tests: `HandheldTests.uprightAFoldDownDividesTheMenuBelowThePicture` (18 Fälle), `TouchLayoutTests.uprightTheSimulatedBookKeepsEveryKeyOfTheGBA` (6 Fälle). Beim DS ist diese Geometrie nicht angepasst: L und R sind dort 46 bis 58 pt breit, unter den 64 pt der Invarianten; alle Tasten sind da und drücken (UI-Test grün), die Invariantenprüfung deckt nur das GBA ab.
- **Schutzrand oben** (`LayoutMetrics.topEdgeGuard`): In den obersten 64 pt liegt nichts, was Berührungen nimmt, also keine Taste, kein Touchscreen und keine Pausentaste; ein sicherer Bereich oben zählt mit (`GameLayout.firstInputRow`). Bilder ohne Touch dürfen hinein. Auch die Trefferflächen (Toleranz um eine Taste, Reichweite des Steuerkreuzes) enden dort und am aktiven Falz (`TouchLayout.Limits`, `docs/wissen/app.md`). Gründe: die Randgesten des Systems an der Oberkante und die Reichweite der Daumen; der Streifen ohne Touch im Simulator war ein Fehler der App (Stolperfallen).
- **Menu-Taste ohne Touch-Tasten** (`GameLayout.pauseButton`): 44 pt in der ersten Ecke des sicheren Bereichs unter dem Schutzrand, die weder Touchscreen noch aktiven Falz noch eine Verdeckungsregion noch einen Bildschirm samt Blende berührt, in der Reihenfolge unten rechts, unten links, oben rechts, oben links; hat keine Ecke des Gehäuses Platz, liegt sie als Glas in einer Ecke innerhalb eines Bildschirms ohne Touch, 8 pt vom Rand, nie quer über einer Blende. Beispiel: DS flach hochkant mit Controller, unten rechts im oberen Bildschirm. Mit Touch-Tasten liegt sie als Menu-Taste in der Menüzone und nimmt Berührungen auf mindestens 44 × 44 pt.
- **Die Menüzone** (`ControlZones.menu`) nimmt Start, Select und die Menu-Taste der App auf.
- **Regeln,** am Ende jeder Vorlage noch einmal durchgesetzt (`Templates.finished`): Tasten im sicheren Bereich unter dem Schutzrand, nie auf dem Touchscreen, nie auf einem aktiven Falz samt Rändern. Bildschirme ganzzahlig, im sicheren Bereich, nie auf dem Kern des Falzes (Falz ohne Ränder), außer einem einzelnen Bild im Buch. Der Touchscreen nimmt Eingaben wie die Tasten und bleibt deshalb auch aus den Rändern heraus; ein Bild ohne Touch darf hineinreichen.
- Ohne Touch-Tasten (Controller in Benutzung) werden die Bildschirme größer oder bleiben gleich, nie kleiner (Test `aControllerNeverShrinksAScreen`).

**Tests über alle Geometrien:** `LayoutInvariantTests` prüft die Regeln dieser Vorlagen über viele Geometrien: den Duo in allen Posen, fünf iPhones hochkant und quer und den Falz am Rand (aktiv und inaktiv, GBA und DS, mit und ohne Tasten). Dazu gehören der Abstand des Menüs zu Steuerkreuz und Aktionstasten, die Teile des Menüs in einer Reihe oder Spalte, ein geteiltes Menü beiderseits eines senkrechten Falzes, das Menü unter jedem Bild, unter dem es steht, und eine Liste der Fälle, in denen Tasten über einem Bildschirm stehen dürfen (nur die schlanke Fassung des DS). Die Tests der App laufen über dieselben Geometrien für beide Systeme (`ConsoleCaseTests`: jeder Bildschirm in einer Blende, keine Taste auf einer Blende, die Mulde einer Taste berührt keinen Bildschirm, ein Scharnier schneidet keinen Bildschirm, mit Controller liegt die Menu-Taste nicht auf Blende, Falz oder Kamera); `HandheldTests` hält die Größen der iPhones fest, `TouchLimitTests` die Grenzen der Trefferflächen.

**Zahlen** mit den Maßen des Simulators, alle aus `GameLayoutTests` (Spalte „belegt“: auch im Simulator gemessen):

| System | Pose | Bild(er) | belegt |
| --- | --- | --- | --- |
| GBA | zu, Leiste oben (466 × 562 pt) | 5× 1200 × 800 px bei (99, 246) | UI-Test, Bildschirmfoto |
| GBA | zu, Leiste rechts | 4× 960 × 640 px bei (93, 0) | Test |
| GBA | zu, quer | 5× bei (417, 270); ohne sicheren Bereich (Annahme) 5× bei (417, 209), mit Controller 8× | Test |
| GBA | flach quer, Buch 16 pt | 8× bei (466, 273), mit Controller 11× | Test |
| GBA | flach hochkant / Tabletop 16 pt | 7× bei (163, 153) / (163, 141), mit Controller 8× | Test |
| DS | zu, Leiste oben (466 × 562 pt) | 3× je 768 × 576 px bei (315, 246) und (315, 954), mit Controller 4× | UI-Test, Bildschirmfoto |
| DS | zu, Leiste rechts, schlank | 4× bei (61, 0) und (61, 828) | Test |
| DS | zu, quer | 3× bei (231, 246) und (1035, 246) | Test |
| DS | flach hochkant | oben 6×, Touchscreen 4×, mit Controller beide 7× | Test |
| DS | flach quer / Buch 16 pt | 5× bei (73, 192) und (1499, 192) / (61, 192) und (1511, 192), am Schutzrand | Test |
| DS | Tabletop 16 pt | oben 6× bei (235, 125), Touchscreen 4× bei (491, 1677) | Test |
| DS | Tabletop, Plan 1878 × 2670 px | oben 6× bei (171, 91) | Test |

Mit 2007 × 2853 px und Tasten bleibt der obere DS-Bildschirm im Tabletop wegen des Randes des Gehäuses bei jedem Falzband bis 64 pt 6-fach; ohne Tasten ist er 7-fach bis 55 pt Falzband, ab 56 pt 6-fach (Test `dsTabletopUpperScreen`); mit 8 pt Rändern hält er 7-fach bei 55 pt nur, weil er in den Rand reicht (Test `screensReachIntoTheMarginsAndTheTouchScreenDoesNot`).

**Touch.** `TouchMapping` rechnet einen Punkt zuerst in den Gerätepixel um, der ihn enthält (`floor(p · s + 10⁻⁶)`), dann ganzzahlig in die Zelle (`floor((d − x₀) / k)`). Die Toleranz von einem Millionstel Pixel hält Punkte wie 121,333… pt auf ihrem Pixel, deren Produkt mit 3 knapp darunter fällt. `clampedPixel` klemmt auf den Rand, `framePixel` addiert die Lage im Kernbild (DS unten: y + 192), `center` liefert die Pixelmitte in Punkten. Belegt: alle 49 152 Pixelmitten bei Faktor 1 bis 7 und Ursprüngen, die kein Vielfaches von 3 sind, und jeder Gerätepixel einer Diagonale, einer Zeile und einer Spalte landet in seiner Zelle.

## Posen per Software (privates Werkzeug, nicht im Repo)

Stand 7. November 2026, geprüft mit Xcode 27.2 (27B52), Runtime iOS 27.1 (24A94425) und macOS 27.2. Ein Posen-Werkzeug setzt Winkel und Ausrichtung eines gebooteten Duo-Simulators per Software, wie die Knöpfe von Device Hub, aber ohne Klick und ohne sudo. Es nutzt private Schnittstellen des Simulators und ist deshalb nicht Teil des Repos: ein privates Werkzeug, nur für den Simulator und nur zur Entwicklung, nie in der App (ADR 0006, Abschnitt 15 und „Entscheidungen bei der Annahme“).

**Einbinden.** `Scripts/pose-check.sh` nimmt das Werkzeug über die Umgebungsvariable `POSE_CHECK_POSTURE_TOOL`: ein ausführbares Programm, das `<UDID> <Pose> [--orientation landscape-left] --quiet` versteht und erst zurückkehrt, wenn die Pose steht; scheitert es, bricht die Prüfung ab. Ohne die Variable, oder mit `POSE_CHECK_HUB=1`, fragt das Skript je Schritt nach dem Wechsel in Device Hub.

```bash
POSE_CHECK_POSTURE_TOOL=<Werkzeug> Scripts/pose-check.sh ds    # danach ds-slim und gba
```

`ds-slim` startet `selftest.nds` mit `-LargerScreens YES`: die schlanke Fassung des DS mit der Leiste des Systems neben dem Spiel und 4-fachen Bildschirmen, in eigener Szene.

Die Schritte des Skripts (jeder nach dem Wechsel 4 s ohne Eingriff, dann Bildschirmfotos beider Displays und der Zustand der Displays): `01-closed` (Start), `02-closed-landscape` (zu, quer: das Spiel steht als Handgerät auf dem Außendisplay und läuft weiter), `03-open`, `04-book`, `05-tabletop`, `06-flat-upright`, `07-closed` (Zuklappen: das Spiel pausiert, das Pausenmenü steht außen) und `08-open` (Aufklappen: das Spiel setzt von selbst fort). Ohne Werkzeug fragt das Skript je Schritt nach dem Wechsel in Device Hub; der Text dort für Drehen und Zurückdrehen ist nicht geprüft.

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

Stand 7. November 2026, vor der Konsole: Die Faktoren und die Lage der Tasten dieses Abschnitts sind die der Layouts davor, die heutigen stehen im Abschnitt FoldLayout; die Aussagen zu Szene, Display, Division-Region und Emulation gelten unverändert. Die Läufe nach der Konsole stehen im folgenden Abschnitt „Nach der Konsole (11. November 2026)“.

**Nach der Konsole (11. November 2026)** (`Scripts/pose-check.sh ds`, `ds-slim` und `gba`, je etwa 3 Minuten, Posen per Software, Exit 0 in jedem Lauf):

- **Pause und Fortsetzen:** in jedem Lauf „Paused: folded“ beim Zuklappen und „Resumed“ beim Aufklappen, nie „Game view disappeared“.
- **GBA:** keine Lücken und keine Neusynchronisationen, auch neben weiteren Testläufen auf demselben Mac.
- **DS:** Der Lauf ohne andere Last auf dem Mac (13:55, vor den Nachbesserungen nach dem Lauf, die den Weg der Emulation nicht berühren) blieb ohne Lücke und ohne Neusynchronisation, mit 59,8 Bildern/s. Zwei Läufe neben weiteren Testläufen auf demselben Mac (15:53 und 17:50) zeigten Lücken von 51,9 bis 66,0 ms und 14 und 28 Neusynchronisationen, an wechselnden Schritten und zum Teil Sekunden nach dem Wechsel (einmal 3,4 s nach dem neuen Layout). Das Soll „keine Lücke und keine Neusynchronisation im Fenster eines Wechsels“ ist in diesen beiden Läufen verfehlt; das Bild spricht für die Last des Macs als Ursache, nicht für den Wechsel.
- **DS schlank:** bisher nur neben weiteren Testläufen gelaufen (15:55): im Fenster des Wechsels zum Buch (04) eine Lücke von 52,5 ms, zum Tabletop (05) 12 Neusynchronisationen und Lücken von 61,5 und 56,6 ms, zu zugeklappt (07) 2 Neusynchronisationen. Ein Lauf ohne andere Last steht aus.
- **Anwenden:** Die Posenprüfung misst Echtzeit und läuft allein auf dem Mac. Neben anderen Builds oder Tests sagt ein Lauf mit Lücken nichts über die App; er wird ohne Last wiederholt.

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
| `com.faentiver.arcfold.debug.keys.hold`, `.release` | hält Hoch, A, L und Select wie mit Fingern gedrückt und lässt sie los: ein Bildschirmfoto zeigt gedrückte Tasten, und das Spiel sieht sie |

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
