#!/usr/bin/env bash
#
# Installs the spike app on a simulator, runs one graphics path and copies the
# results (PNG files, report.txt, core.log) to an output directory.
#
# Usage: run-spike.sh <simulator udid> <gles|vulkan|software> <output dir> [launch arguments]
# Example launch arguments: -frames 600 -scale 2 -capture 60,300
#
# Build the app first:
#   xcodebuild -project Spikes/PSPGPU/PSPGPUSpike.xcodeproj -scheme PSPGPUSpike \
#     -destination "platform=iOS Simulator,id=<udid>" -derivedDataPath build/DerivedData-pspgpu build

set -euo pipefail

if [[ $# -lt 3 ]]; then
  sed -n '3,12p' "$0" | sed 's/^# \{0,1\}//'
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

xcrun simctl bootstatus "$udid" -b > /dev/null
xcrun simctl install "$udid" "$app"
status=0
xcrun simctl launch --console-pty --terminate-running-process "$udid" "$bundle_id" \
  -backend "$backend" -exitWhenDone YES "$@" || status=$?

container="$(xcrun simctl get_app_container "$udid" "$bundle_id" data)"
mkdir -p "$output"
cp -R "$container/Documents/$backend/." "$output/"
echo "Results in $output (exit $status)"
exit "$status"
