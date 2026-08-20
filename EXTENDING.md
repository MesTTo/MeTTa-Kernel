# Extending PeTTa without forking it

PeTTa has eight extension points. You should not need to change the engine to
add a feature, and you should not have to guess which mechanism to reach for.
This page lists them in order of runtime cost, measured rather than asserted,
and says what each one is actually for.

The short version: **C, Prolog, macros and compiled Python all cost about what
a MeTTa function costs, and a Python operation costs the janus crossing.** Pick
by how hot the code is, and by which language the work is already in.

## What each one costs

Measured by `bindings/python/benchmarks/extension_cost.py`, which `check.sh` re-runs as
a GATE against a committed baseline, so these numbers cannot drift at all.
Every tier is measured in one process against one driver shape, and the driver's own cost is measured
separately and subtracted, so a row is the marginal cost of **one call** rather
than of the loop around it.

| extension point | inferences/call | vs MeTTa | microseconds/call | vs MeTTa |
|---|---|---|---|---|
| C foreign predicate | 1.00 | 0.33x | 0.02 | 0.41x |
| translator rule (a macro) | 2.00 | 0.67x | 0.04 | 0.79x |
| Prolog grounded predicate | 2.00 | 0.67x | 0.04 | 0.78x |
| ordinary MeTTa function | 3.00 | 1.00x | 0.05 | 1.00x |
| `@m.define`, annotated | 3.00 | 1.00x | 0.05 | 1.06x |
| `@m.define`, no annotations | 3.01 | 1.00x | 0.05 | 1.00x |
| Python operation, `raw=True` | 6.00 | 2.00x | 0.87 | 16.71x |
| Python operation, encoded | 13.01 | 4.33x | 1.99 | 38.34x |

One run's output, not a best-of: the columns divide by each other, so mixing
runs would give ratios no run measured. The inference column is exact and the
microsecond column is not, because the four native tiers land near the timer's
resolution and this box is rarely idle. Read the first for the comparison and
the second for the order of magnitude.

How much the second column moves is worth a number rather than a warning. The
annotated `@m.define` row came out at 1.06x here and at 1.09x, 1.45x and 1.66x
on other runs minutes apart, on a box at the same load, while its inference
figure was 3.00 on every one. Any native-tier ratio here inside about 2x is
timer noise.

Read both columns, because each one hides something.

The write door has its own table, in the same harness against the same
committed baseline: what an `add-atom` costs once something claims the
space it writes into. The hook row is the price of consulting an
arbitrary-MeTTa policy per write, paid only by the space that asked; the
handler's call site is translated once when the claim is made, not per
write, which is what holds the row at this size. The pool rows go through
the shipped `declare_admits` and `declare_capacity` surface, which claims
the pool's pre-add hook with the `space-admission-verdict` judge; a space
nothing claimed keeps the direct write path, which is why the plain row
fell from 49.01 when the old global admission wrapper came off.

| write door | inferences/add | vs plain add |
|---|---|---|
| add-atom, no claims on the space | 29.01 | 1.00x |
| add-atom through an accept-all pre-add hook | 39.02 | 1.34x |
| add-atom into a pool with a declared admits type | 51.01 | 1.76x |
| add-atom into a pool with a declared capacity | 60.01 | 2.07x |

The capacity row used to read 4569.69 at a thousand held atoms and grew
with every one, because the bespoke check counted the pool by enumeration
per add. A native capacity claim now installs one rollback-safe dynamic
count, updated only on that pool's accepted writes and reset by its removal
and clear doors. The judge reads the indexed fact in 3.00 inferences, so the
row's cost no longer depends on either the atom count or the number of stored
arities. A pool with no capacity claim owns no counter, and a space with no
hook claim never probes for one; the 29.01 plain row is therefore unchanged.
The admits and capacity rows also read their fixed contract heads directly,
ground type witnesses take an indexed declaration hit before their exact
fallback, and a compiled hook fire already in its declaring module skips the
module switch.

**Inferences understate Python.** The janus crossing counts as one inference
and costs real microseconds, so inferences say a raw Python operation is 1.7
times a MeTTa function while wall clock says **more than ten times**, the one
figure here that moves with the box's load. If you are deciding whether to
move a hot loop out of Python, trust the microseconds.

**Inferences flatter C.** A foreign predicate is one inference no matter how
much work it does inside, so the 1.00 above measures the call, not the
computation. C wins on this table because the operation is trivial; what it
actually buys you is that the work inside is invisible to the Prolog engine.

**Inferences no longer see a type check at all.** This is the one row where
the exact column is the misleading one, so read it carefully before concluding
that annotating is free.

`@m.define` compiles Python into MeTTa equations, and with no annotations it
costs exactly what the hand-written equation costs. Annotate it and the
generated `(: f (-> Number Number))` sends every call through typed dispatch,
which emits a check per argument and one on the result. That used to read as
3.01 against 11.00 in this table.

The compiler now settles most of that at compile time. A literal argument's
type is decided while the call site compiles, so no check is emitted for it,
and a call whose arguments are all literals of the declared types compiles to
exactly what the untyped one does. A check it cannot drop it specialises
instead: `Number`, `String` and `Bool` are each decided by one Prolog builtin,
and the declared type is known while compiling, so `number/1` goes in front of
the general lookup.

SWI compiles `number/1` to a VM instruction and does not count it as an
inference. So the first column now says 3.00, the same as an ordinary MeTTa
function, and **that is a fact about the counter rather than about the work**.
The check still runs. Measured in retired instructions on a workload that is
nothing but declared calls with unknown arguments, it is 6,390,131,589 with
the specialisation and 9,219,256,868 without, so about 30% of that workload is
still the checking. `check.sh` gates that number as the `typed-call` case, for
exactly the reason this paragraph exists: the inference gate every other row
relies on is blind here.

So: declare types where you want the checking. It is much cheaper than it was
and it is not free, a literal argument costs nothing, and a parameter you do
not mean to constrain can be declared `%Undefined%`, which emits no check at
all.

**The Python operation has two paths and they are not close.** `raw=True`
skips the wire encoding both ways. The encoded path WALKS the term, so the
single number above is its best case, on a one-argument integer:

| argument | encoded | `raw=True` | ratio |
|---|---|---|---|
| integer | 13.00 | 6.00 | 2.17x |
| flat, 4 items | 24.00 | 6.00 | 4.00x |
| flat, 16 items | 48.00 | 6.00 | 8.00x |
| flat, 64 items | 144.00 | 6.00 | 24.00x |
| nested, depth 4 | 46.00 | 6.00 | 7.67x |
| nested, depth 8 | 78.00 | 6.00 | 13.00x |

The raw path is **flat whatever the argument is**. The encoded one costs about
two inferences per flat item and about eight per nesting level, so a 64-item
list through an encoded operation costs 144 inferences against a Prolog
predicate's 2.

One of the raw path's six inferences is the catch that turns a Python failure
into a MeTTa error naming your call. It is the floor rather than a choice, the
manual putting `catch/3` at "comparable to `call/1`", and against a crossing
that costs 0.87 microseconds where a MeTTa function costs 0.05, it is not the
number that decides anything. What `raw=True` gives up is the symbol-string distinction:
symbols reach a raw operation as plain strings. `pettorch` uses it throughout
for exactly this reason.

The four native tiers are within two inferences of each other, so choose
between them on what the code is, not on speed: a macro when the shape is
known at compile time, Prolog when you are writing new logic, C when you are
wrapping something that already exists in C or Rust, and `@m.define` when the
logic is easier to say in Python than in MeTTa.

The macro row is the only one that can go lower than it says. Its 2.00 is the
cost of the code it emitted, and a rule that settles the answer at compile time
emits no code at all, leaving a fact to look up. *Writing the rule in Prolog*
below is how a library reaches that.

## 1. Translator rules: macros, and they cost nothing at all

`add-translator-rule!` makes a MeTTa function run at **compile time**. Whatever
it returns, quoted, becomes the compiled code. The call is not there at
runtime.

```metta
(: for (-> Atom Atom Atom %Undefined%))
(= (for $var $collection $body)
   (quote (let $var (superpose $collection) $body)))

!(add-translator-rule! for)

(= (myfun $L)
   (for $x $L (if (== (% $x 2) 0) (even $x) (odd $x))))
```

`for` is now part of the language. Nobody forked the engine to add it.

That it really disappears is visible in the compiled clause. Given

```metta
(= (inc $x) (quote (+ $x 1)))
!(add-translator-rule! inc)
(= (uses-macro $n) (inc $n))
```

the engine compiles `uses-macro` to

```prolog
'uses-macro'(A, B) :- +(A, 1, B).
```

The macro is gone. This is the right tool for new syntax, for control forms,
and for anything where the shape is known when the program is written.

Examples: `examples/translation/translatorrule.metta`,
`translatorrule_for.metta`, `translatorrule_fib.metta`, and `lib_patrick.metta`
and `lib_spaces.metta` in the library tree.

### Writing the rule in Prolog, and deciding how your forms compile

A rule runs as a Prolog predicate. The translator appends one argument for the
expansion and calls it, so a rule whose MeTTa body is a single call to a
registered predicate has all of its logic in Prolog. Combined with
`translatePredicate`, which compiles one goal inline, that is a library
deciding how its own forms compile rather than only what they mean.

Here is a planner that fuses a scale into an add:

```prolog
% in your library's .pl file
'vs-plan'(Form, Out, Goal) :-
    (   Form = ['vec-add', Inner, W], nonvar(Inner),
        Inner = ['vec-scale', V, K]
    ->  Goal = ['translatePredicate', ['vec_saxpy', K, V, W, Out]]
    ;   Form = ['vec-add', A, B]
    ->  Goal = ['translatePredicate', ['vec_add', A, B, Out]]
    ;   Form = ['vec-scale', V, K]
    ->  Goal = ['translatePredicate', ['vec_scale', K, V, Out]]
    ).
```

```metta
(: vecop (-> Atom Atom %Undefined%))
(= (vecop $form $out) (vs-plan $form $out))
!(add-translator-rule! vecop)
```

`(vecop (vec-add (vec-scale $v $k) $w) $z)` now compiles to a single
`vec_saxpy` goal, and the intermediate vector the two-step spelling would build
is never created. Over 500-element vectors the fused form ran 68,161 inferences
against 69,176 for the same result written as two `vecop` calls, which is the
one traversal it removed [measured 2026-08-16].

Because the rule runs at compile time it can also settle the answer outright.
A planner that computes a ground result emits a unification instead of a call:

```prolog
'add-plan'(A, B, Out, Goal) :-
    (   integer(A), integer(B)
    ->  C is A + B, Goal = ['translatePredicate', ['=', Out, C]]
    ;   Goal = ['translatePredicate', ['plus', A, B, Out]] ).
```

Given `(= (twenty-two-more) (progn (addop 20 22 $z) $z))` the equation compiles
to a fact, and the same rule still emits a real goal where it cannot fold:

```prolog
'twenty-two-more'(42).
'at-runtime'(A, B, C) :- plus(A, B, C).
```

Three things make this work, and each is easy to get wrong.

Declare the form's parameters `Atom`, as *Taking an argument unevaluated* below
describes, or the translator evaluates them before your rule sees them and a
planner meaning to inspect `(vec-scale $v $k)` receives that vector's value.

Guard every shape test with `nonvar/1` first. A planner sees unbound subterms
whenever a value comes from an earlier goal, and `['vec-add', S, W]` with `S`
unbound unifies happily with the fused shape, so the rule emits a scale that
never happens.

Return the form itself, with no `quote` around it. A rule written in MeTTa
evaluates its own `quote` and expands to whatever `quote` returned; a rule that
builds the term in Prolog is already holding that term, so quoting it there
hands the translator a list it can only read as data. The engine refuses that
by name, as it refuses a `translatePredicate` or `call` whose shape it cannot
compile. Both used to be silent, answering an unbound variable or a data list
named after the form.

## 2. Prolog grounded predicates: new primitives, native speed

A predicate follows the compiled calling convention, inputs then one output,
and is registered from MeTTa:

```metta
!(import! &self (library lib_import))
!(import_prolog_functions_from_file (library lib_mine.pl) (my-op other-op))
```

No boundary is crossed: the engine is Prolog, so this is an ordinary call. Use
it for anything that needs a real implementation and is called often. Every
library in `lib/` that is not pure MeTTa works this way, including `lib_string`,
`lib_file`, `lib_json` and `lib_thread`.

### What the interface guarantees

A registered predicate is compiled into a direct call. `(my-double 21)` becomes
`'my-double'(21, A)`, with no dispatch and no boundary in between, and its
**nondeterminism is the MeTTa function's answer set**: a predicate that offers
three solutions gives `(collapse (my-pick 7))` the answer `(7 7 7)`.

Two things it refuses rather than doing quietly, because both used to produce a
silent wrong answer:

- **A name with no predicate behind it.** A registration records the arities
  the name is callable at, so a name with nothing behind it records none, and
  `incomplete_application_kind/3` reads a missing arity as "not applied far
  enough": every later call compiled into a *partial application* instead of
  failing. `!(no-such-predicate 1)` answered `(partial no-such-predicate (1))`
  and the import reported success. It raises now, where the name is written.
- **A file that is not there.** `consult/1` throws
  `existence_error(source_sink, Path)` and names the file; an `exists_file/1`
  guard used to swallow that and leave the import failing silently.
- **A source that does not load cleanly.** SWI PRINTS a syntax error inside a
  consulted file and the load then succeeds with the predicate undefined, so
  the author's whole diagnostic used to be one line on stderr while the API
  reported success. The load now raises with the file, the line and the
  column.

The same rule catches a subtler case: your predicate must be in the HOST
module, `user`, which is where `consult_global/1` puts it. A Prolog library
loaded from inside a named space defines itself in that space's module, where
the registration cannot see it, and every call to it used to compile to a
partial application. That is an error too.

`user` is the host, and it is no longer where MeTTa code lives. Every space,
`&self` included, compiles its equations into a module of its own, which
`space_module/2` names, and those modules inherit the engine's and through it
`user`. So a predicate you consult into `user` is reachable from every space,
and an equation a program writes cannot replace it: the equation lands in the
space's own module and shadows it there. Two consequences for an extension:

- Ask `space_module/2` for a module; never write one. `with_metta_module/2`
  takes that module, and it REFUSES a space name, because the two are
  different atoms now and passing the wrong one would silently run your goal
  against a module nothing compiles into.
- If you call a MeTTa function from Prolog, qualify it with that module. An
  unqualified call resolves where YOUR clause was compiled, which for a
  consulted extension is `user`, and `user` is the parent: it cannot see a
  space's clauses. If you hand a goal to one of the engine's own predicates
  instead, the engine's `meta_predicate` declarations carry the module for
  you.

A registration also records WHERE its clauses live, which is what keeps it
working after a space defines an equation of the same name. Without that, one
named space claiming a name turned every registered predicate into inert data
in every space, silently, from code that had not changed. That space's own
equation still shadows it, which is the behaviour that should happen.

### Add a builtin type without replacing the type table

A Prolog library may add an intrinsic type by contributing one clause to the
`builtin_type_declaration/2` declaration seam:

```prolog
:- metta_extension(my_blob_types, [version('0.1.0')]).
builtin_type_declaration('my-blob', 'MyBlob').
```

Do not redeclare the predicate in the library. The engine declares it
`multifile`, so this clause joins the builtins parsed from
`lib_builtin_types.metta`; unloading the extension removes only the library's
clause. The engine's other arrows remain present before, during, and after the
extension's lifetime [tested:
`test_a_library_types_its_own_blob_without_destroying_the_table`;
commit=1a5459b9e81b168ee402bf9eda2c407e55f7eae0].

### Taking an argument unevaluated

Declare the parameter `Atom` and the argument arrives as written:

```metta
(: shape-of (-> Atom Atom))
!(shape-of (+ 1 2))            ; the predicate sees (+ 1 2), not 3
```

This is what a control form needs, and it is not Python-only: it works on a
Prolog-registered predicate exactly as it does on a Python one. Minimal MeTTa's
`function` and `unify-mod` are built on it, which is how the whole instruction
set moved out of Python. Measured 2026-08-15: `(function (return 42))` cost
36.14 inferences and 3.95us as a Python operation and 11.14 and 0.21us as a
Prolog predicate, so 3.2x fewer inferences and 18.8x faster.

Declare it only where you mean it. An operation whose argument must arrive
*evaluated* and is declared `Atom` receives the literal expression instead of
its value, which is a silent wrong answer rather than an error.

The same distinction is visible at the Python decorator. Given
`(= (side) 42)`, a registered `def anyatom(x: petta.Atom)` receives and may
return `(side)`, while an otherwise identical unannotated `def anyval(x)`
receives `42`. The annotation therefore changes the call's evaluation order;
it is not documentation applied after evaluation.

### Calling a Prolog goal without registering anything

Registration publishes a name. For a goal you do not want to publish, or a
one-off, MeTTa can reach Prolog three ways, and they do not cost the same.

**`(call (goal ...))` compiles straight into the clause body and needs no
registration at all.** It follows the same convention, inputs then one output:

```metta
!(call (succ_or_zero 3))       ; compiles to succ_or_zero(3, Out)
```

This is the right reach for a one-off and for a predicate a library does not
want to publish as a MeTTa function. `translatePredicate` is the same idea
with the output slot written out:

```metta
!(progn (translatePredicate (is $x 2))
        (translatePredicate (+ $x 40 $z))
        $z)                              ; 42
```

`translatePredicate` is written for its BINDINGS rather than its value: it
compiles the goal inline and leaves the variables bound for the rest of the
form, which is why it appears inside a `progn`.

Both are live in the tree: `lib/lib_tabling.metta`, `lib/lib_spaces.metta`,
`examples/translation/callquoteevalreduce.metta` and
`examples/translation/translatepredicate.metta`.

**`(callPredicate (Predicate ...))` builds the goal term at run time** through
`=../2` and meta-calls it, which costs about five inferences more than the two
above:

```metta
(= (consult_file $prologfile)
   (callPredicate (Predicate (quote (consult_global $prologfile)))))
```

`quote` matters here and is not optional decoration. `Predicate` is an
ordinary registered function, so **its argument is evaluated first**. When the
goal names something that is also a MeTTa function, the unquoted form applies
that function and raises a domain error naming arities you never wrote. Quote
it and the goal reaches `Predicate` as written. `assertaPredicate`,
`assertzPredicate` and `retractPredicate` are the same idea for the database.

### Arguments are bidirectional, and the output slot takes an input

An earlier version of this page said `callPredicate` was "the escape hatch for
a predicate whose last argument is an input, which the convention cannot
express". That was wrong, and the correction is worth having because it is
free speed: the convention expresses it fine, because Prolog unification does
not care which way a value flows. The output slot is just an argument, and a
`let` puts a value into it:

```metta
(= (consult-it $path) (let $path (consult_global) done))
```

Read that carefully, because the shape is the point. `consult_global/1` has one
Prolog argument, which the convention makes the OUTPUT slot, so its MeTTa arity
is zero and it is written `(consult_global)` with nothing in the parentheses.
The `let` then unifies the path INTO that slot, which is how the value gets in.
`lib/lib_import.metta` already relies on this.

The same fact runs the other way. A registered predicate can BIND a caller's
unbound variable, and the binding escapes into the MeTTa program:

```metta
!(let $v (binds-its-input $free) ($free $v))
```

**If you get `is/2: Arguments are not sufficiently instantiated`, you wrote the
output slot first.** It is the most likely mistake at this tier and the message
names `is/2` rather than your predicate, because by then the engine is inside
arithmetic and has no way to know which argument you meant as the answer.
`'scale'(Out, X) :- Out is X * 2.` called as `(scale 21)` becomes
`'scale'(21, Out)`, so it computes `21 is Out * 2` and stops. Inputs first, one
output last:

```prolog
'scale'(X, Out) :- Out is X * 2.
```

Wrapping it in `rethrow_metta_operation_error/2` puts your predicate's name on
the message, which is worth doing anyway; it does not tell you the argument
order is the cause, so this paragraph does.

So reach for `let` first, and for `callPredicate` only when the goal really has
to be built at run time. Both directions are pinned:
`the_output_slot_takes_an_input` and
`a_registered_predicate_binds_a_callers_variable` in
`tests/prolog/prolog_interface.plt`, the second asserting the exact bindings
that escape, `((a a!) (b b!) (c c!))`.

## 3. C foreign predicates: wrapping what is already native

When the work already exists in C or Rust, you do not need Prolog in the
middle. Follow SWI's foreign interface and the same calling convention, inputs
then one output:

```c
#include <SWI-Prolog.h>

static foreign_t pl_c_bump(term_t x, term_t y)
{ int64_t v;
  if ( !PL_get_int64_ex(x, &v) ) return FALSE;
  return PL_unify_int64(y, v + 1);
}

install_t install_cbump(void)
{ PL_register_foreign("c-bump", 2, pl_c_bump, 0);
}
```

Build it with `swipl-ld`, which knows where the headers are:

```sh
swipl-ld -shared -o cbump cbump.c
```

From Python, one call loads it and registers what it defines:

```python
m.register_foreign_library(Path(__file__).parent / "cbump.so",
                           entry="install_cbump", names=["c-bump"])
```

`entry` is the C initialiser, `install_cbump` in `install_t
install_cbump(void)`; leave it out when the entry is plain `install`. The path
is resolved to an absolute one for you, which is the part worth having: a
relative path resolves against the working directory, SWI deprecates that and
warns on every load, so a library shipping one works from the repo root and
warns or fails anywhere else.

From MeTTa, load and register it the same way as any other Prolog:

```prolog
% loader.pl
:- use_module(library(shlib)).
:- use_foreign_library('/abs/path/cbump.so', install_cbump).
```

```metta
!(import! &self (library lib_import))
!(import_prolog_functions_from_file "loader.pl" (c-bump))
!(c-bump 41)                                    ; 42
```

Give `use_foreign_library/2` an absolute path or a `foreign(Name)` alias. A
path relative to the working directory still resolves but SWI deprecates it and
says so on every load.

Two obligations the convention puts on you. Return `TRUE` or `FALSE`, and use
the `_ex` accessors (`PL_get_int64_ex` and friends) so a wrong argument type
raises a proper Prolog type error rather than failing silently. And if your
predicate has more than one solution, that is `PL_retry`/`PL_foreign_control`
with the `PL_FA_NONDETERMINISTIC` flag; a deterministic foreign predicate that
should have been nondeterministic loses answers with no sign that it did.

`backends/mork/mork_ffi/mork.c` is the worked example in this repo, and it shows the other
load route: `LD_PRELOAD` in `run.sh`, which is right when the library must be
present before the engine boots.

### Hand back a handle, not a serialisation

The expensive mistake at this boundary is converting your structure to text.
`backends/mork/mork_ffi/mork.c` does exactly that, and it is worth knowing what it costs:
reading MORK's answer for a single `(fact a 1)` costs **4.49us and 149
inferences to parse**, against **0.37us and 2 inferences for the FFI call that
produced it** [measured 2026-08-16]. The crossing is cheap. The text is not.

Give MeTTa an opaque handle instead. SWI's blob interface does this and the
engine needs no changes for it: a blob already answers `Grounded` to
`get-metatype`, compares by identity, and prints through the type's own
callback, so it is an ordinary MeTTa value.

```c
static PL_blob_t vector_blob =
{ PL_BLOB_MAGIC, PL_BLOB_NOCOPY, "vector",
  release_vector, NULL, write_vector, NULL
};

static foreign_t pl_vector_new(term_t length, term_t out)
{ vector_t *v = ...;                      /* malloc'ed, owned by the blob */
  return PL_unify_blob(out, v, sizeof(*v), &vector_blob);
}
```

```metta
!(vector-length (vector-new 1000))       ; 1000
!(vector-nth (vector-new 1000) 700)      ; 700
```

`examples/integration/c_extension/handle.c` is the worked version, with its own
example and README beside it. On a thousand-element vector, reading one element
through the handle costs **0.1968us and 2.00 inferences**, while writing that
vector as text costs **389.94us and 16,906 inferences** and reading it back
costs **919.35us and 44,600** [measured 2026-08-16]. The handle's cost is flat
in the structure's size and the text's is linear, the same shape as `raw=True`
against the encoded path in the argument-size table above.

The handle crosses to Python too, by reference. A blob reaching the
Python boundary arrives as `petta.Handle`, an opaque atom carrying a
registry id and the blob's own printed text; hand it back and the very
same native object answers, so identity and mutation survive the round
trip, and a Python function can unpack the structure through whatever
accessors the extension registered. It used to arrive as its printed
STRING, silently, which made the round trip impossible [measured
2026-08-17; pinned in `bindings/python/tests/test_c_handle_crossing.py`].
`release()` retracts the engine-side registry entry that keeps the blob
alive; a released handle raises by id instead of answering wrongly.

Two things the blob interface asks of you. `PL_BLOB_NOCOPY` means SWI keeps the
pointer you hand `PL_unify_blob`, so hand it heap memory and not the address of
a local. And write a release callback, because that is where the structure is
freed when SWI garbage-collects the handle; without one, every handle leaks.

## 4. Python grounded operations: reaching the host

```python
@m.register_op(name="my-op")
def my_op(x):
    return x + 1
```

This is how you reach NumPy, PyTorch, an LLM, a database, or anything else
Python can see. It costs the janus crossing, so it earns its price when the
work on the other side is substantial and loses it when the operation is
trivial. `lib_llm`, `lib_torch` and the `arrays` integration are all this.

### Writing logic in Python: use `@m.define`, not `register_op`

`register_op` is for **reaching Python libraries**: NumPy, an LLM, a database,
anything whose value is on the other side of the crossing. It is not for
writing logic in Python. For that there is `@m.define`, which reads the
function's source with `ast` and lowers it into MeTTa equations:

```python
@m.define
def classify(n):
    if n < 0:
        return "negative"
    return "positive" if n else "zero"
```

Those equations compile like any others, so the call costs what a hand-written
MeTTa equation costs: 3.01 inferences against 3.00, which is a compiler result
rather than a coincidence. There is no crossing at run time and no Python in
the loop.

The subset is a real subset, and a construct outside it is refused by name and
line rather than silently falling back to a Python operation. `_define_twins`
keeps the original function reachable as `.py`, so a compiled equation can be
checked against its Python twin on any ground input.

Annotate it and the picture changes: the generated declaration sends every
call through typed dispatch, at 11.00 inferences for a call with an unknown
argument and an unknown result. A literal argument costs nothing extra,
because its type is settled while the call site compiles. That is the right
trade where you want the checking and the wrong one in an inner loop over
values the compiler cannot see. See the note under the cost table.

### Running a Python operation backwards

A Prolog predicate is bidirectional for free, because unification does not
care which way a value flows: *Arguments are bidirectional* above is that
story. A Python function is not. It runs forwards, and asked to run backwards
it fails somewhere inside Python:

```metta
!(let (concat $h $t) (1 2 3) ($h $t))
; Python TypeError in (concat $_0 $_1)
;   Value after * must be an iterable, not Var
;   arguments 1, 2 were unbound, so the operation ran in a pattern position;
;   a Python operation runs forwards only
```

Give it the backwards direction and it stands in that position like an
equation does:

```python
m.register_op(
    lambda head, tail: (head, *tail),
    name="concat",
    inverse=lambda whole: (whole[0], tuple(whole[1:])),
)
```

```metta
!(concat 1 (2 3))                          ; -> (1 2 3)
!(let (concat $h $t) (1 2 3) ($h $t))      ; -> (1 (2 3))
```

The inverse takes the result and returns the arguments, as a tuple of the
operation's width, or the bare value at arity one. It is a **relation**, not a
function, so a generator enumerates every preimage and `None` or `Decline`
means there is none, which fails rather than raising:

```python
def roots(y):
    yield (int(y ** 0.5),)
    yield (-int(y ** 0.5),)

m.register_op(lambda x: x * x, name="sq", inverse=roots)
# !(collapse (let (sq $r) 9 $r))  ->  (3 -3)
```

It runs only when the arguments are not ground and the result is, so a forward
call never reaches it. An operation that declares no inverse compiles exactly
the clause it compiled before, which is why this costs nothing to the
operations that cannot serve the direction.

Why supply it rather than derive it: a foreign function cannot be narrowed.
Curry does not invert its own `external` functions either, and Prolog's own
`plus/3` and `succ/2` are builtins with a hand-written implementation per
mode. This is the same answer. `functions/invertfunction.metta` shows what you
get for free when the function is a MeTTa equation instead, including solving
`$X + 35 = 42` through a constraint while destructuring a list in the same
pattern.

### Keep the Python when you rewrite it in Prolog

The reason to write the reference in Python and the fast one in Prolog is that
you then have two implementations of one function, which is a differential
oracle. Declare them together and it stays one:

```python
@m.define(prolog=Path(__file__).parent / "fast.pl")
def vec_dot(a, b):
    """The readable reference."""
    return sum(x * y for x, y in zip(a, b))
```

The Prolog is registered and answers `(vec-dot ...)`; the Python is not
compiled and stays reachable as `vec_dot.py`. The file must register that
function's own MeTTa name, at the twin's arity of inputs then one output, and
says so if it does not. Its `metta_export` declaration owns the types, so
annotations on the Python are documentation.

Then run the pair:

```python
from petta import testing

def test_the_fast_one_still_agrees():
    testing.check_twin(vec_dot, [((1, 2), (3, 4)), ((0,), (9,))])
```

`cases` is an iterable of argument tuples; drive it with hypothesis for a real
sweep, using the strategies `petta.testing` already exports. A generator twin
is compared answer by answer in order, and a twin that RAISES on a case
requires the engine to answer nothing for it, which is the disagreement most
worth catching: a reference with no answer and a fast side that invents one.

### Building a fast library on PyPeTTa

`register_op` is the extension point most people find first, and it is the
slowest tier. If you are writing a library **on top of PyPeTTa** and its hot
path is arithmetic, matching or list work, you do not have to pay for Python
on every call. Ship Prolog and register it from Python:

```python
# inline, for a small helper
m.register_prolog("'vec-dot'(A, B, Out) :- ... .", names=["vec-dot"])

# or a file shipped beside your Python package
m.register_prolog(path=Path(__file__).parent / "fast.pl",
                  names=["vec-dot", "vec-norm"])
```

Those predicates then run at tier 2 speed, about a third of the cost of the
same operation written as a Python op, while your library still installs with
`pip install` and configures itself in Python.

Every name is registered explicitly rather than discovered. That is deliberate:
registering a name whose predicate is absent records no arity, and then every
call to it compiles into a partial application instead of failing, which is a
silent wrong answer.

Four things are refused, all of them before the source loads, because a
consulted predicate replaces the engine's own the moment it loads and no later
refusal can undo that:

- a name with **no predicate** behind it;
- a **builtin's** name, because your clauses would replace the engine's for
  every program in the process. A named space compiles its own clauses, so an
  equation there shadows a builtin for that space alone;
- a **special form's** name, because the translator compiles those before
  function dispatch, so the registration could never be reached;
- a name **another tier already owns**. One name has one owning tier, refused
  in both directions, with the incumbent left usable.

Nothing is registered unless every name can be, so a typo in the list changes
nothing. The consulted source does stay loaded on failure, which is
deliberate: loading it again is the retry, and it is idempotent, because the
source is identified by a hash of its own content.

### Declare your exports in the file that implements them

Passing `names=` works and is fine for a snippet. For a library, declare in the
`.pl` instead, and the name, the arity and the type stop being three statements
nothing keeps in agreement:

```prolog
:- metta_extension(pettorch, [version('0.3.1')]).
:- metta_export("
    (: vec-dot (-> Number Number Number))
    (: shape-of (-> Atom Atom))
    (export vec-helper 1)
").

'vec-dot'(A, B, Out) :- ...
```

```python
m.register_prolog(path=Path(__file__).parent / "fast.pl")   # no names=
m.unregister_prolog("pettorch")                              # everything, gone
```

The declaration is MeTTa, in a string, because the types are MeTTa types and
the reader that parses them is the engine's own. The MeTTa arity comes from the
type chain, so `(-> Number Number Number)` means `'vec-dot'/3` and a
declaration naming an arity the file does not define is refused rather than
registered. `(export name arity)` is the form for a name whose type you do not
want to state.

Three things follow, and the middle one is the reason to bother:

- **A helper that shares your prefix is not published.** The arity used to be
  DISCOVERED from whatever `current_predicate/1` held, so a library shipping a
  public `'vec-dot'/3` and an internal `'vec-dot'/2` published both, and the
  author had no way to prevent it.
- **The type cannot land late.** It arrives with the name, so the ordering trap
  cannot open: a call site compiled before a separate `(: ...)` declaration
  keeps evaluating an `Atom` argument for ever, and nothing warns.
- **The registrations go together.** `unregister_prolog` releases every name
  the extension installed, its type declarations, and its clauses. There is no
  uninstall to write, and no way to release one member on its own, which is
  what stops one registry keeping a claim on a name another route replaced.

### Say what a caller may assume

```prolog
:- metta_export("
    (: now (-> Number))
    (volatility now volatile)
").
```

PostgreSQL's ladder, because purity is not a boolean: `volatile` makes no
assumptions, `stable` gives the same answer within one evaluation, and
`immutable` gives the same answer forever. A `volatile` function refuses to be
memoized, naming itself, because caching a function whose answers are not
reproducible skips whatever the call does on the second one. Before this,
nothing recorded whether caching was sound and `lib_memo` would happily cache
a side-effecting predicate.

Silence stays permission, deliberately. Memoization is already opt-in by the
CALLER, so making an undeclared function refuse would break every existing
`(memoize f)` without telling anyone anything they did not know. What was
missing is the LIBRARY's ability to say no.

### Say how many answers there are

```prolog
:- metta_export("
    (: vec-dot (-> Expression Expression Number))
    (determinism vec-dot det)
").
```

A predicate that leaves a choice point behind costs its callers about twice,
and **the inference counter cannot see it**: no-cut, cut and SSU dispatch of
the same workload all reported exactly 1,000,003 inferences while wall clock
was 0.1887, 0.0928 and 0.1128. Declare `det` and SWI's own `det/1` raises where
the leak is, at your door, instead of taxing everyone who calls you.

Read `det` as **exactly one answer, always**, not at most one. SWI raises
`Deterministic procedure f/2 failed` as readily as it raises on a choice point,
so a function whose empty answer set is a legitimate result is `semidet`, not
`det`. Getting this wrong turns a normal no-answer into an error.

`semidet` and `nondet` are recorded rather than checked, since SWI has a
directive for `det` alone. They are still worth writing, because
`profile_extension` reports them beside the redo count: a redo on a function
declaring `nondet` is the function working, and a redo on one that declared
nothing is a question.

### Say which seam you were written against

```prolog
:- metta_extension(pettorch, [version('0.3.1'), requires(1-0)]).
```

A library built on today's `ext_points.pl` will be loaded into a later engine,
and with nothing to check against a removed or renamed hook shows up as
silence. Erlang's NIF loader is the model: the major must match and the minor
must not be newer, or the load fails, naming both versions. A library that
declares nothing keeps working, so this costs nothing until you use it.

### Prove your provider before your users do

```python
from petta import testing

def test_my_provider_conforms():
    testing.check_space_provider(MyProvider(rows))
```

It drives every capability the provider declares, refuses one declared without
a method behind it, and checks the contract that everything else rests on: a
provider may over-approximate its match and may never under-approximate, so
every stored atom must be answered by a pattern that is the atom itself. A
provider that filters too eagerly fails there rather than answering an empty
set in production.

### Find out where YOUR library's time goes

The table at the top of this page answers "what does a tier cost in general".
Once your library is written, the question is narrower: of the functions I
registered, which one is costing me, and is anything wrong with how it went in.

```python
groups, costs = m.profile_extension("!(my-workload)", extension="mylib")
for cost in costs:
    print(cost)
# <mylib-join/3 prolog: 40100 calls, 39900 redos, 812 ticks, index 1x>
# <mylib-norm/2 prolog: 40100 calls, 0 redos, 41 ticks, index 300x>
```

Every declared member gets a row, including one the workload never reached,
which is the answer to "did that registration take". `names=[...]` takes an
explicit list instead.

Two columns are worth reading before the ticks. **Redos** are the engine
re-entering your predicate for another answer, which is what a leftover choice
point looks like from outside; a function you meant to be deterministic showing
redos is costing its callers about twice, and the inference counter cannot see
it at all. **speedup** is the ratio SWI computes for the clause index it chose,
so `index 1x` means no argument discriminates and every call walks your clause
list. `indexed` False on a function nothing has called much only means SWI has
not built the index yet, since it builds them on first need.

A row also carries what the library DECLARED, so redos read against intent:
`declared nondet` beside redos is the function working, and redos on a function
that declared nothing is a question. See *Say how many answers there are*.

Calls and redos are counted, so they are exact. Ticks are sampled, so profile
something that runs.

### Dispatching on a value's type

Almost every registered predicate starts by asking what it was handed. Write
that as an if-then-else chain and stop worrying about the order:

```prolog
my_text(Value, Text) :-
    (   string(Value) -> Text = Value
    ;   atom(Value)   -> atom_string(Value, Text)
    ;   number(Value) -> number_string(Value, Text)
    ;   throw_metta_type_error('my-op', 'String', Value)
    ).
```

SWI inlines `var/1`, `atom/1`, `number/1`, `string/1`, `atomic/1`,
`compound/1` and `callable/1`, so a chain of them costs the same whichever
order you write it in: testing a number after passing over `string` and `atom`
is 3.00 inferences, exactly what testing it first costs [measured 2026-08-16].
Order them so the code reads well.

Four tests are not inlined and every call that passes over one pays for it:
`is_list/1` and `is_dict/1` and `blob/2` cost two inferences each, `ground/1`
costs one. Put those last, or guard them with an inlined test the way the
engine's own type probe guards its `blob/2` with `atomic(X), \+ atom(X)`.

The three alternatives are all worse for this, which is worth saying because
each of them is right somewhere else. Per call, on the same inputs [measured
2026-08-16]:

| shape | inferences/call |
|---|---|
| if-then-else chain | 4.17 |
| a clause per type, guard and cut | 6.17 |
| SSU `=>` rules with guards | 8.17 |
| compute a tag, dispatch on it | 11.17 |

A type test cannot be a clause index, because indexing needs the argument's
principal functor in the head and "any string" is not one. Computing a tag to
get an indexable first argument does not rescue it either: a four-clause
predicate gets **no index at all**, still `none` after 50,000 calls, and the
tag has already cost you seven inferences. Reach for SSU when the clauses
would otherwise leave a **choice point**, which is a different problem and one
the inference counter cannot see; the chain above already leaves none.

### Two libraries cannot take one name

A consulted file REPLACES a static predicate of the same name, and SWI only
warns about it, on stderr, where no caller sees. Two libraries each shipping
`'norm'/2` used to mean the second silently wiped the first: library A's answer
changed the moment B loaded, and both registrations reported success.

A second Prolog source claiming a name another one owns is now refused, naming
the file that owns it. The refusal necessarily comes after the load, because
SWI prints rather than throws and no `catch/3` can see it, so the only reliable
check is a positive one afterwards. What it buys is that you hear about it
instead of shipping a library bound to someone else's code.

### When you need both of them anyway

A refusal is the right answer when one of the two libraries is wrong. It is the
wrong answer when neither is: two packages you do not control both export
`norm/2`, and you need both. Ship them as Prolog **modules** and rename at the
import, which is how Prolog has resolved this for thirty years:

```prolog
:- module(liba, ['norm'/2]).      % in each library's own file
```

```python
m.register_prolog(path="liba.pl", names={"norm": "liba-norm"})
m.register_prolog(path="libb.pl", names={"norm": "libb-norm"})

m.one("(liba-norm -5)")     # 5
m.one("(libb-norm -5)")     # 25
```

`names` as a mapping is `{the module's own name: the MeTTa name}`. The arity
comes from the module's export list, so you write two names and no arity, and
a name the module does not export is refused with the list of what it does.

This is SWI's own `use_module/2` import list underneath, so the renamed name is
a real imported predicate rather than a wrapper, and costs nothing per call.
Without it SWI declines the second import, prints `No permission to import
libb:'norm'/2 into user (already imported from liba)` on stderr, and continues,
which leaves the newcomer silently bound to the incumbent's code.

### Ship files beside your Python package

```python
# in your package's __init__
m.register_library_path(Path(__file__).parent / "prolog", "pettorch")
```

Or say nothing at all and let `pip install` be the whole of the wiring. An
integration that ships Prolog and no Python setup names its files:

```python
# in your package's __init__
PETTA_PROLOG = ["fast.pl"]
```

`m.integrate(pettorch)` and `petta.integrate.discover(m)` then register the
library path and every file, and each file declares its own exports, so there
is no name list anywhere. Before this the standard plugin mechanism carried no
Prolog at all: a native library had to hand-write an `install()` that hardcoded
a `__file__`-relative path.

`(library pettorch fast.pl)` then resolves, from MeTTa and from
`register_prolog(path=...)`. Without it a pip-installed library is under
neither the engine's `lib/` nor a git checkout, so it has to compute absolute
paths from `__file__` by hand. This is SWI's own `file_search_path/2`, so an
alias registered here is one every SWI tool already understands, and aliases
compose.

Use Python for what Python is for, the host libraries and the configuration,
and Prolog for the inner loop.

**There is no public "call any Prolog goal from Python" surface, deliberately.**
The supported way to reach your own Prolog from Python is to register it and
call it as a MeTTa function, which keeps one set of conversion rules, one error
taxonomy and one lock. A raw goal is janus's job, and janus is importable
directly. `m.prolog()` opens the interactive toplevel, which is for debugging.

## 5. Space providers: where atoms actually live

### Shipping one, which this chapter used not to say

A provider file declares an EXTENSION and exports nothing:

```prolog
:- metta_extension(mylib_space, [version('1.0.0')]).

:- multifile metta_foreign_space/1.
...
```

`metta_export` is for functions and a provider has none, so that is the
declaration to write, and it is what makes the file loadable at all.
`m.register_prolog(path=...)` accepts it and answers `()`, because it
registered no functions. Ship it the way section 4 ships any `.pl`, by listing
it in your package's `PETTA_PROLOG`.

A file that declares NEITHER is refused before it loads, which is worth
knowing because it used to be refused AFTER: an author who wrote a provider,
shipped it and caught the `ValueError` would have found that catching it made
everything work.

Prove it before your users do with `(check-space-provider &mine)` from
`lib_conformance`, which is the Python kit's three checks asked of a space
name; see "Prove your provider before your users do" in section 4.

A provider answers `match`, `add`, `remove` and enumeration for a named space
whose atoms live wherever you keep them: a SQL table, a dataframe, a service, a
remote engine. The engine keeps unification for itself, so a provider may
over-approximate its filtering and stay correct; pushing the bound parts of a
pattern down into the backend is a performance lever, never a correctness
requirement.

There are two ways in, and they differ in cost the same way tiers 2 and 3 do.

**From Python**, implement the `SpaceProvider` protocol in
`bindings/python/petta/foreign.py` and `register_space`. Every match crosses the janus
boundary, which is right when the atoms live somewhere Python already talks to.
`das.py`, `remote.py` and `persistent.py` are three real instances.

**From Prolog**, add clauses to the multifile seam in `engine/spaces.pl`:

```prolog
:- multifile metta_foreign_space/1.     % this space is mine
:- multifile metta_foreign_add/2.       % add an atom
:- multifile metta_foreign_remove/3.    % remove one
:- multifile metta_foreign_atoms/2.     % enumerate
:- multifile metta_foreign_match/3.     % answer a pattern
:- multifile metta_foreign_erring/5.    % a declared error mode's stream
:- multifile metta_foreign_begin/1.     % transactional participation:
:- multifile metta_foreign_commit/1.    %   one begin at the first write,
:- multifile metta_foreign_rollback/1.  %   one commit or rollback after
:- multifile metta_foreign_clear/1.     % empty the space
```

Two more seams carry custom matching, Hyperon's CustomMatch: a grounded
value may own its matching logic, consulted by `(unify ...)` when the
value meets a non-variable operand. `metta_matchable_value/1` says a
value has such logic, and `metta_custom_match/2` enumerates one solution
per binding set, binding the other operand's variables through ordinary
unification; no solutions means no match. Variables always bind the
value whole without consulting it, and a value nobody claims falls
through to ground equality. The Python side implements both for any
object whose class defines `match_` (see `petta.foreign.CustomMatch`),
so a Python value participates with no registration at all; a
Prolog-hosted value participates by adding clauses to these seams.

```prolog
:- multifile metta_matchable_value/1.   % this value owns its matching
:- multifile metta_custom_match/2.      % one solution per binding set
```

`metta_foreign_clear/1` is the sixth and is easy to miss: it lived in
`bindings/python/petta/shim.pl` rather than beside the other five, so a Prolog provider
that implemented `clear`, as `lib/lib_redis.pl` does, was reachable only when
Python happened to be in the process. It is declared with them now.

The engine consults `metta_foreign_space/1` before reaching its own storage, so
your clauses take the space over entirely, with no boundary crossing. This is
how MORK plugs a Rust trie in underneath MeTTa: `backends/mork/mork_ffi/morkspaces.pl` is a
complete worked example, and `examples/integration/c_space/` is the
smallest one, a mutex-guarded C store behind four clauses, proven by
the conformance kit inside its own example and driven concurrently by
`hyperpose` and a Python thread pool.

Worked instances now exist per language and per backend class, so start
from the one nearest yours: C (`examples/integration/c_space/`), SQL
derived from one declaration (`bindings/python/petta/tables.py` with
`bindings/python/examples/integration/sqlite_space.py`; DuckDB with pushdown in
`duckdb_space.py` beside it), another MeTTa runtime as a subprocess
(`cetta_space.py`), TypeScript over the wire
(`bindings/python/examples/integration/typescript_space/`, which also documents
the remote protocol itself; `petta.testing.GatewayComplianceSuite`
certifies any implementation of that protocol by URL), and Redis
(`lib/lib_redis.pl`).

**The seam is order-independent, and that is the point of it.** Every one of
the operations above consults `metta_foreign_space/1` as a guard before
reaching native storage, so it does not matter when your file loads. Do not
add raw `match/4` clauses instead: declaring `match/4`, `add-atom/3`,
`remove-atom/3` and `get-atoms/2` multifile puts your clauses ahead of the
engine's whenever your file loads first, which makes the engine's own
instantiation guards unreachable. MORK did that and `(get-atoms $any)`
answered from MORK rather than refusing. Moving to this seam is what fixed it.

### Take a whole batch in one crossing

A seventh hook is optional, and it exists because one crossing per atom is the
wrong shape for bulk ingestion:

```prolog
:- multifile metta_foreign_add_many/2.  % a list of atoms, your way

metta_foreign_add_many('&mine', Atoms) :- mine_bulk_load(Atoms).
```

Write it and `m.add(a, b, c)`, `add-atom` over a list, and any other bulk write
reach you once with the list. Leave it out and you get one
`metta_foreign_add/2` per atom, which is what every provider written before
this gets. The write hooks are yours either way, exactly as they are for your
per-atom add. `backends/mork/mork_ffi/morkspaces.pl` implements it by joining the atoms into
one payload that MORK parses itself.

**A batch is a transport optimisation and never a semantic one.** Whatever the
engine does for an atom on its own it must still do when the atoms arrive
together, so it routes only atoms whose add is a store and nothing more through
this hook: an equation or a type declaration anywhere in the list drops the
whole batch to `add-atom/3` per atom, and you never see it here. That is
enforced upstream rather than asked of you. It is enforced because it was got
wrong: the Python bridge chose the bulk path for MORK itself and so skipped the
rule, and an equation added alongside any other atom was stored inert while the
same equation added alone compiled.

### Claim a whole join

The engine splits a conjunction one pattern at a time and re-dispatches the
next on every binding of the previous. That is a nested-loop plan, and a
provider that never sees more than one pattern cannot do better than one
however fast it is. Say you take conjunctions and you get them whole:

```prolog
:- multifile metta_foreign_plan/5.

%   metta_foreign_plan(Space, Patterns, Claimed, Rest, Goal)
metta_foreign_plan('&mine', Patterns, Patterns, [], mine_join('&mine', Patterns)).
```

```python
class Joins(SpaceProvider):
    def plan(self, patterns):
        rows = my_backend.join(patterns)      # or None to decline
        return list(patterns), [], iter(rows)
```

Nothing about the MeTTa changes. `(match &mine (, (edge $x $y) (edge $y $z))
($x $z))` is the same query it always was; the claim happens underneath it.
That is the point of doing this as a space rather than as a query API: a
backend is reached the way every other space is reached.

**Declining is the default and always legal.** No clause, or `None`, and you
get exactly today's behaviour. **A partial claim is legal too**: take the two
patterns you own and leave the third in `Rest`, and the engine plans the
remainder as it always did. `Claimed` and `Rest` must partition the
conjunction; dropping a conjunct is refused, because the engine plans only what
you leave, so a dropped pattern stops constraining the query and the join
answers rows nobody asked for.

**A claim is exact, and this is the one place the seam's usual rule is
reversed.** Everywhere else you may over-approximate freely because the engine
re-unifies each candidate you yield, which costs a unification. There is no
cheap re-check for a join: verifying one row means running the join. So the
engine trusts a claim, a provider that cannot answer a conjunction exactly must
decline it, and `check_space_provider` verifies the claim against the engine's
own split instead of taking your word for it.

What it is worth, measured on MORK's real join against the engine's split over
the same store. Two workloads, because they say different things:

| workload | split grows | claimed grows | ratio |
|---|---|---|---|
| triangle, output-bound (2,730 rows from 3,060 edges) | n^2.95 | n^3.3 | 27x → 19x, shrinking |
| triangle over two hubs, intermediates ~N² and output ~2N | n^1.99 | n^1.49 → n^1.79 | 33x → **68x**, growing |

The first is a large constant factor and nothing more: when the answer itself
is most of the work, both plans have to enumerate it and the gap closes. The
second is the case worst-case-optimal joins exist for, where the pairwise
intermediates blow up and the answer does not. There the split is pinned to the
intermediate size and the claim is not, and the ratio grows with the data
[measured 2026-08-16, `instructions:u`, min of 2 per point, baseline
subtracted].

### Hold rules, not only facts

In MeTTa a space is BOTH a data source and where the program lives, and that
is the point rather than a nuance: evaluation is match against `(= lhs rhs)`
atoms, facts and rules are the same kind of thing, and `add-atom` of an
equation is how a program grows. `&self` is a knowledge base and a program at
once.

Say your space holds equations and the engine evaluates through it:

```prolog
metta_foreign_capability('&mine', Capability) :-
    member(Capability, [match, enumerate, add, remove, rules]).
```

```python
class Rules(SpaceProvider):
    def can_run(self, capability, /, **request):
        if capability == "rules":
            return True
        return super().can_run(capability, **request)
```

Nothing else is asked of you. You store an equation the way you store any other
atom, and the engine compiles it, so
`(add-atom &mine (= (double $x) (* 2 $x)))` then makes `(double 21)` answer
`42`. Nothing in your provider has to know what an equation is.

That the engine compiles it is the whole of the design, and it is worth saying
why, because the obvious alternative is wrong. Reading evaluation as "match the
space for `(= (f Args) $body)` and reduce `$body`" is the naive reading, and
MeTTa's own tutorial says where it falls short: the interpreter "is performing
some additional processing on top of such equality queries". Three of those
differences bite immediately. A body is evaluated further, so
`(= (nest) (+ 1 (* 2 3)))` must not hand `(* 2 3)` to `+` as a list. A
bare-variable body must NOT be evaluated, or an `Atom` parameter comes back
reduced. And `if` evaluates only the branch it takes, so `(= (loop) (loop))`
under an `if` has to terminate. Going through the compiler gets all of them and
every future one for free; a second evaluator would get them wrong one at a
time. The suite pins this as a differential: the same eleven programs run in a
native space and in a foreign one and must answer identically
[`tests/prolog/spaces.plt`, `a_foreign_space_evaluates_exactly_as_a_native_one`].

Two things to know. A rule you hold BELONGS TO YOUR SPACE, exactly as a native
named space's equations belong to it, so it is called from there:
`(metta (double 21) %Undefined% &mine)` rather than `(double 21)` in `&self`.
And the engine learns about an equation when it goes through `add-atom`, so one
that appears in your space by another door, your own bulk loader or a backend
calculus like MORK's `mm2-exec`, is stored and inert.

Say nothing and an equation added to your space is REFUSED at `add-atom`,
naming the capability. It used to be stored and inert: `(only-foreign 21)`
answered itself, where the identical shape in a native named space answered
42.

### Shipping a native backend

A backend whose implementation is a shared library needs one thing a Prolog
provider does not: somewhere to be loaded from. That is a file in `backends/`,
named after the backend, and it is the whole mechanism.

```prolog
% backends/mine.pl
:- prolog_load_context(directory, Dir),
   directory_file_path(Dir, '../mine_ffi/target/release/libmine.so', Artefact),
   (   exists_file(Artefact)
   ->  directory_file_path(Dir, '../mine_ffi/minespaces.pl', Backend),
       ensure_loaded(Backend)
   ;   true
   ).
```

The engine loads every file in `backends/` when the host passes `backends`,
which `run.sh`, the packaged CLI and the Python library all do. It knows none
of them by name. **Not built is not an error and half built is**: a backend
whose artefact is missing loads nothing and says nothing, and one whose
artefact is there and broken raises. Both of those are decisions your file
makes, and no host has to implement either.

Two multifile hooks go with it, and both exist so the engine never has to name
a backend:

```prolog
:- multifile metta_backend_builtin/1.   % a builtin your bridge provides
:- multifile metta_backend_selftest/0.  % your smoke test, run by the CLI demo
```

Declare `metta_backend_builtin/1` in the file that DEFINES the predicates, not
in `backends/mine.pl`, so the names exist exactly when the predicates do.
Registering a name whose predicate is absent records no arity, and every call
to it then compiles to a partial application rather than running or failing.

MORK is one of these and used to be none of it. `'../backends/mork/mork_ffi/morkspaces'` was
written into `engine/metta.pl`'s load list, in a second copy of that list behind
an argv test, and its three builtin names into a second argv test further down,
and `mork_test/0` was called by name from `engine/main.pl`. So a second native
backend could not be added without editing the engine, which is the one thing
this page promises you never have to do, and MORK reached the engine through a
door no other provider had. It goes through the seam now like everyone else,
and `backends/mork/decider.pl` is 12 lines.

### What you may call back

Everything above is the engine calling you. This is the other direction, and it
is short on purpose: seven predicates you may call, and they are the only ones.
Four of them are about text.

```prolog
swrite(Term, Text)                  % a MeTTa atom as text
sread(Text, Term)                   % text back as a MeTTa atom
metta_symbol_writable(Symbol)       % does this name survive the round trip
metta_unwritable_symbol(Term, Bad)  % the first value in Term that does not

throw_metta_type_error(Op, Expected, Got)   % raise as a builtin would
rethrow_metta_operation_error(Op, Error)    % put your name on somebody else's
current_metta_module(Module)                % which module the call site is in
```

You need the first four because being a shared library is a text problem. Your
atoms live
on the far side of a boundary that carries bytes, so every atom you store gets
written and every atom you hand back gets read, and both spellings have to be
the engine's rather than yours.

The last two are one rule worth knowing before you store anything. `swrite/2`
will happily print a symbol that `sread/2` does not read back as the same
symbol, because MeTTa has no quoted-symbol syntax: a name with a space, a
parenthesis or a quote in it comes back as something else. You cannot decide
that for yourself, the grammar owns it, so ask and refuse:

```prolog
metta_foreign_add('&mine', Atom) :-
    (   metta_unwritable_symbol(Atom, Bad)
    ->  throw(error(domain_error(mine_text_symbol, Bad),
                    context('add-atom'/3,
                            'that name cannot cross a text boundary')))
    ;   swrite(Atom, Text),
        mine_store(Text)
    ).
```

MeTTa's own builtins are published too and are not repeated in that list. Call
`'add-atom'/3` or `match/4` the way any program calls them.

Anything else under `engine/` is an internal, and calling one is a gate failure
rather than a style note:

```
the backend predicate mine_store/1 calls register_prolog_arities/1, which is
an engine internal rather than published surface
```

This exists because MORK reached past the seam for years and nothing said so.
It called `swrite/2` and `metta_unwritable_symbol/2` out of `engine/parser.pl`,
wrapping the second under a private name of its own, and `bindings/python/petta/shim.pl`
had independently wrapped the same predicate under a different private name.
Two extensions inventing two names for one undeclared dependency is what the
problem looks like from the outside. They are declared now, in
`engine/ext_points.pl` beside the hooks, and `tests/prolog/static_checks.pl` reads
that declaration rather than a list of its own, so a backend that reaches for an
eighth thing fails the gate with the line above. The walk is SWI's
`prolog_walk_code/1`, which means a call hidden in a `maplist/3` argument or in
a helper of yours that takes a goal is found too.

If you need something that is not there, say so and it can be declared. The
last three above arrived that way: this page had been telling you to call them
for longer than anything declared them, which is the same drift in miniature.
The point is that the surface is written down, not that it is small.

### Say why you are saying no

A capability your space does not provide is refused by the engine, and the
refusal is generic unless you write one:

```prolog
:- multifile metta_foreign_refuse/2.

metta_foreign_refuse('&mine', add) :-
    throw(error(petta_readonly_space('&mine'), context(add, 'load it with the importer'))).
```

It THROWS rather than answering; reaching the end of it means the engine and
your provider disagree about what you provide. A Python provider gets this for
free from its `refusal()` method, which is why "does not implement add" reads
differently there from "declines this add request".

### Say what your provider answers

```prolog
:- multifile metta_foreign_capability/2.
metta_foreign_capability('&mine', Capability) :-
    member(Capability, [add, remove, match, enumerate]).
```

The capabilities are `add`, `remove`, `match`, `enumerate` and `clear`. A space
that declares nothing is taken to provide all five, so an existing provider
needs no change; declaring buys two things.

**Enumeration is enough.** A provider that declares `enumerate` and not `match`
has its enumeration filtered by the engine for a bound pattern, instead of
answering nothing. That is what the Python half has always done, and the Prolog
half quietly required both until it was declared.

**A missing operation refuses instead of vanishing.** An operation a space did
not declare raises `permission_error(Operation, foreign_space, Space)`, naming
both. Four of the five used to fail silently: a write vanished, a removal
reported nothing removed, and a match answered the empty set while the space
demonstrably held matching atoms. A write that merely FAILS is an error too,
because a write either happened or it did not.

Use the Prolog seam when the backend is reachable from Prolog or C and the
query volume is high; use the Python one when the backend is a Python library.

### Letting the backend do less: what your provider is already told

Two levers that a provider backing a SQL table or a vector index needs are
already in place, and both are easy to miss.

**The bound parts of a pattern reach you, including from a join.** Query
`(fact $k $v)` and `(other $k $w)` together and your `match` is called once
with `(fact $_ $_)` and then once per outer row with `(other a0 $_)`,
`(other a1 $_)` and so on. Those ground positions are your `WHERE` clause.

**The engine stops pulling as soon as it has enough.** A provider is driven
lazily, so a `limit=3` query against a provider holding a thousand atoms pulls
four of them and abandons the generator [measured 2026-08-16]. You do not need
to be careful about yielding a lot; you need to be lazy about producing it.

What neither of those tells you is a COUNT, which is what a backend needs to
write `LIMIT 3` rather than fetch a page and throw it away. Take a `limit`
keyword and you are told:

```python
class Rows(SpaceProvider):
    def match(self, pattern, *, limit=None):
        sql = "select subject, object from facts where subject = ?"
        if limit is not None:
            sql += f" limit {limit}"
        ...
```

```prolog
metta_foreign_match('&mine', Pattern, Options) :-
    ( memberchk(limit(N), Options) -> true ; N = unbounded ),
    ...
```

You only get that number if you have said you can use it, which is the next
section. Two other things about it are worth knowing first.

It is **not sent across a join**. The bound belongs to the joined rows, so an
outer match truncated at N would lose the rows its later candidates would have
joined to. A multi-pattern query, and a guarded one, tell you nothing.

It is **optional on the Python side**. A provider whose `match` takes no
`limit` keyword is called without one, decided from the signature the way
capabilities are decided from the narrow protocols. In Prolog there is one
match hook and the options are always passed, so a provider with nothing to do
with them writes `_Options` and is done. There used to be a `/2` beside it and
the engine chose between them by asking whether ANY provider had declared the
bounded form, which the Python shim always has: with Python in the process, a
Prolog-only provider writing `/2` had `/3` called instead and a bounded query
against it answered nothing at all.

There is deliberately no `order` option. MeTTa's match promises no answer
order, so a provider ordering its output changes nothing a program can see,
and no consumer can ask for one.

### Say when your filtering is exact, and get the bound

The bound is only safe for a provider whose candidates ARE its answers. You
may over-approximate, so N candidates are generally not N answers, and
truncating at N without knowing which of them unify answers fewer rows than
exist, which is the one thing the contract forbids.

So the number goes to a provider that has said, for this pattern, that it does
not over-approximate:

```python
class Rows(SpaceProvider):
    def match(self, pattern, *, limit=None): ...

    def pushdown(self, pattern):
        # Exact when the WHERE clause covers everything the pattern
        # constrains: a ground position becomes a comparison, and a variable
        # needs none, so what is left is what the query would ignore.
        unfiltered = (
            arg for arg in pattern.args
            if not isinstance(arg, Gnd) and not isinstance(arg, Var)
        )
        return "inexact" if next(unfiltered, None) is not None else "exact"
```

```prolog
:- multifile metta_foreign_pushdown/3.
metta_foreign_pushdown('&mine', [_|Args], Class) :-
    ( forall(member(A, Args), (var(A) ; ground(A))) -> Class = exact
    ; Class = inexact ).
```

Answer `"exact"` when every candidate you yield for that pattern unifies with
it, and `"inexact"` otherwise. Say nothing and you are inexact, which is
always safe: you are called exactly as a provider written before this was, and
you are never handed a number you could wrongly truncate to.

Ask **per pattern**, not per provider. A backend is usually exact on an
indexed equality and inexact on a scan, and one flag for the whole provider
would force it to claim the weaker answer everywhere.

**The claim is about the whole pattern, not your best column.** This is the
trap, and the first draft of the example above fell into it: a provider that
indexes the subject and answers `(fact a $n)` precisely is still inexact for
`(fact a 1)` if its query ignores the second position, because it yields
`(fact a 3)` too. Filtering brilliantly on one position while the pattern
constrains another is inexact however good that one filter is.

**Where the number comes from.** Two callers set one, and they follow the same
rule. `m.query(pattern, limit=k)` from Python, and `take` from MeTTa:

```metta
!(collapse (take 3 (match &mine (fact $k $v) (fact $k $v))))
```

Both push the bound down only when the request is ONE pattern against ONE
space, because across a join the bound belongs to the joined rows and an outer
match truncated at k loses the rows its later candidates would have joined to.
In MeTTa that means the match's template has to be the pattern itself, as
above; give it a computed template or a conjunction and you get the answers
bounded and no number, which costs you nothing but a chance to be faster.

The bound is always applied by the engine as well, so honouring it can make
you cheaper and can never make an answer wrong. That is why ignoring it is
always correct.

This is Apache DataFusion's `TableProviderFilterPushDown`, whose `Exact` rung
reads "Your source guarantees that no output rows will have a false value for
this predicate. Because the filter is fully evaluated at the source, DataFusion
will not add a `FilterExec` for it", against `Inexact`, "Your source has the
ability to reduce the data produced, but the output may still include rows
that do not satisfy the predicate". Spark's DataSourceV2 draws the same line,
as filters "that need to be evaluated after scanning" against those that do
not. DataFusion's third rung, `Unsupported`, has no counterpart here: it exists
because its planner decides whether to send a filter at all, and the pattern is
the only thing a PeTTa provider is given.

A claim that is wrong costs answers, so `check_space_provider` tests it against
your own output, matching every stored atom against itself and failing if a
pattern you called exact yields anything that does not match. It is the one
claim in the seam that unification cannot cover for you: everything else you
say is protected by the engine re-unifying, and this is the one that licenses
you to stop early. The worked instance is
`bindings/python/examples/integration/duckdb_space.py`, whose `pushdown` reads exactly
the positions its `WHERE` clause covers and whose claim the kit confirms:
`pushdown: 3 of 3 patterns claimed exact, and are`.

## 6. Atom hooks: reacting to writes

`metta_on_atom_added/2` and `metta_on_atom_removed/2` are multifile predicates
in `engine/ext_points.pl`. Assert a clause and every write to a space calls it.
This is how Python subscriptions deliver, and how `lib_thread`'s `await-atom`
blocks on a space without polling.

**Shipping the clause in a consulted file works too**, which is what the
`multifile` declaration is for and what a library usually wants:

```prolog
:- multifile metta_on_atom_added/2.
metta_on_atom_added(Space, Term) :- my_index_update(Space, Term).
```

The write wrapper is installed lazily, and a clause arriving from a FILE
reaches the channel that installs it just as an `assertz` does. That is worth
saying because `prolog_listen/2`'s documented action list does not mention
loading, so reading the manual suggests the opposite; it was probed, and the
hook fires on the next write either way.

Assert it instead when the handler is only needed once a feature is used: a
resident clause costs four inferences on every compiled equation, and a
library that installs on first use pays nothing until then.

The cost is per write and only while a hook exists: `metta_add_hooks_idle/1`
takes a space off the bulk fast path exactly when somebody is listening, so an
unobserved space pays nothing.

### The one way to get a handler wrong

Write your guard as `( Condition -> Action ; true )`, not `Condition, !`:

```prolog
% wrong: silently disables every handler loaded after yours
metta_on_atom_added(Space, Term) :-
    my_space(Space), !, my_index_update(Term).

% right: same guard, same cost, prunes nothing
metta_on_atom_added(Space, Term) :-
    ( my_space(Space) -> my_index_update(Term) ; true ).
```

Atom hooks run through `forall/2`, so every handler is called. A cut in your
clause prunes the remaining clauses of `metta_on_atom_added/2`, and those are
the other libraries' handlers. Nothing reports it. `lib_tabling` cut after a
global condition once, `duals.pl`'s invalidation handler was ordered after it
and never ran, and `(not-provable (pq 2))` answered True and False at once.

The rule differs by seam, so each one carries its kind as a fact beside its
declaration in `engine/ext_points.pl`:

```prolog
?- ext_point_kind(metta_on_atom_added/2, Kind).
Kind = event.

?- ext_point_kind(metta_foreign_match/3, Kind).
Kind = ownership.
```

An **event** seam runs for its effect and runs every handler, so no cut. A
**declaration** seam is a fact table the engine reads, so no cut there either.
An **ownership** seam is claimed by the first handler that succeeds, and a cut
after a guard proving the request is yours is correct and fast there:
`lib_redis` cuts after `redis_space_conn(Space, _)`, which fails for a space
redis does not own, so no other provider's clauses are touched. The question
to ask of your guard is whether it proves the request is yours or is merely
true.

A **service** is the odd one out and none of that applies to it, because it
runs the other way: you write the clauses of the first three and the engine
calls them, while a service is a predicate the engine defines and you call.
`swrite/2` is one, and it cuts, correctly. `ext_point_clauses_from/2` is what
says which way a kind runs, and the cut checks read that rather than the kind,
so a service is not mistaken for a handler that has gone wrong.

From MeTTa the same list is `(extension-points)` in `lib_reflect`, answering
`(name arity kind)` one per solution, both directions included.

Two checks enforce this, so a cut in the wrong place fails the build rather
than surfacing as a wrong answer months later. One scans the tree's sources,
the other scans the live database after the libraries load, because a handler
you install with `assertz` at run time is in no file to read.

### Making your errors read like a builtin's

A library predicate that throws reports in the vocabulary of whatever threw.
`'i16-scale'(X, Y) :- Y is X * 2.` given a symbol says
`system:(is)/2: Arithmetic: 'foo/0' is not a function`, which names an engine
internal rather than the operation the program wrote. Builtins avoid that with
`rethrow_metta_operation_error/2`, which keeps the ISO formal term so a MeTTa
`catch` still inspects it and replaces only the host context:

```prolog
'vec-dot'(A, B, Out) :-
    catch(vec_dot_(A, B, Out), Error,
          rethrow_metta_operation_error('vec-dot', Error)).
```

Measured on the same predicate both ways, given a symbol where a number
belongs:

```
unwrapped   EngineError:          is/2: Arithmetic: `foo/0' is not a function
wrapped     MettaOperationError:  'vec-dot': Arithmetic: `foo/0' is not a function
```

Both halves change: the name becomes the operation the program wrote, and the
CLASS becomes `MettaOperationError`, so a caller can catch a library's
operation errors specifically instead of catching every engine error. This is
a convention rather than a hook, so it costs nothing on the path that does not
use it.

### A signal that must not be recovered from

An error your library raises for a caller to handle is one thing. A
CANCELLATION is another: a budget your library enforces, a stop your library's
worker was told to make, a deadline. If you throw one as an ordinary term, the
first recovery catch it meets swallows it and the program continues as though
nothing happened, which is the engine's own hardest-won lesson. A swallowed
limit signal here also disarmed `call_with_inference_limit` for the rest of the
call, measured at six million inferences spent under a thousand-inference
budget.

So say so, and every recovery site in the engine will let it through:

```prolog
:- multifile control_exception/1.

control_exception(mylib_cancelled).
control_exception(error(mylib_budget_exceeded(_), _)).
```

This is KeyboardInterrupt living outside Exception. The engine's own entries
are the limits, the abort and the interrupt; yours join them, and an ordinary
error from your library still takes the recovery it should.

It has to arrive by CONSULTING, not by `assertz`: the seam is static, like the
foreign-space hooks, so a runtime assert raises "No permission to modify
static procedure". Declare it in the file that raises the signal.

That covers an error some OTHER predicate threw. For one your library raises
itself, throw a term of your own and give it a rendering:

```prolog
:- multifile prolog:error_message//1.

vec_dot_or_refuse(A, B) :-
    ( same_length(A, B) -> true
    ; throw(error(vec_length_mismatch(A, B), context(vec_dot/3, _))) ).

prolog:error_message(vec_length_mismatch(A, B)) -->
    [ 'vec-dot needs two vectors of one length; got ~w and ~w'-[A, B] ].
```

The formal term is what a `catch` inspects, so keep the data in it and put the
prose only in the message clause. Two rules worth knowing, both learned the
hard way in this engine. **Match on your own formal alone**, never on SWI's
`context/2` with an unbound argument: a clause head that binds it relabels
every ordinary error of that shape, which once made every type error in the
process report as a MeTTa operation error. And **keep a file's message clauses
together**, because SWI warns about discontiguous clauses of a multifile
predicate and the warning is easy to lose in a load.

### Make a value applicable

MeTTa's own definition of a Grounded atom is that it "may contain any binary
object, for example operation (including deep neural networks), collection or
value". An operation is a thing you call, and the engine could not call one: a
head that was neither a function name nor a partial application was left
unreduced, so a Python function, a compiled model or any other host callable
held in a MeTTa variable was a value you could pass around and never apply.

```prolog
:- multifile metta_grounded_apply/3.

%   metta_grounded_apply(Value, Args, Out)
metta_grounded_apply(Obj, Args, Out) :- my_callable(Obj), my_apply(Obj, Args, Out).
```

Succeed to claim the head and bind `Out`; **fail and the expression stays
unreduced**, which is what a value that is not an operation should do rather
than raising.

A companion answers the same question with no arguments to hand:

```prolog
:- multifile metta_grounded_applicable/1.

metta_grounded_applicable(Obj) :- my_callable(Obj).
```

`bind!` needs it. A name bound to a callable is callable by that name, which is
the language's own idiom (`(bind! abs (py-atom numpy.absolute))` then
`(abs -5)`), and deciding that at bind time means asking whether a value is an
operation before there are any arguments. The engine consults this only for a head that is neither a
function name nor a partial application, so an ordinary MeTTa call never
reaches it.

Nothing in the engine knows what makes a value applicable, which is the point.
`bindings/python/bridge.pl` claims Python callables, which is what makes
`((py-atom numpy.absolute) -5)` work; a bridge for something else claims its
own.

### Give a value a structure, without giving up the value

MeTTa names three things a grounded value may define for itself: "Grounded
value type creators can define custom **type**, **execution** and **matching**
logic for the value". Type is the class walk above, execution is
`metta_grounded_apply/3`, and this is matching.

```prolog
:- multifile metta_grounded_structure/2.

%   metta_grounded_structure(Value, Expression)
metta_grounded_structure(Obj, Elements) :- my_sequence(Obj, Elements).
```

The problem it solves is that a host container wants to be two things at once.
Held as a value it must stay the host's own object, so that identity survives, a
mutation is visible, and passing it back hands over the same thing. Taken apart
it should read like any MeTTa expression. Answer this and it does both:
`car-atom`, `cdr-atom`, `size-atom`, `sort-atom`, `index-atom` and
`decons-atom` all consult it, and only for an argument that is not already an
expression, so nothing you do here can slow an ordinary list down.

It is one atom with two readings, not two answers, and the disambiguation is
the language's own. A space atom nested in another space already behaves this
way: a query that is "just a variable, e.g. `$x`" matches the atom itself, and a
structured query is delegated inward. So a variable binds your value and a
pattern reads its elements.

Two things to get right. **Check cheaply before you build anything**: this is
consulted for every term that is not a MeTTa expression, so a guard that
allocates before it can fail is a cost with no result. Reading a functor with
`compound_name_arity/3` allocates nothing where `compound_name_arguments/3`
builds the whole argument list first, and the difference measured at 402 million
instructions on one benchmark while showing up nowhere in its inference count.
And **the second argument may arrive partly bound**: if it is a proper list you
can reject on length alone, which is how matching `($x $y)` against a
million-element host container costs one question rather than a million.

A value with no structural reading simply has no clause here, and that is a real
answer rather than a gap: `bindings/python/bridge.pl` gives one to Python sequences and
withholds it from a `dict`, a `set` and a `str`, following PEP 634's rule for
which objects a sequence pattern may take apart.

### Say that an operation is safe to cache

```prolog
:- multifile metta_pure_operation/1.

metta_pure_operation(my_lookup).
```

Anything that may hand back a CACHED answer later reads this: tabling and
memoization both do. Declare an operation here when it only inspects its
arguments, and leave it out when it reads or writes a space, reads or writes
state, prints, draws at random, reads the clock, or crosses to a host.

It is an **allow-list**, and the asymmetry is the whole argument. A missing
entry in a deny-list is a silent wrong answer; a missing entry here is a loud
refusal that someone adds a line for. Before this list existed, tabling treated
an unrecognised goal as inert, and that cached a random draw so two calls
answered from one draw, printed a `println!` once for two calls, performed a
space write once for two calls, and kept answering from the cache after the
Python data behind an operation had changed.

Your library's operations are yours to declare. The engine ships its own core
list and knows nothing about yours, so an operation nobody declares is refused
rather than assumed, which is the safe direction to be wrong in.

From Python it is a keyword rather than a clause, and it says the same thing:

```python
m.register_op(len, name="size", pure=True)
```

### Say who your dispatch goal really is

Only if you are writing a BRIDGE, meaning a tier that compiles a MeTTa
operation into a call on a dispatcher of your own. `register_op` and
`register_prolog` are not this; the Python bridge underneath `register_op` is.

```prolog
:- multifile metta_effect_operation_name/3.

%   metta_effect_operation_name(Goal, Name, Arity)
metta_effect_operation_name(my_dispatch(Name, Args, _), Name, Arity) :-
    length(Args, Arity).
```

The refusal above reads the goal it is refusing, and for a bridge that goal is
yours and not the program's. Without this the Python bridge's refusal said
`petta_py_dispatch_det/3` and advised declaring THAT pure: not a name any
author wrote, and not one a declaration could have matched, since the refusal
never reached the operation's own name. Answer here and the message names what
the program wrote and what `metta_pure_operation/1` will match.

### Say how a value prints

```prolog
:- multifile metta_grounded_text/2.

%   metta_grounded_text(Value, Text)
metta_grounded_text(Obj, Text) :- my_object(Obj), my_render(Obj, Text).
```

The writer has no other way to know. With no provider it falls back to the
term's own text, so this is never required and can never fail a print, but that
fallback names an address where the value could have named itself:
`bindings/python/bridge.pl` answers with `repr`, which is why `(py-atom "[1, 2, 3]")`
displays `[1, 2, 3]` and a numpy array displays `array([1, 2, 3])`.

### The seams this page did not list

`engine/ext_points.pl` declares more than the atom hooks, and two of the rest are
exactly what a performance library wants.

**`metta_dispatch_call/4`** is consulted at every compiled call site,
which makes it the seam for installing your OWN caching strategy rather than
using `lib_memo`'s. `lib/lib_memo.pl` is one implementation of it, not the only
possible one. A handler reads `current_metta_module/1` to learn which module
the call site is in, because a named space compiles its equations into a module
of its own and a function name alone does not identify a function.

**`metta_on_function_changed/1` and `metta_on_function_removed/1`** are how any
library keeps derived state coherent when equations change. The specializer,
the tracer, the memo cache, tabling and the dual predicates all hang off them.

Both are dynamic and both cost per compiled equation while a handler exists,
which is why a library should install its handler when its feature is first
used rather than when its file loads: a resident handler clause measured four
inferences on every compiled equation.

**`metta_grounded_extra_type/2`, `metta_grounded_type_names/2` and
`metta_grounded_class_type/2`** are how a host value gets a TYPE. The class
walk itself is the host bridge's clause of `metta_grounded_class_type/2`,
because enumerating a value's classes is host code by nature: the shipped
Python bridge answers every class on the object's MRO except `object`, so a
`torch.Linear` is a `Linear` and a `Module`, and an engine with no host
loaded has no clause there, which is the right answer for a configuration in
which no host value can exist. `metta_grounded_extra_type/2` adds names
beyond the walk, which is how a protocol an object satisfies can name a type
and a declared `(-> Tensor Tensor Tensor)` can hold for values the host made.
`metta_grounded_type_names/2` replaces the walk entirely, for a bridge that
knows how to read its own objects and answers every name at once.

**The `host_service` surface** is the other half of the host contract: the
engine predicates a host BINDING's transport may call back, measured from the
shipped shim and declared in `engine/ext_points.pl` so the static walk can keep
the list honest. Today's list: `catch_recover/2`, `match_foreign/5`,
`metta_add_atoms/2`, `metta_host_adopt_function/4`,
`metta_host_clear_defined/1`, `metta_host_clear_space/1`,
`metta_host_digest/2`, `metta_host_drop_function/2`,
`metta_host_explain_match/3`, `metta_host_fast_header/1`,
`metta_host_forget_function/1`, `metta_host_load_fast/2`,
`metta_host_load_file/3`, `metta_host_open_function/3`,
`metta_host_operation_error/5`, `metta_host_read_forms/2`,
`metta_host_remove_reported/3`, `metta_host_run_source/4`,
`metta_host_run_source_status/3`, `metta_host_save_fast/3`,
`metta_host_stored/2`, `metta_host_substitute/3`, `metta_reducible_head/2`,
`metta_source_declarations/2`, `metta_space_names/1`,
`metta_string_declarations/2`, `metta_substitute_self/3`,
`metta_trace_source/4`, `petta_annotations/2`, `petta_contract_fact/1`,
`petta_error_answer/3`, `petta_handles_coherent/1`, `petta_on_error_mode/3`,
`petta_source_reset/1`, `petta_transaction/1`, `petta_transport_failure/1`,
`sread_with_names/3`, `translate_expr/3`, `unregister_metta_extension/1` and
`with_metta_module/2`. Shrinking this list is the shim-thinning work's
scoreboard; growing it is a deliberate publication, not a drive-by.

Registering an operation is four of those calls, the engine's own protocol
rather than bookkeeping a binding restates: `metta_host_open_function(Name,
Tier, PredArity)` proves the name free BEFORE you assert anything (a taken
name refuses here, naming its owner); you assert your dispatch clause into
the base tier's module; `metta_host_adopt_function(Name, Tier, Kind,
PredArity)` makes the asserted clause a claimed function and recompiles the
definitions that had been treating the name as data; and on the way out,
`metta_host_drop_function/2` retires one arity while
`metta_host_forget_function/1` releases a name nothing defines any more,
recompiling its mentions back to data.

Reading and removing stored atoms is two more: `metta_host_stored(Space,
Pattern)` enumerates stored atoms unifying a pattern (index-directed on a
native space, provider-enumerated on a foreign one), and
`metta_host_remove_reported(Space, Term, Verdict)` removes with the
whether-anything-went verdict a host API wants. And
`metta_host_explain_match(Space, Patterns, Report)` answers what the seam
already decided for a query without running it, as one term report
(per-pattern classes with structured origins, the plan's claimed and rest
indexes, refusals preflighted), so a transport renders prose instead of
re-deriving routing precedence.

**`metta_host_builtin/1`, `metta_host_import/1`, `metta_form_rewriter/1` and
`metta_host_object/1`** are how a whole HOST plugs in, and the shipped Python
bridge is their one worked example. `metta_host_object/1` answers whether a
value is a live object of the bridge at all, the question in front of every
grounded-type lookup, so an engine with no host loaded answers no at one
failed lookup and never initializes anything. `metta_host_builtin/1` declares the bridge's own operations
(`py-call`, `py-atom` and their family there); the engine's registry
directive registers whatever was declared, so no list inside the engine
names a host. `metta_host_import/1` lets a bridge CLAIM an import whose
source is its own kind of file and perform the whole job itself, lifecycle
included, through the same published `import_when/4` the engine uses; with
no host loaded, or none claiming, every import is a MeTTa import.
`metta_form_rewriter/1` is a registration slot: a rewriter installed there
runs over every loaded form, and a bridge installs one only while the
feature needs it, the way the Python bridge registers its import-as alias
rewrite when the first alias lands, so a program that never uses the
feature pays one failed lookup per form and nothing more.

A clause of either that THROWS is your bug and is not caught. Reading a throw
as "no bridge answered" once ran the class walk instead, and one broken
protocol predicate silently destroyed typing for every host object in the
process, with `get-type` answering the envelope's own class for all of them.
The fallback exists for a bridge that is ABSENT, which is ordinary
configuration, not for one that is broken.

**A cut in one of these is a bug, and in the space hooks it is not.** The
foreign-space hooks are dispatched by OWNERSHIP: exactly one provider answers,
so a clause may cut after the guard that establishes the space is its own, and
`lib/lib_redis.pl` does. The hooks above are EVENTS: every handler runs, the
callers enumerate them with `forall/2`, and a cut in one clause silently
disables every handler loaded after it. Write `( Condition -> Action ; true )`
there, which keeps the guard and prunes nothing. A static check enforces the
distinction.

## 7. Custom matchers: how things match

Matching has two tiers, and they answer to different authorities.

**Inside unification, the value's own matcher is the authority.** A
grounded value that defines matching logic (section 5's
`metta_matchable_value/1` and `metta_custom_match/2`, or any Python
object whose class defines `match_`) is consulted when `(unify ...)`
meets it, and its binding sets are final: nothing re-derives or
re-checks them, exactly as Hyperon's CustomMatch behaves. That is the
point. An embedding matcher's "close enough" has no structural check
even in principle, and a space is exactly such a value whose matcher is
query. The bindings it yields are arbitrary by design, okBind
semantics; `bindings/python/examples/integration/cetta_space.py`'s `CettaMatch`
is a worked instance whose bindings come from a different MeTTa
runtime entirely.

**Above unification, scored matching is a library convention.** A
scoring matcher is a MeTTa function answering `(score value)` pairs,
generating best-first when the candidate is unbound; `lib/lib_soft.metta`
and `lib/lib_measure.metta` are that story, in user space on the
general seam, deliberately not in the engine or the Python package.
Matchers compose through ordinary MeTTa evaluation and nondeterminism,
never through new syntax, because fixing one notion of closeness in the
core would exclude every other.

## 8. The contract: declarations in `&petta`, the extension story itself

Everything above is a MECHANISM. What ties them into one seam is the
contract: declarations are ordinary atoms in the `&petta` space, and the
engine routes queries by them. A backend attaches by declaring what it
can do, not by the engine growing a case for it.

Each declaration is one atom, written through a sugar that validates the
vocabulary or added like any atom. Queries route by the most specific
matching shape, exactly as evaluation dispatches a call against equation
heads; two overlapping entries that disagree are a loud conflict naming
both and the query they disagree on.

| declaration | what it decides | sugar |
|---|---|---|
| `(op <name> <arity> <kind>)` | how a registered operation compiles; `register_op` asserts these and compiles FROM them | `register_op` |
| `(effect <name> immutable)` | the operation may sit in a tabled or memoized body | `register_op(pure=True)` |
| `(cache <name> unchecked)` | the caller accepts stale answers for an impure body | add the atom |
| `(handles <ctx> <pattern> Exact\|Partial\|Sound\|Refuse [det])` | how faithful a context's own filtering is, per shape; `Exact` licenses count pushdown, `Refuse` makes the query a loud error; `(in $x)` marks a position that must arrive bound | `declare_handles` |
| `(source <ctx> linear\|repeated\|peek)` | consumption discipline; a linear source's second touch is loud where the floor answered silently empty | `declare_source` |
| `(on-error <ctx> <shape> keep\|empty\|abort)` | what a provider failure becomes: an `(Error ...)` answer, declared silence, or the abort floor | `declare_on_error` |
| `(writes <ctx> transactional\|atomic-single\|best-effort)` | whether `(transaction ...)` delegates, refuses, or proceeds by declared acceptance | `declare_writes` |
| `(context <ctx> closed-world\|open-world)` | whether negation may consult the context at all | `declare_context` |
| `(annotations <ctx> bool\|bag\|set\|ranked\|prob\|prov)` | the semiring answer annotations live in; `ranked` is what `(top k ...)` consumes, `prov` carries source terms readable via `(annotation)` | `declare_annotations` |
| `(emits <ctx> depth\|fair\|best-first)` | the context's own emission order; best-first lets `top` push its bound | `declare_emits` |
| `(merge <pattern> depth\|fair\|best-first)` | how the engine merges one shape's answers ACROSS contexts | `declare_merge` |
| `(on <ctx> <pattern> <op>)` | a bridge: when a matching atom lands, run `(insert ...)`, `(retract ...)` or `(revise ...)` under the match's bindings | `declare_reaction` |
| `(admits <pool> <Type>)`, `(capacity <pool> <n>)` | a typed, bounded pool; a space of spaces is the thread-pool reading | `declare_admits`, `declare_capacity` |

Ask the seam itself what it will do: `!(explain (match &s <pattern> $x))`
answers the route as atoms, which entry matched, at what fidelity,
whether a bound would push, and every declaration above. What explain
says is what execution does; that law has its own tests.

Undeclared is always today's behaviour: the contract is monotone, and a
provider written before any of this keeps working unchanged.

### The catalog describes its own kinds, and yours

Every row in the table above is an instance of a KIND, and the kinds are
themselves rows in `&petta`:

```
(vocabulary fidelity Exact Partial Sound Refuse)   ; a value set
(kind handles symbol pattern (one-of fidelity)     ; a declaration's shape
      (optional (one-of determinism)))
(claim semiring ranked ordered)                    ; a per-value fact
(routed-by-shape handles)                          ; entries route by shape
```

One generic checker validates every `&petta` write against the standing
kind rows, and a violation is a hard error naming the atom, the argument
position and the argspec it missed, where it used to sit silently and
never match. A head with no kind row passes untouched, so your own kind
starts as plain data and becomes schema-checked the moment you declare
its rows. Argspecs are `symbol`, `integer`, `pattern`, `term`,
`(one-of <vocabulary>)`, trailing `(optional <spec>)` and final
`(rest <spec>)`. Removing a row withdraws it: remove-then-redeclare is
how a program deliberately widens a shipped kind, and the presets return
on the next engine boot only where their subject has no row standing.

`(routed-by-shape <head> [context|global])` gives your kind the SAME
router the shipped ones use: entries are patterns, queries route by the
most specific matching entry with `(in $x)` adornments and loud
coherence conflicts, all inherited, none reimplemented. Read the routed
view back with the published service `petta_shape_route/5`.

To make the engine ACT on your kind, ship exploitation rules riding the
published seams. The routing seam is `metta_route_cap/4`: consulted
where the declared fidelity or the provider's method proposes a route
class, and every loaded advisor may only DEMOTE, the most conservative
voice winning (`refuse` below `inexact` below `exact`, refuse loud and
naming your Why). A freshness kind is the worked instance, an ordinary
extension file:

```prolog
:- metta_extension(freshness, [requires(1-1)]).

:- multifile metta_route_cap/4.
metta_route_cap(Space, Pattern, inexact, freshness(cached)) :-
    petta_shape_route(freshness, Space, Pattern, _, [cached]).
metta_route_cap(Space, Pattern, refuse, freshness(stale)) :-
    petta_shape_route(freshness, Space, Pattern, _, [stale]).
```

With `(vocabulary freshness-level live cached stale)`,
`(kind freshness symbol pattern (one-of freshness-level))` and
`(routed-by-shape freshness)` declared, `(freshness &rows (edge $a $b)
cached)` demotes the engine's bound pushdown to re-unification for that
shape, and `stale` refuses the route outright; the whole path is pinned
by `test_a_third_party_declaration_kind_changes_routing_through_published_seams`.
A freshness vocabulary gating routes is a production discipline, not an
invention here: Oracle's `QUERY_REWRITE_INTEGRITY` decides whether a
stale materialized view may keep serving rewrites, and its `RELY`
constraint state is a per-declaration trust claim the optimizer acts on.

The contract language is MeTTa on purpose, and it reaches the boundary
itself: a backend's whole conversion can be ONE declaration relating
the atom shape to the backend's shape, `(bridge (edge $a $b)
(row edges (a $a) (b $b)))`, used in both directions the way any MeTTa
pattern is. `bindings/python/petta/tables.py` derives a complete SQL provider
from such atoms, WHERE from bound positions, the equalities repeated
variables demand, INSERT from grounding, honest pushdown claims, and
the conformance kit checks the derived claims the way the lens laws
check a bidirectional transformation, the round-trip law now a named
check. A provider takes a SCHEMA, any number of declarations, shapes
answering together the way overlapping equations do; `tables.declare`
writes them into `&petta` ctx-scoped, MeTTa source can add the same
atoms itself, and `TableBridge.from_context` reads them back, so a
program carries its schema as knowledge and the attach is one line. Writing the consistency relation
and deriving both directions is the bidirectional-transformations
literature's third approach, and MeTTa's pattern pairs are already the
right notation for it.

One rule governs every name an extension adds, on either side of the
seam: one concept has one name, and its two spellings map mechanically,
hyphen to underscore, ceremony dropped, never a synonym. `add-atom` is
`add`, `new-space` is `new_space`, and a Python method that stores
`(on ...)` atoms is named after `on`, not after a metaphor. If the
Python name cannot be derived from the MeTTa name by that rule, it is
the wrong name; the guide's Concepts page holds the full table.

## Choosing

| you want to | use |
|---|---|
| add syntax or a control form | a translator rule |
| add a primitive that is called often | a Prolog predicate |
| wrap something already written in C or Rust | a C foreign predicate |
| write logic in Python and run it at MeTTa speed | `@m.define` |
| reach a Python library | a Python operation, `raw=True` if the argument is big |
| ship a fast library that installs with pip | `register_prolog` from Python |
| put atoms somewhere else | a space provider |
| react when a space changes | an atom hook |
| cache calls your own way | `metta_dispatch_call/4` |
| keep derived state coherent | `metta_on_function_changed/1` |
| change what counts as a match | a matcher, by convention |
| reach the engine from a language it has never been used from | the wire codec, [CODEC.md](CODEC.md) |

Three of those are **declared seams** in `engine/ext_points.pl`, and a change to
one is a breaking change: the foreign-space hooks, the atom hooks, and the
memo and function-change hooks. The rest are mechanisms. Custom matchers in
particular are a **convention** rather than a hook, deliberately: they compose
through ordinary evaluation and nondeterminism, so there is nothing to
declare.

If none of these fits, that is worth reporting as a gap rather than working
around: the point of having eight is that forking should never be the answer.
