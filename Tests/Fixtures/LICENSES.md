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
| `ps2/alu.elf` | [ps2autotests](https://github.com/unknownbrackets/ps2autotests), `tests/cpu/ee/alu.elf`, Commit `97469ffbed8631277b94e28d01dabd702aa97ef3` (16.11.2019), Datei unverändert seit `e9bfc371` (07.04.2015) | ps2autotests project contributors (Unknown W. Brackets, Jean-Philip Desjardins) | ISC (`LICENSE.md` im Repo). Das ELF enthält statisch gelinkte Laufzeitteile aus ps2sdk (AFL-2.0) und der EE-Toolchain (GCC 3.2.2 mit newlib). Es läuft nur im Emulator und wird nicht mit der App gelinkt. | `b4e9bc2478a10b74d984b748cf4ae183798af1222c8ac5cfa61d2a76aff04dd6` |
| `ps2/alu.expected` | wie oben, `tests/cpu/ee/alu.expected` | wie oben | ISC | `ca8e2f3e76df48f98b2ebc89b4d1181dd5b407e76e6bae642cfec5a933223c76` |
| `ps2/gs_sprites.elf` | eigenes Testprogramm, erzeugt mit `python3 -I Tests/Fixtures/ps2/gs_sprites/make_gs_sprites.py Tests/Fixtures/ps2/gs_sprites.elf` (ohne SDK, ohne BIOS) | The Arcfold Authors | GPL-3.0-only (SPDX-Angabe im Generator) | `a6099a01a25af0a0e9b916c2404ac223b19ec6afc97bf839e80b69195c14c122` |

`alu.elf` prüft die ALU-Befehle der EE und schreibt die Ergebnisse auf stdout. Play! leitet stdout in `ps2_stdout.txt` um; ein korrekter Lauf erzeugt genau den Inhalt von `alu.expected`. Grafik zeigt das Programm nicht.

`gs_sprites.elf` stellt die Anzeige auf NTSC 640 × 448 und zeichnet in jedem Bild fünf farbige Flächen über den GIF. Weil es jedes Bild neu zeichnet, liefert Play! fortlaufend Bilder; das Programm dient für Bildvergleich und Bildrate. Der Generator erzeugt die Datei byte-genau reproduzierbar.
