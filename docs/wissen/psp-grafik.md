---
name: psp-grafik
description: PPSSPP als libretro-Kern für iOS bauen und mit GPU-Grafik hosten (OpenGL ES, Vulkan über MoltenVK, Software) – Build-Details, Stolperfallen, Werkzeuge
---

# PSP-Grafik: Build und Stolperfallen

Stand 6. November 2026, PPSSPP v1.20.4, MoltenVK 1.4.2, Xcode 27.2. Entscheidung und Belege stehen in `docs/adr/0001-psp-grafik.md`.

## Kern bauen

```bash
git submodule update --init Cores/ppsspp
git -C Cores/ppsspp submodule update --init --depth 1 libretro/libretro-common ext/OpenXR-SDK \
  ext/SPIRV-Cross ext/aemu_postoffice ext/armips ext/cpu_features ext/glslang ext/libchdr ext/lua \
  ext/miniupnp ext/rapidjson ext/rcheevos ext/zstd
git -C Cores/ppsspp/ext/armips submodule update --init --depth 1 ext/filesystem
CMAKE_BUILD_PARALLEL_LEVEL=6 Scripts/build-core.sh ppsspp
```

Ergebnis: `Cores/Build/ppsspp_libretro.xcframework`, je Scheibe 12,7 MB Binärdatei plus 4,8 MB Assets. Ein sauberer Build für beide Scheiben dauerte auf dem Mac mini mit 6 Jobs knapp 3 Minuten. Das Submodul belegt 220 MB Arbeitskopie und 425 MB Git-Daten.

Das Rezept `Scripts/cores/ppsspp.sh` prüft die Unter-Submodule und nennt bei Fehlen genau die Befehle oben. `git submodule update --init --recursive` geht auch, holt aber zusätzlich FFmpeg (800 MB), MoltenVK, SDL und die Testsammlung.

## Stolperfallen im Rezept

- **Deployment-Target:** PPSSPPs `CMakeLists.txt` setzt für iOS gleich nach `project()` `CMAKE_OSX_DEPLOYMENT_TARGET` auf 12.0. Das libc++ im SDK 27.2 warnt dann „The selected platform is no longer supported by libc++“. Das Rezept hängt über `CMAKE_PROJECT_PPSSPP_INCLUDE` ein `variable_watch` ein, das den Wert aus `build-core.sh` (27.0) wiederherstellt.
  - **Warum:** Ohne Eingriff in das Submodul lässt sich das `set()` nicht anders überstimmen; `CMAKE_C_FLAGS` stehen in der Kommandozeile vor dem Deployment-Flag und verlieren.
  - **Anwenden:** Bei neuen Kernen nach `CMAKE_OSX_DEPLOYMENT_TARGET` im CMake-Code suchen und das Ergebnis mit `vtool -show-build` prüfen.
- **Prozessor:** Mit `CMAKE_SYSTEM_NAME=iOS` bleibt `CMAKE_SYSTEM_PROCESSOR` leer. PPSSPP wählt dann keine ARM64-Quellen, und `cpu_features` bricht mit „Unsupported architectures“ ab. Das Rezept setzt `arm64`.
- **GL-Variante:** PPSSPPs eigene Toolchain-Datei setzt `USING_GLES2`, `MOBILE_DEVICE` und `OPENGL_LIBRARIES "-framework OpenGLES"`. Mit dem CMake-eigenen iOS-Support muss das Rezept sie selbst setzen, sonst sucht CMake Desktop-OpenGL.
- **Header-Submodule:** `ext/OpenXR-SDK` und `ext/miniupnp` werden nur wegen Headern gebraucht, die immer mitkompilieren (`Common/VR/OpenXRLoader.h`, `Core/Util/PortManager.h`), auch mit `USE_MINIUPNPC=OFF`.
- **Version:** `git-version.cmake` sucht ein Verzeichnis `.git/`, in einem Submodul ist `.git` aber eine Datei. Ohne Gegenmittel meldet der Kern `library_version` „unknown“. Das Rezept schreibt `git-version.cpp` mit `PPSSPP_GIT_VERSION_NO_UPDATE 1` vorab, wie PPSSPPs `b-ios.sh`.
- **Exporte:** Die Wildcard `_retro_*` aus `build-core.sh` exportiert neben den 25 API-Funktionen auch 21 `retro_vfs_*_impl` aus libretro-common. Mit `dlopen(RTLD_LOCAL)` ist das harmlos.
- **FFmpeg:** aus. PPSSPPs vorkompilierte Bibliotheken für iOS (`ffmpeg/ios/universal`, FFmpeg 3.0.2, Mindest-iOS 7.0) haben armv7, arm64 (nur iPhone), i386 und x86_64, keine arm64-Simulator-Scheibe. Ohne FFmpeg fehlen PMF-Videos und AAC.
- **Assets:** `core_package` legt `compat.ini` und `vfpu/` nach `<Framework>/system/PPSSPP/`. Der Host übergibt `<Framework>/system` als Systemordner, der Kern hängt `PPSSPP` selbst an. Nicht dabei: `ppge_atlas.zim` (aus kommerziellen Schriften gerendert, siehe `ppge_atlasscript.txt`) und `flash0/font` (Herkunft der Ausgangsschriften undokumentiert).

## Stolperfallen im Host

- **GL bevorzugen:** `GET_PREFERRED_HW_RENDER` muss `OPENGL` oder `OPENGLES3` melden oder die Core-Option `ppsspp_backend=opengl` gesetzt sein. Bei `OPENGLES2` überspringt der Kern GL. Er fordert dann selbst `OPENGLES2` an und nimmt einen ES-3.0-Kontext gern.
- **GL-Thread:** Der Kern emuliert die CPU auf eigenem Thread, die GL-Befehle laufen in `retro_run`. Der EAGL-Kontext muss auf dem Thread aktuell sein, der `retro_run` ruft. Ursprung unten links (`bottom_left_origin`).
- **Vulkan-Instanz:** Mit der Version aus `vkEnumerateInstanceVersion` anlegen, nicht mit der 1.0 aus der `VkApplicationInfo` des Kerns; der Kern rechnet mit der gemeldeten Version.
- **Vulkan-Surface:** Pflicht, auch wenn nie präsentiert wird. Ein `CAMetalLayer` ohne View reicht.
- **Vulkan-Device:** `VK_KHR_portability_subset` als Pflichterweiterung übergeben, PPSSPP aktiviert es nicht. Der Kern meldet Negotiation v2, implementiert aber nur v1 (`create_device`). Das Device räumt der Host ab, `destroy_device` ist leer.
- **Sync-Index:** Die Bitmaske von `get_sync_index_mask` bestimmt, wie viele Bilder der Kern anlegt. Im Spike 2, mit einem Fence je Index.
- **Befehlspuffer:** Mit `ppsspp_inflight_frames` „Up to 1“ oder „Up to 2“ (Standard) startet ein Render-Thread, der Submits und `set_image` auch nach `retro_run` absetzen kann. Der Spike nutzt „No buffer“.
- **Bild nach Metal:** Das Bild des Kerns entsteht ohne `VkExportMetalObjectCreateInfoEXT`, also nicht exportieren, sondern in ein eigenes, exportierbares `VkImage` kopieren und dessen `MTLTexture` holen.
- **Reihenfolge:** `context_reset` nach `retro_load_game`, `context_destroy` vor `retro_unload_game`.
- **Boot:** `retro_load_game` startet einen Loader-Thread, `retro_run` liefert bis zum Ende des Boots leere Frames. In einer engen Schleife ohne Pause ist der Boot nach 3000 Aufrufen noch nicht fertig; wer dann entlädt, bringt den Kern zum Absturz (`__KernelStartIdleThreads`). Der Spike wartet 1 ms je Boot-Aufruf, höchstens 10 s.
- **Ordner:** Der Kern schreibt Shader-Caches nach `<Speicherordner>/PSP/SYSTEM/CACHE` und legt im Ordner des Inhalts eine Testdatei an (Prüfung auf Groß-/Kleinschreibung). Inhalte also nicht im App-Bundle ablegen.
- **JIT:** `GET_JIT_CAPABLE` mit `false` beantworten und `ppsspp_cpu_core=IR JIT` setzen (IR-Interpreter, kein Maschinencode).
- **Log-Rauschen:** Im Simulator meldet der Kern Dutzende `vm_remap failed (3)`, bis er eine Basisadresse für den PSP-Speicher findet, dazu fehlende `ppge_atlas.zim` und `lang/*.ini`. Das ist kein Fehler.

## Simulator

- OpenGL ES im iOS-27.2-Simulator: `OpenGL ES 3.0 APPLE-24.0.2`, Renderer „Apple Software Renderer“, also CPU. `CVOpenGLESTextureCache` liefert dort `-6683`.
- MoltenVK im Simulator: Gerät „Apple iOS simulator GPU“, GPU Family Apple 2, Metal Shading Language 4.0. Für die Simulator-Scheibe braucht es `MoltenVK-all.tar`, `MoltenVK-ios.tar` enthält nur `ios-arm64`.
- Der Gerätetyp iPhone Duo verlangt Runtime 27.1 oder neuer, die Runtime iOS 27.2 (24B8117) schließt ihn aber aus (`unsupportedDeviceTypes` mit `iPhone19,4` in ihrer `profile.plist`). `simctl create` meldet „Incompatible device“.

## Testprogramm

`Tests/Fixtures/psp/gu-test.elf` entsteht aus `Tests/Fixtures/psp/gu-test/main.c`:

```bash
Tests/Fixtures/psp/gu-test/build.sh <pspdev-Ordner>
```

Die Toolchain ist das Release v20261101 von PSPDEV (`pspdev-macos-latest-arm64.tar.gz`, 154 MB, entpackt 399 MB). Sie liegt nicht im Repo; zum Bauen reicht es, das Archiv in einen beliebigen Ordner zu entpacken. Ihr Compiler braucht Homebrew-Bibliotheken: `gmp`, `mpfr`, `libmpc` und `zstd`. Zwei Builds ergaben dieselbe SHA-256.

## Werkzeuge

| Werkzeug | Version | Herkunft | Wofür |
| --- | --- | --- | --- |
| MoltenVK | 1.4.2 | offizielles Release, `Spikes/PSPGPU/Scripts/fetch-moltenvk.sh` lädt nach `build/moltenvk` | Vulkan im Spike |
| PSPDEV | v20261101 | GitHub-Release, nur im Scratchpad | Testprogramm bauen |
| libmpc | 1.4.1 | Homebrew, für Arcfold installiert | PSPDEV-Compiler |
| mpfr | 4.2.2 | Homebrew, als Abhängigkeit von libmpc | PSPDEV-Compiler |

Entfernen: `brew uninstall libmpc mpfr`. Build-Artefakte liegen in `build/cores/ppsspp`, `build/moltenvk` und `build/DerivedData-pspgpu`.
