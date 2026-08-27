#!/bin/sh
# Purpose: make a git worktree of this repository run the SAME configuration
#   the main checkout runs, by linking the build artefacts git does not track.
# Assumes:
#   - run from inside the worktree that needs setting up, and the main
#     checkout has been built (`sh build.sh`).
# Guarantees:
#   - after this, `backends/mork/decider.pl` finds its artefact and the MORK backend
#     loads, so the suites gate the same configuration in both trees
#     [tested: tests/shell/test_worktree_configuration.sh].
#   - the C extension example's cbump and handle shared objects are built in
#     the worktree exactly as check.sh builds them, so a direct pytest run
#     here exercises the same integration surface instead of skipping it.
#   - engine/reader.so is built from the worktree's OWN reader.c exactly as
#     check.sh builds it, so benchmarks and suites here measure the C-reader
#     configuration the main gate measures: artifact presence alone moves
#     file-load 8704891 to 722264 with zero code change, and a worktree
#     without the artifact silently benchmarks the Prolog fallback against
#     C-reader pins [measured 2026-08-25 on a detached scratch worktree,
#     bench.py --counter-only, same commit both ways; commit=f48e9d8e6fa62eeff46082b6f8584cfe44bc5b93].
# Fails when:
#   - the main checkout has not been built. That is reported, because a
#     worktree quietly running a SMALLER configuration than the tree it was
#     cut from is the failure this script exists to prevent: a fresh
#     worktree has no backends/mork/mork_ffi/target/ and no backends/mork/mork_ffi/morklib.so, both are
#     gitignored build output, and `backends/mork/decider.pl` reads their absence as
#     "this backend was not built" rather than as an error. Every suite then
#     passes while testing one backend fewer.
# Open Obligations:
#   To Do: None
#   Hacks: None
#   Future Enhancements: None
set -eu

HERE=$(cd -- "$(dirname -- "$0")" && pwd)

# The main checkout is the first line of `git worktree list`, which git
# guarantees is the primary one. Deriving it beats naming a path, so this
# keeps working wherever the repository lives.
MAIN=$(cd "$HERE" && git worktree list | head -1 | awk '{print $1}')

if [ "$MAIN" = "$HERE" ]; then
    echo "worktree.sh: this IS the main checkout; nothing to link" >&2
    exit 0
fi

linked=0
for artefact in backends/mork/mork_ffi/target backends/mork/mork_ffi/morklib.so; do
    source="$MAIN/$artefact"
    if [ ! -e "$source" ]; then
        # A main checkout from before the tree partition holds the same
        # build product at the crate's old top-level home; link across the
        # rename rather than demanding a rebuild for a layout change.
        legacy="$MAIN/mork_ffi/${artefact#backends/mork/mork_ffi/}"
        if [ -e "$legacy" ]; then
            source="$legacy"
        else
            echo "worktree.sh: $MAIN has no $artefact; run 'sh build.sh' there" >&2
            echo "worktree.sh: without it this worktree runs one backend fewer" >&2
            exit 1
        fi
    fi
    mkdir -p "$(dirname "$HERE/$artefact")"
    ln -sfn "$source" "$HERE/$artefact"
    linked=$((linked + 1))
done

echo "worktree.sh: linked $linked artefact(s) from $MAIN"

# The C extension example's shared objects are build output check.sh compiles
# on every run; a worktree used for DIRECT suite runs needs them too, or the
# example and its tests quietly skip. Same recipe, same tolerance for a
# missing toolchain.
if command -v swipl-ld >/dev/null 2>&1; then
    for source in "$HERE"/examples/ch19-*/*/*.c; do
        [ -f "$source" ] || continue
        directory=$(dirname "$source")
        unit=$(basename "$source" .c)
        ( cd "$directory" && swipl-ld -shared -o "$unit" "$unit.c" ) ||
            echo "worktree.sh: the C example $unit failed to build" >&2
    done
else
    echo "worktree.sh: swipl-ld not found, the chapter 19 C examples will skip" >&2
fi

# The engine's C reader is gitignored build output with its own gate: parses
# run in C only while engine/reader.so exists beside reader.c. Build it from
# THIS tree's source (not a link from the main checkout, whose reader.c may
# differ across commits), with check.sh's exact recipe and stance: a missing
# toolchain notes the fallback, a build failure fails loudly.
if [ -f "$HERE/engine/reader.c" ]; then
    if ! command -v swipl-ld >/dev/null 2>&1; then
        echo "worktree.sh: swipl-ld not found, this worktree runs the Prolog reader fallback and its counters will not compare against C-reader pins" >&2
    elif ! command -v cc >/dev/null 2>&1 &&
         ! command -v gcc >/dev/null 2>&1 &&
         ! command -v clang >/dev/null 2>&1; then
        # swipl-ld drives a C compiler it does not carry; without one the
        # build fails, so this rung notes the fallback the same way
        # check.sh's consolidated build_engine_reader does.
        echo "worktree.sh: swipl-ld found but no C compiler, this worktree runs the Prolog reader fallback and its counters will not compare against C-reader pins" >&2
    elif [ ! -f "$HERE/engine/reader.so" ] ||
         [ "$HERE/engine/reader.c" -nt "$HERE/engine/reader.so" ]; then
        ( cd "$HERE/engine" && swipl-ld -shared -O2 -o reader.so reader.c ) ||
            { echo "worktree.sh: engine/reader.c failed to build; suites here would measure the Prolog fallback against C-reader pins" >&2
              exit 1; }
    fi
fi

# Warm the engine once so the Quick Load Format artifacts generate in a
# single process before any concurrent lane first-boots this tree
# (engine/qlf_boot.pl carries the staleness and recovery story).
swipl -g halt -s "$(dirname -- "$0")/engine/main.pl" -- backends >/dev/null 2>&1 || true
