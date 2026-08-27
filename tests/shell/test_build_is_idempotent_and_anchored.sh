#!/bin/sh
# Purpose: prove build.sh can be run twice, from anywhere, without dirtying the
#   working tree, and that a build which cannot happen says so instead of
#   reporting success.
#
#   Every property here is a defect this file was written against. build.sh had
#   no `set -e`, so a failed cargo build fell through to the next line; it
#   resolved `../MORK` and `cd ./backends/...` against the CALLER's working
#   directory, so running it by absolute path provisioned beside the caller; and
#   its last four lines cloned faiss_ffi with no destination argument after two
#   `cd`s, which landed a whole vendored checkout in backends/mork/faiss_ffi --
#   a path no ignore rule covers, so one successful run dirtied `git status` and
#   the next failed on "destination path already exists".
# Guarantees:
#   - two consecutive runs from a directory that is not the repository root both
#     exit 0 and leave `git status --porcelain` byte-identical
#   - backends/mork/faiss_ffi does not appear
#   - backends/mork/mork_ffi/build.sh with no toolchain on PATH exits nonzero and
#     NAMES what it could not find, where it used to print
#     "Successfully built mork_ffi" whatever happened
# Fails when:
#   - nothing here reaches the network. A checkout missing its MORK/PathMap
#     siblings, or missing a MORK build, is reported and skipped, because
#     provisioning is not the property under test.
# Open Obligations:
#   To Do: None
#   Hacks: None
#   Future Enhancements: None
set -eu

command -v git >/dev/null

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
workspace=$(dirname -- "$project_dir")

# Skip rather than provision: build.sh clones the siblings when they are absent,
# and a gate that reaches the network fails for a reason that is not the tree.
for sibling in MORK PathMap; do
    if [ ! -d "$workspace/$sibling" ]; then
        echo "skipped: $workspace/$sibling is absent, and this test must not clone it"
        exit 0
    fi
done
if [ ! -e "$project_dir/backends/mork/mork_ffi/target/release/libmork_ffi.so" ]; then
    echo "skipped: no MORK build here, so a run would be a full compile rather than a re-run"
    exit 0
fi

before=$(git -C "$project_dir" status --porcelain)

# Anywhere but the repository root, which is the whole point: an unanchored
# script reads ../MORK relative to THIS directory.
elsewhere=$(mktemp -d)
cleanup() { rm -rf "$elsewhere"; }
trap cleanup EXIT HUP INT TERM

run=1
while [ "$run" -le 2 ]; do
    if ! ( cd "$elsewhere" && sh "$project_dir/build.sh" >"$elsewhere/run$run.log" 2>&1 ); then
        echo "FAIL: run $run of build.sh exited nonzero" >&2
        cat "$elsewhere/run$run.log" >&2
        exit 1
    fi
    run=$((run + 1))
done

after=$(git -C "$project_dir" status --porcelain)
if [ "$before" != "$after" ]; then
    echo "FAIL: build.sh changed the working tree" >&2
    echo "--- before ---" >&2; printf '%s\n' "$before" >&2
    echo "--- after ----" >&2; printf '%s\n' "$after" >&2
    exit 1
fi

if [ -e "$project_dir/backends/mork/faiss_ffi" ]; then
    echo "FAIL: backends/mork/faiss_ffi is back; the destination-less clone returned" >&2
    exit 1
fi

# The honesty half, and it needs no compiler precisely because it is about what
# happens when there is none. /bin/sh by absolute path, because `PATH=... cmd`
# applies to the lookup of cmd itself.
if PATH=/nonexistent /bin/sh "$project_dir/backends/mork/mork_ffi/build.sh" \
       >"$elsewhere/toolless.log" 2>&1; then
    echo "FAIL: mork_ffi/build.sh reported success with no toolchain on PATH" >&2
    cat "$elsewhere/toolless.log" >&2
    exit 1
fi
if ! grep -q "missing:" "$elsewhere/toolless.log"; then
    echo "FAIL: mork_ffi/build.sh failed without naming what was missing" >&2
    cat "$elsewhere/toolless.log" >&2
    exit 1
fi
if grep -q "Successfully built" "$elsewhere/toolless.log"; then
    echo "FAIL: mork_ffi/build.sh claimed success on a run that failed" >&2
    exit 1
fi

echo "OK: build.sh is idempotent, anchored, tree-clean, and honest when it cannot build"
