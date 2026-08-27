#!/bin/sh
# Purpose: build the engine's own C artifacts, one .so beside each .c it comes
#   from.
# Assumes:
#   - swipl-ld, which ships with SWI-Prolog and is therefore present wherever
#     the engine is, plus a C compiler for it to drive.
#   - each engine/<unit>.c builds to engine/<unit>.so on its own, and the
#     Prolog file that loads it names that path.
# Guarantees:
#   - it rebuilds only what is out of date, so running it twice compiles once
#   - a tree with no swipl-ld, or no compiler, exits 0 with a note. Every C
#     unit here accelerates a Prolog implementation that stays the
#     specification and answers identically, so "not built" is a slower
#     configuration and not an error. A build that is ATTEMPTED and FAILS exits
#     nonzero: that is the half-built case, and it is the same split every
#     decider in this tree draws.
# Open Obligations:
#   To Do: None
#   Hacks: None
#   Future Enhancements: None

set -eu

HERE=$(cd -- "$(dirname -- "$0")" && pwd)

if ! command -v swipl-ld >/dev/null 2>&1; then
    echo "engine/build.sh: swipl-ld not found; the engine will use its Prolog implementations" >&2
    exit 0
fi
if ! command -v cc >/dev/null 2>&1 &&
   ! command -v gcc >/dev/null 2>&1 &&
   ! command -v clang >/dev/null 2>&1; then
    echo "engine/build.sh: swipl-ld found but no C compiler; the engine will use its Prolog implementations" >&2
    exit 0
fi

# Discovered rather than listed, so adding a C unit beside its Prolog file
# needs no edit here.
for source in "$HERE"/*.c; do
    [ -f "$source" ] || continue
    unit=$(basename "$source" .c)
    if [ ! -f "$HERE/$unit.so" ] || [ "$source" -nt "$HERE/$unit.so" ]; then
        ( cd "$HERE" && swipl-ld -shared -O2 -o "$unit.so" "$unit.c" )
    fi
done
