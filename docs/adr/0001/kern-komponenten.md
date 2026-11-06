# Komponenten im PPSSPP-Kern und ihre Lizenzen

Stand 6. November 2026, PPSSPP v1.20.4 (`fa50bb1`), gebaut mit `Scripts/build-core.sh ppsspp`. Grundlage für die Lizenzhinweise der App (harte Regel „Lizenzen“) in M3.

Erzeugt aus dem Build-Graphen des Simulator-Builds:

```bash
ninja -C build/cores/ppsspp/iphonesimulator/cmake -t inputs ppsspp_libretro   # kompilierte Quellen
ninja -C build/cores/ppsspp/iphonesimulator/cmake -t deps                     # eingebundene Header
```

Die Lizenzen habe ich aus den Lizenzdateien der Ordner gelesen, wo es keine gibt aus den Kopfkommentaren der Quellen (Spalte „Beleg“). Pfade relativ zu `Cores/ppsspp`.

## Kompiliert

| Komponente | Pfad | Dateien | Lizenz | Beleg |
| --- | --- | --- | --- | --- |
| PPSSPP | `Common`, `Core`, `GPU`, `libretro/*.cpp`, dazu die erzeugte `git-version.cpp` | 528 + 1 | GPL-2.0-or-later, darin Teile des PSPSDK unter BSD | `LICENSE.TXT`, `README.md` |
| libretro-common | `libretro/libretro-common` | 11 | MIT | Kopfkommentare |
| glslang | `ext/glslang` | 49 | BSD-3-Clause, BSD-2-Clause, MIT, Apache-2.0; der erzeugte Parser `glslang_tab.cpp` GPL-3.0-or-later mit Bison-Ausnahme | `LICENSE.txt` |
| SPIRV-Cross | `ext/SPIRV-Cross` | 6 | Apache-2.0 | `LICENSE` |
| cpu_features | `ext/cpu_features` | 17 | Apache-2.0 | `LICENSE` |
| basis_universal | `ext/basis_universal` | 1 | Apache-2.0 | Kopfkommentare |
| jpge | `ext/jpge` | 2 | Public Domain oder Apache-2.0 | `README.md` |
| armips | `ext/armips` | 56 | MIT | `LICENSE.txt` |
| Lua | `ext/lua` | 32 | MIT | `lua.h` |
| rcheevos | `ext/rcheevos` | 23 | MIT | `LICENSE` |
| VulkanMemoryAllocator | `ext/vma` | 1 | MIT | `vk_mem_alloc.h` |
| pugixml | `ext/pugixml` | 1 | MIT | Kopfkommentare |
| gason | `ext/gason` | 1 | MIT | `LICENSE` |
| CityHash | `ext/cityhash` | 1 | MIT | `COPYING` |
| riscv-disas, loongarch-disasm | `ext/riscv-disas.cpp`, `ext/loongarch-disasm.cpp` | 2 | MIT | Kopfkommentare |
| libzip | `ext/libzip` | 112 | BSD-3-Clause | Kopfkommentare |
| zstd | `ext/zstd` | 30 | BSD-3-Clause (wahlweise GPL-2.0) | `LICENSE`, `COPYING` |
| libchdr | `ext/libchdr` | 16 | BSD-3-Clause | `LICENSE.txt` |
| snappy | `ext/snappy` | 4 | BSD-3-Clause | `COPYING` |
| SFMT | `ext/sfmt19937` | 1 | BSD-3-Clause | Kopfkommentare |
| udis86 | `ext/udis86` | 6 | BSD-2-Clause | `LICENSE` |
| xxHash | `ext/xxhash.c` | 1 | BSD-2-Clause | Kopfkommentar |
| libpng 1.7 | `ext/libpng17` | 17 | libpng-Lizenz | `png.h` |
| LZMA SDK | `ext/lzma-sdk` | 13 | Public Domain | Kopfkommentare |
| minimp3 | `ext/minimp3` | 1 | CC0-1.0 | `minimp3.h` |
| disarm | `ext/disarm.cpp` | 1 | eigene freie Lizenz (Hinweis im Quelltext behalten) | Kopfkommentar |
| at3_standalone | `ext/at3_standalone` | 9 | LGPL-2.1-or-later (aus FFmpeg) | `README.txt`, Kopfkommentare |
| libkirk | `ext/libkirk` | 6 | GPL-3.0-or-later; Teile „GPL version 2 or version 3“; AES Public Domain | Kopfkommentare |
| xBRZ | `ext/xbrz` | 1 | GPL-3.0 mit MAME-Ausnahme | `xbrz.h` |
| aemu_postoffice | `ext/aemu_postoffice` | 6 | GPL-3.0 (Lizenztext ohne „or later“-Angabe) | `gpl-3.0.txt` |

## Nur über Header

| Komponente | Pfad | Lizenz | Beleg |
| --- | --- | --- | --- |
| Vulkan-Header | `ext/vulkan` | Apache-2.0 | SPDX-Angaben |
| OpenXR-SDK | `ext/OpenXR-SDK` | Apache-2.0 OR MIT | SPDX-Angaben |
| RapidJSON | `ext/rapidjson` | MIT | `license.txt` |
| sol2 | `ext/sol` | MIT | Kopfkommentare |
| stb_rect_pack | `ext/stb` | MIT oder Public Domain | Kopfkommentar |
| miniupnp | `ext/miniupnp` | BSD-3-Clause | `LICENSE` |
| zlib | `ext/zlib` | zlib-Lizenz (die Bibliothek selbst kommt aus dem System) | `zlib.h` |

## Folgen

- **Lizenz des Kerns:** Der gebaute Kern verbindet GPL-2.0-or-later-Code (PPSSPP) mit GPL-3.0-Code (xBRZ, libkirk, aemu_postoffice) und Apache-2.0-Code (SPIRV-Cross, cpu_features, basis_universal), der mit GPL-2.0 nicht vereinbar ist. Weitergeben lässt er sich deshalb nur unter GPL-3.0. Das passt zur App (GPL-3.0).
- **Hinweispflichten:** BSD, MIT, zlib, libpng und Apache-2.0 verlangen Copyright-Vermerk und Lizenztext in der Doku der Binärfassung, also unter „Lizenzen“ in der App. NOTICE-Dateien hat keine der Apache-2.0-Komponenten im Baum (`find Cores/ppsspp/ext -maxdepth 3 -iname 'NOTICE*'` leer). PPSSPPs `LICENSE.TXT` enthält zusätzlich den BSD-Vermerk des PSPSDK.
- **LGPL:** at3_standalone (LGPL-2.1-or-later) ist mit GPL-3.0 vereinbar; das gilt auch für ein späteres FFmpeg-Rezept.
- **MoltenVK** steckt nicht im Kern, sondern in der App (Apache-2.0, `build/moltenvk/MoltenVK/LICENSE`). MoltenVK v1.4.2 baut laut `ExternalRevisions` auf SPIRV-Cross, SPIRV-Headers, SPIRV-Tools, Volk, Vulkan-Headers, Vulkan-Tools und cereal auf; welche davon im statischen Archiv landen, prüft M3 (Annahme: mindestens SPIRV-Cross und cereal).
- **Offen für M3:** die Liste beim Wechsel der PPSSPP-Version mit denselben Befehlen neu erzeugen und die Lizenztexte für den Bildschirm „Lizenzen“ sammeln.
