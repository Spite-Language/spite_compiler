#!/usr/bin/env bash
# Shows that a flag of the compiler is one line (spite_compiler#306, command_line/contract.md): builds a copy of this
# source with one more setting in environment.spite, and checks that the copy reads it and the installed compiler does not.
# It builds a whole compiler, so it is a script and not a spite_spec test.
#
#   bash scripts/flag_is_one_line.sh
#
# COMPILER names another compiler to build the copy with (default .spite/spite.exe). Exits 1 when a check fails.
set -uo pipefail

here="$(cd "$(dirname "$0")/.." && pwd)"
parent="$(cd "$here/.." && pwd)"
compiler="${COMPILER:-$here/.spite/spite.exe}"
work="$here/.spite/one_line"
failed=0

windows() { cygpath -w "$1"; }

clean() {
  for name in spite_standard_library spite_spec spite_documentation; do
    [ -e "$work/$name" ] && cmd //c "rmdir $(windows "$work/$name")" > /dev/null
  done
  rm -rf "$work"
}
trap clean EXIT

check() {
  if [ "$2" = "true" ]; then
    echo "ok: $1"
  else
    echo "FAILED: $1"
    failed=1
  fi
}

# The flags are given to the compiler with the program's folder as the working directory, like any run.
ask() {
  (cd "$work/spare_program" && "$1" $2 2>&1) || true
}

clean
mkdir -p "$work/spare_program"
for name in spite_standard_library spite_spec spite_documentation; do
  cmd //c "mklink /J $(windows "$work/$name") $(windows "$parent/$name")" > /dev/null
done
mkdir -p "$work/spite_compiler"
(cd "$here" && tar --exclude=./.spite --exclude=./.git -cf - .) | (cd "$work/spite_compiler" && tar -xf -)
sed -i 's/^var connect = 0/var spare_flag = false\nvar connect = 0/' "$work/spite_compiler/environment.spite"
grep -q "^var spare_flag = false" "$work/spite_compiler/environment.spite" || { echo "FAILED: the line was not added"; exit 1; }

cat > "$work/spare_program/spare_program.spite" <<'SPITE'
var console = Console()

func SpareProgram() {
    load "../spite_standard_library/windows"
    console.print("spare")
}
SPITE

start=$SECONDS
(cd "$work/spite_compiler" && "$compiler" --build --executable-path=../spare_compiler.exe) > "$work/build.txt" 2>&1
built=$?
echo "the copy built in $((SECONDS - start)) seconds"
if [ $built -ne 0 ] || [ ! -f "$work/spare_compiler.exe" ]; then
  tail -20 "$work/build.txt"
  echo "FAILED: the compiler with one more line does not build"
  exit 1
fi
spare="$work/spare_compiler.exe"

before="$(ask "$compiler" "--spare-flag=maybe --check")"
check "the compiler as it is refuses --spare-flag" "$(echo "$before" | grep -q "is not a compiler option" && echo true)"
given="$(ask "$spare" "--spare-flag --check")"
check "with the line, --spare-flag is read" "$(echo "$given" | grep -q "error" || echo true)"
wrong="$(ask "$spare" "--spare-flag=maybe --check")"
check "with the line, --spare-flag=maybe is checked as a Boolean" "$(echo "$wrong" | grep -q "the setting Environment.spare_flag was given 'maybe'" && echo true)"
other="$(ask "$spare" "--other-flag --check")"
check "with the line, --other-flag is still refused" "$(echo "$other" | grep -q "is not a compiler option" && echo true)"

exit $failed
