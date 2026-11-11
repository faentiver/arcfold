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
# poses: the pose part, in every variant. The script sets each pose once with
# the private posture tool outside the repository that POSE_CHECK_POSTURE_TOOL
# names, as Scripts/pose-check.sh does (closed, closed-landscape, open, book,
# tabletop, flat-upright), and runs in it, for each variant in turn, the states
# of the whole app: the game as DS (30) and GBA (31), each with the pause
# sheet, the library (32), the menu (33), the search (34), the licenses (35),
# a long notice with the status chip over a game (36) and the failure view
# (37); in closed-landscape also 12 (the sheet sideways) and
# GlassUITests/testSidewaysTheRButtonIsFree. In closed and closed-landscape it
# runs the DS a second time in the slim case (-LargerScreens YES, the vertical
# bar at the side): the game (30), the notice (36), the failure view (37) and,
# in light and dark, the clean picture (38), into <variant>-<pose>-slim/ with
# the pose named <pose>-slim. In the variants light and dark it
# also photographs the running DS and GBA without the debug overlay (38), the
# pictures for the documents: <variant>-38-<pose>-ds-clean.png and
# <variant>-38-<pose>-gba-clean.png, upright in every pose. In the variant
# light it also runs GameOverlayUITests and LibraryLayoutUITests, which take
# the pose as it is, and PoseUITests/testBothTestProgramsStartFromTheLibrary,
# which starts both test programs through their tiles ("ds started from the
# library.png", "gba started from the library.png").
# Then it starts selftest.nds open, closes the device and photographs the pause
# sheet on the outer display, and opens it again (40 to 42), for light and
# dark. Each pose and variant leaves <output>/<variant>-<pose>/ and
# <output>/<variant>-<pose>.xcresult, the photographs of the closing
# <output>/<variant>-closing/. The pose part needs a booted iPhone Duo and
# ends closed and upright. Without POSE_CHECK_POSTURE_TOOL it is skipped with a
# note and the script still ends with exit 0; the other variants run.
#
# ARCFOLD_TOUR_POSES limits the pose part to some poses, as in
# ARCFOLD_TOUR_POSES="tabletop book", and ARCFOLD_TOUR_POSE_VARIANTS to some
# variants, as in ARCFOLD_TOUR_POSE_VARIANTS=light; the photographs of the
# closing (40 to 42) are taken only with every pose.
#
# ARCFOLD_DERIVED_DATA names the derived data folder (default build/DerivedData).
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
derived=${ARCFOLD_DERIVED_DATA:-$root/build/DerivedData}
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
        -derivedDataPath "$derived" "${only[@]}" -resultBundlePath "$bundle" > "$log" 2>&1 || status=$?
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
    -derivedDataPath "$derived" > "$output/build.log" 2>&1 || {
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
    run_tests "$output/$variant.xcresult" "$output/$variant.log" ScreenshotTour
    export_attachments "$output/$variant.xcresult" "$output/$variant"
done

if [[ $runs_poses == 1 ]]; then
    read -r -a pose_variants <<< "${ARCFOLD_TOUR_POSE_VARIANTS:-light dark contrast large}"
    read -r -a poses <<< "${ARCFOLD_TOUR_POSES:-closed closed-landscape open book tabletop flat-upright}"
    for pose in "${poses[@]}"; do
        set_pose "$pose"
        export TEST_RUNNER_ARCFOLD_TOUR_POSE=$pose
        # The edges of the fold of the book in points of the window, for LibraryLayoutUITests.
        if [[ $pose == book ]]; then
            export TEST_RUNNER_ARCFOLD_LIBRARY_FOLD=455.5,495.5
        else
            unset TEST_RUNNER_ARCFOLD_LIBRARY_FOLD
        fi
        for variant in "${pose_variants[@]}"; do
            set_appearance "$variant"
            export TEST_RUNNER_ARCFOLD_TOUR_VARIANT=$variant
            tests=(ScreenshotTour/test30DSInThePose ScreenshotTour/test31GBAInThePose
                ScreenshotTour/test32LibraryInThePose ScreenshotTour/test33MenuInThePose
                ScreenshotTour/test34SearchInThePose ScreenshotTour/test35LicensesInThePose
                ScreenshotTour/test36NoticesInThePose ScreenshotTour/test37FailureInThePose)
            if [[ $pose == closed-landscape ]]; then
                tests+=(ScreenshotTour/test12PauseLandscape)
            fi
            # The games without the debug overlay, the pictures for the documents.
            if [[ $variant == light || $variant == dark ]]; then
                tests+=(ScreenshotTour/test38CleanGamesInThePose)
            fi
            if [[ $variant == light ]]; then
                tests+=(GameOverlayUITests LibraryLayoutUITests PoseUITests/testBothTestProgramsStartFromTheLibrary)
                if [[ $pose == closed-landscape ]]; then
                    tests+=(GlassUITests/testSidewaysTheRButtonIsFree)
                fi
            fi
            tests+=(ScreenshotTour/test99Metrics)
            export TEST_RUNNER_ARCFOLD_TOUR_LARGER_SCREENS=0
            run_tests "$output/$variant-$pose.xcresult" "$output/$variant-$pose.log" "${tests[@]}"
            export_attachments "$output/$variant-$pose.xcresult" "$output/$variant-$pose"
            # The closed DS once more in the slim case.
            if [[ $pose == closed || $pose == closed-landscape ]]; then
                tests=(ScreenshotTour/test30DSInThePose ScreenshotTour/test36NoticesInThePose
                    ScreenshotTour/test37FailureInThePose)
                if [[ $variant == light || $variant == dark ]]; then
                    tests+=(ScreenshotTour/test38CleanGamesInThePose)
                fi
                tests+=(ScreenshotTour/test99Metrics)
                export TEST_RUNNER_ARCFOLD_TOUR_LARGER_SCREENS=1
                run_tests "$output/$variant-$pose-slim.xcresult" "$output/$variant-$pose-slim.log" "${tests[@]}"
                export_attachments "$output/$variant-$pose-slim.xcresult" "$output/$variant-$pose-slim"
                export TEST_RUNNER_ARCFOLD_TOUR_LARGER_SCREENS=0
            fi
        done
    done
    unset TEST_RUNNER_ARCFOLD_TOUR_POSE TEST_RUNNER_ARCFOLD_LIBRARY_FOLD TEST_RUNNER_ARCFOLD_TOUR_LARGER_SCREENS

    # The pause sheet after closing: selftest.nds runs open, the device
    # closes, the sheet stands on the outer display; opening resumes. Only
    # with every pose.
    closing_variants=(light dark)
    if [[ -n ${ARCFOLD_TOUR_POSES:-} ]]; then
        closing_variants=(none)
    fi
    for variant in "${closing_variants[@]}"; do
        [[ $variant == none ]] && continue
        set_appearance "$variant"
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
