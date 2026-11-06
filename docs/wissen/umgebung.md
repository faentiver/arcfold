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

## Stolperfallen

- `simctl` ist unter Xcode 27.2 ein Skript, das zuerst `xcodebuild -runFirstLaunch` startet. Solange der Erststart fehlt, hängt jede `simctl`-Abfrage an einem Passwort-Dialog von macOS. Prüfen mit `xcodebuild -checkFirstLaunchStatus` (Exit 0 heißt erledigt).
- CMake 4 lehnt `cmake_minimum_required` unter 3.5 ab. Ältere Kerne brauchen `-DCMAKE_POLICY_VERSION_MINIMUM=3.5`.

## Entfernen

Alles, was für Arcfold dazukam, lässt sich so wieder entfernen:

```bash
brew uninstall cmake ninja
brew cleanup
```

Build-Artefakte liegen nur im Projekt (`Cores/Build/`, `build/`) und in `~/Library/Developer/Xcode/DerivedData/Arcfold-*`.
