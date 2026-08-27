#!/bin/sh
# Purpose: one entry point with verbs, over the five root scripts that grew one
#   at a time: build.sh, check.sh, run.sh, test.sh and bench.sh.
# Assumes: each verb DELEGATES rather than reimplements. Every script it calls
#   stays runnable on its own, because the gate, CI and this repository's own
#   documentation all invoke them directly and none of that has to change for a
#   convenience to exist.
# Guarantees:
#   - `metta list` reads what is on disk and BUILDS nothing, so it answers on a
#     machine that cannot build a single component
#   - every verb's exit status is its delegate's; nothing is piped through a
#     filter on the way back, which is how a failed gate reads as success
#   - an unknown verb refuses naming the verbs that exist, rather than falling
#     through to a default
# Open Obligations:
#   To Do: None
#   Hacks: None
#   Future Enhancements: None

set -eu

HERE=$(cd -- "$(dirname -- "$0")" && pwd)

usage() {
    cat <<'EOF'
metta <verb> [argument ...]

  build [component ...]   build every component that can build here, or the named ones
  check [lane ...]        run the gate, or only the named lanes
  test  [file ...]        run the MeTTa example corpus, or the named examples
  run   <file>            run one MeTTa file through the engine
  bench [name ...]        run the benchmark suite
  list                    what components exist, and what each can do here

  Environment: GATE_ONLY=1 for check's blocking tier only; CHECK_PY to pick the
  interpreter.
EOF
}

# A component is a directory carrying at least one of the contract files. The
# same glob the engine uses for a decider and build.sh uses for a build, so a
# new seat is a folder rather than an entry in three lists.
components() {
    for candidate in "$HERE/engine" \
                     "$HERE"/backends/*/ "$HERE"/bindings/*/ \
                     "$HERE"/examples/ch19-*/; do
        directory=${candidate%/}
        [ -d "$directory" ] || continue
        if [ -f "$directory/build.sh" ] || [ -f "$directory/check.sh" ] ||
           [ -f "$directory/decider.pl" ]; then
            printf '%s\n' "$directory"
        fi
    done
}

verb_list() {
    printf '%-42s %-7s %-7s %-8s %s\n' COMPONENT BUILD CHECK DECIDER 'BUILDABLE HERE'
    components | while IFS= read -r directory; do
        name=$(printf '%s' "$directory" | sed "s|^$HERE/||")
        [ -f "$directory/build.sh" ]   && build=yes   || build=-
        [ -f "$directory/check.sh" ]   && check=yes   || check=-
        [ -f "$directory/decider.pl" ] && decider=yes || decider=-
        # Asking is the point: a component present but unbuildable here says
        # WHICH prerequisite is missing, where the gate would silently skip it.
        # Every build.sh exits 0 with a note when its toolchain is absent, so
        # this runs none of them; it reports what the note would say by testing
        # the same tools, and says "ask build.sh" when it cannot tell cheaply.
        if [ "$build" = yes ]; then
            case "$name" in
                engine|examples/ch19-*)
                    command -v swipl-ld >/dev/null 2>&1 && why=yes || why='no: swipl-ld' ;;
                bindings/cetta)
                    command -v make >/dev/null 2>&1 && command -v swipl >/dev/null 2>&1 &&
                        why=yes || why='no: make or swipl' ;;
                bindings/node)
                    if ! command -v npm >/dev/null 2>&1; then why='no: npm'
                    elif [ ! -d "$directory/node_modules" ]; then why='no: npm install'
                    else why=yes; fi ;;
                backends/mork)
                    command -v cargo >/dev/null 2>&1 && why=yes || why='no: cargo' ;;
                *) why='ask build.sh' ;;
            esac
        else
            why='-'
        fi
        printf '%-42s %-7s %-7s %-8s %s\n' "$name" "$build" "$check" "$decider" "$why"
    done
}

[ "$#" -ge 1 ] || { usage; exit 2; }
verb=$1
shift

case "$verb" in
    build) exec sh "$HERE/build.sh" "$@" ;;
    check) exec sh "$HERE/check.sh" "$@" ;;
    test)  exec sh "$HERE/test.sh"  "$@" ;;
    run)   exec sh "$HERE/run.sh"   "$@" ;;
    bench) exec sh "$HERE/bench.sh" "$@" ;;
    list)  verb_list ;;
    -h|--help|help) usage ;;
    *) echo "metta: no such verb '$verb'" >&2; usage >&2; exit 2 ;;
esac
