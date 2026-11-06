# 0003 · Kerne als eingebettete, nicht gelinkte Frameworks

Status: Angenommen · 6. November 2026 mit der M0-Abnahme

## Kontext

- Alle Libretro-Kerne exportieren dieselben Funktionen (`retro_init`, `retro_run` und so weiter). Zwei Kerne lassen sich deshalb nicht zusammen in die App linken (Plan, Leitplanke 1 und Risiko „Gleiche Funktionsnamen“).
- Die Libretro-Callbacks tragen keinen Kontext. Es ist immer genau ein Kern aktiv (Leitplanke 3).
- Richtlinie 2.5.2: Ausführbarer Code darf nicht nachgeladen werden. Alle Kerne müssen signiert im App-Bundle liegen.
- Gerät und Simulator brauchen je eine eigene Binärdatei (arm64 für iOS und arm64 für den iOS-Simulator).

## Optionen

1. **Statisch linken, Symbole je Kern umbenennen.** Jeder Kern bräuchte eigene Präfixe für Hunderte Symbole und einen eigenen Glue-Code. Das ist fehleranfällig, und jeder neue Kern bringt eigene Ausnahmen mit.
2. **Ein Framework pro Kern, eingebettet und gelinkt** (Xcodes „Embed & Sign“). dyld lädt dann alle Kerne schon beim App-Start und führt ihre Initialisierer aus, obwohl nur einer gebraucht wird. Die App referenziert ohnehin kein `retro_*`-Symbol direkt.
3. **Ein Framework pro Kern, eingebettet und signiert, aber nicht gelinkt.** LibretroKit lädt den Kern beim Spielstart per `dlopen`.
4. **Kerne als ladbare Bundles** (`MH_BUNDLE`, `.bundle`). Auf iOS gehört ausführbarer Code in den Ordner `Frameworks`; andere eingebettete Binärdateien sind für den Store nicht vorgesehen.

## Entscheidung

Option 3.

**Aufbau.** `Scripts/build-core.sh <kern>` baut je SDK (`iphoneos`, `iphonesimulator`, beide arm64, minos 27.0) eine Dylib nach dem Rezept `Scripts/cores/<kern>.sh`, verpackt sie als `<CORE_NAME>.framework` mit eigener Info.plist (Bundle-ID `com.faentiver.arcfold.core.<CORE_NAME mit - statt _>`, etwa `com.faentiver.arcfold.core.mgba-libretro`, Version aus dem Submodul-Tag) und fasst beide Scheiben zu `Cores/Build/<CORE_NAME>.xcframework` zusammen (`ios-arm64`, `ios-arm64-simulator`).

**Exporte.** Gelinkt wird mit `-Wl,-exported_symbol,_retro_*`. Exportiert sind also nur Symbole mit dem Präfix `retro_`: bei mGBA genau die 25 Funktionen der Libretro-API. PPSSPP exportiert über dasselbe Muster zusätzlich 21 `retro_vfs_*_impl` aus libretro-common (`docs/wissen/psp-grafik.md`); die feste Liste der 25 Funktionen kommt in M3 (Plan, Abschnitt 10). So kollidiert ein Kern weder mit der App noch mit anderen Kernen.

**Install-Name.** `@rpath/<CORE_NAME>.framework/<CORE_NAME>`, gesetzt mit `install_name_tool`. Danach signiert build-core.sh ad hoc. Xcode signiert beim Einbetten neu.

**Einbettung ohne Linken.** In `project.yml` steht jeder Kern als `framework:`-Abhängigkeit mit `embed: true` und `link: false`. XcodeGen 2.45.4 trägt die Datei dann nur in die Phase „Embed Frameworks“ ein (Ziel `Frameworks`, Attribute `CodeSignOnCopy` und `RemoveHeadersOnCopy`), nicht in „Link Binary With Libraries“. Das zeigen die Projekt-Spezifikation (Linking options `embed`, `link`) und der Generator-Code (`PBXProjGenerator.swift`, Fall `.framework`): Ohne `link` entsteht kein Eintrag in der Link-Phase. Xcode 27.2 wählt beim Kopieren die passende Scheibe des xcframeworks und signiert sie.

**Laden.** `LibretroCore(named:in:)` sucht `<name>.framework` in `Bundle.privateFrameworksURL` (das Bundle lässt sich für Tests austauschen), nimmt die Binärdatei aus `Bundle(url:).executableURL` und öffnet sie mit `dlopen(RTLD_NOW | RTLD_LOCAL)`. `RTLD_LOCAL` hält die Symbole aus dem globalen Namensraum, sodass ein zweiter Kern nie an den ersten gebunden wird. Die Funktionen löst `dlsym` typisiert als `@convention(c)` auf. Beim Freigeben ruft der Typ `dlclose`. Fehler tragen den Text von `dlerror`.

**Erkennung.** Als Kern gilt jedes Framework, dessen Name auf `_libretro` endet (Libretro-Konvention). Andere Frameworks im Bundle übergeht LibretroKit, etwa später MoltenVK oder das `LibretroKit_…_PackageProduct.framework`, das Xcode in Test-Builds einbettet.

## Belege

Stand 6. November 2026, Xcode 27.2 (27B52), XcodeGen 2.45.4:

- Im erzeugten `project.pbxproj` steht `mgba_libretro.xcframework` nur in „Embed Frameworks“. Die Link-Phase der App enthält nur LibretroKit, FoldLayout und Renderer.
- `otool -L` auf die App-Binärdatei (Release für Gerät) und auf `Arcfold.debug.dylib` (Debug) listet kein `mgba_libretro`.
- `Arcfold.app/Frameworks/mgba_libretro.framework` hat im Simulator-Build die Plattform `IOSSIMULATOR`, im Geräte-Build `IOS`, jeweils minos 27.0. Xcode kopiert dafür `ios-arm64-simulator` bzw. `ios-arm64` und signiert.
- `nm -gU` auf den eingebetteten Kern zeigt 25 Symbole, alle `_retro_*`. Install-Name `@rpath/mgba_libretro.framework/mgba_libretro`.
- `EmbeddedCoreTests` lädt den Kern aus dem App-Bundle: Name „mGBA“, API-Version 1 (`RETRO_API_VERSION`), Version „0.10.5“, Endung `gba`.

## Folgen

- Ein neuer Kern braucht ein Rezept und eine Zeile in `project.yml`. `Scripts/bootstrap.sh` baut jeden Kern, den `project.yml` einbettet. Außerdem braucht er in `.github/workflows/ci.yml` den Submodul-Schritt und den Cache-Schlüssel, bis die CI die Liste selbst aus `project.yml` liest (geplant für M3 zusammen mit dem Rezept-Haken für Unter-Submodule). Für PPSSPP braucht `bootstrap.sh` vorher diesen Rezept-Haken, sonst holt es alle 23 Unter-Submodule rekursiv, allein FFmpeg rund 800 MB (Plan M3, ADR 0001).
- Ein Kern nur für den JIT-Build (Play!) bekommt zusätzlich in Debug und Release `EXCLUDED_SOURCE_FILE_NAMES: <CORE_NAME>.framework`. Ausprobiert mit mGBA: Der Name des Frameworks nimmt den Kern aus „Embed Frameworks“, der Name des xcframeworks nicht.
- Fehlt ein xcframework, bricht Xcode schon beim Erstellen der Build-Beschreibung ab, mit „There is no XCFramework found at '…/Cores/Build/mgba_libretro.xcframework'“. Das passiert vor jeder Build-Phase, ein eigenes Run-Script käme also nie zu Wort. Den Hinweis „run Scripts/bootstrap.sh“ gibt deshalb `Scripts/bootstrap.sh --check`, das XcodeGen vor jedem Generieren ausführt (`preGenCommand`). Ein Projekt ohne Kerne entsteht so gar nicht erst, und ein später gelöschter Kern lässt den Build mit Pfadangabe scheitern statt still ohne Kern.
- XcodeGen setzt für jede `framework:`-Abhängigkeit zusätzlich `FRAMEWORK_SEARCH_PATHS = Cores/Build`. Das ist harmlos, weil nichts gegen die Kerne gelinkt wird.
- Die Kerne gibt es nur für arm64, deshalb baut auch die App nur arm64 (`ARCHS = arm64`). Simulatoren auf Intel-Macs fallen weg.
- `LibretroCore` ist nicht kopierbar und bewusst nicht `Sendable`: Ein Kern hat genau einen Besitzer und bleibt in der Isolationsdomäne, die ihn geladen hat. Ab M1 ist das der Emulations-Thread, an den der Wert mit `sending` übergeben werden kann. Die Callback-Trampoline für genau einen aktiven Kern kommen in M1.
- Ob sich ein Kern per `dlclose` sauber entladen lässt, hängt vom Kern ab (statische Destruktoren, eigene Threads). Für mGBA ist in M0 nichts aufgefallen. PPSSPP bleibt nach `dlclose` geladen, ein zweiter Durchlauf im selben Prozess klappt trotzdem (belegt in ADR 0001). Auf `dlclose` als Speicherfreigabe verlässt sich LibretroKit deshalb nicht. Während einer Spielsitzung bleibt der Kern ohnehin geladen.
