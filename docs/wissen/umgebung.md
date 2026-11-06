---
name: umgebung
description: Werkzeuge und Versionen auf dem Mac mini für Arcfold, Stolperfallen und wie man alles wieder entfernt
---

# Umgebung

Stand 6. November 2026, Mac mini (M4 Pro, 14 Kerne, 24 GB, macOS 27.2).

| Werkzeug | Version | Herkunft | Wofür |
| --- | --- | --- | --- |
| Xcode | 27.2 (27B52), iOS-SDK 27.2 | war vorhanden | App, Simulator, Tests |
| Swift | 6.4.2 | Xcode | |
| XcodeGen | 2.45.4 | Homebrew, war vorhanden | Xcode-Projekt aus `project.yml` |
| Git LFS | 3.7.1 | Homebrew, war vorhanden | Homebrew-Test-ROMs |
| CMake | 4.4.5 | Homebrew, für Arcfold installiert | Kerne bauen |
| Ninja | 1.13.2 | Homebrew, für Arcfold installiert | Kerne bauen |
| actionlint | 1.7.12 | Homebrew, für Arcfold installiert | CI-Workflow lokal prüfen |
| ShellCheck | 0.11.0 | Homebrew, mit actionlint installiert | Skripte prüfen, auch die `run:`-Blöcke im Workflow |
| libmpc, mpfr | 1.4.1, 4.2.2 | Homebrew, für Arcfold installiert | Laufzeitbibliotheken des PSPDEV-Compilers |
| PSPDEV | v20261101 | nur entpackt im Scratchpad einer Session, nicht dauerhaft | baut `Tests/Fixtures/psp/gu-test` neu, Herkunft und Prüfsumme in `Tests/Fixtures/LICENSES.md` |
| MoltenVK | 1.4.2 (`MoltenVK-all.tar`) | lädt der PSP-Spike nach `build/` (ignoriert) | Vulkan im PSP-Spike, `MoltenVK-ios.tar` hat keine Simulator-Scheibe |
| Simulator-Runtimes | iOS 27.2 (24B8117), iOS 27.1 | `xcodebuild -downloadPlatform iOS` bzw. `-buildVersion 27.1` | Tests; den Duo-Simulator gibt es nur mit iOS 27.1 |

## Stolperfallen

- `simctl` ist unter Xcode 27.2 ein Skript, das zuerst `xcodebuild -runFirstLaunch` startet. Solange der Erststart fehlt, hängt jede `simctl`-Abfrage an einem Passwort-Dialog von macOS. Prüfen mit `xcodebuild -checkFirstLaunchStatus` (Exit 0 heißt erledigt).
- CMake 4 lehnt `cmake_minimum_required` unter 3.5 ab. Ältere Kerne brauchen `-DCMAKE_POLICY_VERSION_MINIMUM=3.5`.
- **Der Duo-Simulator läuft nicht mit der Runtime iOS 27.2.** Die Runtime iOS 27.2 (24B8117) führt das iPhone Duo (`iPhone19,4`) in ihrem Profil unter `unsupportedDeviceTypes`, `simctl create` meldet „Incompatible device“. Der Gerätetyp verlangt mindestens iOS 27.1. Den Duo-Simulator gibt es also nur mit einer Runtime iOS 27.1, wie sie auf GitHubs Image `xcode-27` installiert ist. Prüfen mit `plutil -p "<Runtime>/Contents/Resources/profile.plist" | grep -A3 unsupportedDeviceTypes`; den Pfad nennt `xcrun simctl list runtimes -j` (`bundlePath`).
- actionlint 1.7.12 kennt das Runner-Label `xcode-27` (Vorschau-Image) noch nicht. Aufruf deshalb mit `actionlint -ignore 'label "xcode-27" is unknown' .github/workflows/ci.yml`.
- `xcrun simctl launch --console-pty` gibt den Exit-Code der App nicht weiter, er ist immer 0. Skripte müssen das Ergebnis aus der Ausgabe oder einer Berichtsdatei lesen.
- OpenGL ES läuft im Simulator über den „Apple Software Renderer“. Bildraten sind dort nur Plausibilitätswerte, und die Bilder sind nicht bitgenau (ADR 0001).

## Entfernen

Alles, was für Arcfold dazukam, lässt sich so wieder entfernen:

```bash
brew uninstall cmake ninja actionlint shellcheck libmpc mpfr
brew cleanup
```

Die Simulator-Runtimes entfernt man in Xcode unter Settings > Components oder mit `xcrun simctl runtime delete <ID>`. Build-Artefakte liegen nur im Projekt (`Cores/Build/`, `build/`) und in `~/Library/Developer/Xcode/DerivedData/Arcfold-*`.
