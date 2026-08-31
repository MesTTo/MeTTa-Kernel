# Purpose: choose the one interpreter every runner in this tree uses, and point
#   SWI's Janus bridge at it, so a script run BY HAND behaves the way the gate
#   runs it.
# Assumes: it is SOURCED, not executed, with $METTA_ROOT naming the repository
#   root. Sourcing is what lets it set $PY in the caller and refuse by the
#   CALLER's name, which is the name a developer typed.
# Guarantees:
#   - $PY names an interpreter: $CHECK_PY when set, then this box's
#     .venv-pypetta, then a .venv beside the checkout, then python3
#   - VIRTUAL_ENV and PATH are exported when $PY belongs to a virtual
#     environment, because Janus follows VIRTUAL_ENV rather than the executable
#     a script chose: engine/test.sh had no selection at all and its 18
#     shim_python_scalar_semantics cases failed with "No module named
#     'docstring_parser'" when a developer ran it directly, while the same file
#     passed under check.sh, which exports the variable
#     [measured 2026-08-31: sh engine/test.sh exits 1 with 18 failures and
#     VIRTUAL_ENV=... sh engine/test.sh exits 0 with none; commit=WORKTREE]
#   - $PY is EMPTY when no interpreter answers, and what that means is the
#     caller's to say: a test lane refuses, a benchmark lane skips, and
#     engine/test.sh only ever wanted the exported environment
# Fails when: executed rather than sourced. It sets shell variables and has no
#   effect of its own.
# Open Obligations:
#   To Do: None
#   Hacks: None
#   Future Enhancements: None

PY=${CHECK_PY:-}
if [ -z "$PY" ]; then
    for metta_python_candidate in \
        "$HOME/Dev/.venv-pypetta/bin/python" \
        "${METTA_ROOT:-.}/.venv/bin/python" \
        python3
    do
        if command -v "$metta_python_candidate" >/dev/null 2>&1; then
            PY="$metta_python_candidate"
            break
        fi
    done
    unset metta_python_candidate
fi
if command -v "$PY" >/dev/null 2>&1; then
    # The prefix is the interpreter's own, two directories up from bin/python,
    # and pyvenv.cfg is what makes it a virtual environment rather than a
    # system one.
    METTA_CHECK_PREFIX=$(dirname "$(dirname "$PY")")
    if [ -f "$METTA_CHECK_PREFIX/pyvenv.cfg" ]; then
        VIRTUAL_ENV="$METTA_CHECK_PREFIX"
        PATH="$METTA_CHECK_PREFIX/bin:$PATH"
        export VIRTUAL_ENV PATH
    fi
else
    PY=""
fi
