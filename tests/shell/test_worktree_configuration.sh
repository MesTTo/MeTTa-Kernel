#!/bin/sh
# Purpose: prove a git worktree of this repository runs the SAME backend
#   configuration the main checkout runs, once worktree.sh has linked the
#   build artefacts git does not track.
#
#   A fresh worktree has no extensions/mork/mork_ffi/target/ and no extensions/mork/mork_ffi/morklib.so,
#   both gitignored build output, and extensions/mork/extension.pl reads their absence
#   as "this backend was not built" rather than as an error, exactly as it
#   should for a tree that never built it. The consequence for a worktree
#   is that every suite passes while testing one backend fewer, and nothing
#   says so. This test is the thing that says so.
# Guarantees:
#   - a fresh worktree does NOT load the MORK backend, and after
#     `sh worktree.sh` it DOES, so the difference is demonstrated in both
#     directions rather than assumed.
# Fails when:
#   - the main checkout has not been built, which it reports and skips,
#     because "not built" is not the failure under test here.
# Open Obligations:
#   To Do: None
#   Hacks: None
#   Future Enhancements: None
set -eu

command -v git >/dev/null
command -v swipl >/dev/null

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)

if [ ! -e "$project_dir/extensions/mork/mork_ffi/target/release/libmork_ffi.so" ]; then
    echo "skipped: the main checkout has no MORK build to compare against"
    exit 0
fi

probe=$(mktemp -d)
tree="$probe/worktree"
branch="worktree-config-probe-$$"
cleanup() {
    git -C "$project_dir" worktree remove --force "$tree" 2>/dev/null || true
    git -C "$project_dir" branch -D "$branch" 2>/dev/null || true
    rm -rf "$probe"
}
trap cleanup EXIT HUP INT TERM

git -C "$project_dir" worktree add --quiet -b "$branch" "$tree"

# The probe asks the ENGINE whether the backend registered, rather than
# looking for a file, because the file being present is not the property
# that matters.
probe_backend() {
    swipl --stack_limit=2g -q -g "
        consult('$1/engine/main.pl'),
        ( current_predicate(mork/3) -> writeln(loaded) ; writeln(absent) ),
        halt" -t 'halt(1)' -- extensions 2>/dev/null | tail -1
}

before=$(probe_backend "$tree")
if [ "$before" != absent ]; then
    echo "FAIL: a fresh worktree already reports the backend as '$before';" >&2
    echo "      this test can no longer show the difference it exists for" >&2
    exit 1
fi

cp "$project_dir/worktree.sh" "$tree/worktree.sh"
sh "$tree/worktree.sh" >/dev/null

after=$(probe_backend "$tree")
if [ "$after" != loaded ]; then
    echo "FAIL: after worktree.sh the backend is still '$after'," >&2
    echo "      so a worktree still runs a smaller configuration" >&2
    exit 1
fi

# The backend is one of the artefacts a worktree lacks; the engine's own C is
# the other, and it is checked the same way rather than by naming a file,
# because an artefact this test did not know about is the same hole with a new
# name. Skipped where nothing can build C at all, which is the one case
# worktree.sh reports rather than fails.
if command -v swipl-ld >/dev/null 2>&1 &&
   { command -v cc >/dev/null 2>&1 || command -v gcc >/dev/null 2>&1 ||
     command -v clang >/dev/null 2>&1; }; then
    for source in "$tree"/engine/*.c; do
        [ -f "$source" ] || continue
        unit=${source%.c}
        if [ ! -f "$unit.so" ]; then
            echo "FAIL: worktree.sh left $(basename "$unit").c without its .so," >&2
            echo "      so this worktree runs that unit's Prolog fallback while" >&2
            echo "      its counters are compared against pins measured in C" >&2
            exit 1
        fi
    done
fi

echo "ok: a worktree runs one backend fewer, and no engine C, until worktree.sh provisions it"
