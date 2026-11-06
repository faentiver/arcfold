#!/usr/bin/env bash
#
# Experiment for ADR 0002: builds the Play! core for iPhone and the iOS
# Simulator from a copy of Cores/play with Play--CodeGen pull request #34 (JIT
# arena for iOS 26 devices with TXM, not merged upstream) and, unless
# --without-companion is given, patches/play-basicblock-writable-alias.patch
# (the BasicBlock change of Play! pull request #1622).
# The submodule stays untouched. The core reports its version as 0.77-pr34,
# which the spike app uses to pick the matching JIT check.
#
# Usage: Spikes/PS2JIT/try-codegen-pr34.sh <work-dir> [--without-companion]
#
# The pull request comes from patches/codegen-pr34-23b29221.patch, the diff
# of the tested head, so the build needs no network and stays the same when
# the pull request changes. Needs Scripts/build-core.sh play first (for the
# frameworks' Info.plist). The compiler flags repeat those of
# Scripts/build-core.sh and Scripts/cores/play.sh. Result:
# <work-dir>/play_libretro.xcframework. To try it, put it in place of
# Cores/Build/play_libretro.xcframework, build the spike app and rebuild the
# regular core afterwards.

set -euo pipefail

SPIKE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SPIKE_DIR/../.." && pwd)"
readonly SPIKE_DIR REPO_ROOT
readonly PR_PATCH="$SPIKE_DIR/patches/codegen-pr34-23b29221.patch"
readonly UPSTREAM_XCFRAMEWORK="$REPO_ROOT/Cores/Build/play_libretro.xcframework"

[[ $# -ge 1 ]] || { sed -n '3,20p' "$0" | sed 's/^# \{0,1\}//'; exit 64; }
mkdir -p "$1"
work="$(cd "$1" && pwd)"
companion=1
[[ "${2:-}" == "--without-companion" ]] && companion=0
if [[ -e "$work/play_libretro.xcframework" ]]; then
  echo "error: $work already holds a build, pick a new folder" >&2
  exit 73
fi

rsync -a --exclude .git "$REPO_ROOT/Cores/play/" "$work/src/"
(cd "$work/src/deps/CodeGen" && patch -p1 < "$PR_PATCH")
if [[ "$companion" == 1 ]]; then
  (cd "$work/src" && patch -p1 < "$SPIKE_DIR/patches/play-basicblock-writable-alias.patch")
fi

version="$(git -C "$REPO_ROOT/Cores/play" describe --tags --always)-pr34"
frameworks=()
for sdk in iphoneos iphonesimulator; do
  sdk_path="$(xcrun --sdk "$sdk" --show-sdk-path)"
  cmake -S "$work/src" -B "$work/cmake-$sdk" -G Ninja \
    -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT="$sdk_path" -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=27.0 -DCMAKE_BUILD_TYPE=Release -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
    "-DCMAKE_SHARED_LINKER_FLAGS=-Wl,-exported_symbol,_retro_*" \
    -DCMAKE_FIND_ROOT_PATH="$sdk_path" -DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER \
    -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY \
    -DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=ONLY "-DCMAKE_IGNORE_PREFIX_PATH=/opt/homebrew;/usr/local" \
    -DTARGET_IOS=ON -DBUILD_LIBRETRO_CORE=ON -DBUILD_PLAY=OFF -DBUILD_PSFPLAYER=OFF -DBUILD_TESTS=OFF \
    -DENABLE_AMAZON_S3=OFF -DUSE_AOT_CACHE=OFF -DWITH_SYSTEM_ZLIB=ON \
    "-DCMAKE_CXX_FLAGS=-DIOS=1 -UPLAY_VERSION -DPLAY_VERSION=\\\"$version\\\""
  cmake --build "$work/cmake-$sdk" --target play_libretro

  slice=ios-arm64
  [[ "$sdk" == "iphonesimulator" ]] && slice=ios-arm64-simulator
  framework="$work/framework-$sdk/play_libretro.framework"
  mkdir -p "$framework"
  cp "$work/cmake-$sdk/Source/ui_libretro/play_libretro_ios.dylib" "$framework/play_libretro"
  cp "$UPSTREAM_XCFRAMEWORK/$slice/play_libretro.framework/Info.plist" "$framework/"
  install_name_tool -id @rpath/play_libretro.framework/play_libretro "$framework/play_libretro"
  codesign --force --sign - --timestamp=none "$framework"
  frameworks+=(-framework "$framework")
done
xcodebuild -create-xcframework "${frameworks[@]}" -output "$work/play_libretro.xcframework" > /dev/null
echo "==> $work/play_libretro.xcframework (pull request head 23b29221, companion patch $companion)"
