#!/bin/sh
set -eu

command -v uv >/dev/null
command -v swipl >/dev/null

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT HUP INT TERM

uv build --wheel --out-dir "$fixture/dist" "$project_dir"
wheel=$(find "$fixture/dist" -name 'petta-*.whl' -print -quit)
uv venv "$fixture/venv"
uv pip install --python "$fixture/venv/bin/python" --no-deps "$wheel"
test -x "$fixture/venv/bin/petta"

mkdir "$fixture/unrelated cwd"
printf '!(+ 1 1)\n' > "$fixture/basic.metta"
printf '!(import! &self (library lib_import))\n' > "$fixture/import.metta"
printf '!(import! &self (library lib_roman))\n!(map-flat (+ 1) (1 2 3))\n' \
    > "$fixture/roman.metta"

(
    cd "$fixture/unrelated cwd"
    unset PETTA_PATH
    "$fixture/venv/bin/petta" "$fixture/basic.metta" > "$fixture/basic.log"
    "$fixture/venv/bin/petta" "$fixture/import.metta" > "$fixture/import.log"
    "$fixture/venv/bin/petta" "$fixture/roman.metta" > "$fixture/roman.log"
)

grep -Fxq '2' "$fixture/basic.log"
grep -Fq '(2 3 4)' "$fixture/roman.log"

# The runtime tree an installed PeTTa has to find, checked in the install
# rather than in the checkout. backends/ is here because the engine GLOBS it on
# every boot and expand_file_name/2 answers [] for a missing directory exactly
# as it does for one holding no built backend: an unshipped seam and an unbuilt
# backend are the same thing at run time, so nothing but a packaging check
# tells them apart. setup.py did not ship it until 2026-08-17, which made
# EXTENDING.md's "a backend is a file in backends/" false for every wheel.
"$fixture/venv/bin/python" - <<'PY'
from pathlib import Path
import petta

runtime = Path(petta.__file__).parent / "_runtime"
for required in ("engine", "lib", "backends"):
    assert (runtime / required).is_dir(), f"{required}/ is missing from the wheel"
assert list((runtime / "backends").glob("*.pl")), "backends/ shipped empty"
PY

echo "packaged petta CLI tests passed"
