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

## Building

You need a Mac with Apple silicon, Xcode 27.1 or later and four tools from Homebrew:

```sh
brew install xcodegen cmake ninja git-lfs
git lfs install
```

Git LFS stores the freely licensed homebrew test programs; `git lfs install` sets it up once per user account.

Then prepare the checkout and open the project:

```sh
Scripts/bootstrap.sh
open Arcfold.xcodeproj
```

`Scripts/bootstrap.sh` fetches the submodules of the emulation cores, builds every core the app embeds as an XCFramework in `Cores/Build/` and generates `Arcfold.xcodeproj` from `project.yml`. The Xcode project is not checked in. Run the script again after every pull; it only rebuilds what changed.

There are two schemes:

- **Store** builds the App Store variant without any JIT code path.
- **JIT** builds the sideloading variant (`Arcfold JIT`, its own bundle ID) for cores that need a JIT compiler.

To run the tests from the command line on the iPhone Duo simulator:

```sh
xcodebuild test -project Arcfold.xcodeproj -scheme Store \
  -destination 'platform=iOS Simulator,name=iPhone Duo,OS=27.1'
```

The iPhone Duo simulator needs the iOS 27.1 simulator runtime. The iOS 27.2 runtime does not support it, so on iOS 27.2 the tests run on the iPhone 18 Pro:

```sh
xcodebuild test -project Arcfold.xcodeproj -scheme Store \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro,OS=27.2'
```

## Project documents

- [Project plan](docs/PLAN.md) (German)
- [Architecture decisions](docs/adr/)

## License

Arcfold is licensed under the GNU General Public License v3.0, see [LICENSE](LICENSE). The emulation cores keep their own licenses, all of them compatible with GPL-3.0.
