<!--
Purpose: teach the CMeTTa extension itself: how it builds, how a C program of your
  own links against it, and the one thing that is true of this extension and no
  other, which is that the engine runs inside your process and there is no
  serialisation at the boundary.
Assumes: the reader writes C, and has SWI-Prolog with its development headers
  and a C compiler.
Guarantees:
  - every fence was compiled and run against this checkout on 2026-08-29, and
    the outputs written beside them are what it printed
    [source: extensions/cmetta/examples/hello.c,
    extensions/cmetta/examples/ops.c, extensions/cmetta/examples/stream.c,
    extensions/cmetta/examples/lower.c; commit=57f21ba9edf94bcf28cde11f938bce2c241a3709]
  - the four example programs run under the extension's own suite, so a fence copied
    from one cannot drift away from working code
        [tested: sh extensions/cmetta/test.sh;
    commit=57f21ba9edf94bcf28cde11f938bce2c241a3709]
  - the page is in the navigation and its links resolve
    [tested: test_every_site_page_is_reachable_from_the_navigation,
    npm run docs:build; commit=57f21ba9edf94bcf28cde11f938bce2c241a3709]
-->

# The CMeTTa tutorial

Here is a whole program. It installs a rewrite, runs it, and reduces a term
built in C.

```c
#define MT_SHORTHAND
#include <cmetta.h>
#include <stdio.h>

int main(void)
{ metta *m = mt_open(NULL);
  if ( !m ) return fprintf(stderr, "boot: %s\n", mt_errmsg()), 1;

  mt_do(m, "(= (double $x) (* 2 $x))");

  mt_each (a, mt_run(m, "!(double 21)"))
      printf("%s\n", mt_show(a));

  printf("%lld\n", (long long)mt_one_int(mt_eval(m, E("+", 1, 2))));

  mt_close(m);
  return 0;
}
```

```text
42
3
```

`mt_open` starts the engine in the process this `main` is running in. There is
no server, no socket and no subprocess.

## Build the library

```sh
cd extensions/cmetta
make
```

That produces `libcmetta.so`, the four example programs, and the two drivers
the cross-extension parity test and the benchmarks use. `make test` builds from
clean and runs the C suite, the header-surface check, and all four examples.

Two prerequisites: a C compiler, and SWI-Prolog with its development files.
The Makefile finds SWI by asking SWI, through
`swipl --dump-runtime-variables`, which is how SWI tells a build where its
headers and `libswipl` are without a pkg-config file. When one of them is
missing, the build says so and names the package instead of failing later on a
header it cannot find:

```text
Makefile:34: *** swipl is not on PATH or does not answer --dump-runtime-variables;
this binding EMBEDS SWI-Prolog and needs its development files. Set
SWIPL=/path/to/swipl, or install the SWI-Prolog development package.  Stop.
```

`swipl-ld` is not the tool here. It builds an extension loaded INTO SWI, and
this extension goes the other way: it calls `PL_initialise` to embed SWI in a C
program of yours.

## Compile a program of your own

One header to include and one library to link. The two SWI paths come from the
same place the Makefile gets them:

```sh
PLBASE=$(swipl --dump-runtime-variables | sed -n 's/^PLBASE="\(.*\)";$/\1/p')
PLLIBDIR=$(swipl --dump-runtime-variables | sed -n 's/^PLLIBDIR="\(.*\)";$/\1/p')

cc -std=c11 -I extensions/cmetta -I "$PLBASE/include" \
   first.c -o first \
   -L extensions/cmetta -Wl,-rpath,"$PWD/extensions/cmetta" -lcmetta \
   -L "$PLLIBDIR" -Wl,-rpath,"$PLLIBDIR" -lswipl
```

Add `-lm` if your program uses libm. The engine tree is baked into
`libcmetta.so` at build time, so a linked program boots with nothing set in the
environment; `METTA_PATH` still overrides it at run time.

## There is no boundary to cross

This is what makes the extension worth having. PyMeTTa reaches the engine through
janus and MeTTa-node reaches it through a WebAssembly build, so both cross a
language boundary and both encode every term into the tagged arrays
[the wire codec](../../engine/codec) describes. C is already inside. It
reads `term_t` directly with the `PL_get_*` family, and there is no wire codec
on this path at all.

That shows up in the surface as terms you build with no parsing step:

```c
mt_expr("+", 1, 2)                     /* (+ 1 2)       */
mt_expr("edge", "a", mt_var("y"))      /* (edge a $y)   */
mt_expr("f", mt_expr("g", 1), 2.5)     /* (f (g 1) 2.5) */
```

No count to keep in step and no constructor per child: `_Generic` reads each
argument's C type, so an integer becomes a Number, a float a Number, a bare
string a Symbol, and an atom itself. Building and reading terms starts no
engine. `#define MT_SHORTHAND` before the include gives you the one-letter
builders `S() V() T() N() R() B() E()`.

A bare C string in term position is a SYMBOL, so `mt_expr("+", 1, 2)` is
`(+ 1 2)` and not `("+" 1 2)`. MeTTa writes a symbol bare and a string quoted;
in C everything is quoted, so the default is the one MeTTa writes bare. Text is
`mt_text("...")`.

`mt_show()` is display text for logs and terminals. When the text must be read
back as the same atom, use the counted writer and reader:

```c
mt_string source = mt_write_dup(atom);
mt_atom *copy = source.data ? mt_parsen(source.data, source.len) : NULL;
mt_free(source.data);
```

The count preserves an embedded NUL. The strict writer refuses a value whose
presentation spelling would read back as another atom.

For a hash table in your C process, use `mt_hash(atom)` beside `mt_eq(a, b)`.
Equal atoms always have the same 64-bit hash, including NaNs and live objects
that crossed the engine and returned as another C atom. It is a fast,
non-cryptographic table hash. Object addresses and native byte order make it
process-local, so it is not a persistent atom identifier.

Unification and substitution are pure C walks too. They do not start the
engine:

```c
mt_atom *pattern = E("job", V("who"), V("rank"));
mt_atom *fact = E("job", "ada", 9);
mt_atom *template = E("hired", V("who"), V("rank"));
mt_bindings *bindings = mt_unify(pattern, fact);
mt_atom *answer = bindings ? mt_substitute(template, bindings) : NULL;

if ( answer ) printf("%s\n", mt_show(answer));  /* (hired ada 9) */

mt_drop(answer);
mt_bindings_free(bindings);
mt_drop(template);
mt_drop(fact);
mt_drop(pattern);
```

`mt_unify` borrows both operands and returns an owned normalized binding set.
Variables on either side bind. `_` remains anonymous. `mt_unifyv` makes every
operand agree with the first under one shared substitution. A structural
mismatch returns NULL without setting `mt_error`, while an allocation or
contract failure records its reason. `mt_binding(bindings, "who")` borrows one
value; `mt_bindings_len`, `mt_binding_var` and `mt_binding_value` iterate all of
them. The binding set retains its atoms until `mt_bindings_free`.

Two more rules and you have the memory and error models. A `const mt_atom *`
BORROWS and a non-`const` one is TAKEN, so every function you hand a fresh term to
consumes it and the common shape needs no cleanup line; `mt_keep(t)` hands over
a new reference for a term you are keeping. Errors are `errno`-shaped: set on
failure and not cleared on success, so a run of calls is checked once with
`mt_ok()` after `mt_clear()` rather than once per call.

## Answers are stepped, not drained

`mt_eval` computes one answer per step, so an endless generator is ordinary.
`mt_each` opens the cursor, walks it and closes it however the loop is left,
`break` included:

```c
int taken = 0;

mt_do(m, "(= (from $n) (superpose ($n (from (+ $n 1)))))");

mt_each (a, mt_eval(m, E("from", 0)))
{ printf("take %d: %lld\n", ++taken, (long long)mt_int(a));
  if ( taken == 5 ) break;          /* the sixth is never computed */
}
```

```text
take 1: 0
take 2: 1
take 3: 2
take 4: 3
take 5: 4
```

`mt_rows` binds an `mt_row` instead of the atom alone, which carries the atom,
the engine's own rendering of it, the `!` group it came from, and the cursor.
The cursor keeps the pattern it was opened with, so `mt_bound` gives a binding
back under the name you wrote:

```c
mt_rows (row, mt_match(kb, E("edge", "a", V("n"))))
    printf("n = %s\n", mt_show(mt_bound(row, "n")));
```

That is `mt_bound(row, "n")` rather than `mt_at(row, 2)` and a comment
explaining why 2. It works at any depth in the pattern and costs one walk of
the term, with no engine call.

When you want one value rather than a walk, four functions take it for you.
`mt_one(r)` claims exactly one answer and refuses zero or many.
`mt_first(r)` takes the first and claims nothing about the rest.
`mt_one_int(r)`, and its `_float`, `_truth` and `_name` siblings, give you
the value with no atom to look after. `mt_all(r)` gives every answer as an
`mt_list`. Each consumes the cursor.

The resulting list can become one space write without rebuilding it:

```c
mt_list values = mt_all(mt_run(m, "!(superpose (red green blue))"));
if ( !mt_add_all(kb, values) ) fprintf(stderr, "%s\n", mt_errmsg());
```

`mt_add_all` takes the array and every atom, checks every member before the
write, and reaches the engine once for the whole batch. `{NULL, 0}` is a valid
empty batch.

## C values and functions

`mt_object(pointer, type_name, release)` carries a C value through MeTTa by
identity. SWI normally releases its blob during atom garbage collection, and
the callback runs when that engine reference and every C reference are gone.
Use `mt_object_free(handle)` when the resource must close immediately. It
consumes the handle and invalidates any aliases still stored in the engine; an
attempt to return one reports `MT_UNSUPPORTED` rather than dereferencing the
released value. A reference retained with `mt_keep` remains valid until it is
dropped.

There are two ways to give MeTTa a C function. `mt_def` publishes a C function the
engine CALLS:

```c
static mt_status op_hypot(mt_call *call, void *user)
{ double a, b;
  (void)user;

  mt_clear();
  a = mt_float(mt_arg(call, 0));
  b = mt_float(mt_arg(call, 1));
  if ( !mt_ok() ) return mt_fail(call, "hypot wants two numbers");
  return mt_answer(call, R(hypot(a, b)));
}

mt_def(m, (mt_op){ .name = "hypot", .arity = 2,
                   .effect = MT_PURE, .fn = op_hypot });
```

`(hypot 3.0 4.0)` now answers `5.0`. Designated initializers are what C has
instead of keyword arguments, and they are why the effect class reads at the
call site rather than being the third of five positional arguments. Naming it
is required: the engine cannot see inside a published function, so it reasons
about caching, reordering and transactions from that one field. The name
reaches MeTTa through C's own casing convention, so a function called
`word_count` publishes as `word-count`.

`mt_lower` installs an EQUATION, which is a different thing:

```c
mt_lower(m, (twice $x), (* 2 $x));
mt_lower(m, (fib $n), (if (< $n 2) $n
                          (+ (fib (- $n 1)) (fib (- $n 2)))));
```

The body is C tokens the compiler saw, so there is no quoting, no escaped
newlines, and unbalanced parentheses are a compile error rather than a runtime
one. `mt_lower` expands C macros before stringifying, which is useful for a body
parameterised by operator macros. Use `mt_lower_raw` when a MeTTa symbol
collides with a C macro and its literal spelling must survive. The preprocessor
is what makes it possible: Python lowers by reading a
function's `__code__` and Node by reading its `toString()`, and C has neither
at run time but has `#`, which is access to the program's own source at the one
moment C offers it.

The difference is what the engine can see. A lowered equation is an atom in the
space, so you can ask about it:

```c
mt_each (a, mt_match(mt_self(m), E("=", E("poly", V("x")), V("body"))))
    puts(mt_show(a));
```

```text
(= (poly $_0) (+ (* 3 $_1) 1))
```

The same query against an `mt_def` name finds nothing, and a lowered call
crosses into no host at all. `examples/lower.c` runs both sides, including one
body parameterised by its operators so that it expands to C in one mode and to
MeTTa in the other, and the function exists once and is callable from both.

## Put a bound on it, because it is your process

An embedded engine that cannot be stopped is a hazard, so bounds are part of
the surface:

```c
mt_limit(m, (mt_limits){ .seconds = 2.0, .inferences = 1000 });
if ( !mt_run(m, "!(from 0)") && mt_error() == MT_LIMIT )
    fprintf(stderr, "%s\n", mt_errmsg());
```

```text
metta: the evaluation passed its 1000 inference bound and was stopped (inference_limit)
```

`MT_LIMIT` is its own status because a bound is not a fault. On a lazy cursor
the inference bound is a cumulative budget for the whole cursor, built into the
goal the engine runs, so a bigger budget really does buy more steps. The wall
bound applies per step, so time your host spends between steps does not count
against it, and a bound stops work mid-way and lets what was already made
stand.

One runtime per process, because `PL_initialise` sets up the process's single
Prolog heap. A second `mt_open` with a matching configuration hands back the
same runtime. A thread other than the one that opened it calls
`mt_thread_attach` before touching the engine.

## Where to go next

[The CMeTTa extension page](./) is the extension's own README: the five rules in full,
the twelve atom kinds, scope cleanup with `MT_AUTO`, measuring with the
engine's own counters, and what a C value crossing MeTTa by reference does and
does not get. `extensions/cmetta/cmetta.h` is the contract and documents every
call. `extensions/cmetta/examples/` holds the four programs this page draws
from: `hello`, `ops`, `stream` and `lower`.
