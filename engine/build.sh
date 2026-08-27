#!/bin/sh
# Purpose: build the engine's own C artifact, reader.so, beside the reader.c it
#   comes from.
# Assumes:
#   - swipl-ld, which ships with SWI-Prolog and is therefore present wherever
#     the engine is, plus a C compiler for it to drive.
# Guarantees:
#   - it rebuilds only when reader.c is newer than reader.so, so running it
#     twice compiles once
#   - a tree with no swipl-ld, or no compiler, exits 0 with a note. The engine
#     falls back to the Prolog grammar, which is the specification the C reader
#     implements, so "not built" is a slower configuration and not an error.
#     A build that is ATTEMPTED and FAILS exits nonzero: that is the half-built
#     case, and it is the same split every decider in this tree draws.
# Open Obligations:
#   To Do: None
#   Hacks: None
#   Future Enhancements: None

set -eu

HERE=$(cd -- "$(dirname -- "$0")" && pwd)

if ! command -v swipl-ld >/dev/null 2>&1; then
    echo "engine/build.sh: swipl-ld not found; the engine will use the Prolog reader" >&2
    exit 0
fi
if ! command -v cc >/dev/null 2>&1 &&
   ! command -v gcc >/dev/null 2>&1 &&
   ! command -v clang >/dev/null 2>&1; then
    echo "engine/build.sh: swipl-ld found but no C compiler; the engine will use the Prolog reader" >&2
    exit 0
fi

if [ ! -f "$HERE/reader.so" ] || [ "$HERE/reader.c" -nt "$HERE/reader.so" ]; then
    ( cd "$HERE" && swipl-ld -shared -O2 -o reader.so reader.c )
fi
