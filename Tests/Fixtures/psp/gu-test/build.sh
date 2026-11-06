#!/usr/bin/env bash
#
# Builds Tests/Fixtures/psp/gu-test.elf from main.c with the PSPDEV toolchain
# (https://github.com/pspdev/pspdev, release v20261101 for the checked-in
# file). The toolchain is not part of the repo, see Tests/Fixtures/LICENSES.md.
#
# Usage: build.sh <pspdev directory> [<output file>]

set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  sed -n '3,8p' "$0" | sed 's/^# \{0,1\}//'
  exit 64
fi

pspdev="$(cd "$1" && pwd)"
source_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
output="${2:-$source_dir/../gu-test.elf}"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

# Same flags as PSPSDK's build.mak for a plain (non-PRX) ELF.
"$pspdev/bin/psp-gcc" -O2 -Wall -Wextra -std=c11 \
  -I"$pspdev/psp/include" -I"$pspdev/psp/sdk/include" -D_PSP_FW_VERSION=600 \
  -c "$source_dir/main.c" -o "$work_dir/main.o"
"$pspdev/bin/psp-gcc" -L"$pspdev/psp/lib" -L"$pspdev/psp/sdk/lib" -Wl,-zmax-page-size=128 \
  "$work_dir/main.o" -lpspgum -lpspgu -lpspdisplay -lpspge -lpspctrl \
  -o "$work_dir/gu-test.elf"
"$pspdev/bin/psp-fixup-imports" "$work_dir/gu-test.elf"
"$pspdev/bin/psp-strip" "$work_dir/gu-test.elf" -o "$output"

echo "Wrote $output"
shasum -a 256 "$output"
