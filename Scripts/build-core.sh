#!/usr/bin/env bash
#
# Builds a libretro core as a dynamic framework for iOS devices and for the
# iOS Simulator (both arm64) and combines them into
# Cores/Build/<CORE_NAME>.xcframework.
#
# Usage: Scripts/build-core.sh <core> [--debug] [--clean] [--fingerprint]
#
# --fingerprint prints what the build depends on (submodule commit, recipe,
# this script, build type) and builds nothing. After a build the same text is
# stored in Cores/Build/<CORE_NAME>.stamp, so Scripts/bootstrap.sh can tell
# whether a core is outdated.
#
# Every core has a recipe in Scripts/cores/<core>.sh. A recipe sets
#   CORE_NAME     binary and framework name, for example mgba_libretro
#   CORE_SOURCE   path of the core's submodule, relative to the repo root
# and defines
#   core_build <sdk> <work_dir>
# which builds the core for <sdk> (iphoneos or iphonesimulator) and leaves the
# shared library at <work_dir>/<CORE_NAME>.dylib. Recipes that use CMake pass
# "${IOS_CMAKE_ARGS[@]}", which holds the common cross-compile flags.
# A recipe may also define
#   core_package <sdk> <framework_dir> <work_dir>
# to add files the core needs at runtime (assets, shaders) to the framework
# before it is signed.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_ROOT
readonly DEPLOYMENT_TARGET="27.0"
readonly OUTPUT_DIR="$REPO_ROOT/Cores/Build"
readonly SDKS=(iphoneos iphonesimulator)

usage() {
  sed -n '3,26p' "$0" | sed 's/^# \{0,1\}//'
  exit 64
}

core=""
build_type="Release"
clean=0
print_fingerprint=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --debug) build_type="Debug" ;;
    --clean) clean=1 ;;
    --fingerprint) print_fingerprint=1 ;;
    -h | --help) usage ;;
    -*) echo "error: unknown option $1" >&2; usage ;;
    *) if [[ -z "$core" ]]; then core="$1"; else usage; fi ;;
  esac
  shift
done
[[ -n "$core" ]] || usage

recipe="$REPO_ROOT/Scripts/cores/$core.sh"
if [[ ! -f "$recipe" ]]; then
  echo "error: no recipe at Scripts/cores/$core.sh" >&2
  exit 66
fi

CORE_NAME=""
CORE_SOURCE=""
# shellcheck source=/dev/null
source "$recipe"
[[ -n "$CORE_NAME" && -n "$CORE_SOURCE" ]] || {
  echo "error: $recipe must set CORE_NAME and CORE_SOURCE" >&2
  exit 65
}
declare -F core_build > /dev/null || {
  echo "error: $recipe must define core_build" >&2
  exit 65
}
if [[ ! -e "$REPO_ROOT/$CORE_SOURCE/.git" ]]; then
  echo "error: $CORE_SOURCE is missing, run: git submodule update --init $CORE_SOURCE" >&2
  echo "       If the core needs nested submodules, Scripts/cores/$core.sh names them." >&2
  exit 66
fi

# Everything the built core depends on. A change in any line makes it outdated.
fingerprint() {
  local source_commit recipe_hash script_hash
  source_commit="$(git -C "$REPO_ROOT/$CORE_SOURCE" rev-parse HEAD)"
  recipe_hash="$(shasum -a 256 "$recipe" | cut -d ' ' -f 1)"
  script_hash="$(shasum -a 256 "$REPO_ROOT/Scripts/build-core.sh" | cut -d ' ' -f 1)"
  printf 'source %s %s\nrecipe %s %s\nbuild-core %s\nbuild-type %s\n' \
    "$CORE_SOURCE" "$source_commit" "$core" "$recipe_hash" "$script_hash" "$build_type"
}

if [[ "$print_fingerprint" == 1 ]]; then
  fingerprint
  exit 0
fi

# Common CMake flags for a cross build to one SDK. Package lookups stay inside
# the SDK so that Homebrew's macOS libraries never end up in an iOS binary.
# Only the libretro API is exported, so cores never clash with each other.
set_ios_cmake_args() {
  local sdk="$1" sdk_path
  sdk_path="$(xcrun --sdk "$sdk" --show-sdk-path)"
  # shellcheck disable=SC2034 # used by the recipes
  IOS_CMAKE_ARGS=(
    -G Ninja
    -DCMAKE_SYSTEM_NAME=iOS
    -DCMAKE_OSX_SYSROOT="$sdk_path"
    -DCMAKE_OSX_ARCHITECTURES=arm64
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET"
    -DCMAKE_BUILD_TYPE="$build_type"
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5
    "-DCMAKE_SHARED_LINKER_FLAGS=-Wl,-exported_symbol,_retro_*"
    -DCMAKE_FIND_ROOT_PATH="$sdk_path"
    -DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER
    -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY
    -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY
    -DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=ONLY
    "-DCMAKE_IGNORE_PREFIX_PATH=/opt/homebrew;/usr/local"
  )
}

# Version for the framework's Info.plist, taken from the submodule's tag.
core_version() {
  local tag
  tag="$(git -C "$REPO_ROOT/$CORE_SOURCE" describe --tags --abbrev=0 2> /dev/null || true)"
  tag="$(sed -E 's/^[^0-9]*//; s/[^0-9.].*$//' <<< "$tag")"
  echo "${tag:-0.0.0}"
}

# Wraps a dylib into <out_dir>/<CORE_NAME>.framework.
make_framework() {
  local sdk="$1" dylib="$2" out_dir="$3"
  local framework="$out_dir/$CORE_NAME.framework"
  local platform="iPhoneOS"
  [[ "$sdk" == "iphonesimulator" ]] && platform="iPhoneSimulator"

  rm -rf "$framework"
  mkdir -p "$framework"
  cp "$dylib" "$framework/$CORE_NAME"
  install_name_tool -id "@rpath/$CORE_NAME.framework/$CORE_NAME" "$framework/$CORE_NAME"

  cat > "$framework/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>$CORE_NAME</string>
	<key>CFBundleIdentifier</key>
	<string>com.faentiver.arcfold.core.${CORE_NAME//_/-}</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>$CORE_NAME</string>
	<key>CFBundlePackageType</key>
	<string>FMWK</string>
	<key>CFBundleShortVersionString</key>
	<string>$(core_version)</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>CFBundleSupportedPlatforms</key>
	<array>
		<string>$platform</string>
	</array>
	<key>MinimumOSVersion</key>
	<string>$DEPLOYMENT_TARGET</string>
</dict>
</plist>
PLIST

  if declare -F core_package > /dev/null; then
    core_package "$sdk" "$framework" "$(dirname "$out_dir")"
  fi

  # install_name_tool invalidates the linker's ad-hoc signature. Xcode signs
  # the framework again when it embeds it into the app.
  codesign --force --sign - --timestamp=none "$framework" > /dev/null
}

work_root="$REPO_ROOT/build/cores/$core"
if [[ "$clean" == 1 ]]; then
  rm -rf "$work_root"
fi

frameworks=()
for sdk in "${SDKS[@]}"; do
  work_dir="$work_root/$sdk"
  mkdir -p "$work_dir"
  echo "==> Building $CORE_NAME for $sdk ($build_type)"
  set_ios_cmake_args "$sdk"
  core_build "$sdk" "$work_dir"

  dylib="$work_dir/$CORE_NAME.dylib"
  if [[ ! -f "$dylib" ]]; then
    echo "error: core_build did not produce $dylib" >&2
    exit 70
  fi
  make_framework "$sdk" "$dylib" "$work_dir/framework"
  frameworks+=(-framework "$work_dir/framework/$CORE_NAME.framework")
done

mkdir -p "$OUTPUT_DIR"
rm -f "$OUTPUT_DIR/$CORE_NAME.stamp"
rm -rf "$OUTPUT_DIR/$CORE_NAME.xcframework"
xcodebuild -create-xcframework "${frameworks[@]}" -output "$OUTPUT_DIR/$CORE_NAME.xcframework" > /dev/null
fingerprint > "$OUTPUT_DIR/$CORE_NAME.stamp"
echo "==> Wrote Cores/Build/$CORE_NAME.xcframework"
for sdk in "${SDKS[@]}"; do
  xcrun vtool -show-build "$work_root/$sdk/framework/$CORE_NAME.framework/$CORE_NAME" |
    awk -v sdk="$sdk" '/platform/ { p = $2 } /minos/ { m = $2 } END { printf "    %-16s platform %s, minos %s\n", sdk, p, m }'
done
