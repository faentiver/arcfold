# Test-ROMs und ihre Lizenzen

Hier liegen ausschließlich frei lizenzierte Homebrew-Programme für Tests. Sie sind klein und liegen als normale Dateien im Repo, ohne Git LFS. Spiele, BIOS-Dateien, Firmware und Schlüssel sind verboten (siehe `CLAUDE.md`, harte Regeln).

Jeder Eintrag nennt Datei, Herkunft (URL und Commit oder Version), Autor, Lizenz und Prüfsumme (SHA-256).

## GBA

### `gba/selftest.gba`

- **Herkunft:** eigenes Testprogramm in diesem Repo, erzeugt mit `python3 -I Tests/Fixtures/gba/selftest/make_gba_selftest.py Tests/Fixtures/gba/selftest.gba` (ohne SDK, ohne BIOS, Logo-Bereich leer). Zwei Läufe ergaben dieselbe Prüfsumme. Erstellt am 6. November 2026 für ADR 0005.
- **Autor:** Fatih (faentiver).
- **Lizenz:** GPL-3.0-or-later (SPDX-Angabe im Generator), wie alle eigenen Testprogramme (Plan, Abschnitt 12, festgelegt am 7. November 2026).
- **Inhalt:** Modus 3 mit einem Balken, der pro Bild um ein Pixel wandert, dazu Boot-, Bild- und Tastenzähler als 8 × 8-Blöcke. Rechteckton auf PSG-Kanal 2 mit 439,8 Hz, bei gedrückter Taste A 879,7 Hz. SRAM mit der Kennung „ARCF“, dem Boot-Zähler in Byte 4 und einem Herzschlag alle 64 Bilder in Byte 5. Positionen und Farben stehen im Generator. Startet in mGBA 0.10.5 ohne BIOS (Beleg: `docs/adr/0005/selftest-mgba-macos.txt`).
- **SHA-256:** `7df143129e713b1188ec40b3d91bd84ccb95188dd1f6264f2bb75fba4544f9fd` (864 Bytes)

## DS

Noch keine.

## PSP

### `psp/gu-test.elf`

- **Herkunft:** eigener Quelltext in diesem Repo, `Tests/Fixtures/psp/gu-test/main.c`, gebaut mit `Tests/Fixtures/psp/gu-test/build.sh` und der PSPDEV-Toolchain [v20261101](https://github.com/pspdev/pspdev/releases/tag/v20261101) (Archiv `pspdev-macos-latest-arm64.tar.gz`, SHA-256 `066a20cf743bcf9ff948cc8c2f1204ad705ad018e9f80ccd444e488f44bc22c8`). Zwei Builds ergaben dieselbe Prüfsumme. Erstellt am 6. November 2026 für ADR 0001.
- **Autor:** Fatih (faentiver).
- **Lizenz:** eigener Code GPL-3.0-or-later (SPDX-Kopf in `main.c`). Statisch gelinkt sind Teile von [PSPSDK](https://github.com/pspdev/pspsdk/tree/c3da4314d783ac26323e5cdaf8163ac369c2089d) (BSD-3-Clause), [newlib](https://github.com/pspdev/newlib/tree/09d1adaf18bdac953fc401deb3c04e41ae9ee510) libc und libm (BSD-artige Lizenzen laut `COPYING.NEWLIB`), [pthread-embedded](https://github.com/pspdev/pthread-embedded/tree/97fe4ce006b420894f2bcaeb530d1f1f53111fc2) (LGPL-2.1) und libgcc aus [GCC](https://github.com/pspdev/gcc/tree/1a33997924916ff5a6f61b64179ff9c8921f46c6) (GPL-3.0 mit GCC Runtime Library Exception). Alle sind mit GPL-3.0 vereinbar.
- **Inhalt:** zeichnet pro Frame einen texturierten, rotierenden Würfel (Tiefentest, bilineare Filterung), ein Dreieck mit Farbverlauf, ein halbtransparentes Rechteck und einen Balken, der pro Frame um ein Pixel wächst. Gleiche Frame-Nummer, gleiches Bild.
- **SHA-256:** `fde83fb4e689c6da37211743ab4b8170e0c4314d165ccee36d62b604808500ef` (144 260 Bytes)

## PS2

| Datei | Herkunft | Autor | Lizenz | SHA-256 |
| --- | --- | --- | --- | --- |
| `ps2/alu.elf` | [ps2autotests](https://github.com/unknownbrackets/ps2autotests), `tests/cpu/ee/alu.elf`, Commit `97469ffbed8631277b94e28d01dabd702aa97ef3` (16.11.2019), Datei unverändert seit `e9bfc371` (07.04.2015) | ps2autotests project contributors (Unknown W. Brackets, Jean-Philip Desjardins) | ISC, Lizenztext mit Copyright-Vermerk in `ps2/LICENSE-ps2autotests.txt` (Kopie von `LICENSE.md` am selben Commit). Statisch gelinkte Laufzeit siehe unten. Das ELF läuft nur im Emulator und wird nicht mit der App gelinkt. | `b4e9bc2478a10b74d984b748cf4ae183798af1222c8ac5cfa61d2a76aff04dd6` |
| `ps2/alu.expected` | wie oben, `tests/cpu/ee/alu.expected` | wie oben | ISC, siehe `ps2/LICENSE-ps2autotests.txt` | `ca8e2f3e76df48f98b2ebc89b4d1181dd5b407e76e6bae642cfec5a933223c76` |
| `ps2/gs_sprites.elf` | eigenes Testprogramm, erzeugt mit `python3 -I Tests/Fixtures/ps2/gs_sprites/make_gs_sprites.py Tests/Fixtures/ps2/gs_sprites.elf` (ohne SDK, ohne BIOS) | Fatih (faentiver) | GPL-3.0-or-later (SPDX-Angabe im Generator) | `a6099a01a25af0a0e9b916c2404ac223b19ec6afc97bf839e80b69195c14c122` |

Laufzeit in `alu.elf`: Das ELF ist ohne Symbole gelinkt. Übersetzt ist es mit GCC 3.2.2 (Abschnitt `.comment`), die Gerätepräfixe der Dateifunktionen („cdrom0:“, „host0:“, „mass0:“) deuten auf die libc von ps2sdk (AFL-2.0). Ob auch Teile von newlib darin stecken, lässt sich am ELF nicht feststellen. AFL-2.0 verlangt Hinweise nur im Quellcode abgeleiteter Werke (Abschnitt 6), nicht bei der Weitergabe eines übersetzten Programms (eigene Lesart des Lizenztexts). ps2autotests selbst verteilt `alu.elf` nur mit seiner ISC-Lizenz.

`alu.elf` prüft die ALU-Befehle der EE und schreibt die Ergebnisse auf stdout. Play! leitet stdout in `ps2_stdout.txt` um; ein korrekter Lauf erzeugt genau den Inhalt von `alu.expected`. Grafik zeigt das Programm nicht.

`gs_sprites.elf` stellt die Anzeige auf NTSC 640 × 448 und zeichnet in jedem Bild fünf farbige Flächen über den GIF. Weil es jedes Bild neu zeichnet, liefert Play! fortlaufend Bilder; das Programm dient für Bildvergleich und Bildrate. Der Generator erzeugt die Datei byte-genau reproduzierbar.
