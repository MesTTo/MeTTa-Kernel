#!/bin/sh
# Purpose: prove a git worktree of this repository runs the SAME backend
#   configuration the main checkout runs, once worktree.sh has linked the
#   build artefacts git does not track.
#
#   A fresh worktree has no mork_ffi/target/ and no mork_ffi/morklib.so,
#   both gitignored build output, and backends/mork.pl reads their absence
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

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

if [ ! -e "$project_dir/mork_ffi/target/release/libmork_ffi.so" ]; then
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
        halt" -t 'halt(1)' -- backends 2>/dev/null | tail -1
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

echo "ok: a worktree runs one backend fewer until worktree.sh links it"
