#!/usr/bin/env bash
#
# Prepares the checkout for building and can run any number of times: it
# fetches the submodules of the cores the app embeds, builds every core that
# is missing or outdated and generates Arcfold.xcodeproj from project.yml.
#
# Usage: Scripts/bootstrap.sh [--check]
#
# --check builds and generates nothing and fails if a core is missing or
# outdated. XcodeGen runs it before generating the project (preGenCommand in
# project.yml), so the project is never generated without its cores.
#
# The embedded cores are the Cores/Build/<CORE_NAME>.xcframework dependencies
# in project.yml. Each one comes from the recipe in Scripts/cores/ that sets
# that CORE_NAME. A core is outdated when its submodule commit, its recipe or
# Scripts/build-core.sh changed since it was built, that is when the stamp
# next to the xcframework no longer matches
# `Scripts/build-core.sh <recipe> --fingerprint`. Build logs go to build/logs/.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_ROOT
readonly CORES_DIR="$REPO_ROOT/Cores/Build"
readonly LOG_DIR="$REPO_ROOT/build/logs"

usage() {
  sed -n '3,18p' "$0" | sed 's/^# \{0,1\}//'
  exit 64
}

check_only=0
case "${1-}" in
  "") ;;
  --check) check_only=1 ;;
  -h | --help) usage ;;
  *) echo "error: unknown option $1" >&2; usage ;;
esac
[[ $# -le 1 ]] || usage

require() {
  command -v "$1" > /dev/null || {
    echo "error: $1 not found, install it with: $2" >&2
    exit 69
  }
}

# CORE_NAMEs of the xcframeworks that project.yml embeds, one per line.
embedded_cores() {
  sed -nE 's#^[[:space:]]*-[[:space:]]*framework:[[:space:]]*Cores/Build/([A-Za-z0-9_]+)\.xcframework[[:space:]]*$#\1#p' \
    "$REPO_ROOT/project.yml"
}

# Value of a plain assignment such as CORE_NAME="mgba_libretro" in a recipe.
recipe_value() {
  sed -nE "s/^$2=[\"']?([^\"']*)[\"']?[[:space:]]*$/\1/p" "$1" | head -n 1
}

# The recipe file that sets CORE_NAME to $1.
recipe_for() {
  local file
  for file in "$REPO_ROOT"/Scripts/cores/*.sh; do
    if [[ "$(recipe_value "$file" CORE_NAME)" == "$1" ]]; then
      echo "$file"
      return 0
    fi
  done
  return 1
}

# Checks out the commit the repository records for the submodule at $1.
# Does nothing when it is checked out already, as in CI after a shallow fetch.
sync_submodule() {
  local status
  status="$(git -C "$REPO_ROOT" submodule status -- "$1")"
  case "$status" in
    " "*) ;;
    "-"* | "+"*)
      echo "    $1: checking out the recorded commit"
      git -C "$REPO_ROOT" submodule update --init --recursive -- "$1"
      ;;
    "")
      echo "error: $1 is not a submodule" >&2
      exit 65
      ;;
    *)
      echo "error: $1 has merge conflicts" >&2
      exit 65
      ;;
  esac
}

# Prints missing, outdated or current.
core_state() {
  local recipe="$1" name="$2" source_dir="$3"
  if [[ ! -e "$REPO_ROOT/$source_dir/.git" || ! -d "$CORES_DIR/$name.xcframework" ]]; then
    echo missing
  elif [[ -f "$CORES_DIR/$name.stamp" &&
    "$("$REPO_ROOT/Scripts/build-core.sh" "$recipe" --fingerprint)" == "$(cat "$CORES_DIR/$name.stamp")" ]]; then
    echo current
  else
    echo outdated
  fi
}

build_core() {
  local recipe="$1" name="$2" state="$3" log="$LOG_DIR/$1.log" start="$SECONDS"
  require cmake "brew install cmake"
  require ninja "brew install ninja"
  mkdir -p "$LOG_DIR"
  echo "    $name: $state, building (log: build/logs/$recipe.log)"
  if ! "$REPO_ROOT/Scripts/build-core.sh" "$recipe" > "$log" 2>&1; then
    tail -n 30 "$log" >&2
    echo "error: building $name failed, see build/logs/$recipe.log" >&2
    exit 70
  fi
  echo "    $name: built in $((SECONDS - start)) s"
}

require git "xcode-select --install"

cores=()
while IFS= read -r name; do
  cores+=("$name")
done < <(embedded_cores)

[[ "$check_only" == 1 ]] || echo "==> Cores"
failed=0
for name in ${cores[@]+"${cores[@]}"}; do
  recipe_file="$(recipe_for "$name")" || {
    echo "error: project.yml embeds $name, but no recipe in Scripts/cores/ sets CORE_NAME=\"$name\"" >&2
    exit 65
  }
  recipe="$(basename "$recipe_file" .sh)"
  source_dir="$(recipe_value "$recipe_file" CORE_SOURCE)"

  if [[ "$check_only" == 1 ]]; then
    state="$(core_state "$recipe" "$name" "$source_dir")"
    if [[ "$state" != current ]]; then
      echo "error: Cores/Build/$name.xcframework is $state, run Scripts/bootstrap.sh" >&2
      failed=1
    fi
    continue
  fi

  sync_submodule "$source_dir"
  state="$(core_state "$recipe" "$name" "$source_dir")"
  if [[ "$state" == current ]]; then
    echo "    $name: up to date"
  else
    build_core "$recipe" "$name" "$state"
  fi
done

if [[ "$check_only" == 1 ]]; then
  exit "$failed"
fi

echo "==> Project"
require xcodegen "brew install xcodegen"
xcodegen generate --spec "$REPO_ROOT/project.yml" --quiet
echo "    generated Arcfold.xcodeproj"
