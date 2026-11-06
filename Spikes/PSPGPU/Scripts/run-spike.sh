#!/usr/bin/env bash
#
# Installs the spike app on a simulator, runs one graphics path and copies the
# results (PNG files, report.txt, core.log) to an output directory. While the
# app runs, its installed bundle is read-only, as it is on a device.
#
# Usage: run-spike.sh <simulator udid> <gles|vulkan|software> <output dir> [launch arguments]
# Example launch arguments: -frames 600 -scale 2 -capture 60,300 -cycles 2 -dlclose YES
# Environment variables named SIMCTL_CHILD_* reach the app, for example
# SIMCTL_CHILD_DYLD_INSERT_LIBRARIES=<absolute path to libgltrap.dylib>.
#
# Build the app first:
#   xcodebuild -project Spikes/PSPGPU/PSPGPUSpike.xcodeproj -scheme PSPGPUSpike \
#     -destination "platform=iOS Simulator,id=<udid>" -derivedDataPath build/DerivedData-pspgpu build

set -euo pipefail

if [[ $# -lt 3 ]]; then
  sed -n '3,14p' "$0" | sed 's/^# \{0,1\}//'
  exit 64
fi

udid="$1"
backend="$2"
output="$3"
shift 3

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
app="$repo_root/build/DerivedData-pspgpu/Build/Products/Debug-iphonesimulator/PSPGPUSpike.app"
bundle_id="com.faentiver.arcfold.spike.pspgpu"

if [[ ! -d "$app" ]]; then
  echo "error: $app is missing, build the app first" >&2
  exit 66
fi

installed=""
make_writable() {
  if [[ -n "$installed" && -d "$installed" ]]; then
    chmod -R u+w "$installed"
  fi
}
trap make_writable EXIT

xcrun simctl bootstatus "$udid" -b > /dev/null
# A bundle that an aborted run left read-only could not be replaced.
if installed="$(xcrun simctl get_app_container "$udid" "$bundle_id" app 2> /dev/null)"; then
  make_writable
fi
xcrun simctl install "$udid" "$app"
installed="$(xcrun simctl get_app_container "$udid" "$bundle_id" app)"
chmod -R a-w "$installed"

launched=0
xcrun simctl launch --console-pty --terminate-running-process "$udid" "$bundle_id" \
  -backend "$backend" -exitWhenDone YES "$@" || launched=$?
make_writable

container="$(xcrun simctl get_app_container "$udid" "$bundle_id" data)"
mkdir -p "$output"
cp -R "$container/Documents/$backend/." "$output/"
# simctl does not pass the app's exit code on, so the report decides.
if [[ "$launched" == 0 ]] && grep -q '^result OK$' "$output/report.txt" 2> /dev/null; then
  echo "Results in $output (result OK)"
  exit 0
fi
echo "Results in $output (result FAILED or missing, simctl exit $launched)"
exit 1
