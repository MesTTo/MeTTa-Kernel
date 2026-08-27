#!/bin/sh
# Purpose: prove the engine reads its own sources and writes its own output
#   as UTF-8 whatever locale the operator booted under, and that a .qlf set
#   compiled under a different encoding is purged rather than served.
#
#   The failure this exists for is not a crash. SWI derives its default file
#   encoding from setlocale(), so one boot with LANG unset compiles every
#   non-ASCII engine atom to U+FFFD, writes that into the .qlf set, and
#   leaves the artifacts newer than every source: the poison OUTLIVES the
#   locale, and every later boot under a correct locale serves it. The
#   engine's verdict marks live in engine/metta/runtime.pl, so what a
#   poisoned tree loses is the corpus's own pass and fail marks, which
#   test.sh and the pytest example lane grep for. On 2026-08-26 that is
#   exactly what happened here: sixteen verdict lines in one example and the
#   whole pytest example lane failed on artifacts, with every source byte
#   intact.
# Guarantees:
#   - a C-locale boot on a purged tree produces a tree whose verdict marks
#     are still the real marks, in both the compiled artifacts and the
#     output stream, demonstrated by running an example afterwards.
#   - the stamp records the encoding, so a set compiled under another one is
#     purged on the next boot instead of being trusted by mtime.
# Fails when:
#   - swipl cannot start, which is reported rather than skipped: an engine
#     that will not boot is not a passing encoding test.
# Open Obligations:
#   To Do: None
#   Hacks: None
#   Future Enhancements: None
set -eu

command -v swipl >/dev/null

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

# The mark is built from its code point rather than written literally, so
# this file stays ASCII and cannot itself be the thing that breaks.
mark=$(printf '\342\234\205')

probe=$(mktemp -d)
cleanup() {
    rm -rf "$probe"
}
trap cleanup EXIT HUP INT TERM

# A scratch copy, because the test compiles artifacts under a hostile locale
# and must not leave them in the checkout it was run from.
#
# A FILTERED copy, and the filter is what makes the lane runnable rather than
# a tidiness preference. `cp -a` of the whole checkout moved 4.1 GiB, of which
# 3.0 GiB is the MORK crate's Rust target/ intermediates and 0.5 GiB is .git;
# where TMPDIR is a tmpfs the copy ran out of space and the lane reported
# "could not copy the tree" for a reason that is nothing to do with the engine
# [measured 2026-08-27: 3.0 GiB free in /tmp against a 4.1 GiB tree]. What is
# excluded is version control, tool caches and build INTERMEDIATES; every
# built backend library under target/release stays, because a probe that
# quietly loads one backend fewer is a probe of a configuration nobody ships.
tree="$probe/tree"
mkdir -p "$tree"
tar -C "$project_dir" -cf - \
    --exclude=.git --exclude=.claude --exclude=./ai-tmp \
    --exclude=__pycache__ --exclude=node_modules --exclude='*.egg-info' \
    --exclude=.hypothesis --exclude=.mypy_cache --exclude=.pytest_cache \
    --exclude=.ruff_cache --exclude=.benchmarks --exclude=.playwright-mcp \
    --exclude=./build --exclude=./dist --exclude=./repos \
    --exclude='target/debug' --exclude='target/*/deps' \
    --exclude='target/*/build' --exclude='target/*/incremental' \
    . 2>/dev/null | ( cd "$tree" && tar -xf - 2>/dev/null )
# The pipeline's status is the extractor's, so it is not the oracle here.
# What the copy is FOR is the thing to check: the engine and the example.
if [ ! -f "$tree/engine/main.pl" ] || [ ! -f "$tree/run.sh" ]; then
    echo "FAIL: could not copy the tree to probe under" >&2
    exit 1
fi

find "$tree/engine" "$tree/lib" -name '*.qlf' -delete 2>/dev/null || true
rm -f "$tree/engine/.qlf-stamp"

# The poisoning boot: no locale at all, which is what a container, a cron
# entry, or a CI runner with a scrubbed environment gives the engine.
( cd "$tree" && LC_ALL=C LANG=C swipl -g halt -s engine/main.pl -- backends ) \
    >/dev/null 2>&1 || {
    echo "FAIL: the engine did not boot under LC_ALL=C" >&2
    exit 1
}

verdicts=$( cd "$tree" && sh run.sh examples/reasoning/measure.metta 2>/dev/null |
            grep ' should ' || true )
if [ -z "$verdicts" ]; then
    echo "FAIL: the example printed no verdict lines at all, so this test" >&2
    echo "      can no longer see the property it exists for" >&2
    exit 1
fi

missing=$(printf '%s\n' "$verdicts" | grep -cv "$mark" || true)
if [ "$missing" != 0 ]; then
    echo "FAIL: $missing verdict line(s) lost the mark after a C-locale boot;" >&2
    echo "      the compiled artifacts or the output stream took the" >&2
    echo "      operator's encoding instead of the engine's own:" >&2
    printf '%s\n' "$verdicts" | grep -v "$mark" | head -3 >&2
    exit 1
fi

# The same run under a C locale reading a CORRECT set: an ASCII output
# stream does not fail, it escapes, so this half of the property needs its
# own check rather than riding on the one above.
escaped=$( cd "$tree" && LC_ALL=C LANG=C sh run.sh examples/reasoning/measure.metta 2>/dev/null |
           grep ' should ' | grep -cv "$mark" || true )
if [ "$escaped" != 0 ]; then
    echo "FAIL: $escaped verdict line(s) lost the mark when the RUN itself" >&2
    echo "      ran under LC_ALL=C, so the output stream still follows the" >&2
    echo "      locale rather than the engine's own encoding" >&2
    exit 1
fi

stamp="$tree/engine/.qlf-stamp"
if [ ! -f "$stamp" ]; then
    echo "FAIL: no .qlf stamp was written, so nothing records the" >&2
    echo "      configuration the artifacts were compiled under" >&2
    exit 1
fi
if ! grep -q 'utf8' "$stamp"; then
    echo "FAIL: the stamp does not name the encoding its artifacts were" >&2
    echo "      compiled under, so a set compiled under another one would" >&2
    echo "      be trusted on mtime alone: $(cat "$stamp")" >&2
    exit 1
fi

# A stamp from before the encoding field, which is what a tree poisoned
# before the fix carries: the next boot must purge rather than trust it.
printf 'qlf_stamp(1).\n' > "$stamp"
before=$(find "$tree/engine" -name '*.qlf' | wc -l)
( cd "$tree" && swipl -g halt -s engine/main.pl -- backends ) >/dev/null 2>&1
if ! grep -q 'utf8' "$stamp"; then
    echo "FAIL: an old-shape stamp survived a boot, so a set compiled" >&2
    echo "      under another encoding would keep being served" >&2
    exit 1
fi

echo "ok: the engine keeps its own UTF-8 whatever the locale, over" \
     "$before compiled artifacts, and the stamp carries the encoding"
