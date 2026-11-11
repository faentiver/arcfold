#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Check of the iPhone Duo poses with Arcfold (ADR 0006, section 15).
#
# The script creates its own Simulator device, installs the app, starts
# selftest.nds or selftest.gba with -ArcfoldAutorun and records the log of the
# app; ds-slim starts selftest.nds in the slim case of the DS as well
# (-LargerScreens YES: the vertical bar stays at the side of the outer
# display, the screens grow to 4 times, its own scene). Then it goes through
# the poses closed, closed sideways, open, book, tabletop, flat upright,
# closed and open. A posture tool named in POSE_CHECK_POSTURE_TOOL
# changes each pose by software (a program outside this repository that takes
# `<UDID> closed|open|book|tabletop [--orientation landscape-left] --quiet`,
# docs/wissen/falz.md); without one you change them yourself with the buttons
# below the device in Device Hub (Closed, Partially Open, Open, Rotate) and
# confirm each step with Return. After each change it waits 4 s without
# touching anything (the window of the change), then takes screenshots of
# both displays and the state of the displays. Screenshots and devicectl
# delay the emulation in the Simulator themselves (up to 383 ms,
# docs/wissen/falz.md), so steps.txt keeps the times of both windows, and
# summary.txt assigns every gap and resynchronisation of the log to the
# change, to a screenshot or to neither.
# At the end it deletes the device. It never uses `simctl io ... screenConfig
# ... power`, which leaves the outer display black until the device restarts.
#
# Usage: Scripts/pose-check.sh [ds|ds-slim|gba]
#
#   POSE_CHECK_POSTURE_TOOL=<program>
#                         the posture tool that changes the poses by software;
#                         without it the script asks for each step in Device Hub.
#   POSE_CHECK_HUB=1      change the poses by hand in Device Hub even if a
#                         posture tool is named.
#   POSE_CHECK_DRY_RUN=1  dry run without any change of the pose (also
#                         POSE_CHECK_NO_HUB=1): the steps follow each other
#                         after POSE_CHECK_STEP_SECONDS (default 3), the pose
#                         stays closed.
#   POSE_CHECK_OUT=<dir>  where the results go; default
#                         build/pose-check/<time>-<system> in the repository.
#   POSE_CHECK_APP=<app>  the built Arcfold.app for the Simulator; default the
#                         Debug build in build/DerivedData, which the script
#                         builds or brings up to date first, so that an older
#                         build never stands in for the current code.
#
# Needs Xcode with the iOS 27.1 Simulator runtime (the only one with the
# iPhone Duo) and Arcfold.xcodeproj from Scripts/bootstrap.sh.

set -euo pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)
SYSTEM=${1:-ds}
# Launch arguments beyond the game.
EXTRA=()
case "$SYSTEM" in
    ds) GAME="$REPO/Tests/Fixtures/ds/selftest.nds" ;;
    ds-slim)
        GAME="$REPO/Tests/Fixtures/ds/selftest.nds"
        EXTRA=(-LargerScreens YES)
        ;;
    gba) GAME="$REPO/Tests/Fixtures/gba/selftest.gba" ;;
    *)
        echo "Usage: $0 [ds|ds-slim|gba]" >&2
        exit 64
        ;;
esac
DRY_RUN=${POSE_CHECK_DRY_RUN:-${POSE_CHECK_NO_HUB:-}}
POSTURE_TOOL=${POSE_CHECK_POSTURE_TOOL:-}
BY_HAND=${POSE_CHECK_HUB:-}
if [[ -z "$POSTURE_TOOL" ]]; then
    BY_HAND=1
elif [[ ! -x "$POSTURE_TOOL" ]]; then
    echo "POSE_CHECK_POSTURE_TOOL is not an executable program: $POSTURE_TOOL" >&2
    exit 64
fi
if [[ -n "$DRY_RUN" ]]; then
    MODE="none (dry run)"
elif [[ -n "$BY_HAND" ]]; then
    MODE="by hand in Device Hub"
else
    MODE="by software ($(basename "$POSTURE_TOOL"))"
fi
STEP_SECONDS=${POSE_CHECK_STEP_SECONDS:-3}
OUT=${POSE_CHECK_OUT:-"$REPO/build/pose-check/$(date +%Y%m%d-%H%M%S)-$SYSTEM"}
APP=${POSE_CHECK_APP:-}
BUNDLE_ID=com.faentiver.arcfold
DEVICE_NAME="Arcfold Posen"
mkdir -p "$OUT"

if [[ -z "$APP" ]]; then
    APP="$REPO/build/DerivedData/Build/Products/Debug-iphonesimulator/Arcfold.app"
    if [[ ! -d "$REPO/Arcfold.xcodeproj" ]]; then
        echo "Arcfold.xcodeproj is missing: run Scripts/bootstrap.sh first." >&2
        exit 1
    fi
    echo "Building Arcfold (Store, Debug, Simulator) …"
    (cd "$REPO" && xcodebuild build -project Arcfold.xcodeproj -scheme Store \
        -destination 'generic/platform=iOS Simulator' -derivedDataPath build/DerivedData >"$OUT/build.log" 2>&1) || {
        echo "The build failed, see $OUT/build.log" >&2
        exit 1
    }
fi

UDID=$(xcrun simctl create "$DEVICE_NAME" com.apple.CoreSimulator.SimDeviceType.iPhone-Duo \
    com.apple.CoreSimulator.SimRuntime.iOS-27-1)
echo "Device \"$DEVICE_NAME\": $UDID"
LOG_PID=""
cleanup() {
    if [[ -n "$LOG_PID" ]]; then
        kill "$LOG_PID" 2>/dev/null || true
    fi
    xcrun simctl shutdown "$UDID" 2>/dev/null || true
    xcrun simctl delete "$UDID" 2>/dev/null || true
    echo "Device deleted. Results: $OUT"
}
trap cleanup EXIT

xcrun simctl boot "$UDID"
xcrun simctl bootstatus "$UDID" -b >/dev/null
# The home screen takes a moment after booting.
sleep 10
xcrun simctl install "$UDID" "$APP"

xcrun simctl spawn "$UDID" log stream --style compact --level info --predicate \
    'subsystem == "com.faentiver.arcfold" AND (category == "fold" OR category == "stats" OR category == "play")' \
    >"$OUT/log.txt" 2>&1 &
LOG_PID=$!
sleep 2
xcrun simctl launch "$UDID" "$BUNDLE_ID" -ArcfoldAutorun "$GAME" ${EXTRA[@]+"${EXTRA[@]}"} >/dev/null
# Import, start and fill the sound buffer.
sleep 8

if [[ -z "$DRY_RUN" && -n "$BY_HAND" ]]; then
    open -a "Device Hub" || echo "Device Hub did not open; open it from Xcode (Window > Devices and Simulators)."
fi

# Seconds since 1970 with milliseconds, to match the log's times to the steps.
now() {
    perl -MTime::HiRes=time -e 'printf "%.3f\n", time'
}

# After a step: 4 s without anything else, in which the layout and the
# drawable follow the pose (the window of the change); then screenshots of
# both displays (1 outer, 3 inner) and which display is active (the window of
# the screenshots). steps.txt keeps both windows. The window of the change
# starts at the second argument if there is one (the start of a change by
# software), else now.
capture() {
    local name=$1 change=${2:-} photos_start photos_end
    if [[ -z "$change" ]]; then
        change=$(now)
    fi
    sleep 4
    photos_start=$(now)
    xcrun simctl io "$UDID" screenshot --display=1 "$OUT/$name-outer.png" >/dev/null 2>&1 || true
    xcrun simctl io "$UDID" screenshot --display=3 "$OUT/$name-inner.png" >/dev/null 2>&1 || true
    xcrun devicectl device info displays --device "$UDID" --json-output "$OUT/$name-displays.json" >/dev/null 2>&1 || true
    photos_end=$(now)
    echo "$(date -r "${change%.*}" '+%H:%M:%S') $name change=$change photos=$photos_start-$photos_end" >>"$OUT/steps.txt"
}

# Every gap and resynchronisation of the log with the window it falls into:
# the app logs a gap up to about 1.5 s after it (it publishes its lateness
# once a second and the app asks every 250 ms), so a window reaches that far.
classify_gaps() {
    perl -MTime::Local -e '
        my ($steps, $log) = @ARGV;
        my @windows;
        open(my $in, "<", $steps) or die "$steps: $!";
        while (<$in>) {
            push @windows, [$1, $2, $3, $4] if /^\S+ (\S+) change=([\d.]+) photos=([\d.]+)-([\d.]+)/;
        }
        open($in, "<", $log) or die "$log: $!";
        my $count = 0;
        while (my $line = <$in>) {
            next unless $line =~ /Emulation (gap|resynchronized)/;
            next unless $line =~ /^(\d{4})-(\d\d)-(\d\d) (\d\d):(\d\d):(\d\d(?:\.\d+)?)/;
            my $time = timelocal(int($6), $5, $4, $3, $2 - 1, $1) + ($6 - int($6));
            my $window = "outside both windows";
            for my $w (@windows) {
                my ($name, $change, $start, $end) = @$w;
                if ($time >= $change && $time < $start) { $window = "CHANGE to $name"; last }
                if ($time >= $start && $time <= $end + 1.5) { $window = "screenshot after $name"; last }
            }
            $line =~ s/^(\S+ \S+).*?(Emulation .*)$/$1 $2/;
            chomp $line;
            print "$line  <- $window\n";
            $count++;
        }
        print "none\n" unless $count;
    ' "$OUT/steps.txt" "$OUT/log.txt"
}

capture 01-closed
# Name | arguments of the posture tool | what to click in Device Hub
steps=(
    "02-closed-landscape|closed --orientation landscape-left|In Device Hub, select \"$DEVICE_NAME\" and click Rotate (closed, sideways: the game turns with the outer display)"
    "03-open|open|Click Rotate back to upright, then Open (flat, landscape, fold vertical)"
    "04-book|book|Click Partially Open (half open like a book)"
    "05-tabletop|tabletop|Click Rotate so that the fold lies horizontal (tabletop)"
    "06-flat-upright|open --orientation landscape-left|Click Open (flat, upright, fold horizontal)"
    "07-closed|closed|Click Closed (folding shut: the game pauses, the pause menu shows on the outer display)"
    "08-open|open|Click Open (unfolding: the game resumes by itself)"
)
for step in "${steps[@]}"; do
    name=${step%%|*}
    rest=${step#*|}
    posture=${rest%%|*}
    text=${rest#*|}
    if [[ -n "$DRY_RUN" ]]; then
        echo "Dry run: $name"
        sleep "$STEP_SECONDS"
        capture "$name"
    elif [[ -n "$BY_HAND" ]]; then
        read -r -p $'\n'"$text, then press Return: " _
        capture "$name"
    else
        echo "$name: $(basename "$POSTURE_TOOL") $posture"
        change=$(now)
        # The arguments are words on purpose, e.g. "open --orientation landscape-left".
        # shellcheck disable=SC2086
        "$POSTURE_TOOL" "$UDID" $posture --quiet >>"$OUT/posture.log" 2>&1 || {
            echo "The change to $name failed, see $OUT/posture.log" >&2
            exit 1
        }
        capture "$name" "$change"
    fi
done

sleep 3
kill "$LOG_PID" 2>/dev/null || true
LOG_PID=""

# Lines of one category, without the log's prefix.
lines() {
    grep -E "\[$BUNDLE_ID:$1\]" "$OUT/log.txt" | sed -E "s/^([0-9-]+ [0-9:.]+).*\[$BUNDLE_ID:$1\] /\1 /" || true
}

{
    echo "Check of the poses with $SYSTEM ($(basename "$GAME")${EXTRA[*]+ ${EXTRA[*]}}), $(date '+%Y-%m-%d %H:%M')"
    echo "Poses changed: $MODE"
    echo
    echo "Expected (ADR 0006, sections 8 to 10): per step the pose and layout of section 8;"
    echo "no 'Emulation resynchronized' and no 'Emulation gap' line in the window of a"
    echo "CHANGE (gaps in the window of a screenshot come from the screenshot); no 'Game"
    echo "view disappeared' before the end; on 02-closed-landscape the game sideways on"
    echo "the outer display, still running; on 07-closed 'Paused: folded' and the pause"
    echo "menu on the outer display; on 08-open 'Resumed'."
    echo
    echo "Steps (times in seconds since 1970: the change, then the screenshots):"
    cat "$OUT/steps.txt"
    echo
    echo "Gaps and resynchronisations by window:"
    classify_gaps
    echo
    echo "Game view, hinge, scene phases, pauses, gaps:"
    lines fold | grep -E "Game view|Hinge|Scene phase|Still inactive|Paused|Resumed|Emulation" || true
    echo
    echo "Layouts:"
    lines fold | grep -E "Layout:" | uniq || true
    echo
    echo "Scene, screen, drawable, display link:"
    lines fold | grep -E "Scene (shown|changed)|Screen (is|changed)|Drawable|Display link" || true
    echo
    echo "Measurements every 10 s:"
    lines stats || true
    echo
    echo "Screenshots:"
    (cd "$OUT" && ls ./*.png 2>/dev/null) || true
} >"$OUT/summary.txt"
echo "Summary: $OUT/summary.txt"
