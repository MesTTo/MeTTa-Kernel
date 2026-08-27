#!/bin/sh
# Purpose: build the engine's own C artifacts, reader.so and writer.so, beside
#   the reader.c and writer.c they come from.
# Assumes:
#   - swipl-ld, which ships with SWI-Prolog and is therefore present wherever
#     the engine is, plus a C compiler for it to drive.
# Guarantees:
#   - it rebuilds a unit only when that unit's own source, or the metta_token.h
#     both include, is newer than its shared object, so running it twice
#     compiles once and a change to the shared lexical rules rebuilds both
#   - a tree with no swipl-ld, or no compiler, exits 0 with a note. The engine
#     falls back to the Prolog grammar and the Prolog writer, which are the
#     specifications the C units implement, so "not built" is a slower
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
    echo "engine/build.sh: swipl-ld not found; the engine will use the Prolog reader and writer" >&2
    exit 0
fi
if ! command -v cc >/dev/null 2>&1 &&
   ! command -v gcc >/dev/null 2>&1 &&
   ! command -v clang >/dev/null 2>&1; then
    echo "engine/build.sh: swipl-ld found but no C compiler; the engine will use the Prolog reader and writer" >&2
    exit 0
fi

for unit in reader writer; do
    if [ ! -f "$HERE/$unit.so" ] ||
       [ "$HERE/$unit.c" -nt "$HERE/$unit.so" ] ||
       [ "$HERE/metta_token.h" -nt "$HERE/$unit.so" ]; then
        ( cd "$HERE" && swipl-ld -shared -O2 -o "$unit.so" "$unit.c" )
    fi
done
