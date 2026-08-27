# A space whose atoms live in C

`cstore.c` is a mutex-guarded store of text lines; `cstore.pl` puts four
multifile clauses on the foreign-space seam and `&cstore` becomes an
ordinary space: `add-atom`, `match`, `remove-atom` and `get-atoms` reach
C with nothing engine-side knowing the backend exists. This is the
smallest native instance of the seam whose full-scale instance is MORK
(`extensions/mork/extension.pl` and `extensions/mork/mork_ffi/morkspaces.pl`).

Build it, then run the example from the repository root:

```sh
swipl-ld -shared -o examples/ch19-spaces-backed-by-anything/19-02-a-space-in-c/cstore \
                    examples/ch19-spaces-backed-by-anything/19-02-a-space-in-c/cstore.c
sh run.sh examples/ch19-spaces-backed-by-anything/19-02-a-space-in-c/01-c_space.metta
```

The example skips itself when `cstore.so` has not been built, because a
C compiler is not one of the engine's requirements. It says so when it
skips. With the artefact present it also proves itself: the conformance
kit runs inside the example (`check-space-provider`), and a `hyperpose`
block drives concurrent writers against the store's mutex.

The same provider file registers into Python (`m.register_prolog(path=...)`),
which is what
`extensions/python/tests/ch19_spaces_backed_by_anything/test_c_space.py` does
before driving it from a thread pool.

## What the provider declares, and what that costs

`cstore.pl` declares `add`, `remove`, `enumerate` and `clear`, and
deliberately no `match`: the engine filters the enumeration against a
bound pattern itself, so the C side needs no matcher at all and
unification never leaves the engine. Correct first; the cost is honest
[measured 2026-08-17, `m.stats()` inferences per operation]:

| operation | native named space | `&cstore` |
|---|---|---|
| `add-atom` through `m.run` | 625 | 867 |
| bound match over 1,000 stored atoms | 5,833 | 147,819 |

The add markup is the text write. The match figure is the text READ:
enumeration-filtering parses every stored line per query, about 140
inferences each, which is `EXTENDING.md`'s own lesson that the crossing
is cheap and the text is not. A store that wants fast bound queries
declares `seam:foreign_match/3` and filters natively, which is exactly
what `extensions/mork/mork_ffi/morkspaces.pl` does; a structure that should never
become text at all crosses as an opaque handle instead, the
`c_extension` example beside this one.

## Thread safety

Every C entry point takes the store mutex, and an enumeration walks its
own snapshot, so a concurrent add or remove never skips or doubles a
line it did not touch. The example's `hyperpose` block and the Python
suite's thread pool both drive this.
