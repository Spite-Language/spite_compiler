#!/usr/bin/env bash
# Builds this compiler from nothing but the old compiler (0.0.6), as ARCHITECTURE.md ("How the compiler is built")
# describes:
#   1. the old compiler builds the seed, the last commit it can build (SEED_COMMIT);
#   2. the seed builds this checkout's source;
#   3. that compiler builds the source again, and again, until two builds write the same bytes.
# The fixed-point compiler is left in .spite/bootstrap/spite.exe; with --install it also replaces .spite/spite.exe.
#
#   bash scripts/bootstrap.sh [--install]
#
# OLD_COMPILER names the old compiler when it is not in .spite/spite-0.0.6-windows/.
set -euo pipefail

SEED_COMMIT=47767ec

root="$(cd "$(dirname "$0")/.." && pwd)"
old="${OLD_COMPILER:-$root/.spite/spite-0.0.6-windows/spite.exe}"
work="$root/.spite/bootstrap"
library="$root/.spite/library"

fail() {
    echo "bootstrap: $1" >&2
    exit 1
}

[ -x "$old" ] || fail "the old compiler is not at $old: set OLD_COMPILER"
[ -d "$library" ] || fail "$library is missing: make it a junction to ../SpiteStandardLibrary"
[ -d "$root/.spite/spite_compiler" ] || fail "$root/.spite/spite_compiler is missing: make it a junction to this folder"

rm -rf "$work/seed_source"
mkdir -p "$work/seed_source/spite_compiler"
git -C "$root" archive "$SEED_COMMIT" | tar -x -C "$work/seed_source/spite_compiler"

echo "bootstrap: the old compiler builds the seed ($SEED_COMMIT)"
(cd "$work/seed_source" && "$old" spite_compiler --build --executable-path="$work/spite_seed.exe")
[ -f "$work/spite_seed.exe" ] || fail "the old compiler wrote no seed"
# The old compiler's executables reserve 1 MB of stack, too little to resolve this compiler: reserve 256 MB.
python - "$work/spite_seed.exe" <<'PYTHON'
import struct
import sys
path = sys.argv[1]
data = bytearray(open(path, "rb").read())
header = struct.unpack_from("<I", data, 0x3C)[0]
struct.pack_into("<Q", data, header + 24 + 72, 256 * 1024 * 1024)
open(path, "wb").write(data)
PYTHON

build() {
    # build <compiler> <output>: the compiler builds this checkout's source
    (cd "$root" && "$1" .spite/spite_compiler --build --executable-path="$2")
    [ -f "$2" ] || fail "$1 wrote no compiler"
}

echo "bootstrap: the seed builds the source"
build "$work/spite_seed.exe" "$work/spite_1.exe"
previous="$work/spite_1.exe"
round=2
while [ $round -le 4 ]; do
    echo "bootstrap: build $round of the source by the compiler before it"
    build "$previous" "$work/spite_$round.exe"
    if cmp -s "$previous" "$work/spite_$round.exe"; then
        cp "$work/spite_$round.exe" "$work/spite.exe"
        cp "$work/spite_$round.functions" "$work/spite.functions"
        echo "bootstrap: fixed point: build $round writes the same bytes as build $((round - 1))"
        if [ "${1:-}" = "--install" ]; then
            cp "$work/spite.exe" "$root/.spite/spite.exe"
            cp "$work/spite.functions" "$root/.spite/spite.functions"
            echo "bootstrap: installed $root/.spite/spite.exe"
        fi
        exit 0
    fi
    previous="$work/spite_$round.exe"
    round=$((round + 1))
done
fail "no fixed point after four builds: $work/spite_3.exe and $work/spite_4.exe differ"
