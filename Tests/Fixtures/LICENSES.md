# Test-ROMs und ihre Lizenzen

Hier liegen ausschließlich frei lizenzierte Homebrew-Programme für Tests, gespeichert per Git LFS. Spiele, BIOS-Dateien, Firmware und Schlüssel sind verboten (siehe `CLAUDE.md`, harte Regeln).

Jeder Eintrag nennt Datei, Herkunft (URL und Commit oder Version), Autor, Lizenz und Prüfsumme (SHA-256).

## GBA

Noch keine.

## DS

Noch keine.

## PSP

Noch keine.

## PS2

| Datei | Herkunft | Autor | Lizenz | SHA-256 |
| --- | --- | --- | --- | --- |
| `ps2/alu.elf` | [ps2autotests](https://github.com/unknownbrackets/ps2autotests), `tests/cpu/ee/alu.elf`, Commit `97469ffbed8631277b94e28d01dabd702aa97ef3` (16.11.2019), Datei unverändert seit `e9bfc371` (07.04.2015) | ps2autotests project contributors (Unknown W. Brackets, Jean-Philip Desjardins) | ISC, Lizenztext mit Copyright-Vermerk in `ps2/LICENSE-ps2autotests.txt` (Kopie von `LICENSE.md` am selben Commit). Statisch gelinkte Laufzeit siehe unten. Das ELF läuft nur im Emulator und wird nicht mit der App gelinkt. | `b4e9bc2478a10b74d984b748cf4ae183798af1222c8ac5cfa61d2a76aff04dd6` |
| `ps2/alu.expected` | wie oben, `tests/cpu/ee/alu.expected` | wie oben | ISC, siehe `ps2/LICENSE-ps2autotests.txt` | `ca8e2f3e76df48f98b2ebc89b4d1181dd5b407e76e6bae642cfec5a933223c76` |
| `ps2/gs_sprites.elf` | eigenes Testprogramm, erzeugt mit `python3 -I Tests/Fixtures/ps2/gs_sprites/make_gs_sprites.py Tests/Fixtures/ps2/gs_sprites.elf` (ohne SDK, ohne BIOS) | The Arcfold Authors | GPL-3.0-only (SPDX-Angabe im Generator) | `a6099a01a25af0a0e9b916c2404ac223b19ec6afc97bf839e80b69195c14c122` |

Laufzeit in `alu.elf`: Das ELF ist ohne Symbole gelinkt. Übersetzt ist es mit GCC 3.2.2 (Abschnitt `.comment`), die Gerätepräfixe der Dateifunktionen („cdrom0:“, „host0:“, „mass0:“) deuten auf die libc von ps2sdk (AFL-2.0). Ob auch Teile von newlib darin stecken, lässt sich am ELF nicht feststellen. AFL-2.0 verlangt Hinweise nur im Quellcode abgeleiteter Werke (Abschnitt 6), nicht bei der Weitergabe eines übersetzten Programms (eigene Lesart des Lizenztexts). ps2autotests selbst verteilt `alu.elf` nur mit seiner ISC-Lizenz.

`alu.elf` prüft die ALU-Befehle der EE und schreibt die Ergebnisse auf stdout. Play! leitet stdout in `ps2_stdout.txt` um; ein korrekter Lauf erzeugt genau den Inhalt von `alu.expected`. Grafik zeigt das Programm nicht.

`gs_sprites.elf` stellt die Anzeige auf NTSC 640 × 448 und zeichnet in jedem Bild fünf farbige Flächen über den GIF. Weil es jedes Bild neu zeichnet, liefert Play! fortlaufend Bilder; das Programm dient für Bildvergleich und Bildrate. Der Generator erzeugt die Datei byte-genau reproduzierbar.
