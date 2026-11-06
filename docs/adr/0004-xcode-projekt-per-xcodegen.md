# 0004 · Xcode-Projekt per XcodeGen

Status: Angenommen · 6. November 2026 mit der M0-Abnahme

## Kontext

- Der Plan (Abschnitt 9) schlug XcodeGen vor, damit das Projekt textbasiert bleibt und sich im Review lesen lässt, auch am iPhone.
- Eine `project.pbxproj` ist schwer zu lesen und erzeugt bei paralleler Arbeit leicht Merge-Konflikte.
- Das Projekt hat vier Konfigurationen, zwei Schemes, drei lokale Pakete und eingebettete Kerne, die nicht gelinkt werden (ADR 0003). Das alles muss auf beiden Macs und in der CI gleich entstehen.

## Optionen

1. **Eingechecktes `Arcfold.xcodeproj`**, gepflegt in Xcode. Keine zusätzlichen Werkzeuge, aber unlesbare Diffs und Konflikte.
2. **XcodeGen**: `project.yml` im Repo, das Projekt wird erzeugt und nicht eingecheckt.
3. **Tuist**: Manifeste in Swift, mehr Funktionen (Caching, Module-Graphen), aber eine eigene Toolchain und mehr Konventionen, als das Projekt braucht.
4. **Nur Swift-Pakete** ohne Xcode-Projekt. Für eine iOS-App mit Entitlements, eigenen Konfigurationen und eingebetteten Frameworks reicht das nicht.

## Entscheidung

XcodeGen, geprüft mit Version 2.45.4 (`minimumXcodeGenVersion: 2.45.4`). `project.yml` beschreibt:

- **Target `Arcfold`**: iOS-App mit SwiftUI-Lifecycle, Deployment-Target iOS 27.0, nur iPhone (`TARGETED_DEVICE_FAMILY = 1`), Swift 6 (`SWIFT_VERSION = 6.0`, damit Strict Concurrency „complete“), dazu wie in Xcodes App-Vorlage 27.2 `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, Approachable Concurrency und Member Import Visibility. Info.plist wird erzeugt (`GENERATE_INFOPLIST_FILE`, `INFOPLIST_KEY_*`), der Startbildschirm über `UILaunchScreen`. Bundle-ID `com.faentiver.arcfold`, Name „Arcfold“.
- **Konfigurationen** Debug, Release, Debug-JIT und Release-JIT. Nur die JIT-Konfigurationen setzen `JIT_BUILD` (Swift-Bedingung und C-Define `JIT_BUILD=1`), die Bundle-ID `com.faentiver.arcfold.jit`, den Namen „Arcfold JIT“ und `App/Arcfold-JIT.entitlements` mit `get-task-allow = true` für StikDebug.
- **Schemes** `Store` (Debug, Release) und `JIT` (Debug-JIT, Release-JIT). Beide testen `ArcfoldTests` und `LibretroKitTests`.
- **Test-Target `ArcfoldTests`**: Swift Testing mit der App als Host, damit der Test den echten Ladeweg aus `Arcfold.app/Frameworks` prüft.
- **Lokale Pakete** LibretroKit, FoldLayout und Renderer als Abhängigkeiten der App.
- **Projekt-Einstellungen** der Xcode-Vorlage 27.2, die XcodeGens Presets nicht setzen (C- und C++-Standard, User Script Sandboxing, String Catalogs), und `xcodeVersion: 27.2`, also `LastUpgradeCheck = 2720`. Damit sollte Xcode 27.2 keine „Recommended Settings“ vorschlagen. In der Xcode-Oberfläche ist das noch nicht geprüft, die Builds mit `xcodebuild` sind ohne Warnung.
- **`preGenCommand: Scripts/bootstrap.sh --check`**, damit kein Projekt ohne seine Kerne entsteht (ADR 0003).

`Arcfold.xcodeproj` steht in `.gitignore`. `Scripts/bootstrap.sh` erzeugt es, nach Änderungen an `project.yml` reicht `xcodegen generate`.

## Folgen

- Projekteinstellungen werden nur in `project.yml` geändert. Was man in Xcode am Projekt ändert, ist beim nächsten Generieren weg.
- XcodeGens iOS-Preset setzt `TARGETED_DEVICE_FAMILY = 1,2` auf Target-Ebene. Ein Wert auf Projektebene kommt dagegen nicht an, er muss im Target stehen.
- Lokale Pakete übernehmen `ARCHS` nicht aus dem Projekt. Bei einem generischen Simulator-Build kompiliert Xcode sie zusätzlich für x86_64, die App selbst bleibt arm64.
- Linken App und Test-Bundle dasselbe Paket, baut Xcode es in Test-Builds als dynamisches `LibretroKit_…_PackageProduct.framework` und bettet es ein. Im normalen Build bleibt es statisch. Dadurch entsteht kein doppelter Code und keine Warnung.
- Die CI installiert XcodeGen per Homebrew, also die jeweils aktuelle Version (Stand heute 2.46.0). Lokal ist 2.45.4 installiert. Ältere Versionen lehnt `minimumXcodeGenVersion` ab.
- Der Weg zurück bleibt offen: Das erzeugte Projekt lässt sich jederzeit einchecken.
