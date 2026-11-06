#!/usr/bin/env bash
#
# Builds the JIT spike, runs it once in a simulator and collects the results.
#
# Usage: Spikes/PS2JIT/run-simulator.sh <simulator-udid> <output-dir> [launch arguments...]
#
# The core has to exist first: Scripts/build-core.sh play
# Launch arguments are passed to the app, for example `-jitCapable NO` to
# answer RETRO_ENVIRONMENT_GET_JIT_CAPABLE with false. The app always gets
# `-autorun YES`. Results land in <output-dir>: report.json, frame.png
# (the core's last frame), ps2_stdout.txt and screen.png (the app's UI).

set -euo pipefail

SPIKE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SPIKE_DIR/../.." && pwd)"
readonly SPIKE_DIR REPO_ROOT
readonly BUNDLE_ID="com.faentiver.arcfold.spike.jit"
readonly DERIVED_DATA="$REPO_ROOT/build/spike-jit/DerivedData"

[[ $# -ge 2 ]] || { sed -n '3,12p' "$0" | sed 's/^# \{0,1\}//'; exit 64; }
udid="$1"
output_dir="$2"
shift 2

if [[ ! -d "$REPO_ROOT/Cores/Build/play_libretro.xcframework" ]]; then
  echo "error: Cores/Build/play_libretro.xcframework is missing, run Scripts/build-core.sh play" >&2
  exit 66
fi

(cd "$SPIKE_DIR" && xcodegen generate --quiet)
xcodebuild -project "$SPIKE_DIR/JITSpike.xcodeproj" -scheme JITSpike -configuration Debug \
  -destination "id=$udid" -derivedDataPath "$DERIVED_DATA" build -quiet

xcrun simctl bootstatus "$udid" -b > /dev/null
xcrun simctl install "$udid" "$DERIVED_DATA/Build/Products/Debug-iphonesimulator/JITSpike.app"
launched_at="$(date +%s)"
xcrun simctl launch --terminate-running-process "$udid" "$BUNDLE_ID" -autorun YES "$@" > /dev/null

# A report from an earlier launch may still exist; only a newer one counts.
data_dir="$(xcrun simctl get_app_container "$udid" "$BUNDLE_ID" data)"
report="$data_dir/Documents/SpikeResults/report.json"
is_new_report() {
  [[ -f "$report" ]] && [[ "$(stat -f %m "$report")" -ge "$launched_at" ]]
}
for _ in $(seq 1 180); do
  is_new_report && break
  sleep 1
done
if ! is_new_report; then
  echo "error: no new report after 180 s" >&2
  exit 70
fi
# Give SwiftUI a moment to show the result before taking the screenshot.
sleep 2

mkdir -p "$output_dir"
cp "$data_dir/Documents/SpikeResults/"* "$output_dir/"
xcrun simctl io "$udid" screenshot --type=png "$output_dir/screen.png" > /dev/null
xcrun simctl terminate "$udid" "$BUNDLE_ID" > /dev/null || true
cat "$output_dir/report.json"
