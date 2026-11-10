#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Runs the ScreenshotTour UI test (ADR 0007) on one Simulator and exports its
# screenshots and measurements: the states of the interface once per variant,
# and in the pose part the game in every real pose of the iPhone Duo.
#
# Usage: Scripts/screenshot-tour.sh <UDID> <output folder> [light|dark|contrast|large|poses ...]
#
# Variants: light, dark, contrast (dark with Increase Contrast), large (light
# with the text size accessibility-large). Each variant leaves
# <output>/<variant>.xcresult and the folder <output>/<variant>/ with files
# named <variant>-<nn>-<state>.png and <variant>-metrics.txt.
#
# poses: the pose part, light and dark. The script sets each pose with the
# private posture tool outside the repository that POSE_CHECK_POSTURE_TOOL
# names, as Scripts/pose-check.sh does (closed, closed-landscape, open, book,
# tabletop, flat-upright), and runs the states of the game in it: 30 (DS) and
# 31 (GBA), each with the pause sheet, in closed-landscape also 12 (the sheet
# sideways) and GlassUITests/testSidewaysTheRButtonIsFree. Then it starts
# selftest.nds open, closes the device and photographs the pause sheet on the
# outer display, and opens it again (40 to 42). Each pose leaves
# <output>/<variant>-<pose>/ and <output>/<variant>-<pose>.xcresult, the
# photographs of the closing <output>/<variant>-closing/. With
# ARCFOLD_TOUR_MEASURE=1 it measures glass against flat in closed and open
# (state 98, 60 s per system and surface). The pose part needs a booted
# iPhone Duo and ends closed and upright. Without POSE_CHECK_POSTURE_TOOL it
# is skipped with a note and the script still ends with exit 0; the other
# variants run.
#
# Without arguments it runs all four variants and the pose part. It changes
# the appearance, contrast and text size of that Simulator only and sets them
# back to light, contrast off and text size large at the end. The status bar
# shows a fixed time and full bars meanwhile, so two runs give the same
# pictures. It needs a UDID; it never acts on all Simulators.

set -euo pipefail

if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <UDID> <output folder> [light|dark|contrast|large|poses ...]" >&2
    exit 64
fi

udid=$1
output=$2
shift 2
variants=("$@")
if [[ ${#variants[@]} -eq 0 ]]; then
    variants=(light dark contrast large poses)
fi

# The pose part needs the posture tool; without it only that part is left out.
posture_tool=${POSE_CHECK_POSTURE_TOOL:-}
kept=()
for variant in "${variants[@]}"; do
    if [[ $variant == poses && ( -z $posture_tool || ! -x $posture_tool ) ]]; then
        echo "== poses: skipped. Set POSE_CHECK_POSTURE_TOOL to the private posture tool (an executable outside this repository, see docs/wissen/falz.md)."
        continue
    fi
    kept+=("$variant")
done
if [[ ${#kept[@]} -eq 0 ]]; then
    exit 0
fi
variants=("${kept[@]}")

root=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$output"
output=$(cd "$output" && pwd)
bundle_id=com.faentiver.arcfold

restore() {
    xcrun simctl status_bar "$udid" clear || true
    xcrun simctl ui "$udid" appearance light || true
    xcrun simctl ui "$udid" increase_contrast disabled || true
    xcrun simctl ui "$udid" content_size large || true
}
trap restore EXIT
xcrun simctl status_bar "$udid" override --time 9:41 --wifiMode active --wifiBars 3 \
    --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100

# Exports the attachments of a result bundle into a folder and gives every
# file its attachment name; the manifest maps one to the other.
export_attachments() {
    local bundle=$1 folder=$2
    rm -rf "$folder"
    xcrun xcresulttool export attachments --path "$bundle" --output-path "$folder" > /dev/null
    python3 -I - "$folder" <<'PYTHON'
import json
import os
import sys

folder = sys.argv[1]
with open(os.path.join(folder, "manifest.json")) as file:
    manifest = json.load(file)
for test in manifest:
    for attachment in test["attachments"]:
        name = attachment.get("suggestedHumanReadableName")
        exported = attachment["exportedFileName"]
        if not name:
            continue
        # XCTest appends "_<index>_<UUID>" before the extension.
        stem, extension = os.path.splitext(name)
        parts = stem.split("_")
        if len(parts) >= 3:
            stem = "_".join(parts[:-2])
        if not extension:
            extension = os.path.splitext(exported)[1] or ".txt"
        os.replace(os.path.join(folder, exported), os.path.join(folder, stem + extension))
PYTHON
    list_files "$folder"
}

# Prints the files of a folder, indented, without the manifest.
list_files() {
    local file
    for file in "$1"/*; do
        [[ $(basename "$file") == manifest.json ]] || echo "   $(basename "$file")"
    done
}

# Runs tests of ArcfoldUITests without building; the arguments name them.
run_tests() {
    local bundle=$1 log=$2
    shift 2
    local only=()
    for test in "$@"; do
        only+=("-only-testing:ArcfoldUITests/$test")
    done
    rm -rf "$bundle"
    # A measurement that misses its limit fails the run; export what it shot anyway.
    local status=0
    xcodebuild test-without-building -project "$root/Arcfold.xcodeproj" -scheme Store -destination "id=$udid" \
        -derivedDataPath "$root/build/DerivedData" "${only[@]}" -resultBundlePath "$bundle" > "$log" 2>&1 || status=$?
    echo "   xcodebuild exit $status, log $log"
}

set_appearance() {
    case $1 in
        light) appearance=light contrast=disabled size=large ;;
        dark) appearance=dark contrast=disabled size=large ;;
        contrast) appearance=dark contrast=enabled size=large ;;
        large) appearance=light contrast=disabled size=accessibility-large ;;
        *) echo "Unknown variant: $1" >&2; exit 64 ;;
    esac
    echo "== $1: appearance $appearance, contrast $contrast, text size $size"
    xcrun simctl ui "$udid" appearance "$appearance"
    xcrun simctl ui "$udid" increase_contrast "$contrast"
    xcrun simctl ui "$udid" content_size "$size"
}

# Sets a real pose of the Duo by software with the posture tool
# (docs/wissen/falz.md).
set_pose() {
    local arguments
    case $1 in
        closed) arguments=(closed) ;;
        closed-landscape) arguments=(closed --orientation landscape-left) ;;
        open) arguments=(open) ;;
        book) arguments=(book) ;;
        tabletop) arguments=(tabletop) ;;
        flat-upright) arguments=(open --orientation landscape-left) ;;
        *) echo "Unknown pose: $1" >&2; exit 64 ;;
    esac
    echo "-- pose $1: ${arguments[*]}"
    "$posture_tool" "$udid" "${arguments[@]}" --quiet
    # The window follows the fold transition of SpringBoard.
    sleep 3
}

echo "== Building for testing"
xcodebuild build-for-testing -project "$root/Arcfold.xcodeproj" -scheme Store -destination "id=$udid" \
    -derivedDataPath "$root/build/DerivedData" > "$output/build.log" 2>&1 || {
    echo "The build failed, see $output/build.log" >&2
    exit 1
}

runs_poses=0
for variant in "${variants[@]}"; do
    if [[ $variant == poses ]]; then
        runs_poses=1
        continue
    fi
    set_appearance "$variant"
    export TEST_RUNNER_ARCFOLD_TOUR_VARIANT=$variant
    export TEST_RUNNER_ARCFOLD_TOUR_MEASURE=${ARCFOLD_TOUR_MEASURE:-0}
    run_tests "$output/$variant.xcresult" "$output/$variant.log" ScreenshotTour
    export_attachments "$output/$variant.xcresult" "$output/$variant"
done

if [[ $runs_poses == 1 ]]; then
    for variant in light dark; do
        set_appearance "$variant"
        export TEST_RUNNER_ARCFOLD_TOUR_VARIANT=$variant
        for pose in closed closed-landscape open book tabletop flat-upright; do
            set_pose "$pose"
            export TEST_RUNNER_ARCFOLD_TOUR_POSE=$pose
            tests=(ScreenshotTour/test30DSInThePose ScreenshotTour/test31GBAInThePose)
            if [[ $pose == closed-landscape ]]; then
                tests+=(ScreenshotTour/test12PauseLandscape GlassUITests/testSidewaysTheRButtonIsFree)
            fi
            if [[ ${ARCFOLD_TOUR_MEASURE:-0} == 1 && ($pose == closed || $pose == open) ]]; then
                export TEST_RUNNER_ARCFOLD_TOUR_MEASURE=1
                tests+=(ScreenshotTour/test98MeasureGlassAgainstFlat)
            else
                export TEST_RUNNER_ARCFOLD_TOUR_MEASURE=0
            fi
            tests+=(ScreenshotTour/test99Metrics)
            run_tests "$output/$variant-$pose.xcresult" "$output/$variant-$pose.log" "${tests[@]}"
            export_attachments "$output/$variant-$pose.xcresult" "$output/$variant-$pose"
        done
        unset TEST_RUNNER_ARCFOLD_TOUR_POSE

        # The pause sheet after closing: selftest.nds runs open, the device
        # closes, the sheet stands on the outer display; opening resumes.
        folder="$output/$variant-closing"
        rm -rf "$folder"
        mkdir -p "$folder"
        set_pose open
        xcrun simctl terminate "$udid" "$bundle_id" 2> /dev/null || true
        xcrun simctl launch "$udid" "$bundle_id" -ArcfoldAutorun "$root/Tests/Fixtures/ds/selftest.nds" > /dev/null
        sleep 10
        xcrun simctl io "$udid" screenshot --display=3 "$folder/$variant-40-open-before-closing.png" > /dev/null
        set_pose closed
        sleep 2
        xcrun simctl io "$udid" screenshot --display=1 "$folder/$variant-41-closed-pause-sheet.png" > /dev/null
        set_pose open
        sleep 2
        xcrun simctl io "$udid" screenshot --display=3 "$folder/$variant-42-open-again.png" > /dev/null
        xcrun simctl terminate "$udid" "$bundle_id" 2> /dev/null || true
        list_files "$folder"
    done
    set_pose closed
fi
