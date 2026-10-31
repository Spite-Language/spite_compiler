#!/usr/bin/env bash
# Builds this compiler from its seed, as ARCHITECTURE.md ("How the compiler is built") describes:
#   1. the seed is the last compiler this source built itself (D1071): .spite/spite.exe, or, when no compiler is
#      there, the release SEED_TAG of spite_compiler, downloaded into .spite/, which then builds each of STONES in
#      turn, every stone built by the compiler of the one before, and the last stone's compiler is the seed;
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

# The stepping stones from SEED_TAG to this source (spite_compiler#267): each is a commit the compiler before it can
# build, whose compiler reads what the next one is written in. A line is the compiler's commit, then the commits of
# spite_standard_library, spite_spec and spite_documentation it was built beside (its comments link the last two).
# Where the library renamed what the compiler before it writes into every program, the stone is built beside the
# library from before the rename, and bridge_<commit> below adds reopenings that give that library the new names.
# A commit that the last stone's compiler cannot build adds itself here in the same push (AGENTS.md). The list and
# the release go with the first stable release, which builds the compiler itself (D1764).
STONES=(
    "2bd9b1a 315bf65 00f1ab8 a07cfa0"
    "c8e2e45 315bf65 8f11cdc 4d35dc2"
    "333f1cd 2309f29 50bf674 56e3b6a"
    "a4c6b89 f836f28 50bf674 56e3b6a"
    "e79b803 bc670f8 64db1c1 c751899"
    "63e929f bc670f8 64db1c1 7aabefa"
    "5efb72f 40a940e 6eab258 13a3419"
    "d2e6208 40a940e 29fb800 a255986"
    "10ed2e0 3c823ba dc2e5cc f96bbf7"
    "acadacc 531e9b1 63b0b93 39d3918"
    "30824b7 e8df532 3259d3b f755736"
    "f9de322 eab10ec b45a2d9 cce8cd9"
    "b62bcad da18edf d4fdad2 cce8cd9"
)

bridge_c8e2e45() {
    # the library's names of D1714, which c8e2e45 calls, over the library from before them; and the fault machinery
    # of 17ee1f5, which reads no slice, so the compiler it builds writes machinery that the library of D1728 takes
    git -C "$root" show 17ee1f5:symbols/machinery_text.spite >"$1/symbols/machinery_text.spite"
    cat >"$1/buffer.spite" <<'SPITE'
func read_buffer_at(at: Integer, wanted: Integer): Buffer? {
    return read_bytes_at(at, wanted)
}
SPITE
    cat >"$1/directory.spite" <<'SPITE'
func get_folder_name(): String {
    return name
}
SPITE
    cat >"$1/file.spite" <<'SPITE'
func read_as_string(): String? {
    return read()
}

func write_buffer(bytes: Buffer): Boolean {
    return write_bytes(bytes)
}

func get_file_name(): String {
    return name
}

func read_as_buffer(): Buffer? {
    return read_bytes()
}

func write_string(text: String): Boolean {
    return write(text)
}

func byte_count(): Long? {
    return size()
}

func last_written(): Instant? {
    return modified()
}
SPITE
    cat >"$1/process.spite" <<'SPITE'
func read_output_as_string(): String? {
    return output()
}
SPITE
    cat >"$1/string.spite" <<'SPITE'
func to_buffer(): Buffer {
    return to_bytes()
}

func byte_at(index: Integer): Integer {
    return code_at(index)
}
SPITE
}

bridge_63e929f() {
    # the constructor, conversion and preset of D1776, taught to a compiler still written with to_<type>() calls, so
    # the compiler before it builds it beside the library from before conversions: every change of 63e929f that
    # turned a to_<type>() call into a cast is read back as the call
    git -C "$root" diff -U0 e79b803 63e929f | awk '
        function flush() {
            if (casts) {
                if (!printed) { printf "%s", header; printed = 1 }
                printf "%s", hunk
            }
            hunk = ""
            casts = 0
        }
        /^diff --git / { flush(); header = $0 ORS; printed = 0; in_hunk = 0; next }
        /^@@ / { flush(); hunk = $0 ORS; in_hunk = 1; next }
        in_hunk { hunk = hunk $0 ORS; if ($0 ~ /^-.*\.to_[a-z_]+\(/) { casts = 1 }; next }
        { header = header $0 ORS }
        END { flush() }
    ' >"$1/.casts.diff"
    (cd "$1" && git apply -R --unidiff-zero .casts.diff && rm .casts.diff) || fail "could not write the casts of 63e929f back as calls"
}

bridge_5efb72f() {
    # an attribute whose default is null is never proven present (the fix of #268 that d2e6208 carries), so this
    # compiler judges d2e6208 the way the compiler that built it did
    local proof="$1/proofs/present_assignments/present_assignments.spite"
    awk '
        { print }
        $0 == "    fallback attribute.declaration and attribute.declaration.value" {
            print "    if attribute.declaration.value == AbstractSyntaxTree.Shapes.Expressions.LiteralExpression {"
            print "        fallback attribute.declaration.value.kind != \047keyword_null\047"
            print "    }"
        }
    ' "$proof" >"$proof.bridged"
    mv "$proof.bridged" "$proof"
    grep -q "keyword_null" "$proof" || fail "could not write the fix of #268 into 5efb72f"
}

bridge_d2e6208() {
    # the class tests of D1770 written back as value == C, which the compiler before it narrows on
    find "$1" -name "*.spite" -exec sed -i -e 's/\.class == \([A-Z]\)/ == \1/g' -e 's/\.class != \([A-Z]\)/ != \1/g' {} +
}

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
    walk_the_stones=yes
fi

stone() {
    # stone <compiler> <compiler commit> <library commit> <spec commit> <documentation commit>: the compiler builds the
    # commit, beside the other repositories at theirs, into .spite/bootstrap/stone_<commit>.exe
    local sources
    sources="$(mktemp -d)"
    local repositories=(spite_compiler spite_standard_library spite_spec spite_documentation)
    local commits=("$2" "$3" "$4" "$5")
    local index=0
    while [ $index -lt 4 ]; do
        local repository="${repositories[$index]}"
        mkdir -p "$sources/$repository"
        git -C "$parent/$repository" archive "${commits[$index]}" | tar -x -C "$sources/$repository" ||
            fail "could not read $repository at ${commits[$index]}: fetch it"
        index=$((index + 1))
    done
    if declare -F "bridge_$2" >/dev/null; then
        "bridge_$2" "$sources/spite_compiler"
    fi
    rm -f "$work/stone_$2.exe" "$work/stone_$2.functions"
    # every stone's compiler is older than D1775 and takes the folder it builds by position
    (cd "$sources" && "$1" spite_compiler --build --executable-path=spite_compiler/.spite/stone.exe) ||
        fail "$1 could not build the stepping stone $2"
    cp "$sources/spite_compiler/.spite/stone.exe" "$work/stone_$2.exe"
    cp "$sources/spite_compiler/.spite/stone.functions" "$work/stone_$2.functions"
    rm -rf "$sources"
}

if [ "${walk_the_stones:-}" = yes ]; then
    for repository in spite_spec spite_documentation; do
        [ -d "$parent/$repository/.git" ] ||
            fail "the stepping stones need $repository beside this repository: gh repo clone Spite-Language/$repository $parent/$repository"
    done
    for line in "${STONES[@]}"; do
        read -r compiler_commit library_commit spec_commit documentation_commit <<<"$line"
        echo "bootstrap: $seed builds the stepping stone $compiler_commit"
        stone "$seed" "$compiler_commit" "$library_commit" "$spec_commit" "$documentation_commit"
        seed="$work/stone_$compiler_commit.exe"
    done
fi

build() {
    # build <compiler> <round> [by_position]: the compiler builds this checkout's source, the folder it runs in
    # (D1775), into .spite/bootstrap/spite_<round>.exe; a stone's compiler, older than that, is given the folder
    rm -f "$work/spite_$2.exe" "$work/spite_$2.functions"
    if [ "${3:-}" = by_position ]; then
        (cd "$parent" && "$1" "$name" --build --executable-path="$name/.spite/bootstrap/spite_$2.exe")
    else
        (cd "$root" && "$1" --build --executable-path=".spite/bootstrap/spite_$2.exe")
    fi
    [ -f "$work/spite_$2.exe" ] || fail "$1 wrote no compiler"
}

echo "bootstrap: the seed builds the source"
build "$seed" 1 ${walk_the_stones:+by_position}
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
