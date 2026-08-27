#!/bin/sh
# Purpose: build the optional native artefacts this tree ships, from any working
#   directory, naming whatever it cannot find instead of continuing past it.
# Assumes:
#   - MORK and PathMap are checked out BESIDE this repository, because
#     backends/mork/mork_ffi/Cargo.toml reaches them by relative path
#     (../../../../MORK/frontend and three more). They are cloned at the
#     validated revisions when absent, which is the only reason this script
#     writes outside the repository at all; it says so when it does.
# Guarantees:
#   - running it twice does what running it once does, and leaves
#     `git status --porcelain` unchanged
#     [tested: tests/shell/test_build_is_idempotent_and_anchored.sh]
#   - it runs the same from any working directory, so `sh /path/to/PeTTa/build.sh`
#     provisions beside THIS checkout rather than beside the caller
#     [tested: tests/shell/test_build_is_idempotent_and_anchored.sh]
#   - every exit is honest. This used to have no `set -e`, so a failed cargo
#     build fell through to the next line and the run ended by printing
#     "Successfully built mork_ffi".
# Fails when:
#   - a sibling checkout sits at a revision other than its pin. Building against
#     an unvalidated MORK is the silent-wrong-build case, so it stops and prints
#     the command that restores the pin rather than producing an artefact
#     nothing here has checked.
# Open Obligations:
#   To Do: None
#   Hacks: None
#   Future Enhancements: None

set -eu

HERE=$(cd -- "$(dirname -- "$0")" && pwd)
WORKSPACE=$(dirname -- "$HERE")

command -v git >/dev/null 2>&1 || {
    echo "build.sh: git is not on PATH, and the sibling checkouts below need it" >&2
    exit 1
}

# A pinned sibling checkout, idempotently. The revision is checked on EVERY run
# and not only on the fresh clone: a directory that already exists was taken as
# correct whatever it contained, so a MORK left on another branch produced an
# artefact built against an unvalidated tree with nothing said.
provision() {
    name=$1
    url=$2
    pin=$3
    directory=$WORKSPACE/$name

    if [ ! -d "$directory" ]; then
        echo "build.sh: cloning $name beside the repository, at $directory"
        git clone --quiet "$url" "$directory"
        git -C "$directory" checkout --quiet "$pin"
        return
    fi

    at=$(git -C "$directory" rev-parse HEAD 2>/dev/null || echo "not a git checkout")
    if [ "$at" != "$pin" ]; then
        echo "build.sh: $directory is at $at," >&2
        echo "  not the validated $pin." >&2
        echo "  backends/mork/mork_ffi builds against it by relative path, so this" >&2
        echo "  would produce an artefact nothing in this tree has validated." >&2
        echo "  Restore the pin with:" >&2
        echo "    git -C $directory checkout $pin" >&2
        exit 1
    fi
}

provision MORK    https://github.com/trueagi-io/MORK            dd224fd7ced92ca9cfdacd399398dabb609e8faa
provision PathMap https://github.com/Adam-Vandervorst/PathMap   4c84a8b40c7b6a7ecb54e009a70f0c5abbc1b60f

# Each backend's own script owns its toolchain check, so this one tests only
# what IT uses (git, above) and delegates the rest.
( cd "$HERE/backends/mork/mork_ffi" && sh build.sh )

# faiss_ffi is NOT built here. It is a third-party MeTTa library, not a backend
# in this tree, and the engine already fetches it at a pinned revision through
# its own package manager -- `!(git-import! "https://github.com/patham9/faiss_ffi"
# "build.sh")`, which is what put repos/faiss_ffi there and what
# examples/ch20-extending-the-engine/20-04-modules-and-the-catalog/07-git_import2.metta
# demonstrates. This script used to clone it a second time, and because the
# clone ran after two `cd`s with no destination argument it landed in
# backends/mork/faiss_ffi: a path no ignore rule covers, so a successful build
# left an untracked vendored clone in `git status`, and a second run failed on
# "destination path already exists".
