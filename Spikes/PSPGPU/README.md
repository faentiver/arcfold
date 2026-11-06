# Spike PSP-Grafik

Minimaler libretro-Host für ADR 0001 (`docs/adr/0001-psp-grafik.md`). Die App lädt den PPSSPP-Kern per `dlopen` aus `Frameworks/`, kopiert das Testprogramm `Tests/Fixtures/psp/gu-test.elf` in ihren Dokumentenordner, startet es, rendert über einen von drei Wegen und speichert Kernbilder als PNG samt Bericht in ihren Dokumentenordner.

| Weg | Launch-Argument | Host-Code |
| --- | --- | --- |
| OpenGL ES über EAGL | `-backend gles` | `Sources/Host/SPGGLESRenderer.m` |
| Vulkan über MoltenVK | `-backend vulkan` | `Sources/Host/SPGVulkanRenderer.m` |
| PPSSPPs Software-Renderer | `-backend software` | Pixelpuffer in `Sources/Host/SPGSpikeHost.m` |

Weitere Argumente: `-frames 600` (emulierte Frames), `-scale 2` (Renderauflösung), `-capture 60,300` (zusätzlich gespeicherte Frames), `-waitForGPU YES`, `-cycles 2` (ganzer Lebenszyklus mehrmals im selben Prozess), `-dlclose YES` (nach jedem Zyklus `dlclose` mit Prüfung, ob das Image weg ist), `-exitWhenDone YES`.

## Bauen und starten

Voraussetzungen: `Scripts/build-core.sh ppsspp` und `Spikes/PSPGPU/Scripts/fetch-moltenvk.sh`.

```bash
cd Spikes/PSPGPU && xcodegen --spec project.yml && cd ../..
xcodebuild -project Spikes/PSPGPU/PSPGPUSpike.xcodeproj -scheme PSPGPUSpike \
  -destination "platform=iOS Simulator,id=<UDID>" -derivedDataPath build/DerivedData-pspgpu build
Spikes/PSPGPU/Scripts/run-spike.sh <UDID> vulkan <Ausgabeordner> -frames 600
```

`run-spike.sh` installiert die App, setzt das installierte Bundle für die Dauer des Laufs auf schreibgeschützt (wie auf dem Gerät), startet die App mit Konsole und kopiert PNGs, `report.txt` und `core.log` in den Ausgabeordner. Den Exit-Code bestimmt die Zeile `result OK` im Bericht, weil `simctl launch` den Exit-Code der App nicht weitergibt.

## GL-Falle

`Scripts/make-gl-trap.sh` baut nach `build/gl-trap/` zwei Bibliotheken, die jede OpenGL-ES-Funktion des Kerns durch eine ersetzen, die Funktion und Aufrufer ausgibt und den Prozess beendet. Läuft der Vulkan- oder der Software-Weg damit durch, hat er kein GL aufgerufen. Die Variante `libgltrap-core-only.dylib` lässt die GL-Funktionen der App selbst aus und muss auf dem GL-Weg beim ersten Aufruf des Kerns anhalten (Gegenprobe).

```bash
Spikes/PSPGPU/Scripts/make-gl-trap.sh
SIMCTL_CHILD_DYLD_INSERT_LIBRARIES="$PWD/build/gl-trap/libgltrap.dylib" \
  Spikes/PSPGPU/Scripts/run-spike.sh <UDID> vulkan <Ausgabeordner> -frames 600
```

Der Spike ist Wegwerf-Code zum Belegen, kein Vorbild für LibretroKit: Er ist in Objective-C geschrieben, weil die Vulkan- und GL-Strukturen dort ohne Umwege nutzbar sind, und wartet beim Rücklesen auf der CPU.
