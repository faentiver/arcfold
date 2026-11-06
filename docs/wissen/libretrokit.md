---
name: libretrokit
description: Aufbau von LibretroKit in M0 (Laden per dlopen, Typen, Concurrency-Entscheidungen) und die Stolperfallen beim Schreiben
---

# LibretroKit

Stand 6. November 2026 (M0). Paket unter `Packages/LibretroKit`, swift-tools-version 6.4, iOS 27, Swift 6.

## Aufbau

- **`CLibretro`**: `include/libretro.h` unverändert aus libretro/libretro-common, Herkunft in `Sources/CLibretro/README.md`. LibretroKit importiert es mit `internal import`, die öffentliche API ist reines Swift.
- **`LibretroCore`**: lädt `<name>.framework` aus `Bundle.privateFrameworksURL` per `dlopen(RTLD_NOW | RTLD_LOCAL)`, löst `retro_api_version` und `retro_get_system_info` per `dlsym` als `@convention(c)`-Funktionen auf und schließt die Bibliothek in `deinit`. Das Bundle ist injizierbar (`in:`), Standard ist `.main`.
- **`SystemInfo`**: Werttyp mit Bibliotheksname, Version, Endungen (aus der `|`-Liste), `needsFullPath`, `blocksExtract`. Die C-Strings gehören dem Kern und werden sofort kopiert.
- **`LibretroError`**: `frameworkNotFound(name:path:)`, `loadFailed(name:reason:)`, `symbolNotFound(name:symbol:reason:)`. `reason` ist der Text von `dlerror`.
- **`LibretroCore.embeddedCoreNames(in:)`**: alle Frameworks mit der Endung `_libretro`, sortiert.
- **`LibretroCore.hostAPIVersion`**: `RETRO_API_VERSION` aus dem Header, gegen den der Host gebaut ist.

## Entscheidungen

- **Nicht kopierbar (`~Copyable`)**: Der Wert besitzt das Handle. Genau ein Besitzer, genau ein `dlclose`.
- **Nicht `Sendable`** (`@available(*, unavailable) extension LibretroCore: Sendable {}`). **Warum:** Kerne haben globalen Zustand und sind nicht threadsicher. Ein Kern bleibt in der Isolationsdomäne, die ihn geladen hat. **Anwenden:** In M1 den Kern auf dem Emulations-Thread laden oder ihn per `sending` dorthin übergeben, nie von zwei Stellen aus aufrufen.
- **Callbacks erst in M1**: Leitplanke 3 (genau ein aktiver Kern, statische Trampoline) ist noch nicht gebaut. M0 ruft nur Funktionen, die laut Libretro vor `retro_init` erlaubt sind.
- **Kein Kernaufruf auf dem Main Thread**: Die App liest die Kern-Infos in einer `@concurrent`-Funktion (`CoreCatalog.load`).
- **Typed throws** (`throws(LibretroError)`), damit Aufrufer ohne Casts auf die Fälle schalten können.

## Stolperfallen

- Ein `~Copyable`-Struct darf in `init` seine Properties nicht bedingt setzen (Fehler „conditional initialization or destruction of noncopyable types is not supported“). Lösung: erst in lokale Konstanten auflösen, dann alle Properties am Ende setzen.
- `do throws(LibretroError) { … } catch { … }` schreiben. Ohne die Angabe ist `error` im `catch` vom Typ `any Error` und passt nicht zu `throws(LibretroError)`.
- Mit Member Import Visibility braucht jede Datei, die Member eines Typs aus LibretroKit benutzt (etwa `error.description`), selbst `import LibretroKit`.
- Paket-Test für „Symbol fehlt“: Das Test-Bundle selbst ist eine ladbare Mach-O-Datei ohne `retro_*`. Ein Symlink darauf als Framework-Binärdatei ergibt den Fehlerfall ohne echten Kern.
- `Bundle(url:)` merkt sich Bundles pro Pfad. Tests legen deshalb je Fall einen eigenen Ordner mit UUID an.
