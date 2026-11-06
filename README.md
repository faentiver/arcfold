# Arcfold

A multi-system emulator front end for iPhone, written in SwiftUI and designed around the fold of the iPhone Duo.

> **Status:** early development, milestone M0 (foundation). Nothing to play yet.

## Idea

- One app for several systems, with one library, unified save data and settings.
- Fold-native from the start: one layout per system and posture, switching without a restart.
- A tabletop mode with the picture on the upper half and all controls on the lower half.
- Emulation comes from proven open-source cores through the libretro API. The host, rendering, input and fold layouts are written in Swift.

Planned compatibility, in this order: Game Boy Advance (mGBA), Nintendo DS (melonDS) and PlayStation Portable (PPSSPP). After that comes PlayStation 2 as a separate sideload-only JIT build (Play!), followed by Game Boy and Game Boy Color, NES, SNES and PlayStation.

## What Arcfold does not do

- It ships no games, BIOS files, firmware or keys, and no links to them. Use your own legally made dumps.
- It is not affiliated with or endorsed by Apple, Nintendo or Sony. All trademarks belong to their owners.

## Project documents

- [Project plan](docs/PLAN.md) (German)
- [Architecture decisions](docs/adr/)

## License

Arcfold is licensed under the GNU General Public License v3.0, see [LICENSE](LICENSE). The emulation cores keep their own licenses, all of them compatible with GPL-3.0.
