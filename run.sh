SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" && pwd)
# `backends` asks the engine to load every native backend that is built. It
# names none of them: which backends exist is backends/*.pl, and whether one is
# usable is that backend's own business. This script used to test for MORK's
# shared library and LD_PRELOAD it, which meant a second backend needed a
# second branch here; the backend opens its own library with global visibility,
# so the preload was never load-bearing.
swipl --stack_limit=8g -q -s $SCRIPT_DIR/src/main.pl -- "$@" backends
