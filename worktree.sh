#!/bin/sh
# Purpose: make a git worktree of this repository run the SAME configuration
#   the main checkout runs, by linking the build artefacts git does not track.
# Assumes:
#   - run from inside the worktree that needs setting up, and the main
#     checkout has been built (`sh build.sh`).
# Guarantees:
#   - after this, `backends/mork.pl` finds its artefact and the MORK backend
#     loads, so the suites gate the same configuration in both trees
#     [tested: tests/test_worktree_configuration.sh].
# Fails when:
#   - the main checkout has not been built. That is reported, because a
#     worktree quietly running a SMALLER configuration than the tree it was
#     cut from is the failure this script exists to prevent: a fresh
#     worktree has no mork_ffi/target/ and no mork_ffi/morklib.so, both are
#     gitignored build output, and `backends/mork.pl` reads their absence as
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
for artefact in mork_ffi/target mork_ffi/morklib.so; do
    source="$MAIN/$artefact"
    if [ ! -e "$source" ]; then
        echo "worktree.sh: $MAIN has no $artefact; run 'sh build.sh' there" >&2
        echo "worktree.sh: without it this worktree runs one backend fewer" >&2
        exit 1
    fi
    mkdir -p "$(dirname "$HERE/$artefact")"
    ln -sfn "$source" "$HERE/$artefact"
    linked=$((linked + 1))
done

echo "worktree.sh: linked $linked artefact(s) from $MAIN"
