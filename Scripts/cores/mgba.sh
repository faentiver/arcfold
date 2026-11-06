# mGBA (Game Boy Advance), MPL-2.0. Uses the upstream libretro target.
# Game Boy support stays off because SameBoy covers GB and GBC (plan, M5).

CORE_NAME="mgba_libretro"
CORE_SOURCE="Cores/mgba"

core_build() {
  local sdk="$1" work_dir="$2"
  cmake -S "$REPO_ROOT/$CORE_SOURCE" -B "$work_dir/cmake" "${IOS_CMAKE_ARGS[@]}" \
    -DBUILD_LIBRETRO=ON \
    -DSKIP_LIBRARY=ON \
    -DBUILD_QT=OFF \
    -DBUILD_SDL=OFF \
    -DBUILD_SHARED=OFF \
    -DBUILD_STATIC=OFF \
    -DBUILD_GL=OFF \
    -DBUILD_GLES2=OFF \
    -DBUILD_GLES3=OFF \
    -DUSE_EPOXY=OFF \
    -DDISABLE_DEPS=ON \
    -DUSE_DEBUGGERS=OFF \
    -DUSE_EDITLINE=OFF \
    -DUSE_FFMPEG=OFF \
    -DUSE_MINIZIP=OFF \
    -DUSE_LIBZIP=OFF \
    -DUSE_ELF=OFF \
    -DUSE_LUA=OFF \
    -DUSE_LZMA=OFF \
    -DENABLE_SCRIPTING=OFF \
    -DM_CORE_GB=OFF
  cmake --build "$work_dir/cmake" --target mgba_libretro
  cp "$work_dir/cmake/mgba_libretro.dylib" "$work_dir/$CORE_NAME.dylib"
}
