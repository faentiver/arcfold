#!/usr/bin/env bash
#
# Experiment for ADR 0002: builds the iOS Simulator slice of the Play! core
# from a copy of Cores/play with Play--CodeGen pull request #34 (JIT arena for
# iOS 26 devices with TXM, not merged upstream) and, unless
# --without-companion is given, patches/play-basicblock-writable-alias.patch.
# The submodule stays untouched.
#
# Usage: Spikes/PS2JIT/try-codegen-pr34.sh <work-dir> [--without-companion]
#
# Needs gh (fetches the pull request diff) and Scripts/build-core.sh play
# first (for the framework's Info.plist). The compiler flags repeat those of
# Scripts/build-core.sh and Scripts/cores/play.sh for one SDK. Result:
# <work-dir>/play_libretro.xcframework with only the simulator slice. To try
# it, put it in place of Cores/Build/play_libretro.xcframework and run
# run-simulator.sh; rebuild the regular core afterwards.

set -euo pipefail

SPIKE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SPIKE_DIR/../.." && pwd)"
readonly SPIKE_DIR REPO_ROOT
# Head of the pull request when ADR 0002 was written.
readonly TESTED_HEAD="23b29221fd2437dfb918b108a32af571be0a86ab"

[[ $# -ge 1 ]] || { sed -n '3,16p' "$0" | sed 's/^# \{0,1\}//'; exit 64; }
mkdir -p "$1"
work="$(cd "$1" && pwd)"
companion=1
[[ "${2:-}" == "--without-companion" ]] && companion=0

head="$(gh api repos/jpd002/Play--CodeGen/pulls/34 --jq '.head.sha')"
if [[ "$head" != "$TESTED_HEAD" ]]; then
  echo "warning: pull request #34 moved to $head (tested: $TESTED_HEAD)" >&2
fi
rsync -a --exclude .git "$REPO_ROOT/Cores/play/" "$work/src/"
gh pr diff 34 --repo jpd002/Play--CodeGen > "$work/codegen-pr34.diff"
(cd "$work/src/deps/CodeGen" && patch -p1 < "$work/codegen-pr34.diff")
if [[ "$companion" == 1 ]]; then
  (cd "$work/src" && patch -p1 < "$SPIKE_DIR/patches/play-basicblock-writable-alias.patch")
fi

sdk_path="$(xcrun --sdk iphonesimulator --show-sdk-path)"
version="$(git -C "$REPO_ROOT/Cores/play" describe --tags --always)-pr34"
cmake -S "$work/src" -B "$work/cmake" -G Ninja \
  -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT="$sdk_path" -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=27.0 -DCMAKE_BUILD_TYPE=Release -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
  "-DCMAKE_SHARED_LINKER_FLAGS=-Wl,-exported_symbol,_retro_*" \
  -DCMAKE_FIND_ROOT_PATH="$sdk_path" -DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER \
  -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY \
  -DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=ONLY "-DCMAKE_IGNORE_PREFIX_PATH=/opt/homebrew;/usr/local" \
  -DTARGET_IOS=ON -DBUILD_LIBRETRO_CORE=ON -DBUILD_PLAY=OFF -DBUILD_PSFPLAYER=OFF -DBUILD_TESTS=OFF \
  -DENABLE_AMAZON_S3=OFF -DUSE_AOT_CACHE=OFF -DWITH_SYSTEM_ZLIB=ON \
  "-DCMAKE_CXX_FLAGS=-DIOS=1 -UPLAY_VERSION -DPLAY_VERSION=\\\"$version\\\""
cmake --build "$work/cmake" --target play_libretro

framework="$work/framework/play_libretro.framework"
mkdir -p "$framework"
cp "$work/cmake/Source/ui_libretro/play_libretro_ios.dylib" "$framework/play_libretro"
cp "$REPO_ROOT/Cores/Build/play_libretro.xcframework/ios-arm64-simulator/play_libretro.framework/Info.plist" \
  "$framework/"
install_name_tool -id @rpath/play_libretro.framework/play_libretro "$framework/play_libretro"
codesign --force --sign - --timestamp=none "$framework"
xcodebuild -create-xcframework -framework "$framework" -output "$work/play_libretro.xcframework" > /dev/null
echo "==> $work/play_libretro.xcframework (pull request head $head, companion patch $companion)"
