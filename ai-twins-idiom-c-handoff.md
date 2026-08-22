# Handoff for the integrator: branch p14-twins-idiom-c

Folders: `bindings/python/tests/twins/spaces/` (26 twins, `spaces3.py` untouched),
`syntax/` (3), `translation/` (8). Lane verdict on those 37 examples: **0
findings, twice in a row**, ruff clean, codespell clean. Coverage: spaces
26/27 files and 87/87 claims, syntax 3/3 and 20/20, translation 8/12 and 26/26.

Measurements were taken with `sh worktree.sh` run first and
`pytest -k mork` reporting 19 PASSED rather than skipped; the four worked
models land exactly on their pins in this tree (spaces3 449, identity 2289,
multicall 1441, caseconstrain 5).

## residue.json

Merge `ai-tmp-residue-c.json` from this branch: 13 `friction` entries, none of
them a duplicate of a standing entry. No new `declined` entries: every claim
every example in these folders makes is stated and proved.

### Entries that can be RETIRED on the merged tree

- `examples/spaces/mutex_and_transaction.metta`, the **three `declined`
  entries** for forms 1, 2 and 4 ("a point budget for five mutex-protected
  branches scheduled by hyperpose", and the two states that follow it). The
  twin now RUNS the hyperpose through `m.hyperpose(*targets)` and states both
  claims. The counter is not point-deterministic, but its spread is inside the
  lane's own allowance: fourteen fresh processes measured 15509-15513, spread
  4, so the pin sits at the range midpoint 15511 and every observed value is
  within 2 of it [measured 2026-08-22]. Retiring the three entries takes this
  file from 0 owed claims to 2, and the twin proves both.
- `examples/spaces/state.metta`, the `friction` entry "cross-form bind! state
  names through repeated m.eval calls". A Python variable holds the cell now,
  which is exactly what `bind!` dissolves into, and the three cell operations
  are `m.fn` calls; there is no cross-form ceremony left to record.
- `examples/spaces/matchnested.metta` and `examples/spaces/matchnested2.metta`,
  the `friction` entries "a data constructor in a compiled body that is also a
  valid Python name". These twins no longer build those equations at all: the
  rewriting is a Python loop over the subscript door (nested queries in one,
  the comma join in the other), and the only definition either file needs,
  `(= (hide $1) (empty))`, compiles. The underlying subset gap is real
  elsewhere; it no longer bites in these two files.

## Library findings worth their own rows

Each is measured on this tree, 2026-08-22, and each is filed as residue with
the detail.

1. **`petta.order_key` is not the engine's order.** It compares expression
   LENGTH first; the engine compares element by element, which is the standard
   order of the list an expression is. `msort` answers
   `((foo 42 42) (foo (42 42)))` where `sorted(key=order_key)` answers
   `((foo (42 42)) (foo 42 42))`; also `((a b c) (a (b)))` against
   `((a (b)) (a b c))` and `((w w) (x))` against `((x) (w w))`. Equal-length
   pairs agree, which is why it has stayed hidden.
2. **A space handle does not encode as its name atom.** `encode(handle)` is an
   opaque `Gnd`, so `S.evalc(term, metric)` builds `(evalc (foo) <MeTTa>)` and
   `m.fn("evalc")(term, metric)` raises `cannot write <py_Box> as MeTTa text`.
   Every engine call taking a space ARGUMENT needs `S[space.space_name]`.
3. **`space.type(atom)` does not exist.** The ledger names it and the lane's
   dissolution table names it, but `MeTTa.type` is the class-declaration
   decorator: `m.type(S.foo)` raises `AttributeError: 'Sym' object has no
   attribute '__mro__'`.
4. **`len(space)` and `(space-atom-count ...)` answer different questions on an
   inheriting space**, 6 against 3 for `inherited_spaces`. len and iteration
   agree with each other, so the Python side is self-consistent; what is
   missing is a front-store door.
5. **Refusal sentences print atoms in the wire's list form.** `&pool refused
   [secret,1]: no secrets in this pool`, where engine-exact text says
   `(secret 1)`.
6. **`collapse` to `list()` has a size threshold.** At a million answers,
   `len(fn.all(390))` costs 111,707,981 inferences and 34.8s against the
   engine's own `(length (collapse ...))` at 26,313,301 and 5.9s: 4.25x on the
   counter, 5.9x on the clock. `matespace.py` and `matespace2.py` count in the
   engine and say why.

## One lane gap

The source scan excuses string constants in the POSITIONAL arguments of
`sym/var/val/fn/space/new_space` and nowhere else, so a keyword argument that
takes a NAME cannot be written: `m.new_space(restricted=True,
grants=["file"])` is a finding. `restricted_spaces.py` writes
`grants=[S.file.name]` instead. Widening `_named_strings` to a naming call's
keyword arguments would close it.

## One reading of `test` worth documenting

MeTTa's `test` evaluates BOTH sides, so `(test (hold-pairs 1 2)
(hold-pairs 1 2))` in `translation/translatorrule_guard.metta` is weaker than
it looks: its expected value goes through the same translator rule and the
`noeval` wrapper cancels out of the comparison. Python's `assert` compares an
evaluated left against a LITERAL right, so the twin pins
`(noeval (hold-pairs 1 2))` and the wrapper that stops the expansion going
round again is visible. Several other self-comparing `test` forms in these
folders (`spacefunction`, `selfprog`, `callquoteevalreduce2`) are stronger in
the twin for the same reason.
