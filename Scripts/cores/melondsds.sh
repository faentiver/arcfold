# SPDX-License-Identifier: GPL-3.0-or-later
#
# melonDS DS (Nintendo DS), GPL-3.0-or-later: the libretro core by Jesse
# Talavera-Greenberg on top of melonDS (ADR 0006). Built without JIT, without
# OpenGL and without dynamic loading, so no libpcap and no dlopen. Networking
# stays compiled in, because melonDS DS does not build without it; the app
# switches it off with the core option melonds_network_mode=disabled. Patched
# so that it builds without libpcap, carries no key material of the DSi and
# cannot download from Nintendo's servers (hard rules, ADR 0006).
#
# Arcfold's changes, made on 7 November 2026 (GPL-3.0, section 5 a), applied
# to copies of the sources at every build:
# - melonDS DS (core_build): src/libretro/format.cpp and
#   src/libretro/net/net.{cpp,hpp} compile the pcap formatter and two
#   adapter helpers only with HAVE_NETWORKING_DIRECT_MODE, so that the core
#   builds without libpcap; src/libretro/config/console.cpp compiles
#   DownloadTmd and CacheTmd only with ARCFOLD_ALLOW_TMD_DOWNLOAD, which
#   nothing defines, so that the DSi mode cannot download title metadata
#   from Nintendo's update server.
# - melonDS (melondsds_remove_key_material): src/DSi.cpp, src/DSi_AES.cpp
#   and src/DSi_NAND.cpp no longer hold the DSi's key material, that is the
#   AES key of boot2, the key X of modcrypt and of the key slots, the eMMC
#   keys and the key scrambler constant.
# The comments these changes add to the sources carry the same date.

CORE_NAME="melondsds_libretro"
CORE_SOURCE="Cores/melonds-ds"

# The FetchContent dependencies of melonDS DS v1.4.0
# (cmake/FetchDependencies.cmake) as submodules of this repository, at the
# commits v1.4.0 names, so that configuring needs no network. The folder name
# is the FetchContent name. melonDS comes from upstream (melonDS-emu/melonDS)
# instead of the branch jtg/fix-uninitialized-opengl of JesseTG/melonDS that
# v1.4.0 names: that branch is this commit plus one OpenGL-only change that
# upstream has merged since (1e654443e4).
MELONDSDS_DEPENDENCY_DIR="Cores/melonds-ds-deps"
MELONDSDS_DEPENDENCY_NAMES=(
  melonDS libretro-common embed-binaries glm libslirp pntr fmt yamc span-lite date zlib
)
CORE_DEPENDENCIES=()
for melondsds_name in "${MELONDSDS_DEPENDENCY_NAMES[@]}"; do
  CORE_DEPENDENCIES+=("$MELONDSDS_DEPENDENCY_DIR/$melondsds_name")
done
unset melondsds_name

# Takes the key material of the DSi out of the copy of melonDS in $1: the AES
# key of boot2, the key X of modcrypt and of the key slots, the eMMC keys and
# the key scrambler constant (hard rules: no keys in the app; ADR 0006). The
# edits find the code by its names and shape, never by the values, so that
# this repository holds none of them. Each edit must match exactly once, and
# afterwards no key may be set from constants; otherwise the build stops, and
# the edits need a look for the new melonDS. The DSi mode, which alone uses
# the keys, needs the console's own BIOS and NAND, and Arcfold always runs
# the DS mode (melonds_console_mode=ds).
melondsds_remove_key_material() {
  perl - "$1" << 'PERL' || exit 70
use strict;
use warnings;

my $root = shift;

# File, the code to replace (the named group i is its indentation) and the
# lines that replace it.
my @edits = (
  # The key X and key Y of modcrypt, derived from the game code.
  [ 'src/DSi.cpp', qr!
      ^(?<i>[ ]+)u8[ ]keyX\[16\],[ ]keyY\[16\];\n\n
      (?:\g{i}\*\(u32\*\)&keyX\[\d+\][ ]=[ ]0x\w+;\n)+
      (?:\g{i}keyX\[\d+\][ ]+=[ ]header\.GameCode\[\d\];\n)+\n
      \g{i}memcpy\(keyY,[ ]header\.DSiARM9iHash,[ ]16\);\n\n
      \g{i}DSi_AES::DeriveNormalKey\(keyX,[ ]keyY,[ ]tmp\);\n
    !xm, [
      "// Arcfold, 7 November 2026: no key material of the DSi in the app (hard",
      "// rules, ADR 0006). Arcfold runs the DS mode, which never decrypts modcrypt.",
      "memset(tmp, 0, sizeof(tmp));",
    ] ],
  # The AES key of boot2.
  [ 'src/DSi.cpp', qr!
      ^(?<i>[ ]+)const[ ]u8[ ]boot2key\[16\][ ]=[ ]\{[^}]+\};\n
    !xm, [
      "// Arcfold, 7 November 2026: no key material of the DSi in the app (hard rules, ADR 0006).",
      "const u8 boot2key[16] = {};",
    ] ],
  # The key X of slot 0 (modcrypt) and of slot 1 at reset.
  [ 'src/DSi_AES.cpp', qr!
      ^(?<i>[ ]+)//[ ]initialize[ ]keys\n
      \g{i}u64[ ]consoleid[ ]=[ ]DSi\.GetConsoleID\(\);\n\n
      \g{i}//[ ]slot[ ]0:[ ]modcrypt\n
      (?:\g{i}\*\(u32\*\)&KeyX\[0\]\[\d+\][ ]=[ ][^;\n]+;\n)+\n
      \g{i}//[ ]slot[ ]1:[ ]'Tad'/dev\.kp\n
      (?:\g{i}\*\(u32\*\)&KeyX\[1\]\[\d+\][ ]=[ ][^;\n]+;\n)+
    !xm, [
      "// Arcfold, 7 November 2026: no key material of the DSi in the app (hard rules, ADR 0006).",
      "// The key slots begin empty but for the one the console's own BIOS",
      "// fills; the DS mode Arcfold runs never uses the DSi's AES engine.",
    ] ],
  # The key X and key Y of slot 3 (eMMC) at reset.
  [ 'src/DSi_AES.cpp', qr!
      ^\n
      (?<i>[ ]+)//[ ]slot[ ]3:[ ]console-unique[ ]eMMC[ ]crypto\n
      (?:\g{i}\*\(u32\*\)&Key[XY]\[3\]\[\d+\][ ]=[ ][^;\n]+;\n)+
    !xm, [] ],
  # The key scrambler constant.
  [ 'src/DSi_AES.cpp', qr!
      ^(?<i>[ ]+)const[ ]u8[ ]key_const\[16\][ ]=[ ]\{[^}]+\};\n
    !xm, [
      "// Arcfold, 7 November 2026: the DSi's key scrambler constant stays out of",
      "// the app (hard rules, ADR 0006).",
      "const u8 key_const[16] = {};",
    ] ],
  # The eMMC key X and key Y of a NAND image.
  [ 'src/DSi_NAND.cpp', qr!
      ^(?<i>[ ]+)\*\(u32\*\)&keyX\[0\][ ]=[ ]\(u32\)ConsoleID;\n
      (?:\g{i}\*\(u32\*\)&keyX\[\d+\][ ]=[ ][^;\n]+;\n)+\n
      (?:\g{i}\*\(u32\*\)&keyY\[\d+\][ ]=[ ][^;\n]+;\n)+
    !xm, [
      "// Arcfold, 7 November 2026: no key material of the DSi in the app (hard",
      "// rules, ADR 0006); NAND images stay encrypted, and Arcfold never uses them.",
      "memset(keyX, 0, sizeof(keyX));",
      "memset(keyY, 0, sizeof(keyY));",
    ] ],
  # The key X of slot 1, for the ES key of a NAND image.
  [ 'src/DSi_NAND.cpp', qr!
      ^\n
      (?<i>[ ]+)\*\(u32\*\)&keyX\[0\][ ]=[ ]0x\w+;\n
      (?:\g{i}\*\(u32\*\)&keyX\[\d+\][ ]=[ ][^;\n]+;\n)+\n
      (?=\g{i}memcpy\(keyY,[ ]es_keyY,[ ]sizeof\(keyY\)\);\n)
    !xm, [] ],
);

my %text;
for my $edit (@edits) {
  my ($file, $code, $lines) = @$edit;
  $text{$file} //= do {
    open(my $in, '<:raw', "$root/$file") or die "error: melonDS $file: $!\n";
    local $/;
    <$in>;
  };
  my $matches = 0;
  $matches++ while $text{$file} =~ /$code/g;
  die "error: a key material edit for melonDS $file matches $matches times instead of once\n" unless $matches == 1;
  $text{$file} =~ s/$code/join('', map { "$+{i}$_\n" } @$lines)/e;
}
for my $file (sort keys %text) {
  die "error: melonDS $file still sets a key from constants\n"
    if $text{$file} =~ /\*\(u32\*\)&[Kk]ey[XY](?:\[\d+\])+\s*=/
    || $text{$file} =~ /\b(?:boot2key|key_const)\[16\]\s*=\s*\{\s*[^\s}]/;
  open(my $out, '>:raw', "$root/$file") or die "error: melonDS $file: $!\n";
  print $out $text{$file};
  close($out) or die "error: melonDS $file: $!\n";
}
PERL
}

# Fails if the core still carries key material of the DSi or the address of
# Nintendo's update server (hard rules: no keys and no download links in the
# app; ADR 0006). The check reads the values at build time from the unpatched
# source of melonDS at the submodule's commit, so that this repository never
# holds them: the AES key of boot2, the key scrambler constant, the eMMC key
# Y, the key X of modcrypt and of slot 1, and the XOR constants of the key X
# derivation. It fails as well if a value is not where melonDS defines it or
# the disassembly looks incomplete, so that it never silently checks nothing.
# The core must hold no key as bytes (in memory order, reversed, with every
# 32-bit word swapped, and both), no key or XOR constant as a 32-bit word
# built with mov and movk, and no run of 8 or more bytes of boot2's key or
# the scrambler constant in the add, sub or mov immediates of one function,
# which is how the compiler encoded the scrambler constant. In memory order
# the key X of modcrypt is printable text that the core's own strings
# contain, so as bytes it counts only next to the key X of slot 1, as the
# unpatched core holds them.
melondsds_check_key_material() {
  local dylib="$1"
  perl - "$REPO_ROOT/$MELONDSDS_DEPENDENCY_DIR/melonDS" "$dylib" << 'PERL' || exit 70
use strict;
use warnings;
no warnings "portable";

my ($melonds, $dylib) = @ARGV;

sub git {
  open(my $git, '-|', 'git', '-C', $melonds, @_) or die "error: git: $!\n";
  my $output = do { local $/; <$git> };
  close($git) or die "error: git @_ failed for melonDS\n";
  return $output;
}

sub source {
  my ($path) = @_;
  return { path => $path, text => git('show', "HEAD:$path") };
}

# The 16 bytes of const u8 <name>[16] = {...}.
sub array {
  my ($source, $name) = @_;
  my @arrays = $source->{text} =~ /\b\Q$name\E\[16\]\s*=\s*\{([^}]*)\}/g;
  die "error: expected one array $name in $source->{path} of melonDS, found " . @arrays . "\n" unless @arrays == 1;
  my @bytes = $arrays[0] =~ /\b0x([0-9A-Fa-f]{2})\b/g;
  die "error: expected 16 bytes in $name in $source->{path} of melonDS, found " . @bytes . "\n" unless @bytes == 16;
  return pack('H*', join('', @bytes));
}

# The constant words of *(u32*)&<key>[<offset>] = 0x...; at exactly these offsets.
sub words {
  my ($source, $key, @offsets) = @_;
  my %word;
  while ($source->{text} =~ /\*\(u32\*\)&\Q$key\E\[(\d+)\]\s*=\s*0x([0-9A-Fa-f]{8})\s*;/g) {
    die "error: $source->{path} of melonDS sets $key\[$1\] twice\n" if exists $word{$1};
    $word{$1} = hex($2);
  }
  my $found = join(' ', sort { $a <=> $b } keys %word);
  die "error: expected constant words of $key at @offsets in $source->{path} of melonDS, found " . ($found || 'none') . "\n"
    unless $found eq "@offsets";
  return @word{@offsets};
}

# The XOR constants of *(u32*)&<key>[<offset>] = ... ^ 0x...;
sub xors {
  my ($source, @keys) = @_;
  return sort { $a <=> $b } map { hex } map { $source->{text} =~ /\*\(u32\*\)&\Q$_\E\[\d+\]\s*=[^;]*\^\s*0x([0-9A-Fa-f]{8})\s*;/g } @keys;
}

my ($dsi, $aes, $nand) = map { source("src/$_") } qw(DSi.cpp DSi_AES.cpp DSi_NAND.cpp);
my @modcrypt = words($aes, 'KeyX[0]', 0, 4);
my @slot1 = words($aes, 'KeyX[1]', 0, 4);
my @emmc = words($nand, 'keyY', 0, 4, 8, 12);
my @xor = xors($aes, 'KeyX[1]', 'KeyX[3]');
die "error: the key X of modcrypt differs between DSi.cpp and DSi_AES.cpp of melonDS\n"
  unless "@modcrypt" eq join(' ', words($dsi, 'keyX', 0, 4));
die "error: the key X of slot 1 differs between DSi_AES.cpp and DSi_NAND.cpp of melonDS\n"
  unless "@slot1" eq join(' ', words($nand, 'keyX', 0, 4));
die "error: the eMMC key Y differs between DSi_AES.cpp and DSi_NAND.cpp of melonDS\n"
  unless "@emmc[0 .. 2]" eq join(' ', words($aes, 'KeyY[3]', 0, 4, 8));
die "error: expected the same three XOR constants of the key X derivation in DSi_AES.cpp and DSi_NAND.cpp of melonDS\n"
  unless @xor == 3 && "@xor" eq join(' ', xors($nand, 'keyX'));
my %key = (
  'AES key of boot2' => array($dsi, 'boot2key'),
  'key scrambler constant' => array($aes, 'key_const'),
  'eMMC key Y' => pack('V*', @emmc),
  'key X of modcrypt' => pack('V*', @modcrypt),
  'key X of slot 1' => pack('V*', @slot1),
);

my (%found, $patterns);
open(my $in, '<:raw', $dylib) or die "error: $dylib: $!\n";
my $binary = do { local $/; <$in> };
close($in);
for my $name (sort keys %key) {
  my $bytes = $key{$name};
  my $swapped = join('', map { scalar reverse } unpack('(a4)*', $bytes));
  for my $pattern (scalar reverse($bytes), $swapped, scalar reverse($swapped),
    $name eq 'key X of modcrypt' ? $bytes . $key{'key X of slot 1'} : $bytes) {
    $patterns++;
    for (my $at = index($binary, $pattern); $at >= 0; $at = index($binary, $pattern, $at + 1)) {
      $found{"$name as bytes at offset $at"}++;
    }
  }
}

# Words with two nonzero halves, in both byte orders, and the byte runs.
my %word;
for my $name (sort keys %key) {
  $word{$_} //= $name for grep { $_ >> 16 && $_ & 0xFFFF } unpack('V*', $key{$name}), unpack('N*', $key{$name});
}
$word{$_} //= 'XOR constant of the key X derivation' for @xor;
my @runs = map { my @bytes = unpack('C*', $key{$_}); ([$_, \@bytes], [$_, [reverse @bytes]]) }
  'AES key of boot2', 'key scrambler constant';

my ($function, $functions, $built, $immediates, %register, %list) = ('', 0, 0, 0);
my $number = sub { my ($text) = @_; $text =~ /^0x/ ? hex($text) : $text };
my $end_function = sub {
  for my $kind (sort keys %list) {
    my $values = $list{$kind};
    RUN: for my $run (@runs) {
      my ($name, $bytes) = @$run;
      for my $i (0 .. $#$values) {
        my $n = 0;
        $n++ while $n < @$bytes && $i + $n < @$values && $values->[$i + $n] == $bytes->[$n];
        if ($n >= 8) {
          $found{"$name as $kind immediates in $function"}++;
          next RUN;
        }
      }
    }
  }
  %list = ();
  %register = ();
};
open(my $disassembly, '-|', 'xcrun', 'llvm-objdump', '--macho', '--disassemble', '--no-show-raw-insn', $dylib)
  or die "error: llvm-objdump: $!\n";
while (my $line = <$disassembly>) {
  if ($line =~ /^(\S+):$/) {
    $end_function->();
    ($function, $functions) = ($1, $functions + 1);
    next;
  }
  next unless $line =~ /^\s*[0-9a-f]+:\s+(\S+)\s+(.*?)\s*$/;
  my ($op, $operands) = ($1, $2);
  if ($op =~ /^(?:add|sub|mov)$/ && $operands =~ /^w\d+, (?:w(?:\d+|sp), )?#(0x[0-9a-f]+|\d+)$/) {
    my $value = $number->($1);
    if ($value < 256) {
      push @{ $list{$op eq 'mov' ? 'mov' : 'add/sub'} }, $op eq 'sub' ? -$value & 0xFF : $value;
      $immediates++;
    }
  }
  if ($op =~ /^mov[zkn]?$/ && $operands =~ /^([wx])(\d+), #(-?)(0x[0-9a-f]+|\d+)(?:, lsl #(\d+))?$/) {
    my ($size, $r, $negative, $value, $shift) = ($1, $2, $3, $number->($4), $5 // 0);
    if ($op eq 'movk') {
      next unless defined $register{$r};
      $register{$r} = $register{$r} & ~(0xFFFF << $shift) | $value << $shift;
      $built++;
    } elsif ($op eq 'movn') {
      $register{$r} = ~($value << $shift);
    } else {
      $register{$r} = $negative ? -$value & ~0 : $value << $shift;
    }
    $register{$r} &= 0xFFFFFFFF if $size eq 'w';
    for my $half ($register{$r} & 0xFFFFFFFF, $register{$r} >> 32) {
      $found{"$word{$half} as a word in $function"}++ if defined $word{$half};
    }
  } elsif ($operands =~ /^[wx](\d+)\b/) {
    delete $register{$1};
  }
}
$end_function->();
close($disassembly) or die "error: llvm-objdump failed on $dylib\n";
die "error: the disassembly of $dylib looks incomplete: $functions functions, $built words built with movk, $immediates byte immediates\n"
  unless $functions > 1000 && $built > 1000 && $immediates > 1000;

if (%found) {
  print STDERR "error: the core still carries key material of the DSi:\n";
  print STDERR "    $_\n" for sort keys %found;
  exit 1;
}
chomp(my $commit = git('rev-parse', '--short=10', 'HEAD'));
printf "    no key material of the DSi: %d keys and %d XOR constants from melonDS %s, %d byte patterns, %d words, %d byte runs, %d functions\n",
  scalar(keys %key), scalar(@xor), $commit, $patterns, scalar(keys %word), scalar(@runs), $functions;
PERL
  if LC_ALL=C grep -a -q 'nintendowifi' "$dylib"; then
    echo "error: $CORE_NAME still carries the address of Nintendo's update server" >&2
    exit 70
  fi
}

# Fails unless the key table of KEY1 is empty in the FreeBIOS of the ARM7
# that the core embeds from melonDS (hard rules: no BIOS and no keys; ADR
# 0006). In the console's own BIOS the 4168 bytes from offset 0x30 hold the
# Blowfish table of KEY1, the encryption of DS cartridges; FreeBIOS leaves
# them empty. The check finds the array bios_ntr_arm7 with nm -m, maps its
# address to the file through the segments (otool -l) and reads the bytes.
# It fails as well if the symbol is missing or ambiguous, ends before the
# table does or lies outside the part of a segment that the file holds.
melondsds_check_freebios() {
  perl - "$1" << 'PERL' || exit 70
use strict;
use warnings;
no warnings 'portable';

my ($binary) = @ARGV;
my ($symbol, $start, $length) = ('__ZN7melonDS13bios_ntr_arm7E', 0x30, 0x1048);

sub run {
  my @command = @_;
  open(my $output, '-|', @command) or die "error: $command[0]: $!\n";
  my @lines = <$output>;
  close($output) or die "error: @command failed for $binary\n";
  chomp @lines;
  return @lines;
}

my (@segments, @sections, $command);
for (run('otool', '-l', $binary)) {
  if (/^Load command/) { undef $command; next }
  if (/^\s+cmd LC_SEGMENT_64$/) { push @segments, $command = {}; next }
  if (/^Section$/) { push @sections, $command = {}; next }
  next unless $command;
  if (/^\s+(segname|sectname) (\S+)$/) { $command->{$1} = $2 }
  elsif (/^\s+(vmaddr|addr|size) (0x[0-9a-f]+)$/) { $command->{$1} = hex($2) }
  elsif (/^\s+(fileoff|filesize) (\d+)$/) { $command->{$1} = $2 }
}

# The symbol and the next symbol of its section, where the array ends at the latest.
my (@found, %addresses);
for (run('nm', '-m', $binary)) {
  next unless /^([0-9a-f]+) \((\w+),(\w+)\) .* (\S+)$/;
  push @{ $addresses{"$2,$3"} }, hex($1);
  push @found, [hex($1), $2, $3] if $4 eq $symbol;
}
die "error: expected one symbol $symbol (the FreeBIOS of the ARM7 from melonDS) in $binary, found " . @found . "\n"
  unless @found == 1;
my ($address, $segment_name, $section_name) = @{ $found[0] };
my ($section) = grep { $_->{segname} eq $segment_name && $_->{sectname} eq $section_name } @sections;
die "error: otool -l does not list the section $segment_name,$section_name of $binary\n" unless $section;
my ($end) = sort { $a <=> $b } grep { $_ > $address } @{ $addresses{"$segment_name,$section_name"} },
  $section->{addr} + $section->{size};
die sprintf("error: %s in %s ends at 0x%x, before the key table of KEY1 (0x%x to 0x%x)\n",
  $symbol, $binary, $end, $address + $start, $address + $start + $length) if $end < $address + $start + $length;
my ($segment) = grep {
  $_->{segname} eq $segment_name && $address >= $_->{vmaddr} && $address + $start + $length <= $_->{vmaddr} + $_->{filesize}
} @segments;
die sprintf("error: %s at 0x%x in %s does not lie in the part of %s that the file holds\n", $symbol, $address, $binary, $segment_name)
  unless $segment;
my $offset = $segment->{fileoff} + $address - $segment->{vmaddr} + $start;
open(my $in, '<:raw', $binary) or die "error: $binary: $!\n";
seek($in, $offset, 0) or die "error: $binary: $!\n";
read($in, my $bytes, $length) == $length or die "error: $binary ends inside the FreeBIOS of the ARM7\n";
close($in);
my $nonzero = ($bytes =~ tr/\0//c);
die "error: the key table of KEY1 in the FreeBIOS of the ARM7 is not empty in $binary: $nonzero of $length bytes are not zero\n"
  if $nonzero;
printf "    FreeBIOS of the ARM7 without the key table of KEY1: %d bytes from 0x%x of bios_ntr_arm7 (%s,%s, file offset %d) all zero\n",
  $length, $start, $segment_name, $section_name, $offset;
PERL
}

core_build() {
  local work_dir="$2"
  local dependencies="$REPO_ROOT/$MELONDSDS_DEPENDENCY_DIR"

  # Build from a copy of the committed tree with the fixes below, so that the
  # submodule stays clean. melonDS DS v1.4.0 does not build with networking
  # but without its direct mode (libpcap): the pcap formatter and two adapter
  # helpers need #ifdef HAVE_NETWORKING_DIRECT_MODE. And the DSi mode would
  # download a DSiWare title's metadata from Nintendo's update server
  # (DownloadTmd); ARCFOLD_ALLOW_TMD_DOWNLOAD, never defined, takes the code
  # and the address out, so that the core says it cannot download it.
  local source="$work_dir/source"
  rm -rf "$source"
  mkdir -p "$source"
  git -C "$REPO_ROOT/$CORE_SOURCE" archive HEAD | tar -x -C "$source"
  patch -p1 -d "$source" --quiet << 'PATCH'
--- a/src/libretro/format.cpp
+++ b/src/libretro/format.cpp
@@ -81,6 +81,7 @@ auto fmt::formatter<MelonDsDs::FormattedGLEnum>::format(MelonDsDs::FormattedGLEn
 }
 #endif

+#ifdef HAVE_NETWORKING_DIRECT_MODE
 auto fmt::formatter<MelonDsDs::FormattedPCapFlags>::format(MelonDsDs::FormattedPCapFlags e, format_context& ctx) const -> decltype(ctx.out()) {
     auto flags = static_cast<uint32_t>(e);

@@ -118,6 +119,7 @@ auto fmt::formatter<MelonDsDs::FormattedPCapFlags>::format(MelonDsDs::FormattedP

     return formatter<decltype(flagNames)>::format(flagNames, ctx);
 }
+#endif

 auto fmt::formatter<MelonDsDs::BiosType>::format(MelonDsDs::BiosType c, format_context& ctx) const -> decltype(ctx.out()) {
     string_view name = "unknown";
--- a/src/libretro/net/net.cpp
+++ b/src/libretro/net/net.cpp
@@ -125,6 +125,7 @@ int MelonDsDs::NetState::RecvPacket(u8* data) noexcept
     return _net.RecvPacket(data, 0);
 }

+#ifdef HAVE_NETWORKING_DIRECT_MODE
 vector<melonDS::AdapterData> MelonDsDs::NetState::GetAdapters() const noexcept
 {
     ZoneScopedN(TracyFunction);
@@ -150,6 +151,7 @@ bool operator==(const melonDS::AdapterData& lhs, const melonDS::AdapterData& rhs
         strncmp(lhs.DeviceName, rhs.DeviceName, sizeof(lhs.DeviceName)) == 0
     ;
 }
+#endif

 void MelonDsDs::NetState::Apply(const CoreConfig& config) noexcept
 {
--- a/src/libretro/net/net.hpp
+++ b/src/libretro/net/net.hpp
@@ -48,7 +48,9 @@ namespace MelonDsDs

         int SendPacket(std::span<std::byte> data) noexcept;
         int RecvPacket(melonDS::u8* data) noexcept;
+#ifdef HAVE_NETWORKING_DIRECT_MODE
         [[nodiscard]] std::vector<melonDS::AdapterData> GetAdapters() const noexcept;
+#endif
         void Apply(const CoreConfig& config) noexcept;
         [[nodiscard]] NetworkMode GetNetworkMode() const noexcept;
     private:
--- a/src/libretro/config/console.cpp
+++ b/src/libretro/config/console.cpp
@@ -95,8 +95,10 @@
     static void GetTmdPath(const retro::GameInfo &nds_info, std::span<char> buffer);
     static optional<TitleMetadata> GetCachedTmd(string_view tmdPath) noexcept;
     static bool ValidateTmd(const TitleMetadata &tmd) noexcept;
+#ifdef ARCFOLD_ALLOW_TMD_DOWNLOAD
     static optional<TitleMetadata> DownloadTmd(const NDSHeader& header, string_view tmdPath) noexcept;
     static bool CacheTmd(string_view tmd_path, std::span<const std::byte> tmd) noexcept;
+#endif
     static void ImportDsiwareSaveData(NANDMount& nand, const retro::GameInfo& nds_info, const NDSHeader& header, int type) noexcept;
     static optional<Firmware> LoadFirmware(const string& firmwarePath) noexcept;
     static bool LoadBios(const string_view& name, BiosType type, std::span<uint8_t> buffer) noexcept;
@@ -830,7 +832,8 @@
         if (!tmd) {
             // If the TMD isn't available locally...
 
-#ifdef HAVE_NETWORKING
+// Arcfold, 7 November 2026: no download from Nintendo's servers (hard rules, ADR 0006).
+#ifdef ARCFOLD_ALLOW_TMD_DOWNLOAD
             if (tmd = DownloadTmd(header, tmd_path); !tmd) {
                 // ...then download it and save it to disk. If that didn't work...
                 throw missing_metadata_exception("Cannot get title metadata for installation");
@@ -922,6 +925,7 @@
     return true;
 }
 
+#ifdef ARCFOLD_ALLOW_TMD_DOWNLOAD
 static optional<TitleMetadata> MelonDsDs::DownloadTmd(const NDSHeader &header, string_view tmdPath) noexcept {
     ZoneScopedN(TracyFunction);
     auto url = fmt::format(
@@ -1012,6 +1016,7 @@
         return false;
     }
 }
+#endif
 
 static void MelonDsDs::ImportDsiwareSaveData(NANDMount& nand, const retro::GameInfo& nds_info, const NDSHeader& header, int type) noexcept {
     ZoneScopedN(TracyFunction);
PATCH

  # melonDS from a copy as well, without the key material of the DSi
  # (melondsds_remove_key_material).
  local melonds="$work_dir/melonDS"
  rm -rf "$melonds"
  mkdir -p "$melonds"
  git -C "$dependencies/melonDS" archive HEAD | tar -x -C "$melonds"
  melondsds_remove_key_material "$melonds"

  # FETCHCONTENT_SOURCE_DIR_<NAME> uses the upper-case content name, dashes
  # included. melonDS DS looks for the CMake modules of embed-binaries and
  # melonDS in FetchContent's default folders, hence CMAKE_MODULE_PATH. The
  # repository URL and tag of melonDS only end up in version strings.
  local name directory sources=()
  for name in "${MELONDSDS_DEPENDENCY_NAMES[@]}"; do
    directory="$dependencies/$name"
    if [[ "$name" == melonDS ]]; then
      directory="$melonds"
    fi
    sources+=("-DFETCHCONTENT_SOURCE_DIR_$(tr '[:lower:]' '[:upper:]' <<< "$name")=$directory")
  done
  cmake -S "$source" -B "$work_dir/cmake" "${IOS_CMAKE_ARGS[@]}" \
    -DFETCHCONTENT_FULLY_DISCONNECTED=ON \
    "${sources[@]}" \
    "-DCMAKE_MODULE_PATH=$dependencies/embed-binaries/cmake;$melonds/cmake" \
    -DMELONDS_REPOSITORY_URL=https://github.com/melonDS-emu/melonDS \
    -DMELONDS_REPOSITORY_TAG="$(git -C "$dependencies/melonDS" rev-parse --short=10 HEAD)" \
    -DENABLE_JIT=OFF \
    -DENABLE_OPENGL=OFF \
    -DENABLE_DYNAMIC=OFF \
    -DENABLE_NETWORKING=ON \
    -DBUILD_AS_SHARED_LIBRARY=ON \
    -DBUILD_TESTING=OFF
  cmake --build "$work_dir/cmake" --target melondsds_libretro
  cp "$work_dir/cmake/src/libretro/melondsds_libretro.dylib" "$work_dir/$CORE_NAME.dylib"
}

# The recipe's checks of each slice: after every build and with
# Scripts/build-core.sh melondsds --check, after the checks of build-core.sh
# (exports, imports, mmap, JIT).
core_check() {
  local binary="$1"
  melondsds_check_key_material "$binary"
  echo "    no address of Nintendo's update server: no string nintendowifi"
  melondsds_check_freebios "$binary"
}
