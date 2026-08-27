#!/bin/sh
# Purpose: make a git worktree of this repository run the SAME configuration
#   the main checkout runs, by linking the build artefacts git does not track.
# Assumes:
#   - run from inside the worktree that needs setting up, and the main
#     checkout has been built (`sh build.sh`).
# Guarantees:
#   - after this, the artefact `extensions/mork/extension.pl` declares is there
#     and the MORK backend loads, so the suites gate the same configuration in
#     both trees [tested: tests/shell/test_worktree_configuration.sh].
#   - the C extension example's cbump and handle shared objects are built in
#     the worktree exactly as check.sh builds them, so a direct pytest run
#     here exercises the same integration surface instead of skipping it.
#   - engine/reader.so and engine/writer.so are built from the worktree's OWN
#     reader.c and writer.c through the same engine/build.sh check.sh drives,
#     so benchmarks and suites here measure the C-reader and C-writer
#     configuration the main gate measures: reader artifact presence alone
#     moves file-load 8704891 to 722264 with zero code change, and a worktree
#     without the artifacts silently benchmarks the Prolog fallbacks against
#     C pins [measured 2026-08-25 on a detached scratch worktree,
#     bench.py --counter-only, same commit both ways; commit=f48e9d8e6fa62eeff46082b6f8584cfe44bc5b93].
# Fails when:
#   - the main checkout has not been built. That is reported, because a
#     worktree quietly running a SMALLER configuration than the tree it was
#     cut from is the failure this script exists to prevent: a fresh
#     worktree has no extensions/mork/mork_ffi/target/ and no
#     extensions/mork/mork_ffi/morklib.so, both are gitignored build output,
#     and the artefact need in `extensions/mork/extension.pl` reads their
#     absence as "this backend was not built" rather than as an error. Every
#     suite then passes while testing one backend fewer.
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
for artefact in extensions/mork/mork_ffi/target extensions/mork/mork_ffi/morklib.so; do
    product=${artefact#extensions/mork/mork_ffi/}
    source=''
    # This product does not travel with git, which is the whole reason this
    # script exists, so a main checkout sitting on an older commit than the
    # worktree holds it under whatever path that commit used. It has moved
    # twice already -- once when the crate went into its integration's folder,
    # again when the seat folders merged -- so the crate directory is FOUND
    # under the main checkout rather than named. Refusing to link across a
    # layout change would demand a rebuild of a multi-gigabyte crate for a
    # rename.
    for candidate in "$MAIN/$artefact" \
                     "$MAIN"/*/*/mork_ffi/"$product" \
                     "$MAIN"/mork_ffi/"$product"; do
        if [ -e "$candidate" ]; then
            source=$candidate
            break
        fi
    done
    if [ -z "$source" ]; then
        echo "worktree.sh: $MAIN has no $artefact; run 'sh build.sh' there" >&2
        echo "worktree.sh: without it this worktree runs one backend fewer" >&2
        exit 1
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

# The engine's C reader and C writer are gitignored build output with their
# own gates: parses run in C only while engine/reader.so exists beside
# reader.c, and writes only while engine/writer.so exists beside writer.c.
# Build them from THIS tree's sources (not links from the main checkout, whose
# reader.c and writer.c may differ across commits), through the same
# engine/build.sh check.sh drives, with the same stance: a missing toolchain
# notes the fallback, a build failure fails loudly.
if [ -f "$HERE/engine/build.sh" ]; then
    sh "$HERE/engine/build.sh" ||
        { echo "worktree.sh: engine/build.sh failed; suites here would measure the Prolog fallbacks against C-reader and C-writer pins" >&2
          exit 1; }
fi

# Warm the engine once so the Quick Load Format artifacts generate in a
# single process before any concurrent lane first-boots this tree
# (engine/qlf_boot.pl carries the staleness and recovery story).
swipl -g halt -s "$(dirname -- "$0")/engine/main.pl" -- extensions >/dev/null 2>&1 || true
