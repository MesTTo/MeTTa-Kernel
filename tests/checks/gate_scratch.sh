#!/bin/sh
# Purpose: allocate and reclaim repository-local scratch for one root gate run.
# Assumes:
#   - flock is available; without an advisory lock, a cleanup pass cannot tell
#     an orphan from a concurrent run and refuses rather than guessing.
# Guarantees:
#   - allocation exports TMPDIR, TMP and TEMP beneath ai-tmp/check-runs, and
#     the next allocation removes every unlocked run.* orphan while preserving
#     locked active runs [tested: scratch-retention;
#     commit=c96093349e37cc7153f31b3dd9af10246a325301].
# Owns resources:
#   - file descriptor 9 holds the run's lifetime lock; descriptor 7 serializes
#     allocation and descriptor 8 probes old runs. metta_gate_scratch_close
#     removes the current directory and releases its lock.
# Fails when:
#   - flock is absent, the scratch root has an unexpected run.* entry, or a
#     directory cannot be created, locked or removed.

metta_gate_scratch_run_path() {
    [ -n "${METTA_GATE_SCRATCH_BASE:-}" ] || return 1
    [ "$(dirname -- "$1")" = "$METTA_GATE_SCRATCH_BASE" ] || return 1
    case "$(basename -- "$1")" in
        run.??????) return 0 ;;
        *) return 1 ;;
    esac
}

metta_gate_scratch_open() {
    root=$1
    case "$root" in
        /*) ;;
        *) echo "gate scratch: repository root must be absolute: $root" >&2; return 2 ;;
    esac
    command -v flock >/dev/null 2>&1 || {
        echo "gate scratch: flock is required to distinguish active runs from orphans" >&2
        return 2
    }

    METTA_GATE_SCRATCH_BASE="$root/ai-tmp/check-runs"
    mkdir -p "$METTA_GATE_SCRATCH_BASE" || {
        echo "gate scratch: cannot create $METTA_GATE_SCRATCH_BASE" >&2
        return 2
    }
    # Keep the descriptor open for the full critical section. The persistent
    # space already uses this property for crash-safe ownership: the kernel
    # releases flock only after the last descriptor for its open-file
    # description closes [source: extensions/python/metta/_persistent.py,
    # _claim_journal_lock; commit=74e7a8ec5c255812742ec6ec3e3cfa843624c526].
    exec 7>"$METTA_GATE_SCRATCH_BASE/.allocation.lock" || return 2
    flock -x 7 || {
        echo "gate scratch: cannot lock the allocator" >&2
        exec 7>&-
        return 2
    }

    for candidate in "$METTA_GATE_SCRATCH_BASE"/run.*; do
        if [ ! -e "$candidate" ] && [ ! -L "$candidate" ]; then
            continue
        fi
        if [ -L "$candidate" ] || [ ! -d "$candidate" ] ||
           ! metta_gate_scratch_run_path "$candidate"; then
            echo "gate scratch: refusing unexpected run entry $candidate" >&2
            exec 7>&-
            return 2
        fi
        if ! exec 8>"$candidate/.active.lock"; then
            # A concurrent normal cleanup may remove the directory after the
            # glob. Only a still-present path is an allocation failure.
            [ ! -e "$candidate" ] && continue
            echo "gate scratch: cannot open the lifetime lock in $candidate" >&2
            exec 7>&-
            return 2
        fi
        if flock -n -E 75 8; then
            rm -rf -- "$candidate" || {
                echo "gate scratch: cannot reclaim orphan $candidate" >&2
                exec 8>&-
                exec 7>&-
                return 2
            }
        else
            lock_status=$?
            if [ "$lock_status" -ne 75 ]; then
                echo "gate scratch: cannot inspect the lifetime lock in $candidate" >&2
                exec 8>&-
                exec 7>&-
                return 2
            fi
        fi
        exec 8>&-
    done

    METTA_GATE_SCRATCH=$(mktemp -d "$METTA_GATE_SCRATCH_BASE/run.XXXXXX") || {
        echo "gate scratch: cannot allocate beneath $METTA_GATE_SCRATCH_BASE" >&2
        exec 7>&-
        return 2
    }
    exec 9>"$METTA_GATE_SCRATCH/.active.lock" || {
        echo "gate scratch: cannot open $METTA_GATE_SCRATCH/.active.lock" >&2
        exec 7>&-
        return 2
    }
    flock -x 9 || {
        echo "gate scratch: cannot claim $METTA_GATE_SCRATCH" >&2
        exec 9>&-
        exec 7>&-
        return 2
    }
    exec 7>&-

    TMPDIR=$METTA_GATE_SCRATCH
    TMP=$METTA_GATE_SCRATCH
    TEMP=$METTA_GATE_SCRATCH
    export TMPDIR TMP TEMP
}

metta_gate_scratch_close() {
    [ -n "${METTA_GATE_SCRATCH:-}" ] || return 0
    metta_gate_scratch_run_path "$METTA_GATE_SCRATCH" || {
        echo "gate scratch: refusing cleanup outside its run root: $METTA_GATE_SCRATCH" >&2
        return 2
    }
    rm -rf -- "$METTA_GATE_SCRATCH" || {
        echo "gate scratch: cannot remove $METTA_GATE_SCRATCH" >&2
        return 2
    }
    exec 9>&-
    METTA_GATE_SCRATCH=
}
