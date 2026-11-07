---
name: geraetetest
description: Anleitung für alle ausstehenden Gerätetests auf dem iPhone Duo (M1 mit ADR 0005, PS2-JIT mit ADR 0002), was dabei gemessen wird und wo die Ergebnisse hinkommen
---

# Gerätetest auf dem iPhone Duo

Stand 7. November 2026. Der Simulator sagt nichts über Bildrate, Wärme, Tonlatenz, Mehrfachberührung und JIT. Diese Anleitung bündelt alles, was nur das Gerät klärt. Teil 1 (M1) dauert etwa 45 Minuten, Teil 2 (PS2 mit JIT) etwa 30 Minuten und lässt sich getrennt machen.

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

## Teil 2: PS2 mit JIT (ADR 0002)

Die Schritte stehen in `docs/wissen/ps2-jit.md`, Abschnitt „Gerätetest auf dem Duo“: StikDebug einrichten, dann Test A (ausführbarer Speicher und ob er nach dem Detach bleibt) und Test D (Variante mit CodeGen-PR #34). Dafür das Scheme **JIT** statt Store bauen.

## Danach

Fotos und Notizen sammeln. Die Werte kommen in ADR 0005 (neuer Abschnitt „Gerätetest“) und ADR 0002. Die Entscheidungen, die vom Gerät abhängen, fallen nach den Regeln in ADR 0005, Abschnitt „Entscheidungen bei der Annahme“:

- 120 Hz bleibt, solange es nicht deutlich wärmer wird.
- Ab mehr als 10 % späten Bildern mit spürbaren Folgen bekommt der Emulations-Thread eine Echtzeit-Policy.
- Die Falz-Layouts aus M2 nehmen die gemessenen Maße des Innendisplays.
