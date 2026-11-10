#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Builds a libretro core as a dynamic framework for iOS devices and for the
# iOS Simulator (both arm64) and combines them into
# Cores/Build/<CORE_NAME>.xcframework.
#
# Usage: Scripts/build-core.sh <core> [--debug] [--clean] [--fingerprint]
#                                      [--submodules] [--check [<binary>...]]
#
# --fingerprint prints what the build depends on (submodule commits, recipe,
# this script, build type) and builds nothing. After a build the same text is
# stored in Cores/Build/<CORE_NAME>.stamp, so Scripts/bootstrap.sh can tell
# whether a core is outdated.
# --submodules prints the submodules the core needs, CORE_SOURCE first and
# then CORE_DEPENDENCIES, one path per line, and builds nothing.
# --check builds nothing and runs the checks below on every slice of
# Cores/Build/<CORE_NAME>.xcframework, or on the binaries named after it,
# and prints the same summary lines as a build. It cannot be combined with
# --clean, --fingerprint or --submodules (exit status 64).
#
# After building a slice, the script checks the core's binary and stops with
# exit status 70 if a check fails. The Store build must not contain a JIT
# code path (plan, section 8) or load code (App Review Guideline 2.5.2), and
# App Review checks binaries statically:
#   exports  exactly the 25 functions of the libretro API
#   imports  no function that can make memory executable, load code, start a
#            program or relax code signing (nm -u and dyld_info -imports)
#   mmap     every call is a bl whose basic block sets prot and flags to
#            constants, or to a choice between constants, prot without
#            PROT_EXEC and flags without MAP_JIT; a tail call, a taken
#            address or any other reference to mmap that the check finds
#            stops it
#   svc      no system call past libSystem (svc, hvc, smc) and no word in
#            __TEXT,__text that the disassembler cannot decode
#   JIT      no symbol (nm -a) and no string (strings -a) with a typical JIT
#            name such as ARMJIT, Arm64Gen or MAP_JIT
# and then the recipe's own checks (core_check). Each check prints a summary
# line and also fails when its tools report implausibly little (no imports,
# a disassembly that does not cover __TEXT,__text, no local symbols), so
# that it never silently checks nothing. There is no exception: a core for
# the JIT build only (Play!) fails these checks.
#
# What the checks of the code (mmap, svc) are good for: code that the
# compiler generates from the sources of a core maps no executable memory
# and no memory for a JIT. They follow direct jumps and calls, the jump
# tables of LLVM and the constants of a basic block. Hand-written assembly
# can get around them with a detour, for example the address of mmap's
# pointer copied to another register or computed with an offset, a pointer
# relative to the GOT read from data, or an indirect jump into the middle of
# a basic block. They do not replace a review of the assembly sources of a
# core.
#
# Every core has a recipe in Scripts/cores/<core>.sh. A recipe sets
#   CORE_NAME     binary and framework name, for example mgba_libretro
#   CORE_SOURCE   path of the core's submodule, relative to the repo root
# and defines
#   core_build <sdk> <work_dir>
# which builds the core for <sdk> (iphoneos or iphonesimulator) and leaves the
# shared library at <work_dir>/<CORE_NAME>.dylib. Recipes that use CMake pass
# "${IOS_CMAKE_ARGS[@]}", which holds the common cross-compile flags,
# including the list of the 25 libretro functions the core may export.
# A recipe may also set
#   CORE_DEPENDENCIES  further submodules of this repo the build needs, an
#                      array of paths relative to the repo root; their
#                      commits count for the fingerprint like CORE_SOURCE
# and define
#   core_package <sdk> <framework_dir> <work_dir>
# to add files the core needs at runtime (assets, shaders) to the framework
# before it is signed, and
#   core_check <binary>
# for further checks of a built slice; like the checks above, it prints a
# summary line per check and exits with status 70 if one fails.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_ROOT
readonly DEPLOYMENT_TARGET="27.0"
readonly OUTPUT_DIR="$REPO_ROOT/Cores/Build"
readonly SDKS=(iphoneos iphonesimulator)

usage() {
  sed -n '4,73p' "$0" | sed 's/^# \{0,1\}//'
  exit 64
}

core=""
build_type="Release"
clean=0
print_fingerprint=0
print_submodules=0
check_only=0
check_binaries=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --debug) build_type="Debug" ;;
    --clean) clean=1 ;;
    --fingerprint) print_fingerprint=1 ;;
    --submodules) print_submodules=1 ;;
    --check) check_only=1 ;;
    -h | --help) usage ;;
    -*) echo "error: unknown option $1" >&2; usage ;;
    *)
      if [[ -z "$core" ]]; then
        core="$1"
      elif [[ "$check_only" == 1 ]]; then
        check_binaries+=("$1")
      else
        usage
      fi
      ;;
  esac
  shift
done
[[ -n "$core" ]] || usage
if [[ "$check_only" == 1 && ("$clean" == 1 || "$print_fingerprint" == 1 || "$print_submodules" == 1) ]]; then
  echo "error: --check builds nothing and cannot be combined with --clean, --fingerprint or --submodules" >&2
  exit 64
fi

recipe="$REPO_ROOT/Scripts/cores/$core.sh"
if [[ ! -f "$recipe" ]]; then
  echo "error: no recipe at Scripts/cores/$core.sh" >&2
  exit 66
fi

CORE_NAME=""
CORE_SOURCE=""
CORE_DEPENDENCIES=()
# shellcheck source=/dev/null
source "$recipe"
[[ -n "$CORE_NAME" && -n "$CORE_SOURCE" ]] || {
  echo "error: $recipe must set CORE_NAME and CORE_SOURCE" >&2
  exit 65
}
declare -F core_build > /dev/null || {
  echo "error: $recipe must define core_build" >&2
  exit 65
}

if [[ "$print_submodules" == 1 ]]; then
  printf '%s\n' "$CORE_SOURCE" ${CORE_DEPENDENCIES[@]+"${CORE_DEPENDENCIES[@]}"}
  exit 0
fi

for submodule in "$CORE_SOURCE" ${CORE_DEPENDENCIES[@]+"${CORE_DEPENDENCIES[@]}"}; do
  if [[ ! -e "$REPO_ROOT/$submodule/.git" ]]; then
    echo "error: $submodule is missing, run Scripts/bootstrap.sh or: git submodule update --init --depth 1 $submodule" >&2
    echo "       If the core needs nested submodules, Scripts/cores/$core.sh names them." >&2
    exit 66
  fi
done

# Everything the built core depends on. A change in any line makes it outdated.
fingerprint() {
  local source_commit recipe_hash script_hash dependency
  source_commit="$(git -C "$REPO_ROOT/$CORE_SOURCE" rev-parse HEAD)"
  recipe_hash="$(shasum -a 256 "$recipe" | cut -d ' ' -f 1)"
  script_hash="$(shasum -a 256 "$REPO_ROOT/Scripts/build-core.sh" | cut -d ' ' -f 1)"
  printf 'source %s %s\n' "$CORE_SOURCE" "$source_commit"
  for dependency in ${CORE_DEPENDENCIES[@]+"${CORE_DEPENDENCIES[@]}"}; do
    printf 'dependency %s %s\n' "$dependency" "$(git -C "$REPO_ROOT/$dependency" rev-parse HEAD)"
  done
  printf 'recipe %s %s\nbuild-core %s\nbuild-type %s\n' "$core" "$recipe_hash" "$script_hash" "$build_type"
}

if [[ "$print_fingerprint" == 1 ]]; then
  fingerprint
  exit 0
fi

# The 25 functions of the libretro API, the only symbols a core exports.
# Every core exports the same names, so a core never clashes with the app or
# with another core (ADR 0003). A pattern such as _retro_* would also export
# helpers of libretro-common (retro_vfs_*_impl and others, ADR 0006).
readonly LIBRETRO_EXPORTS=(
  retro_set_environment retro_set_video_refresh retro_set_audio_sample
  retro_set_audio_sample_batch retro_set_input_poll retro_set_input_state
  retro_init retro_deinit retro_api_version retro_get_system_info
  retro_get_system_av_info retro_set_controller_port_device retro_reset
  retro_run retro_serialize_size retro_serialize retro_unserialize
  retro_cheat_reset retro_cheat_set retro_load_game retro_load_game_special
  retro_unload_game retro_get_region retro_get_memory_data retro_get_memory_size
)

# Imports that can make memory executable, load code, start a program or
# relax code signing, as regular expressions for the whole base name of an
# import: the name without its leading underscores, without a variant suffix
# such as $DARWIN_EXTSN and without the kernelrpc_ and _trap of the Mach
# traps, so that ___mprotect and __kernelrpc_mach_vm_protect_trap count like
# mprotect and mach_vm_protect. mmap is allowed and checked by check_code;
# any other import with mmap in its name is not.
readonly FORBIDDEN_IMPORTS=(
  # Protection of memory, and mappings that can be executable
  mprotect '(mach_)?vm_protect' '(mach_)?vm_map(_64)?' '(mach_)?vm_remap(_new)?'
  'mach_make_memory_entry(_64)?'
  # Write protection of JIT memory and the caches for generated code
  'pthread_jit_[A-Za-z0-9_]+' 'be_memory_inline_jit_[A-Za-z0-9_]+'
  sys_icache_invalidate sys_dcache_flush sys_cache_control clear_cache
  # Loading code
  dlopen dlopen_preflight dlopen_from dlopen_audited dlsym 'NSCreateObjectFileImageFrom(Memory|File)' NSLinkModule NSAddImage
  # Starting programs, and system calls by number
  'exec(l|le|lp|v|ve|vp|vP)' mac_execve fexecve 'posix_spawnp?' fork vfork forkpty system popen syscall
  # The debugged state of a process, which lifts the enforcement of code
  # signing and with it the ban on generated code
  ptrace 'csops(_audittoken)?'
)

# Names that a JIT leaves in symbols or strings: melonDS's ARMJIT and its
# JitBlock, Arm64Gen, the ARM64 code emitter from Dolphin that melonDS and
# PPSSPP use, the mmap flag MAP_JIT and the JIT interfaces of Darwin and
# BrowserEngineKit. Case matters: melonDS has symbols such as WriteVRAM_AOBJ.
readonly JIT_TRACES=(ARMJIT Arm64Gen JitBlock MAP_JIT jit_write_protect pthread_jit be_memory_inline_jit)

# Common CMake flags for a cross build to one SDK. Package lookups stay inside
# the SDK so that Homebrew's macOS libraries never end up in an iOS binary.
# Only the libretro API is exported, so cores never clash with each other.
set_ios_cmake_args() {
  local sdk="$1" sdk_path
  sdk_path="$(xcrun --sdk "$sdk" --show-sdk-path)"
  # shellcheck disable=SC2034 # used by the recipes
  IOS_CMAKE_ARGS=(
    -G Ninja
    -DCMAKE_SYSTEM_NAME=iOS
    -DCMAKE_OSX_SYSROOT="$sdk_path"
    -DCMAKE_OSX_ARCHITECTURES=arm64
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET"
    -DCMAKE_BUILD_TYPE="$build_type"
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5
    "-DCMAKE_SHARED_LINKER_FLAGS=-Wl,-exported_symbols_list,$exports_file"
    -DCMAKE_FIND_ROOT_PATH="$sdk_path"
    -DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER
    -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY
    -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY
    -DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=ONLY
    "-DCMAKE_IGNORE_PREFIX_PATH=/opt/homebrew;/usr/local"
  )
}

# Fails unless the binary exports exactly the libretro API.
check_exports() {
  local binary="$1" exported
  exported="$(nm -gU "$binary" | awk '{ print $3 }' | sort)" || {
    echo "error: nm cannot read the exports of $binary" >&2
    exit 70
  }
  if [[ "$exported" != "$(printf '_%s\n' "${LIBRETRO_EXPORTS[@]}" | sort)" ]]; then
    echo "error: $CORE_NAME must export exactly the ${#LIBRETRO_EXPORTS[@]} libretro functions, it exports:" >&2
    echo "$exported" >&2
    exit 70
  fi
  echo "    exports: exactly the ${#LIBRETRO_EXPORTS[@]} functions of the libretro API"
}

# Fails if the binary imports a function whose base name is in
# FORBIDDEN_IMPORTS, or a variant of mmap. It reads the imports twice, from
# the symbol table (nm -u) and from the binds of dyld (dyld_info -imports),
# because a stripped symbol table can lack an import that dyld binds; both
# lists must be nonempty.
check_imports() {
  local forbidden
  forbidden="$(IFS='|'; echo "${FORBIDDEN_IMPORTS[*]}")"
  perl - "$1" "$forbidden" "${#FORBIDDEN_IMPORTS[@]}" << 'PERL' || exit 70
use strict;
use warnings;

my ($binary, $forbidden, $rules) = @ARGV;

sub run {
  my @command = @_;
  open(my $output, '-|', @command) or die "error: $command[0]: $!\n";
  my @lines = <$output>;
  close($output) or die "error: @command failed for $binary\n";
  chomp @lines;
  return @lines;
}

my @symbols = run('nm', '-u', $binary);
my @bound = map { /^\s+0x[0-9A-Fa-f]+\s+(\S+)/ ? $1 : () } run('xcrun', 'dyld_info', '-imports', $binary);
die "error: nm -u finds no imports in $binary; a core always imports from libSystem\n" unless @symbols;
die "error: dyld_info -imports finds no imports in $binary; a core always imports from libSystem\n" unless @bound;
my %import = map { $_ => 1 } @symbols, @bound;
my @found = grep {
  (my $name = $_) =~ s/^_+//;
  $name =~ s/\$.*$//;
  $name =~ s/^kernelrpc_(.*?)(?:_trap)?$/$1/;
  $name =~ /^(?:$forbidden)$/ || ($name =~ /mmap/ && $_ ne '_mmap');
} sort keys %import;
if (@found) {
  print STDERR "error: $binary imports functions that can make memory executable, load code, start a program or relax code signing:\n";
  print STDERR "    $_\n" for @found;
  exit 1;
}
printf "    imports: %d %s (nm -u and dyld_info -imports), none of %d names and patterns that can make memory executable, load code, start a program or relax code signing\n",
  scalar(keys %import), keys %import == 1 ? 'symbol' : 'symbols', $rules + 1;
PERL
}

# Reads the code of the binary and checks its system calls and its calls of
# mmap.
#
# It fails on a system call past libSystem (svc, hvc, smc) and on a word in
# __TEXT,__text that the disassembler cannot decode with every extension of
# the instruction set switched on, so that no write to a register goes
# unseen.
#
# It fails unless every call of mmap is a bl whose basic block sets prot
# (w2) and flags (w3) to constants, or to a choice between constants such as
# cinc or csel, with neither PROT_EXEC (0x4) in prot nor MAP_JIT (0x800) in
# flags. A basic block begins at the function's start, after a jump or call
# and at every target of a direct jump; the targets include those of the
# jump tables of the functions that call mmap. A block that only a call of
# mmap right before it leads into also takes over the constants in x19 to
# x28 from the block of that call: mmap returns there and keeps these
# registers (AAPCS64), and the compiler may hold a constant in one of them
# across the call.
#
# It fails as well on a tail call of mmap, on code that takes its address or
# that of its stub (adr, adrp with add or with a load, a literal load), on
# data that holds either, on any other indirect jump in a function that
# calls mmap, on a direct jump that leaves __TEXT,__text and the stubs, on a
# section with code besides them and on a value of prot or flags it cannot
# work out. It fails if the disassembly does not cover __TEXT,__text, if a
# jump into a stub lacks the name otool gives the stub, and if the binary
# imports mmap but the check finds no call, so that it never silently checks
# nothing.
#
# All this holds for code that the compiler generates. The check does not
# follow the address of mmap's pointer through a copy to another register or
# through an offset, it does not see a pointer that data holds relative to
# the GOT, and it does not see an indirect jump from another function into
# the middle of a block. Hand-written assembly that takes such a detour
# passes; its source needs a review.
check_code() {
  perl - "$1" << 'PERL' || exit 70
use strict;
use warnings;
no warnings 'portable';

my ($binary) = @ARGV;
my ($prot_exec, $map_jit) = (0x4, 0x800);
my $unreadable = 'is no jump table this check can read';

sub run {
  my @command = @_;
  open(my $output, '-|', @command) or die "error: $command[0]: $!\n";
  my @lines = <$output>;
  close($output) or die "error: @command failed for $binary\n";
  chomp @lines;
  return @lines;
}

sub number {
  my ($text) = @_;
  my $negative = $text =~ s/^-//;
  my $value = $text =~ /^0x/ ? hex($text) : $text;
  return $negative ? -$value : $value;
}

sub hex_list { join(' or ', map { sprintf('0x%x', $_) } @{ $_[0] }) }

sub count { my ($n, $one, $many) = @_; return "$n " . ($n == 1 ? $one : $many) }

# Segments and sections. Code may only be in __TEXT,__text and in stubs.
my (@segments, @sections, $command);
for (run('otool', '-l', $binary)) {
  if (/^Load command/) { undef $command; next }
  if (/^\s+cmd LC_SEGMENT_64$/) { push @segments, $command = {}; next }
  if (/^Section$/) { push @sections, $command = {}; next }
  next unless $command;
  if (/^\s+(segname|sectname) (\S+)$/) { $command->{$1} = $2 }
  elsif (/^\s+(vmaddr|vmsize|addr|size|flags|maxprot|initprot) (0x[0-9a-f]+)$/) { $command->{$1} = hex($2) }
  elsif (/^\s+(fileoff|filesize|offset|reserved2) (\d+)/) { $command->{$1} = $2 }
}
my ($text) = grep { $_->{segname} eq '__TEXT' && $_->{sectname} eq '__text' } @sections;
die "error: $binary has no section __TEXT,__text\n" unless $text && $text->{size};
for my $segment (@segments) {
  die "error: otool -l gives no initprot or maxprot for $segment->{segname} of $binary\n" unless defined $segment->{initprot} && defined $segment->{maxprot};
  die "error: $binary has an executable segment $segment->{segname}; only __TEXT may hold code\n"
    if ($segment->{initprot} | $segment->{maxprot}) & 0x4 && $segment->{segname} ne '__TEXT';
}
my (%section, @stub_sections);
for my $section (@sections) {
  $section{"$section->{segname},$section->{sectname}"} = $section;
  next unless $section->{flags} & 0x80000400 && $section != $text;
  die "error: $binary has code in $section->{segname},$section->{sectname}, which this check does not read\n"
    unless ($section->{flags} & 0xFF) == 0x8;
  push @stub_sections, $section;
}

# Stubs and pointers of the imports (indirect symbol table).
my (%stub, %mmap_stub, %mmap_pointer, $indirect);
for (run('otool', '-Iv', $binary)) {
  if (/^Indirect symbols for \((\w+),(\w+)\)/) {
    $indirect = $section{"$1,$2"} or die "error: otool -l does not list the section $1,$2 of $binary\n";
    next;
  }
  next unless $indirect && /^0x([0-9a-f]+)\s+\S+\s+(\S+)$/;
  my ($address, $name) = (hex($1), $2);
  if (($indirect->{flags} & 0xFF) == 0x8) {
    $stub{$address} = $name;
    $mmap_stub{$address} = 1 if $name eq '_mmap';
  } elsif ($name eq '_mmap') {
    $mmap_pointer{$address} = 1;
  }
}
# The import whose stub holds $address, if any.
my $stub_at = sub {
  my ($address) = @_;
  for my $section (@stub_sections) {
    next unless $address >= $section->{addr} && $address < $section->{addr} + $section->{size};
    return $stub{ $address - ($address - $section->{addr}) % $section->{reserved2} } // '?';
  }
  return undef;
};
my $is_mmap = sub {
  my ($address) = @_;
  return (grep { $address >= $_ && $address < $_ + 8 } keys %mmap_pointer) || ($stub_at->($address) // '') eq '_mmap';
};

# Both lists of imports, because a stripped symbol table can lack one.
my %import = map { $_ => 1 } run('nm', '-u', $binary),
  map { /^\s+0x[0-9A-Fa-f]+\s+(\S+)/ ? $1 : () } run('xcrun', 'dyld_info', '-imports', $binary);
my $imported = $import{_mmap};

# Data must hold neither the address of mmap nor that of its stub.
my $mmap_binds = 0;
for (run('xcrun', 'dyld_info', '-fixups', $binary)) {
  next unless /^\s+(\S+)\s+(\S+)\s+0x([0-9A-Fa-f]+)\s+(\S+)\s+(\S.*?)\s*$/;
  my ($address, $kind, $target) = (hex($3), $4, $5);
  my $where = sprintf('0x%x in %s,%s', $address, $1, $2);
  if ($kind =~ /bind/ && $target =~ m{^(?:\S+/)?_mmap(?:\s+\+\s+0x[0-9A-Fa-f]+)?(?:\s+\[weak-import\])?$}) {
    die "error: $binary stores the address of mmap at $where; only calls with bl can be checked\n" unless $mmap_pointer{$address};
    $mmap_binds++;
  } elsif ($kind eq 'rebase' && $target =~ /^0x([0-9A-Fa-f]+)$/ && ($stub_at->(hex($1) & 0x00FFFFFFFFFFFFFF) // '') eq '_mmap') {
    die "error: $binary stores the address of the stub of mmap at $where; only calls with bl can be checked\n";
  }
}
die "error: $binary has a stub or a pointer for mmap, but neither nm -u nor dyld_info -imports lists it\n"
  if !$imported && (%mmap_stub || %mmap_pointer || $mmap_binds);

# Functions (LC_FUNCTION_STARTS).
my @starts = sort { $a <=> $b } map { /^\s+0x([0-9A-Fa-f]+)\b/ ? hex($1) : () } run('xcrun', 'dyld_info', '-function_starts', $binary);
die "error: dyld_info finds no function starts in $binary\n" unless @starts;
die "error: the first function of $binary does not start at __TEXT,__text\n" unless $starts[0] == $text->{addr};

# The disassembly of __TEXT,__text, which must cover the section without a
# gap. Without --mattr=+all the disassembler prints the instructions of the
# newer extensions (LSE, RCpc, CRC and others) as .long, and a write to a
# register in one of them would go unseen; a word it still cannot decode
# stops the check, and so does a system call.
my (@instructions, %index, %label, @pending, $started);
for (run('xcrun', 'llvm-objdump', '--macho', '--disassemble', '--no-show-raw-insn', '--mattr=+all', $binary)) {
  if (/^\(__TEXT,__text\) section$/) { $started = 1; next }
  next unless $started && /\S/;
  if (/^(\S.*):$/) { push @pending, $1; next }
  die "error: unexpected line in the disassembly of $binary: $_\n" unless /^\s*([0-9a-f]+):\t(\S+)(?:\t(.*?))?\s*$/;
  my ($address, $mnemonic, $operands) = (hex($1), $2, $3 // '');
  my $comment = $operands =~ s/\s*;\s*(.*)$// ? $1 : '';
  die sprintf("error: the disassembler cannot decode the word at 0x%x in %s (%s %s)\n", $address, $binary, $mnemonic, $operands) if $mnemonic =~ /^(?:\.|<)/;
  die sprintf("error: system call at 0x%x in %s (%s %s); a core must call the system through libSystem\n", $address, $binary, $mnemonic, $operands) if $mnemonic =~ /^(?:svc|hvc|smc)$/;
  $label{$_} = $address for splice(@pending);
  push @instructions, { address => $address, mnemonic => $mnemonic, operands => $operands, comment => $comment };
  $index{$address} = $#instructions;
}
die sprintf("error: the disassembly of %s does not cover __TEXT,__text: %d instructions for %d bytes\n", $binary, scalar(@instructions), $text->{size})
  unless @instructions && @instructions * 4 == $text->{size} && $instructions[0]{address} == $text->{addr}
  && $instructions[-1]{address} == $text->{addr} + $text->{size} - 4;
for my $i (1 .. $#instructions) {
  die sprintf("error: the disassembly of %s skips the address before 0x%x\n", $binary, $instructions[$i]{address})
    if $instructions[$i]{address} != $instructions[$i - 1]{address} + 4;
}
die "error: a function of $binary starts outside __TEXT,__text or between two instructions\n" if grep { !exists $index{$_} } @starts;
my (@function_of, @first, @last);
for my $function (0 .. $#starts) {
  $first[$function] = $index{ $starts[$function] };
  $last[$function] = $function < $#starts ? $index{ $starts[$function + 1] } - 1 : $#instructions;
  $function_of[$_] = $function for $first[$function] .. $last[$function];
}

# Direct jumps and calls: their targets begin basic blocks and must lie in
# __TEXT,__text or in a stub. A jump into a stub must carry the name that
# otool gives the stub. cb\w+ covers cbz, cbnz and the compare-and-branch
# instructions of Armv9.6 (cbgt, cbbeq, cbhne and so on). Any other
# instruction that ends in an address the way a jump does stops the check,
# except the literal loads.
my $jump = qr/^(?:b|bl|b\.\w+|bc\.\w+|cb\w+|tbz|tbnz)$/;
my $block_end = qr/^(?:b|bl|br|blr|ret|cb\w+|tbz|tbnz|b\.\w+|bc\.\w+|bra(?:a|b|az|bz)|blra(?:a|b|az|bz)|reta[ab](?:sppcr?)?|eret|eretaa|eretab|svc|hvc|smc|brk|hlt|udf|dcps[123])$/;
my (%target, $stub_jumps);
for my $instruction (@instructions) {
  unless ($instruction->{mnemonic} =~ $jump) {
    die sprintf("error: this check does not know the instruction at 0x%x in %s (%s %s), which names an address like a jump\n",
      $instruction->{address}, $binary, $instruction->{mnemonic}, $instruction->{operands})
      if $instruction->{operands} =~ /(?:^|,\s*)0x[0-9a-f]+$/ && $instruction->{mnemonic} !~ /^(?:ldr|ldrsw|prfm)$/;
    next;
  }
  my ($destination) = $instruction->{operands} =~ /(?:^|,\s*)(\S+)$/;
  my $target = $destination =~ /^0x([0-9a-f]+)$/ ? hex($1) : $label{$destination};
  die sprintf("error: cannot resolve the jump to %s at 0x%x in %s\n", $destination, $instruction->{address}, $binary) unless defined $target;
  die sprintf("error: the jump at 0x%x in %s leads to 0x%x, outside __TEXT,__text and the stubs\n", $instruction->{address}, $binary, $target)
    unless exists $index{$target} || defined $stub_at->($target);
  $instruction->{target} = $target;
  $target{$target} = 1;
  my $name = $stub_at->($target) // next;
  die sprintf("error: the disassembler names the jump at 0x%x into the stub of %s \"%s\" in %s\n", $instruction->{address}, $name, $instruction->{comment}, $binary)
    unless $instruction->{comment} eq "symbol stub for: $name";
  $stub_jumps++;
}

# Every instruction that refers to mmap: a jump into its stub, the address
# of its stub or pointer computed with adr, with adrp and add or with adrp
# and a load, a literal load of either (the disassembler prints its address
# for a w register and its offset for an x register), or a mention of _mmap
# by the disassembler. An adrp counts until the next write to its register;
# a copy of the register or an add or sub of a page is not followed.
my (@references, %page);
for my $i (0 .. $#instructions) {
  my $instruction = $instructions[$i];
  my ($mnemonic, $operands) = @$instruction{qw(mnemonic operands)};
  %page = () if $first[ $function_of[$i] ] == $i;
  my @addresses = grep { defined } $instruction->{target};
  if ($mnemonic eq 'adr' && $operands =~ /^x\d+, #(-?(?:0x[0-9a-f]+|\d+))$/) {
    push @addresses, $instruction->{address} + number($1);
  } elsif ($mnemonic eq 'add' && $operands =~ /^x\d+, x(\d+), #(0x[0-9a-f]+|\d+)$/ && defined $page{$1}) {
    push @addresses, $page{$1} + number($2);
  } elsif ($operands =~ /\[x(\d+)(?:, #(-?(?:0x[0-9a-f]+|\d+)))?\]/ && defined $page{$1}) {
    push @addresses, $page{$1} + number($2 // 0);
  } elsif ($mnemonic =~ /^ldr/ && $operands =~ /^[wx]\d+, 0x([0-9a-f]+)$/) {
    push @addresses, hex($1);
  } elsif ($mnemonic =~ /^ldr/ && $operands =~ /^[wx]\d+, #(-?(?:0x[0-9a-f]+|\d+))$/) {
    push @addresses, $instruction->{address} + number($1);
  }
  my ($written) = $mnemonic =~ /^(?:st|cmp|cmn|tst|ccmp|ccmn|prfm)/ ? () : $operands =~ /^[wx](\d+)\b/;
  delete $page{$written} if defined $written;
  if ($mnemonic eq 'adrp' && defined $written && $instruction->{comment} =~ /^0x([0-9a-f]+)$/) {
    $page{$written} = hex($1);
  }
  push @references, $i if (grep { $is_mmap->($_) } @addresses) || $instruction->{comment} =~ /(?:^|\s)_mmap$/;
}
my @calls;
for my $i (@references) {
  my $instruction = $instructions[$i];
  my $where = sprintf('at 0x%x in %s', $instruction->{address}, $binary);
  die "error: tail call of mmap $where; only calls with bl can be checked\n"
    if $instruction->{mnemonic} =~ $jump && $instruction->{mnemonic} ne 'bl' && $is_mmap->($instruction->{target});
  die "error: code takes the address of mmap $where ($instruction->{mnemonic} $instruction->{operands}); only calls with bl can be checked\n"
    unless $instruction->{mnemonic} eq 'bl' && $mmap_stub{ $instruction->{target} };
  push @calls, $i;
}
die "error: $binary imports mmap, but the check found no call of it\n" if $imported && !@calls;
die "error: $binary calls mmap, but dyld binds no pointer to it\n" if @calls && !$mmap_binds;

# The jump tables of the functions that call mmap, whose targets begin basic
# blocks as well: the compact tables of LLVM, adrp and add for the table, adr
# for the base, ldrb or ldrh of the entry and add with lsl #2 before br,
# bounded by cmp of the index and b.hi or b.hs. Any other indirect jump in
# such a function stops the check, because its targets are unknown.
my (%table_read, $tables);
my $read_bytes = sub {
  my ($address, $length) = @_;
  my ($segment) = grep { $address >= $_->{vmaddr} && $address + $length <= $_->{vmaddr} + $_->{filesize} } @segments;
  die sprintf("error: 0x%x in %s lies in no part of a segment that the file holds\n", $address, $binary) unless $segment;
  open(my $in, '<:raw', $binary) or die "error: $binary: $!\n";
  seek($in, $segment->{fileoff} + $address - $segment->{vmaddr}, 0) or die "error: $binary: $!\n";
  read($in, my $bytes, $length) == $length or die "error: $binary ends inside a jump table\n";
  close($in);
  return $bytes;
};
my $read_jump_table = sub {
  my ($jump_index, $first, $last) = @_;
  my $where = sprintf('the indirect jump at 0x%x in %s, a function that calls mmap,', $instructions[$jump_index]{address}, $binary);
  # The instruction that last wrote register $number before $from, in the same basic block.
  my $writer = sub {
    my ($number, $from) = @_;
    for (my $i = $from - 1; $i >= $first; $i--) {
      last if $instructions[$i]{mnemonic} =~ $block_end;
      return $i if $instructions[$i]{operands} =~ /^[wx]$number\b/;
      last if $target{ $instructions[$i]{address} };
    }
    die "error: $where $unreadable\n";
  };
  my $match = sub {
    my ($i, $mnemonic, $pattern) = @_;
    my @captures = $instructions[$i]{mnemonic} =~ $mnemonic ? $instructions[$i]{operands} =~ $pattern : ();
    die "error: $where $unreadable\n" unless @captures;
    return @captures;
  };
  my ($base_register) = $match->($jump_index, qr/^br$/, qr/^x(\d+)$/);
  my $add = $writer->($base_register, $jump_index);
  my ($entry_register) = $match->($add, qr/^add$/, qr/^x$base_register, x$base_register, [wx](\d+), (?:lsl|uxt[bhw]) #2$/);
  my $load = $writer->($entry_register, $add);
  my ($table_register, $index_register, $shift) =
    $match->($load, qr/^ldr[bh]$/, qr/^w$entry_register, \[x(\d+), [wx](\d+)(?:, (?:lsl|uxtw) #(\d))?\]$/);
  my $size = $instructions[$load]{mnemonic} eq 'ldrb' ? 1 : 2;
  die "error: $where $unreadable\n" unless ($shift // 0) == $size - 1;
  my $adr = $writer->($base_register, $add);
  my ($offset) = $match->($adr, qr/^adr$/, qr/^x$base_register, #(-?(?:0x[0-9a-f]+|\d+))$/);
  my $low = $writer->($table_register, $load);
  my ($low_offset) = $match->($low, qr/^add$/, qr/^x$table_register, x$table_register, #(0x[0-9a-f]+|\d+)$/);
  my $page = $writer->($table_register, $low);
  $match->($page, qr/^adrp$/, qr/^x$table_register, /);
  my ($page_address) = $instructions[$page]{comment} =~ /^0x([0-9a-f]+)$/ or die "error: $where $unreadable\n";
  my $table = hex($page_address) + number($low_offset);
  my $base = $instructions[$adr]{address} + number($offset);
  # The bound: cmp of the index with a constant right before b.hi or b.hs,
  # with neither a write to the index nor another way in up to the load.
  my $entries;
  for (my $i = $load; $i - 2 >= $first; $i--) {
    last if $target{ $instructions[$i]{address} };
    my ($mnemonic, $operands) = @{ $instructions[$i - 1] }{qw(mnemonic operands)};
    if ($mnemonic =~ /^b\.(?:hi|hs)$/ && $instructions[$i - 2]{mnemonic} eq 'cmp'
      && $instructions[$i - 2]{operands} =~ /^[wx]$index_register, #(0x[0-9a-f]+|\d+)$/) {
      $entries = number($1) + ($mnemonic eq 'b.hi' ? 1 : 0);
      last;
    }
    # LLVM widens an int index with mov w<index>, w<n> after the bound.
    if ($mnemonic eq 'mov' && $operands =~ /^w$index_register, w(\d+)$/) { $index_register = $1; next }
    last if $mnemonic =~ $block_end || $operands =~ /^[wx]$index_register\b/;
  }
  die "error: $where has no bound this check can read\n" unless $entries && $entries <= 4096;
  for my $entry (unpack($size == 1 ? 'C*' : 'v*', $read_bytes->($table, $entries * $size))) {
    my $target = $base + 4 * $entry;
    die sprintf("error: %s jumps to 0x%x outside its function\n", $where, $target)
      unless exists $index{$target} && $index{$target} >= $first && $index{$target} <= $last;
    $target{$target} = 1;
  }
  $table_read{$jump_index} = 1;
  $tables++;
};
for my $i (@calls) {
  my $function = $function_of[$i];
  for my $j ($first[$function] .. $last[$function]) {
    next if $table_read{$j};
    die sprintf("error: the indirect jump at 0x%x in %s, a function that calls mmap, %s\n", $instructions[$j]{address}, $binary, $unreadable)
      if $instructions[$j]{mnemonic} =~ /^bra(?:a|b|az|bz)$/;
    $read_jump_table->($j, $first[$function], $last[$function]) if $instructions[$j]{mnemonic} eq 'br';
  }
}

# The possible values of the registers along a basic block. A write that is
# no constant or choice between constants makes a register unknown, and so
# does every other instruction that names it.
my %known;
# Only the low 32 bits of w2 and w3 count, and the low 32 bits of every result
# modelled here depend only on the low 32 bits of its inputs.
my $mask = sub { 0xFFFFFFFF };
my $read = sub {
  my ($register) = @_;
  return [0] if $register =~ /^[wx]zr$/;
  return undef unless $register =~ /^([wx])(\d+)$/ && $known{$2};
  my $width = $1;
  my %values = map { ($_ & $mask->($width)) => 1 } @{ $known{$2} };
  return [ sort { $a <=> $b } keys %values ];
};
my $write = sub {
  my ($register, $values) = @_;
  return unless $register =~ /^([wx])(\d+)$/;
  my ($width, $number) = ($1, $2);
  my %set = map { ($_ & $mask->($width)) => 1 } @{ $values // [] };
  if (%set && keys %set <= 16) {
    $known{$number} = [ sort { $a <=> $b } keys %set ];
  } else {
    delete $known{$number};
  }
};
my $immediate = qr/^#(-?(?:0x[0-9a-f]+|\d+))$/;
my $gpr = qr/^[wx](?:\d+|zr)$/;
my $apply = sub {
  my ($kind, $value) = @_;
  return $kind eq 'inc' ? $value + 1 : $kind eq 'inv' ? ~$value : $kind eq 'neg' ? -$value : $value;
};
my $step = sub {
  my ($mnemonic, $operands) = @_;
  my @operand = split /,\s*/, $operands;
  my ($shift) = @operand == 3 && $operand[2] =~ /^lsl #(\d+)$/ ? ($1) : (0);
  my ($value) = @operand > 1 && $operand[1] =~ $immediate ? (number($1)) : ();
  my ($value2) = @operand > 2 && $operand[2] =~ $immediate ? (number($1)) : ();
  my ($logic) = $mnemonic =~ /^(orr|and|eor)$/;
  my ($arithmetic) = $mnemonic =~ /^(add|sub)$/;
  my ($set) = $mnemonic =~ /^cset(m?)$/;
  my ($choice) = $mnemonic =~ /^c(inc|inv|neg)$/;
  my ($select) = $mnemonic =~ /^cs(el|inc|inv|neg)$/;
  if ($mnemonic =~ /1716|^ld64b$|^xpaclri$/) {
    %known = ();
  } elsif ($mnemonic eq 'mov' && @operand == 2 && defined $value) {
    $write->($operand[0], [$value]);
  } elsif ($mnemonic eq 'mov' && @operand == 2 && $operand[1] =~ $gpr) {
    $write->($operand[0], $read->($operand[1]));
  } elsif ($mnemonic =~ /^mov[zn]$/ && defined $value && (@operand == 2 || $shift)) {
    $write->($operand[0], [$mnemonic eq 'movn' ? ~($value << $shift) : $value << $shift]);
  } elsif ($mnemonic eq 'movk' && defined $value && (@operand == 2 || $shift)) {
    my $old = $read->($operand[0]);
    $write->($operand[0], $old && [ map { $_ & ~(0xFFFF << $shift) | $value << $shift } @$old ]);
  } elsif ($logic && @operand == 3 && $operand[1] =~ $gpr && defined $value2) {
    my $old = $read->($operand[1]);
    $write->($operand[0], $old && [ map { $logic eq 'orr' ? $_ | $value2 : $logic eq 'and' ? $_ & $value2 : $_ ^ $value2 } @$old ]);
  } elsif ($arithmetic && $operand[1] =~ /^[wx]\d+$/ && defined $value2 && (@operand == 3 || $operand[3] =~ /^lsl #(0|12)$/)) {
    my ($old, $amount) = ($read->($operand[1]), $value2 << (@operand == 4 ? ($operand[3] =~ /(\d+)$/)[0] : 0));
    $write->($operand[0], $old && [ map { $arithmetic eq 'add' ? $_ + $amount : $_ - $amount } @$old ]);
  } elsif (defined $set && @operand == 2) {
    $write->($operand[0], [0, $set ? ~0 : 1]);
  } elsif ($choice && @operand == 3 && $operand[1] =~ $gpr) {
    my $old = $read->($operand[1]);
    $write->($operand[0], $old && [ @$old, map { $apply->($choice, $_) } @$old ]);
  } elsif ($select && @operand == 4 && $operand[1] =~ $gpr && $operand[2] =~ $gpr) {
    my ($true, $false) = ($read->($operand[1]), $read->($operand[2]));
    $write->($operand[0], $true && $false && [ @$true, map { $apply->($select, $_) } @$false ]);
  } else {
    $write->($_, undef) for $operands =~ /\b([wx]\d+)\b/g;
  }
};

# The values before instruction $i: those its basic block sets and, when
# only a call of mmap right before the block leads into it, the registers
# x19 to x28 as the block of that call leaves them, up to 8 blocks back.
# mmap keeps these registers (AAPCS64) and returns to the instruction after
# its bl. Other calls do not count: the compiler may place a landing pad
# after a call that never returns, and a landing pad gets x19 to x28 from
# the call that threw.
my $state;
$state = sub {
  my ($i, $depth) = @_;
  my $block = $i;
  unless ($target{ $instructions[$i]{address} }) {
    for (my $j = $i - 1; $j >= $first[ $function_of[$i] ]; $j--) {
      last if $instructions[$j]{mnemonic} =~ $block_end;
      $block = $j;
      last if $target{ $instructions[$j]{address} };
    }
  }
  %known = ();
  if ($depth < 8 && $block > $first[ $function_of[$block] ] && !$target{ $instructions[$block]{address} }
    && $instructions[$block - 1]{mnemonic} eq 'bl' && $mmap_stub{ $instructions[$block - 1]{target} }) {
    $state->($block - 1, $depth + 1);
    %known = map { ($_ => $known{$_}) } grep { $_ >= 19 && $_ <= 28 } keys %known;
  }
  $step->(@{ $instructions[$_] }{qw(mnemonic operands)}) for $block .. $i - 1;
};

# Each call: prot (w2) and flags (w3) as these values set them.
my %combinations;
for my $i (@calls) {
  my $where = sprintf('at 0x%x in %s', $instructions[$i]{address}, $binary);
  $state->($i, 0);
  my ($prot, $flags) = ($read->('w2'), $read->('w3'));
  die "error: the call of mmap $where does not set prot (w2) to a constant in its basic block\n" unless $prot;
  die "error: the call of mmap $where does not set flags (w3) to a constant in its basic block\n" unless $flags;
  die sprintf("error: the call of mmap %s can map executable memory: prot %s\n", $where, hex_list($prot)) if grep { $_ & $prot_exec } @$prot;
  die sprintf("error: the call of mmap %s can map memory for JIT: flags %s\n", $where, hex_list($flags)) if grep { $_ & $map_jit } @$flags;
  $combinations{ sprintf('prot %s flags %s', hex_list($prot), hex_list($flags)) }++;
}
printf "    mmap: %s (%s, %s, %s, %s)\n",
  $imported
  ? sprintf('%s with bl, prot and flags constant in the basic block (x19 to x28 also from the block of a call of mmap right before it), none with PROT_EXEC or MAP_JIT: %s; no other reference found',
    count(scalar(@calls), 'call', 'calls'),
    join(', ', map { "${\ $combinations{$_}}x $_" } sort { $combinations{$b} <=> $combinations{$a} || $a cmp $b } keys %combinations))
  : 'not imported',
  count(scalar(@instructions), 'instruction', 'instructions'), count(scalar(@starts), 'function', 'functions'),
  count($stub_jumps // 0, 'jump into stubs', 'jumps into stubs'), count($tables // 0, 'jump table', 'jump tables');
printf "    system calls: no svc, hvc or smc among the %s of __TEXT,__text, all decoded\n", count(scalar(@instructions), 'instruction', 'instructions');
PERL
}

# Fails if a symbol (nm -a) or a string in the sections (strings -a) of the
# binary contains a name of JIT_TRACES. It fails as well unless nm -a lists
# the 25 exports and at least one local symbol and strings -a finds at least
# one string, so that a stripped binary or a broken tool does not pass
# unchecked.
check_jit_traces() {
  perl - "$1" "${#JIT_TRACES[@]}" "${JIT_TRACES[@]}" "${LIBRETRO_EXPORTS[@]}" << 'PERL' || exit 70
use strict;
use warnings;

my ($binary, $count, @rest) = @ARGV;
my @traces = splice(@rest, 0, $count);
my @exports = @rest;

sub run {
  my @command = @_;
  open(my $output, '-|', @command) or die "error: $command[0]: $!\n";
  my @lines = <$output>;
  close($output) or die "error: @command failed for $binary\n";
  chomp @lines;
  return @lines;
}

my @symbols = run('nm', '-a', $binary);
my @strings = run('strings', '-a', $binary);
my %symbol = map { /\s(\S+)$/ ? ($1 => 1) : () } @symbols;
my @missing = grep { !$symbol{"_$_"} } @exports;
die "error: nm -a does not list the exports @missing of $binary\n" if @missing;
die "error: $binary has no local symbols; a stripped binary hides the names this check looks for\n"
  unless grep { /^[0-9a-f]+ [a-z] / } @symbols;
die "error: strings -a finds no string in $binary\n" unless @strings;
my @found;
for my $trace (@traces) {
  push @found, map { "symbol: $_" } grep { index($_, $trace) >= 0 } @symbols;
  push @found, map { "string: $_" } grep { index($_, $trace) >= 0 } @strings;
}
if (@found) {
  print STDERR "error: $binary carries traces of a JIT:\n";
  print STDERR "    $_\n" for @found;
  exit 1;
}
printf "    no JIT traces: %d symbols (nm -a) and %d strings (strings -a) without %s\n",
  scalar(@symbols), scalar(@strings), join(', ', @traces[0 .. $#traces - 1]) . " or $traces[-1]";
PERL
}

# Runs every check on one built slice, then the recipe's core_check.
check_core() {
  local binary="$1" architectures
  architectures="$(lipo -archs "$binary" 2>&1)" || {
    echo "error: lipo cannot read $binary: $architectures" >&2
    exit 70
  }
  if [[ "$architectures" != arm64 ]]; then
    echo "error: $binary must be a thin arm64 binary, it has: $architectures" >&2
    exit 70
  fi
  check_exports "$binary"
  check_imports "$binary"
  check_code "$binary"
  check_jit_traces "$binary"
  if declare -F core_check > /dev/null; then
    core_check "$binary"
  fi
}

if [[ "$check_only" == 1 ]]; then
  if [[ ${#check_binaries[@]} -eq 0 ]]; then
    # The slices of SDKS, in the same order, and no others.
    slices=("$OUTPUT_DIR/$CORE_NAME.xcframework"/*/"$CORE_NAME.framework/$CORE_NAME")
    for slice in ios-arm64 ios-arm64-simulator; do
      check_binaries+=("$OUTPUT_DIR/$CORE_NAME.xcframework/$slice/$CORE_NAME.framework/$CORE_NAME")
    done
    if [[ ${#slices[@]} -ne ${#check_binaries[@]} || ! -f "${check_binaries[0]}" || ! -f "${check_binaries[1]}" ]]; then
      echo "error: Cores/Build/$CORE_NAME.xcframework must hold exactly the slices ios-arm64 and ios-arm64-simulator, run Scripts/bootstrap.sh" >&2
      exit 66
    fi
  fi
  for binary in "${check_binaries[@]}"; do
    if [[ ! -f "$binary" ]]; then
      echo "error: no file at $binary" >&2
      exit 66
    fi
    echo "==> Checking ${binary#"$REPO_ROOT"/}"
    check_core "$binary"
  done
  exit 0
fi

# Version for the framework's Info.plist, taken from the submodule's tag.
core_version() {
  local tag
  tag="$(git -C "$REPO_ROOT/$CORE_SOURCE" describe --tags --abbrev=0 2> /dev/null || true)"
  tag="$(sed -E 's/^[^0-9]*//; s/[^0-9.].*$//' <<< "$tag")"
  echo "${tag:-0.0.0}"
}

# Wraps a dylib into <out_dir>/<CORE_NAME>.framework.
make_framework() {
  local sdk="$1" dylib="$2" out_dir="$3"
  local framework="$out_dir/$CORE_NAME.framework"
  local platform="iPhoneOS"
  [[ "$sdk" == "iphonesimulator" ]] && platform="iPhoneSimulator"

  rm -rf "$framework"
  mkdir -p "$framework"
  cp "$dylib" "$framework/$CORE_NAME"
  install_name_tool -id "@rpath/$CORE_NAME.framework/$CORE_NAME" "$framework/$CORE_NAME"

  cat > "$framework/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>$CORE_NAME</string>
	<key>CFBundleIdentifier</key>
	<string>com.faentiver.arcfold.core.${CORE_NAME//_/-}</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>$CORE_NAME</string>
	<key>CFBundlePackageType</key>
	<string>FMWK</string>
	<key>CFBundleShortVersionString</key>
	<string>$(core_version)</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>CFBundleSupportedPlatforms</key>
	<array>
		<string>$platform</string>
	</array>
	<key>MinimumOSVersion</key>
	<string>$DEPLOYMENT_TARGET</string>
</dict>
</plist>
PLIST

  if declare -F core_package > /dev/null; then
    core_package "$sdk" "$framework" "$(dirname "$out_dir")"
  fi

  # install_name_tool invalidates the linker's ad-hoc signature. Xcode signs
  # the framework again when it embeds it into the app.
  codesign --force --sign - --timestamp=none "$framework" > /dev/null
}

work_root="$REPO_ROOT/build/cores/$core"
if [[ "$clean" == 1 ]]; then
  rm -rf "$work_root"
fi
mkdir -p "$work_root"
exports_file="$work_root/libretro-exports.txt"
printf '_%s\n' "${LIBRETRO_EXPORTS[@]}" > "$exports_file"

frameworks=()
for sdk in "${SDKS[@]}"; do
  work_dir="$work_root/$sdk"
  mkdir -p "$work_dir"
  echo "==> Building $CORE_NAME for $sdk ($build_type)"
  set_ios_cmake_args "$sdk"
  core_build "$sdk" "$work_dir"

  dylib="$work_dir/$CORE_NAME.dylib"
  if [[ ! -f "$dylib" ]]; then
    echo "error: core_build did not produce $dylib" >&2
    exit 70
  fi
  make_framework "$sdk" "$dylib" "$work_dir/framework"
  # The checks read the binary that goes into the xcframework, the same one
  # that --check reads later.
  check_core "$work_dir/framework/$CORE_NAME.framework/$CORE_NAME"
  frameworks+=(-framework "$work_dir/framework/$CORE_NAME.framework")
done

mkdir -p "$OUTPUT_DIR"
rm -f "$OUTPUT_DIR/$CORE_NAME.stamp"
rm -rf "$OUTPUT_DIR/$CORE_NAME.xcframework"
xcodebuild -create-xcframework "${frameworks[@]}" -output "$OUTPUT_DIR/$CORE_NAME.xcframework" > /dev/null
fingerprint > "$OUTPUT_DIR/$CORE_NAME.stamp"
echo "==> Wrote Cores/Build/$CORE_NAME.xcframework"
for sdk in "${SDKS[@]}"; do
  xcrun vtool -show-build "$work_root/$sdk/framework/$CORE_NAME.framework/$CORE_NAME" |
    awk -v sdk="$sdk" '/platform/ { p = $2 } /minos/ { m = $2 } END { printf "    %-16s platform %s, minos %s\n", sdk, p, m }'
done
