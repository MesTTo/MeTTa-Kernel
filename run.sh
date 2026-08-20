# Purpose: run a single MeTTa file (or the interactive demo with no file)
#   through the engine, loading every native backend that is built.
# Guarantees:
#   - `backends` names none of them: which backends exist is backends/*.pl,
#     and whether one is usable is that backend's own business. This script
#     used to test for MORK's shared library and LD_PRELOAD it, which meant
#     a second backend needed a second branch here; the backend opens its
#     own library with global visibility, so the preload was never
#     load-bearing.
#   - NO_AUTOLOAD=1 boots with set_prolog_flag(autoload, false) already in
#     effect before engine/main.pl, and so engine/metta.pl, ever loads, via
#     tests/no_autoload_boot.pl (a -g goal cannot do this: see that file's
#     header) [measured 2026-08-18: NO_AUTOLOAD=1 sh test.sh, 200/200
#     examples/ pass; unset, the default GATE_ONLY=1 sh check.sh is
#     unaffected, all 35 lanes still green].
# Open Obligations:
#   To Do: None
#   Hacks: None
#   Future Enhancements: None
SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" && pwd)
if [ "${NO_AUTOLOAD:-}" = "1" ]; then
    BOOT=$SCRIPT_DIR/tests/no_autoload_boot.pl
else
    BOOT=$SCRIPT_DIR/engine/main.pl
fi
swipl --stack_limit=8g -q -s "$BOOT" -- "$@" backends
