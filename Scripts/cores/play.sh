# Play! (PlayStation 2), BSD-2-Clause. Uses the upstream libretro target in
# Source/ui_libretro, which renders through OpenGL ES 3 (GSH_OpenGL with
# GLES_COMPATIBILITY) and asks the frontend for a RETRO_HW_CONTEXT_OPENGLES3
# context. Play! needs no BIOS (high-level emulation of the PS2 kernel).
#
# Only the JIT build may contain this core: its recompilers have no
# interpreter fallback (plan, section 8; ADR 0002).
#
# Build options follow upstream's libretro CI (.gitlab-ci.yml): no standalone
# UI, no tests, no Amazon S3 disc streaming. Extra compiler definitions:
# - IOS=1 enables the upstream check in retro_load_game that asks the frontend
#   for RETRO_ENVIRONMENT_GET_JIT_CAPABLE and refuses to start without JIT
#   instead of crashing in recompiled code.
# - PLAY_VERSION: upstream reads the version with `git describe` only when
#   .git is a directory. In a submodule it is a file, so the core would report
#   the fallback 0.30.
# libchdr uses the SDK's zlib: its bundled zlib renames zconf.h inside the
# submodule during configure, which would leave the submodule dirty.
#
# The core needs these nested submodules only:
#   git submodule update --init Cores/play
#   git -C Cores/play submodule update --init deps/CodeGen deps/Dependencies deps/Framework deps/libchdr
#   git -C Cores/play/deps/Dependencies submodule update --init ghc_filesystem xxHash zstd
# A recursive update also fetches AltKit, Nuanceur, SDWebImage and zlib. The
# build ignores them (iOS app UI, Vulkan GS and a zlib fallback that the SDK's
# zlib makes unnecessary), they only cost download time.

CORE_NAME="play_libretro"
CORE_SOURCE="Cores/play"

core_build() {
  local work_dir="$2" version
  version="$(git -C "$REPO_ROOT/$CORE_SOURCE" describe --tags --always)"
  cmake -S "$REPO_ROOT/$CORE_SOURCE" -B "$work_dir/cmake" "${IOS_CMAKE_ARGS[@]}" \
    -DTARGET_IOS=ON \
    -DBUILD_LIBRETRO_CORE=ON \
    -DBUILD_PLAY=OFF \
    -DBUILD_PSFPLAYER=OFF \
    -DBUILD_TESTS=OFF \
    -DENABLE_AMAZON_S3=OFF \
    -DUSE_AOT_CACHE=OFF \
    -DWITH_SYSTEM_ZLIB=ON \
    "-DCMAKE_CXX_FLAGS=-DIOS=1 -UPLAY_VERSION -DPLAY_VERSION=\\\"$version\\\""
  cmake --build "$work_dir/cmake" --target play_libretro
  cp "$work_dir/cmake/Source/ui_libretro/play_libretro_ios.dylib" "$work_dir/$CORE_NAME.dylib"
}
