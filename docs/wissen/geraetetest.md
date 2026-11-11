---
name: geraetetest
description: Anleitung für alle ausstehenden Gerätetests auf dem iPhone Duo (M1 mit ADR 0005, die Konsole mit ADR 0007, M2 mit ADR 0006, PS2-JIT mit ADR 0002), was dabei gemessen wird und wo die Ergebnisse hinkommen
---

# Gerätetest auf dem iPhone Duo

Stand 11. November 2026 (Teil 1b), sonst 7. November 2026. Der Simulator sagt nichts über Bildrate, Wärme, Tonlatenz, Mehrfachberührung und JIT. Diese Anleitung bündelt alles, was nur das Gerät klärt. Teil 1 (M1) dauert etwa 45 Minuten, Teil 1b (Konsole, ADR 0007) etwa eine Stunde, Teil 2 (PS2 mit JIT) etwa 30 Minuten, Teil 3 (M2, DS und Falz) etwa 45 Minuten; jeder Teil lässt sich getrennt machen.

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

## Teil 1b: Konsole (ADR 0007)

Die Spielansicht ist eine Konsole: ein Gehäuse in der Farbe des Systems, die Bildschirme in dunklen Blenden, ein Scharnier am Falz, Tasten als Kappen in Mulden mit eingeprägten Buchstaben. Glas liegt nur noch über dem Bild (die Menu-Taste mit Controller, wo keine Ecke des Gehäuses frei ist, die Hinweise, der Chip). Der Simulator zeigt Layout und Bild; wie die Tasten unter dem Daumen liegen, wie die Ecken der Anzeige und die Kamera zu den Blenden passen und was Sprachsteuerung und Bildrate machen, zeigt nur das Duo. Etwa eine Stunde mit dem Debug-Build aus Xcode, `selftest.gba` und `selftest.nds`. Den Vergleich Glas gegen flach an den Tasten gibt es nicht mehr, weil im laufenden Spiel keine Taste aus Glas ist; was bleibt, ist die Menu-Taste mit Controller (G15).

Bedienung der Konsole am Gerät. G1 bis G3 sind auch im Simulator belegt, weil das private Posen-Werkzeug das Außendisplay quer stellt (`testSidewaysTheRButtonIsFree`, Tour-Zustand 12); am Gerät zählen sie mit den Randgesten des Systems. Zwei Finger gehen im Simulator nur mit der Wahltaste:

| Nr. | Was | Wie | Erwartet |
| --- | --- | --- | --- |
| G1 | R quer | Duo quer halten, R antippen | Overlay „last R“, „presses“ steigt um 1; kein Pausenmenü |
| G2 | Menu-Taste quer | die Menu-Taste in der Reihe unter dem Bild (zwischen Select und Start) antippen | Sheet geht auf; Inhalt lesbar, nichts unter der Systemspalte abgeschnitten (Bildschirmfoto); Select und Start daneben lösen nichts aus |
| G3 | L neben dem Debug-Overlay | quer im Debug-Build L antippen; das Overlay liegt auf keiner Taste (`OverlayPlacement.debugArea`) | „last L“, „presses“ steigt um 1; das Overlay deckt keine Taste und nimmt keine Berührung an |
| G4 | Zwei Finger | hochkant und quer: Steuerkreuz und A gleichzeitig halten, dann A und B, dann L und R | „Input held“ zeigt beide Tasten; beide Kappen sinken sofort, nichts hinkt nach |
| G5 | Zug über die Tasten | hochkant mit zwei Fingern auf den Tasten nach unten ziehen | Das Spiel bleibt, die Tasten melden den Zug; ein Schließen per Zoom gibt es nicht (`RootView`) |
| G6 | Sheet nach dem Zuklappen | im Spiel zuklappen, außen „Resume“, dann wieder zu und auf | Zuklappen zeigt das Sheet außen; „Resume“ spielt außen weiter; Aufklappen schließt das Sheet und setzt fort |
| G7 | Ränder am Falz im Buch | Duo im Buch aufstellen, Bibliothek ansehen; ebenso die Lizenzen | Kein Kachelrand und kein Text liegt auf der Division-Region; jede Seite hält etwa 20 pt Abstand zu ihr (`FoldDivision.pageMargin`, im Simulator 20 pt bei einer Region von 121 px; die Region des Geräts kann anders sein, Maße notieren) |
| G8 | Pausen-Sheet | im Spiel Menu antippen, zugeklappt hochkant, im Buch und im Tabletop | Das Sheet ist so hoch wie sein Inhalt (im Simulator 269 pt, 34 pt unter „Quit Game“); im Tabletop bleibt es unter dem Falz; mit größter Schrift wächst es und scrollt; die Tasten der Konsole bleiben darunter stehen |
| G9 | Tasten treffen, Gefühl | `selftest.gba` und `selftest.nds` je fünf Minuten spielen, zugeklappt hochkant, zugeklappt quer, offen, im Tabletop; jede Taste einzeln, das Steuerkreuz in allen vier Richtungen und den Diagonalen, X, Y, A, B, Select, Start | Jede Taste löst dort aus, wo ihre Kappe gezeichnet ist (Overlay „last …“); Daumen treffen die Kappen ohne Hinsehen; die gedrückte Kappe sinkt sofort; Select und Start lassen sich vom Menu unterscheiden und werden nicht aus Versehen getroffen |
| G10 | L und R am Scharnier mit dem Daumen | DS zugeklappt, 3-fach (Voreinstellung): L und R an den Enden des Scharniers mit dem Daumen drücken, dann denselben Test in der schlanken Fassung (`-LargerScreens YES`, 4-fach) | L und R lösen sicher aus, ohne dass der Daumen den Touchscreen berührt; in der schlanken Fassung nimmt die Trefferfläche etwas über dem niedrigen Scharnier an, ohne den Touchscreen zu treffen; der Daumen ermüdet nicht |
| G11 | Runde Ecken der Anzeige gegen Blenden | zugeklappt hochkant, zugeklappt quer, offen: die Ecken der Anzeige gegen die Blenden und die Tasten ansehen; im Tabletop mit Controller (das Startargument `-ArcfoldControllerInUse` gibt es nur im Debug-Build, am Gerät lieber einen Controller verbinden) die obere Blende gegen den oberen Rand der Anzeige | Keine Blende und keine Taste wird von einer Ecke der Anzeige abgeschnitten; im Tabletop mit Controller ist das obere Bild nicht angeschnitten (im Simulator steht seine Blende dicht am oberen Rand, das Bild 3,7 pt davon; wie viel am Gerät sichtbar bleibt, notieren) |
| G12 | Sprachsteuerung | Sprachsteuerung einschalten, im Spiel „Tippe Menu“ und „Tippe Pause“ sagen | Beide Namen treffen die Menu-Taste; das Sheet geht auf; „Resume“ setzt fort |
| G13 | Bildrate mit Gehäuse | je 10 Minuten `selftest.gba` und `selftest.nds`, zugeklappt hochkant und offen, Zeilen der Kategorie `stats` aus Konsole.app kopieren (Filter `subsystem:com.faentiver.arcfold category:stats`); dazu 30 Minuten quer | Emulation bleibt bei den Werten der Posenprüfung (DS 59,8, GBA 59,7 Bilder/s), `resync`, „late“ der Anzeige und „GPU busy“ bleiben 0, „Thermal“ nach 30 Minuten nominal; das Gehäuse zeichnet sich bei Tastendrücken nicht neu (nur die gedrückte Taste) |
| G14 | Kamera und Lautsprecher | zugeklappt hochkant mit sichtbarer und versteckter Statusleiste ansehen | Die Mulde des Gehäuses sitzt um die Kamera und liegt in der Kapsel des Systems, die schwarze Kamera des Gehäuses deckt die echte; die Größe der echten Kamera notieren (gezeichnet ist die reservierte Region, im Simulator 37 pt) |
| G15 | Glas über dem Bild | einen Controller verbinden und eine Taste drücken (die Touch-Tasten verschwinden), `selftest.gba` und `selftest.nds` (weißer Balken) laufen lassen, dazu im Stromsparmodus (flach) | Die Menu-Taste steht in einer freien Ecke des Gehäuses oder, wo keine frei ist, als Glas ganz im Bild und liegt nie quer über einer Blende; sie bleibt über dem weißen Balken lesbar, mit Glas wie flach; der Hinweis (Ton) bleibt lesbar; außerdem notieren, ob das Pausen-Sheet am Gerät skaliert gezeichnet wird (im Simulator mit iOS 27.2 auf einem iPhone ohne Falz 386 statt 402 pt breit, auf dem Duo mit iOS 27.1 nicht) |
| G16 | Farben und Lesbarkeit | DS in Kreide und Graphit, GBA in Indigo und Petrol (`-CaseFinish graphite|petrol`) draußen in hellem Licht und im Dunkeln ansehen | Die Namen von Select, Start und Menu und die Buchstaben auf den Kappen sind lesbar; die Farben wirken ruhig, nichts blendet |

Wo der Ton-Chip sitzt (über dem Hinweis auf dem oberen oder einzigen Bildschirm), belegen `OverlayPlacementTests` und die Galerie-Seite `notices`; am Gerät erscheint er nur, wenn der Ton nicht startet.

Ergebnisse tragen die Nummern G1 bis G16 in den Pull Request ein, mit Foto und Zeilen aus `stats` bei G13.

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
