# PPSSPP (PlayStation Portable), GPL-2.0-or-later. Uses the upstream libretro
# target. The core draws through a hardware context the host provides
# (OpenGL ES or Vulkan), see docs/adr/0001-psp-grafik.md.

CORE_NAME="ppsspp_libretro"
CORE_SOURCE="Cores/ppsspp"

# Nested submodules the libretro target needs. OpenXR-SDK and miniupnp only
# contribute headers that PPSSPP always compiles against. FFmpeg, MoltenVK,
# SDL, the test suite and the desktop-only libraries stay uninitialised.
PPSSPP_SUBMODULES=(
  libretro/libretro-common
  ext/OpenXR-SDK
  ext/SPIRV-Cross
  ext/aemu_postoffice
  ext/armips
  ext/cpu_features
  ext/glslang
  ext/libchdr
  ext/lua
  ext/miniupnp
  ext/rapidjson
  ext/rcheevos
  ext/zstd
)

ppsspp_check_submodules() {
  local missing=() path
  for path in "${PPSSPP_SUBMODULES[@]}"; do
    [[ -e "$REPO_ROOT/$CORE_SOURCE/$path/.git" ]] || missing+=("$path")
  done
  if [[ ${#missing[@]} -gt 0 || ! -e "$REPO_ROOT/$CORE_SOURCE/ext/armips/ext/filesystem/.git" ]]; then
    echo "error: PPSSPP submodules missing, run:" >&2
    echo "  git -C $CORE_SOURCE submodule update --init --depth 1 ${PPSSPP_SUBMODULES[*]}" >&2
    echo "  git -C $CORE_SOURCE/ext/armips submodule update --init --depth 1 ext/filesystem" >&2
    exit 66
  fi
}

# CMake leaves CMAKE_SYSTEM_PROCESSOR empty for iOS, but PPSSPP and
# cpu_features pick their ARM64 sources from it. USING_GLES2 selects the
# OpenGL ES backend, the only GL flavour on iOS. The Vulkan backend is always
# built. FFmpeg stays off because PPSSPP's prebuilt iOS libraries have no
# arm64 simulator slice (ADR 0001).
core_build() {
  local sdk="$1" work_dir="$2"
  ppsspp_check_submodules

  # PPSSPP lowers CMAKE_OSX_DEPLOYMENT_TARGET to 12.0 for iOS right after
  # project(), which the SDK's libc++ no longer supports. This hook runs after
  # project(PPSSPP) and restores the value build-core.sh passes.
  local keep_target="$work_dir/keep-deployment-target.cmake"
  cat > "$keep_target" << 'CMAKE'
set(ARCFOLD_DEPLOYMENT_TARGET "${CMAKE_OSX_DEPLOYMENT_TARGET}")
function(arcfold_keep_deployment_target variable access value)
  if(access STREQUAL "MODIFIED_ACCESS" AND NOT value STREQUAL ARCFOLD_DEPLOYMENT_TARGET)
    message(STATUS "Keeping CMAKE_OSX_DEPLOYMENT_TARGET at ${ARCFOLD_DEPLOYMENT_TARGET} instead of ${value}")
    set(CMAKE_OSX_DEPLOYMENT_TARGET "${ARCFOLD_DEPLOYMENT_TARGET}" PARENT_SCOPE)
  endif()
endfunction()
variable_watch(CMAKE_OSX_DEPLOYMENT_TARGET arcfold_keep_deployment_target)
CMAKE

  cmake -S "$REPO_ROOT/$CORE_SOURCE" -B "$work_dir/cmake" "${IOS_CMAKE_ARGS[@]}" \
    -DCMAKE_PROJECT_PPSSPP_INCLUDE="$keep_target" \
    -DCMAKE_SYSTEM_PROCESSOR=arm64 \
    -DLIBRETRO=ON \
    -DUSING_GLES2=ON \
    -DMOBILE_DEVICE=ON \
    "-DOPENGL_LIBRARIES=-framework OpenGLES" \
    -DUSE_FFMPEG=OFF \
    -DUSE_MINIUPNPC=OFF \
    -DUSE_DISCORD=OFF \
    -DUSE_CCACHE=OFF \
    -DHEADLESS=OFF \
    -DUNITTEST=OFF \
    -DATLAS_TOOL=OFF

  # git-version.cmake looks for a .git directory, which a submodule checkout
  # does not have, and would report "unknown". Pin the version the way
  # PPSSPP's own b-ios.sh does.
  printf 'const char *PPSSPP_GIT_VERSION = "%s";\n#define PPSSPP_GIT_VERSION_NO_UPDATE 1\n' \
    "$(git -C "$REPO_ROOT/$CORE_SOURCE" describe --always --tags)" > "$work_dir/cmake/git-version.cpp"

  cmake --build "$work_dir/cmake" --target ppsspp_libretro
  cp "$work_dir/cmake/lib/ppsspp_libretro.dylib" "$work_dir/$CORE_NAME.dylib"
}

# The core reads its assets from <system directory>/PPSSPP. The host passes
# <framework>/system as the system directory. Only assets from PPSSPP's own
# tree with a clear license go in: compat.ini (per-game fixes) and the VFPU
# lookup tables. ppge_atlas.zim (rendered from commercial fonts) and the
# replacement fonts in flash0 stay out until their licenses are clear.
core_package() {
  local assets="$REPO_ROOT/$CORE_SOURCE/assets"
  local target="$2/system/PPSSPP"
  mkdir -p "$target"
  cp "$assets/compat.ini" "$target/"
  cp -R "$assets/vfpu" "$target/"
}
