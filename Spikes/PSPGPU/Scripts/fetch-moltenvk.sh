#!/usr/bin/env bash
#
# Downloads the official MoltenVK release (Apache-2.0) from
# github.com/KhronosGroup/MoltenVK, checks its SHA-256 and unpacks it to
# build/moltenvk/, where Spikes/PSPGPU/project.yml expects it. It takes the
# archive for all platforms because MoltenVK-ios.tar has no simulator slice.

set -euo pipefail

readonly VERSION="v1.4.2"
readonly ARCHIVE="MoltenVK-all.tar"
readonly SHA256="562a15a29bc358446a56a4091c5f7e08f604184187c1d34f712148b61ef17276"

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
target="$repo_root/build/moltenvk"
framework="$target/MoltenVK/MoltenVK/static/MoltenVK.xcframework"

if [[ -d "$framework" && "$(cat "$target/VERSION" 2> /dev/null)" == "$VERSION" ]]; then
  echo "MoltenVK $VERSION is already in build/moltenvk"
  exit 0
fi

download="$(mktemp -d)"
trap 'rm -rf "$download"' EXIT
curl --fail --location --silent --show-error \
  --output "$download/$ARCHIVE" \
  "https://github.com/KhronosGroup/MoltenVK/releases/download/$VERSION/$ARCHIVE"
echo "$SHA256  $download/$ARCHIVE" | shasum -a 256 --check --status || {
  echo "error: checksum mismatch for $ARCHIVE" >&2
  exit 65
}

rm -rf "$target"
mkdir -p "$target"
tar -xf "$download/$ARCHIVE" -C "$target"
echo "$VERSION" > "$target/VERSION"
echo "MoltenVK $VERSION unpacked to build/moltenvk"
