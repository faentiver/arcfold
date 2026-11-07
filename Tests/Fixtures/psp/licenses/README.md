# Lizenzen der Laufzeit in `psp/gu-test.elf`

`gu-test.elf` ist ein eigenes Testprogramm (GPL-3.0-or-later), gebaut mit der PSPDEV-Toolchain v20261101 (siehe `../../LICENSES.md`). Beim Linken kommen Teile der folgenden Bibliotheken fest in das Programm. Ihre Lizenzen verlangen, dass die Texte bei der Weitergabe beiliegen. Die Dateien hier sind unverändert, jeweils vom genannten Commit.

| Datei | Bibliothek | Lizenz | Quelle |
| --- | --- | --- | --- |
| `PSPSDK-LICENSE` | PSPSDK | BSD-3-Clause | [pspdev/pspsdk @ c3da4314](https://github.com/pspdev/pspsdk/blob/c3da4314d783ac26323e5cdaf8163ac369c2089d/LICENSE) |
| `newlib-COPYING.NEWLIB` | newlib (libc und libm) | BSD-artige Lizenzen, Liste in der Datei | [pspdev/newlib @ 09d1adaf](https://github.com/pspdev/newlib/blob/09d1adaf18bdac953fc401deb3c04e41ae9ee510/COPYING.NEWLIB) |
| `pthread-embedded-COPYING`, `pthread-embedded-COPYING.LIB` | pthread-embedded | LGPL-2.1 | [pspdev/pthread-embedded @ 97fe4ce0](https://github.com/pspdev/pthread-embedded/tree/97fe4ce006b420894f2bcaeb530d1f1f53111fc2) |
| `GCC-COPYING.RUNTIME` | libgcc aus GCC 15.2.0 | GPL-3.0 mit GCC Runtime Library Exception; der GPL-Text ist `LICENSE` im Wurzelordner | [pspdev/gcc @ 1a339979](https://github.com/pspdev/gcc/blob/1a33997924916ff5a6f61b64179ff9c8921f46c6/COPYING.RUNTIME) |

Zur LGPL-2.1: Der Quelltext des Programms (`../gu-test/main.c`) und das Build-Skript (`../gu-test/build.sh`) liegen im Repo. Damit lässt sich das Programm mit einer geänderten Fassung von pthread-embedded neu linken.
