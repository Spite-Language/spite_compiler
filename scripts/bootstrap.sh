#!/usr/bin/env bash
# Builds this compiler from its seed, as ARCHITECTURE.md ("How the compiler is built") describes:
#   1. the seed is the last compiler this source built itself (D1071): .spite/spite.exe, or, when no compiler is
#      there, the release SEED_TAG of spite_compiler, downloaded into .spite/;
#   2. the seed builds this checkout's source;
#   3. that compiler builds the source again, and again, until two builds write the same bytes.
# The fixed-point compiler is left in .spite/bootstrap/spite.exe; with --install it also replaces .spite/spite.exe.
# The standard library is the repository spite_standard_library, cloned beside this one.
#
#   bash scripts/bootstrap.sh [--install]
#
# SEED names another seed compiler instead.
set -euo pipefail

SEED_TAG=seed-2026-10-25
SEED_URL="https://github.com/Spite-Language/spite_compiler/releases/download/$SEED_TAG"

root="$(cd "$(dirname "$0")/.." && pwd)"
parent="$(dirname "$root")"
name="$(basename "$root")"
work="$root/.spite/bootstrap"

fail() {
    echo "bootstrap: $1" >&2
    exit 1
}

[ "$name" = "spite_compiler" ] || fail "this repository is cloned as '$name': clone it as spite_compiler, a snake_case folder the compiler can build"
[ -d "$parent/spite_standard_library/windows" ] ||
    fail "the standard library is not beside this repository: gh repo clone Spite-Language/spite_standard_library $parent/spite_standard_library"

mkdir -p "$work"
seed="${SEED:-$root/.spite/spite.exe}"
if [ ! -f "$seed" ]; then
    [ -z "${SEED:-}" ] || fail "the seed $seed does not exist"
    echo "bootstrap: no compiler in .spite/: downloading the seed $SEED_TAG"
    curl -fsSL -o "$root/.spite/spite.exe.part" "$SEED_URL/spite.exe" || fail "could not download $SEED_URL/spite.exe"
    curl -fsSL -o "$root/.spite/spite.functions.part" "$SEED_URL/spite.functions" ||
        fail "could not download $SEED_URL/spite.functions"
    mv "$root/.spite/spite.exe.part" "$root/.spite/spite.exe"
    mv "$root/.spite/spite.functions.part" "$root/.spite/spite.functions"
fi

build() {
    # build <compiler> <round>: the compiler builds this checkout's source into .spite/bootstrap/spite_<round>.exe
    rm -f "$work/spite_$2.exe" "$work/spite_$2.functions"
    (cd "$parent" && "$1" "$name" --build --executable-path="$name/.spite/bootstrap/spite_$2.exe")
    [ -f "$work/spite_$2.exe" ] || fail "$1 wrote no compiler"
}

echo "bootstrap: the seed builds the source"
build "$seed" 1
previous="$work/spite_1.exe"
round=2
while [ $round -le 4 ]; do
    echo "bootstrap: build $round of the source by the compiler before it"
    build "$previous" $round
    if cmp -s "$previous" "$work/spite_$round.exe"; then
        cp "$work/spite_$round.exe" "$work/spite.exe"
        cp "$work/spite_$round.functions" "$work/spite.functions"
        echo "bootstrap: fixed point: build $round writes the same bytes as build $((round - 1))"
        if cmp -s "$seed" "$work/spite.exe"; then
            echo "bootstrap: the fixed point is the seed itself"
        fi
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
