# Spike PSP-Grafik

Minimaler libretro-Host für ADR 0001 (`docs/adr/0001-psp-grafik.md`). Die App lädt den PPSSPP-Kern per `dlopen` aus `Frameworks/`, startet das Testprogramm `Tests/Fixtures/psp/gu-test.elf`, rendert über einen von drei Wegen und speichert Kernbilder als PNG samt Bericht in ihren Dokumentenordner.

| Weg | Launch-Argument | Host-Code |
| --- | --- | --- |
| OpenGL ES über EAGL | `-backend gles` | `Sources/Host/SPGGLESRenderer.m` |
| Vulkan über MoltenVK | `-backend vulkan` | `Sources/Host/SPGVulkanRenderer.m` |
| PPSSPPs Software-Renderer | `-backend software` | Pixelpuffer in `Sources/Host/SPGSpikeHost.m` |

Weitere Argumente: `-frames 600` (emulierte Frames), `-scale 2` (Renderauflösung), `-capture 60,300` (zusätzlich gespeicherte Frames), `-waitForGPU YES`, `-exitWhenDone YES`.

## Bauen und starten

Voraussetzungen: `Scripts/build-core.sh ppsspp` und `Spikes/PSPGPU/Scripts/fetch-moltenvk.sh`.

```bash
cd Spikes/PSPGPU && xcodegen --spec project.yml && cd ../..
xcodebuild -project Spikes/PSPGPU/PSPGPUSpike.xcodeproj -scheme PSPGPUSpike \
  -destination "platform=iOS Simulator,id=<UDID>" -derivedDataPath build/DerivedData-pspgpu build
Spikes/PSPGPU/Scripts/run-spike.sh <UDID> vulkan <Ausgabeordner> -frames 600
```

`run-spike.sh` installiert die App, startet sie mit Konsole und kopiert PNGs, `report.txt` und `core.log` in den Ausgabeordner.

Der Spike ist Wegwerf-Code zum Belegen, kein Vorbild für LibretroKit: Er ist in Objective-C geschrieben, weil die Vulkan- und GL-Strukturen dort ohne Umwege nutzbar sind, und wartet beim Rücklesen auf der CPU.
