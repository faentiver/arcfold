---
name: geraetetest
description: Anleitung für alle ausstehenden Gerätetests auf dem iPhone Duo (M1 mit ADR 0005, Glas gegen flach mit ADR 0007, M2 mit ADR 0006, PS2-JIT mit ADR 0002), was dabei gemessen wird und wo die Ergebnisse hinkommen
---

# Gerätetest auf dem iPhone Duo

Stand 7. November 2026. Der Simulator sagt nichts über Bildrate, Wärme, Tonlatenz, Mehrfachberührung und JIT. Diese Anleitung bündelt alles, was nur das Gerät klärt. Teil 1 (M1) dauert etwa 45 Minuten, Teil 1b (Glas gegen flach, ADR 0007) etwa zwei Stunden, Teil 2 (PS2 mit JIT) etwa 30 Minuten, Teil 3 (M2, DS und Falz) etwa 45 Minuten; jeder Teil lässt sich getrennt machen.

## Einmalig vorbereiten (etwa 15 Minuten)

1. Auf dem Duo: Einstellungen → Datenschutz & Sicherheit → Entwicklermodus einschalten, das Gerät startet neu.
2. Am Mac mini: Xcode → Settings → Accounts → die kostenlose Apple-ID hinzufügen.
3. Im Repo `Scripts/bootstrap.sh`, dann `Arcfold.xcodeproj` öffnen.
4. Target „Arcfold“ → Signing & Capabilities → Team: das „Personal Team“ der Apple-ID. Das Projekt kommt aus XcodeGen, nach `xcodegen generate` ist die Auswahl wieder weg. Für einen Testtag genügt das.
5. Duo per Kabel verbinden, Scheme **Store** und das Duo als Ziel wählen, Run. Beim ersten Start auf dem Duo: Einstellungen → Allgemein → VPN und Geräteverwaltung → dem Entwicklerzertifikat vertrauen.
6. Den Test-ROM auf das Gerät bringen: `Tests/Fixtures/gba/selftest.gba` in den Ordner „iCloud Drive“ am Mac legen. So prüft der Import gleich den Weg über iCloud Drive.

Mit der kostenlosen Apple-ID läuft die App sieben Tage, danach einfach neu aus Xcode starten. Der Debug-Build zeigt das Debug-Overlay von selbst.

## Teil 1: M1 (ADR 0005)

Für jeden Punkt: das Overlay fotografieren oder die Werte notieren.

| Nr. | Was | Wie | Erwartet |
| --- | --- | --- | --- |
| 1 | Import aus iCloud Drive | Bibliothek → Import → iCloud Drive → selftest.gba | Spiel steht in der Bibliothek, kein Fehler |
| 2 | Bildrate über 10 Minuten | Spiel starten, liegen lassen, Bildschirm an | Overlay „Emulation“ 59,7 ± 0,1 fps, „trim“ innerhalb ±0,5 %, „resync“ 0 |
| 3 | Anzeige | dieselben 10 Minuten | „Display“ 60 oder 120 Hz, „skipped“ steigt kaum (im Simulator waren es 25 %) |
| 4 | Ton | Lautsprecher und Kopfhörer, Taste A halten wechselt den Ton | kein Knacken bei Start, Pause, Fortsetzen; „underruns“ bleibt 0 |
| 5 | Lautlos-Schalter | Schalter umlegen | Ton verstummt (`.ambient`) |
| 6 | Hintergrund | Home, 10 s warten, zurück | Spiel pausiert und läuft weiter, kein Knacken |
| 7 | Spielstand | App im App-Umschalter wegwischen, neu starten | Bootzähler im Bild um 1 höher |
| 8 | Mehrfachberührung | Richtung und A gleichzeitig halten, von A nach B gleiten | Overlay „Input held“ zeigt beide Tasten, „last“ wechselt beim Gleiten |
| 9 | Controller | DualSense oder Xbox koppeln, Tasten drücken | Ost = A, Süd = B; Touch-Tasten verschwinden nach dem ersten Druck, kommen beim Trennen zurück |
| 10 | Wärme | 30 Minuten spielen lassen | Overlay „Thermal“: nominal, höchstens fair |
| 11 | 60 gegen 120 Hz | Punkt 10 einmal mit Stromsparmodus (begrenzt auf 60 Hz) wiederholen | Entscheidung laut ADR 0005: 60 Hz nur, wenn 120 Hz deutlich wärmer wird |
| 12 | Innendisplay | Duo aufklappen, Bildschirmfoto (Seitentaste und Lauter), in Fotos die Infos öffnen | Pixelmaße notieren: 2007 × 2853 wie im Simulator oder 1878 × 2670 wie im Plan |
| 13 | Zweiter Emulator (falls installiert) | Import öffnen | `.gba`-Dateien sind auswählbar, nicht ausgegraut |

Optional, für genaue Zahlen: Konsole.app am Mac → das Duo wählen → Filter `subsystem:com.faentiver.arcfold category:stats`. Die App schreibt dort alle 10 s eine Zeile mit allen Werten des Overlays.

## Teil 1b: Glas gegen flach (ADR 0007)

Die Tasten aus Liquid Glass kosten den Render-Server Arbeit; zugeklappt quer liegen die des GBA alle über dem Spielbild, in den anderen Posen liegen die meisten auf dem Deck neben oder unter den Bildschirmen (seit dem Merge mit M2, `docs/wissen/oberflaeche.md`). Der Simulator misst das nur relativ; entscheidend ist das Duo. Etwa zwei Stunden, mit dem Debug-Build aus Xcode; die Läufe lassen sich auf mehrere Tage verteilen.

1. Das Scheme **Store** → Edit Scheme → Run → Arguments: `-ArcfoldControlSurface glass` eintragen. Für den Gegenlauf den Wert auf `flat` ändern. Ohne das Argument entscheidet das System (flach, solange iOS `systemPrefersReducedResourceUsage` meldet).
2. Je 10 Minuten `selftest.gba` laufen lassen, jeweils mit Glas und flach: zugeklappt hochkant und quer, einmal mit 120 Hz und einmal mit Stromsparmodus (60 Hz). Das sind acht Läufe. Dazu je 10 Minuten `selftest.nds` mit Glas und flach, aufgeklappt (offen).
3. Am Ende jedes Laufs das Overlay fotografieren, besser die Zeile aus Konsole.app (Filter `subsystem:com.faentiver.arcfold category:stats`) kopieren.
4. Einmal 30 Minuten quer mit Glas, danach 30 Minuten quer flach, und jeweils „Thermal“ notieren.
5. Optional: Instruments → Vorlage „Animation Hitches“ und „Metal System Trace“, je 2 Minuten quer mit Glas.

| Kriterium | Glas besteht, wenn |
| --- | --- |
| Anzeige | „Display“ weicht höchstens 1 Hz von flach ab |
| Übersprungene Bilder | „skipped“ liegt höchstens 1 Prozentpunkt über flach |
| Verspätete Bilder | „late“ in der Display-Zeile und „GPU busy“ bleiben 0 |
| Wärme | „Thermal“ nach 30 Minuten nicht schlechter als flach |
| Instruments | kein Frame über dem Budget, keine Hitches |

Fällt quer durch, wird quer standardmäßig flach (ADR 0007, „Folgen“). Hochkant liegt über dem Bild dauerhaft nichts aus Glas außer, beim DS zugeklappt, L und R über den unteren Ecken des oberen Bildschirms; der Pause-Knopf sitzt seit dem Merge in der Menüzeile auf dem Deck.

Außerdem, nur am Gerät sichtbar: Wirkt das Glas über hellen Spielen lesbar (selftest hat einen weißen Balken)? Zeigt der Pause-Knopf eine helle „Mondsichel“ an der Kante? Dann im PR melden; der Rückfall ist Rauchglas `.clear.tint(.black.opacity(0.45))` ohne eigene Platte.

Bedienung mit Glas am Gerät. G1 bis G3 sind seit dem Merge mit M2 auch im Simulator belegt, weil das private Posen-Werkzeug das Außendisplay quer stellt (`testSidewaysTheRButtonIsFree`, Tour-Zustand 12); am Gerät zählen sie mit echtem Glas und den Randgesten. Zwei Finger gehen im Simulator nur mit der Wahltaste:

| Nr. | Was | Wie | Erwartet |
| --- | --- | --- | --- |
| G1 | R quer | Duo quer halten, R antippen | Overlay „last R“, „presses“ steigt um 1; kein Pausenmenü |
| G2 | Pause quer | Pause-Knopf in der Menüzeile rechts unten (zwischen Select und Start) antippen | Sheet geht auf; Inhalt lesbar, nichts unter der Systemspalte abgeschnitten (Bildschirmfoto) |
| G3 | L durch das Debug-Overlay | quer im Debug-Build L dort antippen, wo das Debug-Overlay darüberliegt | „last L“, das Overlay nimmt keine Berührung an |
| G4 | Zwei Finger mit Glas | hochkant und quer: Steuerkreuz und A gleichzeitig halten, dann A und B, dann L und R | „Input held“ zeigt beide Tasten; beide leuchten sofort, nichts hinkt nach |
| G5 | Zug über die Tasten | hochkant mit zwei Fingern auf den Tasten nach unten ziehen | Das Spiel bleibt, Tasten melden den Zug; ein Schließen per Zoom gibt es seit dem Merge nicht mehr (`RootView`) |
| G6 | Sheet nach dem Zuklappen | im Spiel zuklappen, außen „Resume“, dann wieder zu und auf | Zuklappen zeigt das Sheet außen; „Resume“ spielt außen weiter; Aufklappen schließt das Sheet und setzt fort |

Wo der Ton-Chip sitzt (über dem Hinweis auf dem oberen oder einzigen Bildschirm), belegen `OverlayPlacementTests` und die Galerie-Seite `notices`; am Gerät erscheint er nur, wenn der Ton nicht startet.

## Teil 2: PS2 mit JIT (ADR 0002)

Die Schritte stehen in `docs/wissen/ps2-jit.md`, Abschnitt „Gerätetest auf dem Duo“: StikDebug einrichten, dann Test A (ausführbarer Speicher und ob er nach dem Detach bleibt) und Test D (Variante mit CodeGen-PR #34). Dafür das Scheme **JIT** statt Store bauen.

## Teil 3: M2, DS und Falz (ADR 0006)

Vorbereitung wie oben; dazu `Tests/Fixtures/ds/selftest.nds` in den Ordner „iCloud Drive“ am Mac legen. Das Debug-Overlay zeigt jetzt auch die Zeilen „Touch“ (letzter Zeigerpixel, Zahl der Drücke), „Fold“ (Pose, Größe des Views, sicherer Bereich, Falz, Verdeckungsregionen als „occlusion“) und „Screens“ (Rechtecke und Faktoren); die Zeile „Emulation“ zählt die Pausen („pauses“). Für jeden Punkt das Overlay fotografieren.

| Nr. | Was | Wie | Erwartet |
| --- | --- | --- | --- |
| 14 | DS-Import aus iCloud Drive | Bibliothek → Import → iCloud Drive → selftest.nds | Spiel steht als „DS“ in der Bibliothek, kein Fehler |
| 15 | Touch auf Glas | zugeklappt starten, mit dem Finger einzelne Punkte des unteren Bildschirms antippen, auch die vier Ecken | Fadenkreuz kreuzt rot am berührten Punkt, „Touch last“ zeigt denselben Pixel, „presses“ zählt jeden Tipp einmal |
| 16 | Ziehen und Abgleiten | auf dem unteren Bildschirm ziehen und über den Rand hinaus | Fadenkreuz folgt, am Rand bleibt es stehen; Tasten reagieren dabei nicht |
| 17 | Tasten und Touchscreen zugleich | mit einem Finger A halten, mit einem zweiten auf den Touchscreen tippen; dann umgekehrt | „Input held“ zeigt A, „Touch“ zählt den Tipp; ein Finger von A auf den Touchscreen drückt dort nichts |
| 18 | Alle Posen | zu, flach quer, halb offen wie ein Buch, gedreht als Tabletop, flach hochkant; in jeder Pose ein Foto des Overlays und des Bildes | Layout wie ADR 0006, Abschnitt 8; das Bild bleibt scharf (ganzzahlig), nichts liegt auf dem geknickten Falz |
| 19 | Zuklappen und Fortsetzen außen | während des Spiels zuklappen, außen „Resume“, dann wieder aufklappen | zugeklappt pausiert mit Menü außen; „Resume“ spielt außen weiter; Aufklappen nach einem Zuklappen ohne „Resume“ setzt von selbst fort |
| 20 | Posenwechsel ohne Ruckler | Punkt 18 bei laufendem Spiel, dann Konsole.app mit `subsystem:com.faentiver.arcfold category:fold` | keine Zeile „Emulation gap“ oder „Emulation resynchronized“ beim Wechsel, „pauses“ bleibt gleich; ob „Scene phase inactive“, „Game view disappeared“, „Screen changed“ oder eine neue Szene kommt, notieren |
| 21 | Maße innen | aufgeklappt flach und als Tabletop | „Fold“: Größe des Views (2007 × 2853 wie im Simulator oder 1878 × 2670 wie im Plan), Lage und Höhe des Falzbands, aktiv oder nicht, Ränder, dazu „occlusion“ (Lage und Größe der Kamera innen); liegt eine Taste oder der Touchscreen auf einer Verdeckungsregion, das Foto beilegen: dann folgen die Tasten den Regionen (ADR 0006, „Entscheidungen bei der Annahme“) |
| 22 | Bildrate und Wärme mit DS | selftest.nds 30 Minuten aufgeklappt flach | „Emulation“ 59,83 ± 0,1 fps, „resync“ 0, „underruns“ 0 nach dem Auffüllen; „Thermal“ höchstens fair |
| 23 | Ton mit DS über lange Zeit | in Punkt 22 auf „underruns“ achten, vor allem nach 90 s | bleibt 0; im Simulator brach die Wandlung aus der Bruchrate nach 80 bis 90 s ein, deshalb wandelt die App aus der auf ganze Hertz gerundeten Rate, beim DS 32 728 Hz (`docs/wissen/renderer.md`) |
| 24 | Display-Link je Display | „Display“ außen und innen ablesen | innen bis 120 Hz, außen laut Gerät; „skipped“ steigt kaum |
| 25 | Oberkante | (a) zugeklappt mit selftest.nds: einmal oben an die Kante tippen, dann L, R und den Touchscreen antippen; einmal von der Oberkante nach unten wischen und weiterspielen. (b) Im Buch (halb offen, Falz senkrecht): dasselbe mit den obersten Zeilen des Touchscreens und den Ecken. (c) Einen Controller koppeln und eine Taste drücken (Touch-Tasten weg), dann die Pausentaste antippen. (d) selftest.gba flach quer und im Buch: L und R antippen | Jeder Tipp zählt im Overlay („Input … presses“ bzw. „Touch last“, „presses“), auch nach dem Tipp an die Kante; nichts, was Berührungen nimmt, liegt in den obersten 64 pt; der erste Wisch von oben zeigt nur den Griff der Mitteilungszentrale, das Spiel läuft weiter, „pauses“ steigt höchstens um eins, falls die Mitteilungszentrale aufging. Im Simulator verschluckte ein Vollbild über der Bibliothek die Berührungen oben; das ist behoben (`docs/wissen/falz.md`, Stolperfallen) |
| 26 | Posen bei laufendem Spiel wie im Simulator | Punkte 18 bis 20 einmal mit selftest.gba | wie beim DS: Layout je Pose, Emulation läuft weiter, Pause nur beim Zuklappen |

Die echten Posenwechsel im Simulator prüft `Scripts/pose-check.sh`, mit Posen per Software über ein privates Werkzeug außerhalb des Repos (`POSE_CHECK_POSTURE_TOOL`) oder von Hand mit Device Hub (ADR 0006, Abschnitt 15); auf dem Gerät gelten dieselben Erwartungen. Die Layouts, die Emulation über den Wechsel, den Touchscreen und die Pause belegen im Simulator auch die UI-Tests mit eingespeister Pose (`DebugRemote`, `docs/wissen/falz.md`); den Wechsel des Displays selbst zeigen nur echte Posen, im Simulator wie auf dem Gerät.

## Danach

Fotos und Notizen sammeln. Die Werte kommen in ADR 0005 (neuer Abschnitt „Gerätetest“) und ADR 0002. Die Entscheidungen, die vom Gerät abhängen, fallen nach den Regeln in ADR 0005, Abschnitt „Entscheidungen bei der Annahme“:

- 120 Hz bleibt, solange es nicht deutlich wärmer wird.
- Ab mehr als 10 % späten Bildern mit spürbaren Folgen bekommt der Emulations-Thread eine Echtzeit-Policy.
- Die Falz-Layouts aus M2 nehmen die gemessenen Maße des Innendisplays; sie rechnen ohnehin mit dem Rahmen der Ansicht. Teil 3 kommt in ADR 0006 (neuer Abschnitt „Gerätetest“).
