# 0001 · PSP-Grafik: Vulkan über MoltenVK

Status: Vorgeschlagen · 6. November 2026

Kennzeichnung: **belegt** heißt im Spike ausgeführt oder im Quelltext/SDK nachgelesen, **Annahme** heißt nicht geprüft, **Gerät** heißt erst auf dem iPhone Duo prüfbar.

## Kontext

PSP ist das riskanteste System im Plan: PPSSPP rendert nicht in einen Pixelpuffer, sondern verlangt über `RETRO_ENVIRONMENT_SET_HW_RENDER` einen GPU-Kontext vom Host (Plan, Abschnitt 5, Leitplanke 5; Abschnitt 11, erstes Risiko). M0 Schritt 7 sollte klären, ob PPSSPP in unserem eigenen Host mit GPU-Grafik läuft und welcher Weg in M3 kommt, bevor Arbeit daran hängt.

Aufbau des Spikes (belegt):

- **Kern:** PPSSPP v1.20.4 (Commit `fa50bb1`) als Submodul `Cores/ppsspp`, libretro-Ziel über PPSSPPs CMake, gebaut mit `Scripts/build-core.sh ppsspp` für iPhone und Simulator (arm64, `minos 27.0`). Nötig sind 13 der 23 Unter-Submodule und ein verschachteltes in armips. FFmpeg ist abgeschaltet (siehe Folgen).
- **Host:** `Spikes/PSPGPU`, eine iOS-App, die den Kern per `dlopen` aus `Frameworks/` lädt, die Environment-Callbacks bedient und drei Wege anbietet: OpenGL ES über EAGL, Vulkan über MoltenVK 1.4.2 (offizielles Release von Khronos) und PPSSPPs Software-Renderer.
- **Inhalt:** eigenes Testprogramm `Tests/Fixtures/psp/gu-test.elf` (GPL-3.0, Quelltext im Repo, Lizenzen in `Tests/Fixtures/LICENSES.md`). Ein fertiges Homebrew mit eindeutiger Lizenz habe ich nicht gefunden; PPSSPPs Testsammlung `pspautotests` zum Beispiel hat keine Lizenz (`LICENSE.txt`: „TO FILL WITH THE LEAST RESTRICTIVE COMPATIBLE LICENSE“).
- **Lauf:** Simulator iPhone 18 Pro mit iOS 27.2 (24B8117), Xcode 27.2 (27B52), Mac mini M4 Pro. Der Duo-Simulator ließ sich nicht anlegen: Die Runtime iOS 27.2 (24B8117) schließt `iPhone19,4` (Duo) in ihrer `profile.plist` unter `unsupportedDeviceTypes` aus. Für die Grafikfrage spielt das Gerätemodell keine Rolle.

### Frage a: OpenGL ES im iOS-27.2-SDK und im Simulator

- **SDK (belegt):** `OpenGLES.framework` liegt in `iPhoneOS27.2.sdk` und `iPhoneSimulator27.2.sdk` (Build 24B8118). `EAGLContext`, `EAGLSharegroup` und `EAGLGetVersion` tragen `OPENGLES_DEPRECATED(ios(2.0, 12.0), tvos(9.0, 12.0))`, dazu 246 Deklarationen in `ES3/gl.h` und 142 in `ES2/gl.h`. Der Makro-Text lautet „OpenGLES API deprecated. (Define GLES_SILENCE_DEPRECATION to silence these warnings)“. Die GL-Brücke von CoreVideo (`CVOpenGLESTextureCache`) ist mit „OpenGL/OpenGLES is no longer supported. Use Metal APIs instead.“ markiert. Als `unavailable` ist für iOS nichts markiert.
- **Simulator (belegt):** Ein EAGL-Kontext mit `kEAGLRenderingAPIOpenGLES3` entsteht und läuft: `GL_VERSION OpenGL ES 3.0 APPLE-24.0.2`, `GL_RENDERER Apple Software Renderer`. OpenGL ES läuft im Simulator also auf der CPU.
- **Simulator (belegt):** Der Zero-Copy-Weg zu Metal, ein IOSurface-`CVPixelBuffer` als GL-Textur und als `MTLTexture`, scheitert im Simulator an `CVOpenGLESTextureCacheCreateTextureFromImage` mit `-6683` (`kCVReturnPixelBufferNotOpenGLCompatible`). Der Spike liest dann mit `glReadPixels`. Ob der Weg auf dem Gerät geht: **Gerät**.
- **Zukunft (Annahme):** Eine Ankündigung, dass Apple OpenGL ES in iOS 27 entfernt, habe ich nicht gefunden (Websuche am 6. November 2026). Veraltet ist es seit iOS 12 (2018).

### Frage b: Was der Kern anfordert und was der Host bereitstellt

Belegt durch den Quelltext von PPSSPP v1.20.4 (`libretro/LibretroGraphicsContext.cpp`, `LibretroGLContext.h`, `LibretroVulkanContext.cpp`, `libretro_vulkan.cpp`) und die Berichte der Läufe in `docs/adr/0001/`.

Der Kern wählt in `retro_load_game`: Er fragt `GET_PREFERRED_HW_RENDER`, die Core-Option `ppsspp_backend` (`auto`, `opengl`, `vulkan`, `none`) überstimmt die Antwort. Dann versucht er GL, danach Vulkan, zuletzt den Software-Renderer. Der Spike setzt die Option und meldet denselben Typ als bevorzugt. Der GL-Versuch greift nur bei `DUMMY`, `OPENGL` oder `OPENGLES3`; ein Host, der `OPENGLES2` als bevorzugt meldet, bekäme kein GL.

| | OpenGL ES | Vulkan |
| --- | --- | --- |
| `SET_HW_RENDER` | `OPENGLES2`, Version 0.0, `depth` an, `stencil` aus, `bottom_left_origin` an, `cache_context` aus | `VULKAN`, Version 1.0.18 (steht im Feld `version_major`), `depth` an, `cache_context` an |
| Host stellt bereit | EAGL-Kontext (der Spike nimmt ES 3.0, der Kern erkennt „OpenGL ES 3.0 support detected“), Framebuffer mit Farbe und `DEPTH24_STENCIL8`, `get_current_framebuffer`, `get_proc_address` (`dlsym`). Der Kontext muss auf dem Thread aktuell sein, der `retro_run` aufruft. | `VkInstance`, `VkSurfaceKHR` auf einem `CAMetalLayer`, Device über die Negotiation, `retro_hw_render_interface_vulkan` Version 5 |
| Threads | CPU-Emulation auf einem eigenen Kern-Thread, die GL-Befehle laufen im `retro_run` des Hosts | ohne Befehlspuffer synchron in `retro_run`; mit Puffer zusätzlich ein Render-Thread (im Spike aus, siehe Folgen) |
| Bild | im Host-Framebuffer, Ursprung unten links, 480 × 270 bei 1x (PPSSPP schneidet standardmäßig auf 16:9 zu) | Der Kern ruft `set_image` aus seinem emulierten `vkQueuePresentKHR`, ohne Semaphoren, Layout `SHADER_READ_ONLY_OPTIMAL`, Format `B8G8R8A8_UNORM` |

Einzelheiten zum Vulkan-Weg (alle belegt):

- **Instanz:** Der Kern liefert `VkApplicationInfo` mit API 1.0, fragt aber `vkEnumerateInstanceVersion` ab und nutzt, was er findet. Der Host legt die Instanz deshalb mit der gemeldeten Version an (1.4.357), mit `VK_KHR_surface`, `VK_EXT_metal_surface`, `VK_KHR_get_physical_device_properties2` und `VK_EXT_swapchain_colorspace`.
- **Surface:** Pflicht. Der Kern setzt eine Surface voraus (`assert(surface)` in `vk_libretro_init`) und fragt über sie Fähigkeiten, Formate und Present-Modi ab, präsentiert aber nie.
- **Device:** Der Kern meldet Negotiation-Version 2, setzt aber nur `get_application_info` und `create_device` (Version 1); `create_instance`, `create_device2` und `destroy_device` sind leer. Er erzeugt das Device selbst und hängt die Pflichterweiterungen des Hosts an. `VK_KHR_portability_subset` aktiviert er nicht von sich aus, MoltenVK verlangt es laut Spezifikation, also übergibt der Host es, dazu `VK_EXT_metal_objects`.
- **Bilder:** Der Kern legt so viele „Swapchain“-Bilder an, wie `get_sync_index_mask` Bits hat, in der Größe 480 × 272 mal Skalierung (minus 2 Zeilen bei 16:9). Vor jedem Frame ruft er `wait_sync_index` und `get_sync_index`, seine Submits schließt er in `lock_queue`/`unlock_queue` ein. `set_command_buffers` und `set_signal_semaphore` nutzt er nicht.
- **Abbau:** `vkDestroyDevice` des Kerns ist ein leerer Wrapper, der Host räumt das Device nach `retro_unload_game` ab.
- **Bild nach Metal:** Der Host kopiert das Bild nach jedem Frame mit `vkCmdCopyImage` in ein eigenes `VkImage`, das mit `VkExportMetalObjectCreateInfoEXT` angelegt ist, und holt sich mit `vkExportMetalObjectsEXT` die `MTLTexture` (480 × 272, `BGRA8Unorm`, `MTLStorageModePrivate`). Ein Metal-Blit liest sie fehlerfrei. Die Spezifikation verlangt die Export-Absicht schon beim Erzeugen; das Bild des Kerns entsteht ohne sie, deshalb die Kopie. Sie kostet bei 1x 0,5 MB, bei 5x 13 MB pro Frame.

Für beide GPU-Wege gilt (belegt): `context_reset` nach `retro_load_game`, `context_destroy` vor `retro_unload_game`, weil der Kern seinen Kontext in `retro_unload_game` löscht und ein späteres `context_destroy` auf einen Nullzeiger fiele.

### Frage c: der Software-Renderer

Mit `ppsspp_backend=none` fordert der Kern keinen HW-Kontext an und liefert XRGB8888-Bilder über den normalen Video-Callback, 480 × 270, nur 1x (belegt, `report-software-1x.txt`). Für den Host ist das derselbe Pfad wie bei mGBA. Das Bild weicht in rund 9 % der Pixel vom GPU-Bild ab, die meisten davon um höchstens 8 Stufen (belegt). Ob er anspruchsvolle 3D-Spiele auf dem A20 Pro mit vollem Tempo schafft, ist offen (**Gerät**); PPSSPP beschreibt ihn selbst als „Slow, accurate“.

### Ergebnisse im Simulator

Alle drei Wege laufen 600 emulierte Frames und zeigen das erwartete Bild (belegt):

| OpenGL ES | Vulkan über MoltenVK | Software |
| --- | --- | --- |
| ![OpenGL ES, Frame 300](0001/gles-frame-0300.png) | ![Vulkan, Frame 300](0001/vulkan-frame-0300.png) | ![Software, Frame 300](0001/software-frame-0300.png) |

| Weg | Median je `retro_run` 1x | 2x (960 × 540) | SHA-256 Frame 300 (1x) |
| --- | --- | --- | --- |
| OpenGL ES | 1,38 ms | 5,35 ms | `a011d6d3…` |
| Vulkan | 0,99 ms | 1,00 ms | `fb58dfaf…` |
| Software | 0,39 ms | nur 1x | `73537197…` |

- **Determinismus (belegt):** 6 Wiederholungen je Weg ergaben dieselbe Prüfsumme bei Frame 300. Der Plan-Ansatz „Bild-Prüfsumme nach fester Frame-Zahl“ trägt also, aber je Grafikpfad getrennt: OpenGL ES und Vulkan unterscheiden sich in 0,82 % der Pixel, fast alle um höchstens 8 Stufen.
- **Leistung:** Die Zahlen stammen aus dem Simulator auf dem M4 Pro und sind für das Gerät nicht aussagekräftig (Plan, Abschnitt 10). Aussagekräftig ist nur der Unterschied in der Art: OpenGL ES läuft im Simulator als Software-GL und wird mit der Auflösung langsamer, Vulkan läuft über Metal auf der GPU des Macs.
- **Ohne JIT (belegt):** Der Host meldet `GET_JIT_CAPABLE = false` und setzt `ppsspp_cpu_core = IR JIT`, laut `libretro.cpp` PPSSPPs IR-Interpreter (`CPUCore::IR_INTERPRETER`, erzeugt keinen Maschinencode). Damit bleibt auch der Vertex-Decoder-JIT aus (`DrawEngineCommon.cpp`). Alle Läufe liefen mit diesen Einstellungen.

## Optionen

### A · OpenGL ES über EAGL

- **Aufwand:** klein. Im Spike 255 Zeilen (Kontext, Framebuffer, IOSurface-Brücke, Rücklesen). PPSSPPs GL-Backend ist ausgereift.
- **Risiko:** hoch. Veraltet seit iOS 12, das SDK nennt GL „no longer supported“. Im Simulator nur Software-GL und ohne IOSurface-Brücke, Tests im Simulator laufen also auf einem anderen Weg als auf dem Gerät. Eine Entfernung ist nicht angekündigt, aber jederzeit möglich (Annahme).
- **Zukunft:** schlecht.

### B · Vulkan über MoltenVK

- **Aufwand:** mittel. Im Spike 741 Zeilen (Instanz, Surface, Negotiation, Interface, Sync, Kopie, Metal-Export), dazu MoltenVK als Abhängigkeit: offizielles Release, Apache-2.0, statisch gelinkt, rund 5 MB in der Binärdatei (Schätzung aus der Release-Größe der Spike-App, 5,0 MB).
- **Risiko:** mittel. PPSSPPs libretro-Vulkan-Pfad arbeitet mit einem eigenwilligen Wrapper (eigene Device-Erzeugung, nachgebildete Swapchain, abgefangene Submits); er lief im Spike ohne Fehler. MoltenVK übersetzt Shader zur Laufzeit nach MSL, neue Pipelines können ruckeln; PPSSPP speichert dafür einen Pipeline-Cache (belegt: `PSP/SYSTEM/CACHE/*.vkshadercache` im Speicherordner). Offen sind der gepufferte Modus mit Render-Thread und die GPU-Synchronisation mit Metal ohne CPU-Warten.
- **Zukunft:** gut. MoltenVK baut auf Metal auf und wird von Khronos gepflegt. PPSSPPs eigene App-Store-App, ein nativer Host ohne libretro, nutzt denselben Grafikweg (Vulkan ist dort Standard, `Core/Config.cpp`; MoltenVK seit Version 1.17.2 laut PPSSPP-News).

### C · Software-Renderer

- **Aufwand:** keiner über den Pixelpuffer-Pfad hinaus.
- **Risiko:** Leistung auf dem Gerät offen, keine Hochskalierung (nur 480 × 272). Auf dem 7,6-Zoll-Duo bliebe das Bild bei ganzzahliger Skalierung scharf, aber ohne HD-Rendering.
- **Zukunft:** gut, aber nur als Ausweg.

Verworfen: ein eigenes Metal-Backend in PPSSPP. PPSSPP hat keines, der Aufwand stünde in keinem Verhältnis.

## Entscheidung

Empfehlung für M3: **Vulkan über MoltenVK** als einziger GPU-Weg für PSP. Der Software-Renderer bleibt als Ausweg über `ppsspp_backend=none`, ohne eigenen Host-Code. OpenGL ES kommt nicht in LibretroKit; der Spike-Code bleibt als Referenz.

Begründung: Beide GPU-Wege laufen im Spike. Also entscheiden Zukunftssicherheit und Testbarkeit, und beide sprechen für Vulkan: Es baut auf Metal auf, läuft im Simulator auf der GPU wie später auf dem Gerät, und das Ergebnisbild kommt als `MTLTexture` direkt in unseren Metal-Renderer. OpenGL ES ist seit 2018 veraltet und im Simulator ein anderer, langsamerer Weg als auf dem Gerät. Der höhere Aufwand für Vulkan ist mit dem Spike zu großen Teilen schon erledigt.

## Folgen

- **LibretroKit und Renderer (M3):** Das Vulkan-Interface aus `Spikes/PSPGPU/Sources/Host/SPGVulkanRenderer.m` wandert in das C-Target von LibretroKit. Der Renderer bekommt pro Frame eine `MTLTexture`. Statt des CPU-Wartens im Spike braucht M3 eine GPU-Synchronisation, etwa ein `MTLSharedEvent`, exportiert über `VkExportMetalSharedEventInfoEXT` (Annahme, nicht gebaut).
- **Befehlspuffer:** Der Spike setzt `ppsspp_inflight_frames = No buffer`, damit Rendern synchron in `retro_run` bleibt. PPSSPPs Standard „Up to 2“ startet einen Render-Thread, der `set_image` später aufrufen kann. M3 muss das mit sauberer Synchronisation testen, bevor es aktiv wird.
- **Lizenzen:** MoltenVK steht unter Apache-2.0 und ist mit GPL-3.0 vereinbar; der Hinweis muss unter „Lizenzen“ in die App. PPSSPP steht unter GPL-2.0-or-later und darf damit unter GPL-3.0 laufen.
- **FFmpeg:** PPSSPPs vorkompilierte iOS-Bibliotheken (`ffmpeg/ios/universal`, FFmpeg 3.0.2) enthalten armv7, arm64 (nur iPhone), i386 und x86_64, aber keine arm64-Scheibe für den Simulator (belegt). Der Kern ist deshalb ohne FFmpeg gebaut: Videos (PMF über `sceMpeg`) und AAC fallen aus, Atrac3 und MP3 dekodiert PPSSPP selbst. Viele Spiele zeigen Zwischensequenzen als PMF, also braucht M3 ein eigenes FFmpeg-Rezept (LGPL, nur die nötigen Decoder) für Gerät und Simulator.
- **Laufzeit-Assets:** Das Framework enthält unter `system/PPSSPP/` nur `compat.ini` und die VFPU-Tabellen (4,8 MB), beide aus PPSSPPs eigenem Quellbaum. Der Host übergibt `<Framework>/system` als Systemordner; schreibgeschützt reicht (belegt). Nicht dabei: `ppge_atlas.zim`, laut `ppge_atlasscript.txt` aus den kommerziellen Schriften Kozuka Gothic Pro und Arial Unicode gerendert, und die Ersatzschriften in `flash0/font`, deren Ausgangsschriften nicht dokumentiert sind. Ohne Atlas zeichnet PPSSPP keine Texte in Systemdialogen (Speichern, Meldungen). M3 braucht einen eigenen Atlas aus freien Schriften oder eine geklärte Lizenz.
- **Schreibzugriffe:** Der Kern schreibt Shader-Caches in den Speicherordner (`PSP/SYSTEM/CACHE`) und legt zur Prüfung der Groß-/Kleinschreibung eine Testdatei im Ordner des Inhalts an (belegt). Inhalte gehören also in einen beschreibbaren Ordner, nicht ins App-Bundle.
- **Boot:** Der Kern bootet asynchron auf einem eigenen Thread. Wer entlädt, bevor der erste Frame emuliert ist, bringt ihn zum Absturz (belegt, Absturzbericht in `__KernelStartIdleThreads`). LibretroKit muss das Entladen bis nach dem Boot zurückhalten.
- **JIT:** Der Kern enthält PPSSPPs ARM64-JIT als Code; unser Host lässt ihn nie laufen (siehe oben). Ob das die harte Regel „kein JIT-Code-Pfad im Store-Build“ erfüllt oder ob der JIT für den Store-Build herausgepatcht werden muss (PPSSPP hat dafür keinen CMake-Schalter), entscheidet Fatih zusammen mit ADR 0002.
- **PS2:** Der libretro-Kern von Play! fordert nur OpenGL an (`OPENGLES3` mit Version 3.2 unter `GLES_COMPATIBILITY`, `Source/ui_libretro/main_libretro.cpp`), EAGL kann höchstens ES 3.0. ADR 0002 muss den GL-Weg für Play! deshalb neu bewerten; der GL-Teil dieses Spikes kann dafür als Ausgangspunkt dienen.
- **Plan:** Abschnitt 5, Leitplanke 5 und die erste Zeile der Risikotabelle sollten auf diese Entscheidung verweisen (Änderung gehört in den PR, der dieses ADR annimmt).

Erst auf dem Gerät prüfbar:

- Bildrate, Wärme und Akku mit MoltenVK auf dem A20 Pro, auch bei 3x bis 5x.
- Leistung des Software-Renderers in einer anspruchsvollen Demo.
- PPSSPPs Speicherabbildung: Im Simulator fand der Kern erst nach 34 bis 37 Versuchen eine Basisadresse (`vm_remap`-Fehler im Log). PPSSPPs App-Store-App kommt ohne Entitlements für erweiterten Adressraum aus (`ios/App.entitlements` enthält nur In-App-Käufe), also vermutlich auch wir (Annahme).
- Die IOSurface-Brücke für OpenGL ES, falls der GL-Weg für Play! doch kommt.

## Belege

Nachbauen (Gerät `<UDID>` ist ein eigenes Simulator-Gerät):

```bash
git submodule update --init Cores/ppsspp
git -C Cores/ppsspp submodule update --init --depth 1 libretro/libretro-common ext/OpenXR-SDK \
  ext/SPIRV-Cross ext/aemu_postoffice ext/armips ext/cpu_features ext/glslang ext/libchdr ext/lua \
  ext/miniupnp ext/rapidjson ext/rcheevos ext/zstd
git -C Cores/ppsspp/ext/armips submodule update --init --depth 1 ext/filesystem
CMAKE_BUILD_PARALLEL_LEVEL=6 Scripts/build-core.sh ppsspp
Spikes/PSPGPU/Scripts/fetch-moltenvk.sh
(cd Spikes/PSPGPU && xcodegen --spec project.yml)
xcodebuild -project Spikes/PSPGPU/PSPGPUSpike.xcodeproj -scheme PSPGPUSpike \
  -destination "platform=iOS Simulator,id=<UDID>" -derivedDataPath build/DerivedData-pspgpu build
Spikes/PSPGPU/Scripts/run-spike.sh <UDID> vulkan <Ausgabeordner> -frames 600 -capture 60,300
```

Weitere Varianten: Backend `gles` oder `software`, `-scale 2`, `-waitForGPU YES` (wartet nach jedem Frame auf die GPU).

Dateien in `docs/adr/0001/`:

- `gles-frame-0300.png`, `vulkan-frame-0300.png`, `software-frame-0300.png`, `vulkan-2x-frame-0300.png`: Kernbilder nach 300 emulierten Frames.
- `report-*.txt`: vollständige Berichte der Läufe `gles-1x`, `vulkan-1x`, `software-1x`, `gles-2x`, `vulkan-2x`, `gles-1x-gpuwait`, `vulkan-1x-gpuwait`.
- `moltenvk-vulkan-1x.txt`: MoltenVK-Ausgabe zum Simulator-GPU (`Apple iOS simulator GPU`, GPU Family Apple 2, Metal Shading Language 4.0) und zu den aktivierten Erweiterungen.

Auszug aus `report-vulkan-1x.txt`:

```text
core PPSSPP v1.20.4, extensions elf|iso|cso|prx|pbp|chd, need_fullpath 1
retro_load_game in 0.2 ms; hardware context requests: VULKAN v4194322.0 (depth 1, stencil 0, bottom_left_origin 0, cache_context 1, debug 0) -> accepted; negotiation interface type 0 v2
Vulkan: instance API 1.4.357 (core asked: PPSSPP, API 1.0.0), instance extensions: VK_KHR_surface, VK_EXT_metal_surface, VK_KHR_get_physical_device_properties2, VK_EXT_swapchain_colorspace; device Apple iOS simulator GPU, API 1.4.357, driver 0x28a2, 114 device extensions; device created by the core through negotiation interface v2 (create_instance not set, create_device2 not set), queue family 0
Vulkan images received 600, frames copied 600
Vulkan exported texture: 480x272, pixel format 80, storage mode 2, usage 0x5, on Apple iOS simulator GPU
```

Auszug aus `report-gles-1x.txt`:

```text
retro_load_game in 0.2 ms; hardware context requests: OPENGLES2 v0.0 (depth 1, stencil 0, bottom_left_origin 1, cache_context 0, debug 0) -> accepted
OpenGL ES: EAGL API 3; GL_VERSION OpenGL ES 3.0 APPLE-24.0.2; GL_RENDERER Apple Software Renderer; GL_VENDOR Apple Inc.; GLSL OpenGL ES GLSL ES 3.00
OpenGL ES interop: plain renderbuffer and glReadPixels (IOSurface path failed: CVOpenGLESTextureCacheCreateTextureFromImage -6683)
```

Pixelvergleich Frame 300, 1x (eigenes Vergleichsprogramm, RGB):

```text
gles vs vulkan:    1069 von 129600 Pixeln verschieden (0,82 %), 1 um mehr als 8 Stufen
gles vs software: 11780 von 129600 Pixeln verschieden (9,09 %), 2249 um mehr als 8 Stufen
```

Gerätebuild: Die Spike-App baut für `generic/platform=iOS` ohne Signatur und ohne Warnung; Kern und App tragen `platform IOS, minos 27.0`. Gelaufen ist sie auf einem Gerät nicht.

## Quellen

- PPSSPP v1.20.4, Commit [`fa50bb1`](https://github.com/hrydgard/ppsspp/tree/fa50bb1976065c4f8b1b47af227d367fe9771555): `libretro/LibretroGraphicsContext.cpp`, `libretro/LibretroGLContext.h`, `libretro/LibretroVulkanContext.cpp`, `libretro/libretro_vulkan.cpp`, `libretro/libretro.cpp`, `libretro/libretro_core_options.h`, `Common/GPU/Vulkan/VulkanContext.cpp`, `GPU/Common/DrawEngineCommon.cpp`, `Core/Config.cpp`, `ppge_atlasscript.txt`, `ios/App.entitlements`, `CMakeLists.txt`.
- libretro-common in PPSSPP, Commit [`76a3d54`](https://github.com/libretro/libretro-common/tree/76a3d54feb0ee0ce9d59b90aa24694f3782063d3): `include/libretro.h`, `include/libretro_vulkan.h`.
- ppsspp-ffmpeg, Commit [`1e3b496`](https://github.com/hrydgard/ppsspp-ffmpeg/tree/1e3b4965632f60b1d85360261d1b9dd45444bc71): `ios/universal/lib`, `ios-build.sh`.
- pspautotests, Commit [`4374348`](https://github.com/hrydgard/pspautotests/tree/4374348477b425f48f99c8fd58a853c439f78acd): `LICENSE.txt`.
- MoltenVK [v1.4.2](https://github.com/KhronosGroup/MoltenVK/releases/tag/v1.4.2), Commit `db66022`, Apache-2.0, Archiv `MoltenVK-all.tar` (SHA-256 `562a15a2…`).
- Vulkan-Referenz [VkExportMetalObjectCreateInfoEXT](https://docs.vulkan.org/refpages/latest/refpages/source/VkExportMetalObjectCreateInfoEXT.html): Export-Absicht beim Erzeugen.
- Play!, Commit [`30568a0`](https://github.com/jpd002/Play-/blob/30568a057dbe071021276c756ee434fa00b5a68a/Source/ui_libretro/main_libretro.cpp): `Source/ui_libretro/main_libretro.cpp`.
- PSPDEV [v20261101](https://github.com/pspdev/pspdev/releases/tag/v20261101) für das Testprogramm.
- [PPSSPP for iOS is back!](https://www.ppsspp.org/news/ppsspp-ios-is-back/) (4. Juni 2024, Version 1.17.2, Vulkan über MoltenVK) und [PPSSPP iOS Support](https://www.ppsspp.org/docs/reference/ios-support/).
- iOS-27.2-SDK (Xcode 27.2, 27B52): `OpenGLES.framework/Headers/EAGL.h`, `OpenGLESAvailability.h`, `ES2/gl.h`, `ES3/gl.h`, `CoreVideo.framework/Headers/CVBase.h`; Simulator-Runtime iOS 27.2 (24B8117): `profile.plist`.
