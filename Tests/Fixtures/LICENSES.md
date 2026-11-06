# Test-ROMs und ihre Lizenzen

Hier liegen ausschließlich frei lizenzierte Homebrew-Programme für Tests, gespeichert per Git LFS. Spiele, BIOS-Dateien, Firmware und Schlüssel sind verboten (siehe `CLAUDE.md`, harte Regeln).

Jeder Eintrag nennt Datei, Herkunft (URL und Commit oder Version), Autor, Lizenz und Prüfsumme (SHA-256).

## GBA

Noch keine.

## DS

Noch keine.

## PSP

### `psp/gu-test.elf`

- **Herkunft:** eigener Quelltext in diesem Repo, `Tests/Fixtures/psp/gu-test/main.c`, gebaut mit `Tests/Fixtures/psp/gu-test/build.sh` und der PSPDEV-Toolchain [v20261101](https://github.com/pspdev/pspdev/releases/tag/v20261101) (Archiv `pspdev-macos-latest-arm64.tar.gz`, SHA-256 `066a20cf743bcf9ff948cc8c2f1204ad705ad018e9f80ccd444e488f44bc22c8`). Zwei Builds ergaben dieselbe Prüfsumme. Erstellt am 6. November 2026 für ADR 0001.
- **Autor:** Arcfold-Projekt (faentiver), geschrieben mit Claude Code.
- **Lizenz:** eigener Code GPL-3.0-or-later (SPDX-Kopf in `main.c`). Statisch gelinkt sind Teile von [PSPSDK](https://github.com/pspdev/pspsdk/tree/c3da4314d783ac26323e5cdaf8163ac369c2089d) (BSD-3-Clause), [newlib](https://github.com/pspdev/newlib/tree/09d1adaf18bdac953fc401deb3c04e41ae9ee510) libc und libm (BSD-artige Lizenzen laut `COPYING.NEWLIB`), [pthread-embedded](https://github.com/pspdev/pthread-embedded/tree/97fe4ce006b420894f2bcaeb530d1f1f53111fc2) (LGPL-2.1) und libgcc aus [GCC](https://github.com/pspdev/gcc/tree/1a33997924916ff5a6f61b64179ff9c8921f46c6) (GPL-3.0 mit GCC Runtime Library Exception). Alle sind mit GPL-3.0 vereinbar.
- **Inhalt:** zeichnet pro Frame einen texturierten, rotierenden Würfel (Tiefentest, bilineare Filterung), ein Dreieck mit Farbverlauf, ein halbtransparentes Rechteck und einen Balken, der pro Frame um ein Pixel wächst. Gleiche Frame-Nummer, gleiches Bild.
- **SHA-256:** `fde83fb4e689c6da37211743ab4b8170e0c4314d165ccee36d62b604808500ef` (144 260 Bytes)

## PS2

Noch keine.
