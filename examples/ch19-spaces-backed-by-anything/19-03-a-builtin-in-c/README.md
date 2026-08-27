# A C extension, end to end

`cbump.c` is the smallest useful C foreign predicate: `c-bump(+X, -Y)`, inputs
first and one output last, which is the calling convention MeTTa compiles every
MeTTa function into.

Build it, then run the example from the repository root:

```sh
swipl-ld -shared -o examples/ch19-spaces-backed-by-anything/19-03-a-builtin-in-c/cbump \
                    examples/ch19-spaces-backed-by-anything/19-03-a-builtin-in-c/cbump.c
sh run.sh examples/ch19-spaces-backed-by-anything/19-03-a-builtin-in-c/01-c_extension.metta
```

The example skips itself when `cbump.so` has not been built, rather than
failing, because a compiler is not part of the engine's requirements. It says
so when it skips.

Measured 2026-08-15: 6.15 inferences and 0.11us per call, against 0.13us for
the same increment as a Prolog predicate and 2.34us as a Python operation. See
`EXTENDING.md` for the whole table and for what those numbers hide.

## An opaque handle, so a structure never becomes text

`handle.c` is the other half of the C story: `vector-new`, `vector-nth`,
`vector-bump` and `vector-length` hand MeTTa an **opaque handle** to a native
vector, built on SWI's blob interface. The vector's contents never cross the
boundary; only the handle does.

```sh
swipl-ld -shared -o examples/ch19-spaces-backed-by-anything/19-03-a-builtin-in-c/handle \
                    examples/ch19-spaces-backed-by-anything/19-03-a-builtin-in-c/handle.c
sh run.sh examples/ch19-spaces-backed-by-anything/19-03-a-builtin-in-c/02-handle.metta
```

Nothing in the engine had to change for this. A blob already answers
`Grounded` to `get-metatype`, compares by identity, and prints through the
type's own callback, so it is an ordinary MeTTa value.

Measured 2026-08-16 on a thousand-element vector: reading one element through
the handle costs 0.1968us and 2.00 inferences, while writing that same vector
as text costs 389.94us and 16,906 inferences and reading it back costs 919.35us
and 44,600. The handle's cost is flat in the structure's size and the text's is
linear, which is the same shape as `transport="raw"` against the encoded path in
`EXTENDING.md`'s argument-size table.
