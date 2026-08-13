# Purpose: upstream parity benchmark. Runs the example programs shared
#   with a base ref (default: the merge-base with origin/main) on both
#   engines and reports output regressions and timing. Correctness is a
#   byte comparison of stdout and exit codes under the engine's own
#   silent flag, so program output is compared, not compiler banners
#   whose cosmetics may change. SWI variable identifiers ($_12345)
#   expose allocation history, not semantics, so outputs differing only
#   in them compare equal after first-occurrence alpha renaming and are
#   reported as such; a nondeterminism double-check runs before any
#   remaining mismatch may be called a regression. Timing is interleaved
#   min-of-N wall clock per file, plus total instructions:u per side
#   when perf is available; run it on an otherwise idle machine, the
#   numbers are only as clean as the box. Both sides run plain swipl
#   with no mork preload, so the comparison isolates the engine sources.
#   Usage: sh bench.sh [BASE_REF]   (BENCH_RUNS=N to change timing runs)
#   Exits nonzero on any output regression.
# Open Obligations:
#   To Do: None
#   Hacks: None
#   Future Enhancements: None

set -u

HERE=$(cd -- "$(dirname -- "$0")" && pwd)
BASE_REF=${1:-$(git -C "$HERE" merge-base HEAD origin/main)}
RUNS=${BENCH_RUNS:-3}
FILE_TIMEOUT=300

command -v swipl >/dev/null || { echo "bench.sh: swipl not found" >&2; exit 2; }
git -C "$HERE" rev-parse --verify "$BASE_REF^{commit}" >/dev/null || {
    echo "bench.sh: base ref $BASE_REF does not resolve" >&2; exit 2; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/petta-bench.XXXXXX")
BASE="$WORK/base"
OUT="$WORK/out"
mkdir -p "$OUT/base" "$OUT/head"
trap 'git -C "$HERE" worktree remove --force "$BASE" >/dev/null 2>&1; rm -rf "$WORK"' EXIT
git -C "$HERE" worktree add --detach --quiet "$BASE" "$BASE_REF" || exit 2

echo "== upstream parity bench"
echo "head: $(git -C "$HERE" rev-parse --short HEAD)  base: $(git -C "$HERE" rev-parse --short "$BASE_REF")"

# The corpus: example programs whose bytes are identical in both refs,
# minus the interactive and hardware-bound files test.sh also skips.
# Files that exist on both sides with different bytes are named, not
# silently dropped; files only the base has would be lost coverage.
SKIP='repl.metta llm_cities.metta torch.metta greedy_chess.metta git_import2.metta torch_lib.metta'
CORPUS="$WORK/corpus.txt"
: > "$CORPUS"
changed=''
baseonly=''
for f in "$BASE"/examples/*.metta; do
    name=$(basename "$f")
    case " $SKIP " in *" $name "*) continue ;; esac
    if [ ! -f "$HERE/examples/$name" ]; then
        baseonly="$baseonly $name"
    elif cmp -s "$f" "$HERE/examples/$name"; then
        echo "$name" >> "$CORPUS"
    else
        changed="$changed $name"
    fi
done
total=$(wc -l < "$CORPUS")
echo "corpus: $total shared identical examples"
[ -n "$changed" ] && echo "differs between refs, not compared:$changed"
[ -n "$baseonly" ] && echo "WARNING, base-only examples (lost coverage):$baseonly"

# One engine run: cwd at the tree root, the relative path test.sh uses,
# plain swipl so neither side preloads mork, the engine's silent flag so
# stdout is the program's own output.
run_one() {
    tree="$1"; name="$2"
    ( cd "$tree" && timeout "$FILE_TIMEOUT" \
        swipl --stack_limit=8g -q -s src/main.pl -- "./examples/$name" silent )
}

echo "== phase 1: correctness"
# First-occurrence renaming of SWI variable identifiers, per file.
normalize_vars() {
    awk '{
        out = ""; rest = $0
        while (match(rest, /\$_[0-9]+/)) {
            id = substr(rest, RSTART, RLENGTH)
            if (!(map[id])) map[id] = "$_V" (++n)
            out = out substr(rest, 1, RSTART - 1) map[id]
            rest = substr(rest, RSTART + RLENGTH)
        }
        print out rest
    }' "$1"
}
regressions=''
nondet=''
renamed=''
while IFS= read -r name; do
    run_one "$BASE" "$name" > "$OUT/base/$name.out" 2> "$OUT/base/$name.err"
    bstat=$?
    run_one "$HERE" "$name" > "$OUT/head/$name.out" 2> "$OUT/head/$name.err"
    hstat=$?
    if [ $bstat -ne $hstat ] || ! cmp -s "$OUT/base/$name.out" "$OUT/head/$name.out"; then
        normalize_vars "$OUT/base/$name.out" > "$OUT/base/$name.norm"
        normalize_vars "$OUT/head/$name.out" > "$OUT/head/$name.norm"
        if [ $bstat -eq $hstat ] && cmp -s "$OUT/base/$name.norm" "$OUT/head/$name.norm"; then
            renamed="$renamed $name"
            continue
        fi
        run_one "$BASE" "$name" > "$OUT/base/$name.out2" 2>/dev/null
        if cmp -s "$OUT/base/$name.out" "$OUT/base/$name.out2"; then
            regressions="$regressions $name"
            echo "REGRESSION: $name (exit $bstat vs $hstat)"
            diff "$OUT/base/$name.out" "$OUT/head/$name.out" | head -20
        else
            nondet="$nondet $name"
            echo "nondeterministic on base, skipped: $name"
        fi
    fi
done < "$CORPUS"
[ -n "$renamed" ] && echo "identical after variable renaming:$renamed"
if [ -z "$regressions" ]; then
    echo "correctness: $total/$total identical stdout and exit codes${nondet:+ (nondeterministic:$nondet)}"
else
    echo "correctness FAILED:$regressions"
fi

echo "== phase 2: timing, interleaved min-of-$RUNS wall clock"
now_ms() { date +%s%N | awk '{ printf "%d", $1 / 1000000 }'; }
TIMES="$WORK/times.txt"
: > "$TIMES"
r=1
while [ "$r" -le "$RUNS" ]; do
    for side in base head; do
        [ "$side" = base ] && tree="$BASE" || tree="$HERE"
        while IFS= read -r name; do
            t0=$(now_ms)
            run_one "$tree" "$name" > /dev/null 2>&1
            t1=$(now_ms)
            echo "$side $name $((t1 - t0))" >> "$TIMES"
        done < "$CORPUS"
    done
    r=$((r + 1))
done

awk '
    { key = $1 "\t" $2 }
    !(key in best) || $3 < best[key] { best[key] = $3 }
    END {
        for (key in best) {
            split(key, part, "\t")
            if (part[1] == "base") { basetot += best[key]; b[part[2]] = best[key] }
            else                   { headtot += best[key]; h[part[2]] = best[key] }
        }
        printf "total min-of-runs: base %d ms, head %d ms, ratio %.3f\n", basetot, headtot, headtot / basetot
        worst = ""
        for (name in b) {
            d = h[name] - b[name]
            if (d > 50 && h[name] > 1.10 * b[name])
                printf "SLOWER: %s  base %d ms -> head %d ms (%+.1f%%)\n", name, b[name], h[name], 100 * d / b[name]
        }
    }
' "$TIMES"

if command -v perf >/dev/null 2>&1; then
    echo "== instructions:u totals (one sweep per side)"
    for side in base head; do
        [ "$side" = base ] && tree="$BASE" || tree="$HERE"
        count=$(
            { while IFS= read -r name; do
                  ( cd "$tree" && timeout "$FILE_TIMEOUT" \
                      perf stat -x, -e instructions:u \
                      swipl --stack_limit=8g -q -s src/main.pl -- "./examples/$name" \
                      >/dev/null 2>"$WORK/perf.csv" )
                  awk -F, '$3 == "instructions:u" { print $1 }' "$WORK/perf.csv"
              done < "$CORPUS"
            } | awk '{ sum += $1 } END { printf "%d", sum }'
        )
        echo "$side: $count instructions:u"
    done
fi

[ -z "$regressions" ] || exit 1
exit 0
