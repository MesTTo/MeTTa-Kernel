<!--
Purpose: teach Python-authored equations, rule sets, and lowering declarations.
Guarantees: examples use the narrow Space.define and Rules.lower doors.
[tested: npm run docs:build; commit=e3787593132a7ece2d300397045f7415709847c9]
Purpose: teach Python-authored equations, rule sets, effect propagation, and lowering declarations.
Guarantees: examples use the narrow Space.define and Rules.lower doors, and describe definition effects as a strongest-member join.
[tested: npm run docs:build and test_a_definition_joins_every_called_operations_effect; commit=e3787593132a7ece2d300397045f7415709847c9]
-->

# Write MeTTa in Python

`@m.define` compiles a Python function into MeTTa equations. Calling the decorated name evaluates through its owning space, the ordinary Python function remains available as `.py`, and `S.name(...)` builds a term explicitly.

```python
@m.define
def fact(n):
    if fn.eq(n, 0):
        return 1
    return fn.mul(n, fact(fn.sub(n, 1)))


check("equations run", m.run("!(fact 6)"), [[720]])
check("the Python twin agrees", fact.py(6), 720)
check("calling the name evaluates", fact(6), [720])
check("the S door builds the term", str(S.fact(6)), "(fact 6)")
```

Repeated definitions stack as MeTTa clauses. Literal defaults become head patterns, and the compiler derives first-match guards:

```python
@m.define
def fib(n=0):
    return 0

@m.define
def fib(n=1):
    return 1

@m.define
def fib(n):
    return fn.add(fib(fn.sub(n, 1)), fib(fn.sub(n, 2)))
    # m.run("!(fib 10)") -> [[55]]
```

Python operators and engine relations are two deliberate spellings. Generic
`left + right`, `left < right`, `abs(value)`, `sum(values)`, and their sibling
forms invoke Python's live data model at engine application time. Reflected
methods, container result types, rich-comparison objects, and in-place methods
therefore behave exactly as they do in the `.py` twin. Such a call is
`oracleIO`: an arbitrary dunder may observe or mutate host state.

Use `fn.add(left, right)`, `fn.lt(left, right)`, `fn.abs_math(value)`, and the
other `fn` names when the body means an engine relation. Those terms stay
matchable, reversible where the engine relation is reversible, and eligible
for structural caching. The factorial and Fibonacci examples use this form
because they are translations of MeTTa equations rather than calls into an
unknown Python type. An exact built-in `int` or `float` annotation also lets
the compiler retain a Python-equivalent native numeric head for basic
arithmetic and ordering; protocol-sensitive operations still take the live
Python path.

The subset includes rebinding, `while`, `for`, nested definitions, generators, lambdas, comprehensions, indexing, slicing, formatted strings, and `match(...)` against the running space. Generators compile to nondeterminism. Lowercase names in match patterns bind as variables.

A star pattern in a `case` arm is the engine's segment variable, so it
destructures a run of children the way Python's own star does:

```python
@m.define
def tail(order):
    match order:
        case (S.Order, id, *rest):
            return S.Kept(id, rest)     # rest is the run, as an expression
        case _:
            return S.Other
```

`yield from call(...)` delegates directly only when the compiler knows the
callee is nondeterministic, including self-recursive generators. A call whose
result might instead be iterable data is refused at compile time. Write
`yield call(...)` to delegate its engine answers, or bind returned iterable
data and then `yield from` that value.

## Bind once, share one choice

If `coin()` yields `0` and `1`, a compiled body that returns
`((choice := coin()), choice)` answers `(0 0)` and `(1 1)`. It never answers
`(0 1)` or `(1 0)`. The walrus lowers to `let*`, so one bound
nondeterministic value is chosen once and shared by both uses. Calling
`coin()` separately in both positions makes two choices instead.

Python generators give the binding rule a familiar shape. `g = gen()` binds
one generator object, and consuming `g` in two places shares one stream and
its position. Calling `gen()` twice creates two independent streams. The
walrus or `let` is the shared binding; two calls are two choice sites. A
generator advances when consumed, while a call-time choice reuses its chosen
value, so the analogy is about shared identity rather than iteration order.

A walrus inside an `S(...)`-built term is ordinary term data and is refused by
the compiler. Bind in the compiled Python body as above, or pass the bound
value through a defined constructor function.

## Rules as ordinary atoms

`@rules` gives each generator parameter a rule-local MeTTa variable, and
calls inside the generator follow the staging split. A call whose arguments
carry a rule variable stages, so the law holds the call term (`double(value)`
yields `(double $value)`); a defined call with ground arguments runs at
construction and embeds its single result (`fib(10)` embeds `55`, constant
folding by construction; a ground call answering several results keeps its
call term, preserving multiplicity). A registered operation follows the same
split: a ground op call runs now, firing its effect exactly once, while an op
call carrying a rule variable stages the op-call term, so the law crosses the
host per application and no host code runs on a variable. The result is a
list of ordinary equation atoms you can inspect, match, and add:

```python
@rules
def arithmetic(value):
    yield equation(S.via_rule(value)).to(twice(value))


m.add(*arithmetic)
```

A rule set can also declare its rewrite strategy and required backend through
one door:

```python
declaration = arithmetic.lower(S.topdown, requires=S.mork, space=m)
assert declaration == S.lowering(S.via_rule, S.topdown, S.requires(S.mork))
```

`lower` adds the equations, writes the queryable declaration to the catalog,
and registers each symbolic rule head with the translator. An empty rule set
raises `ValueError` because it has no head to declare.

`equation(lhs).to(rhs)` keeps both halves on one static Python type. It is
sugar for the container door, which remains first-class:
`m.add(S["="](S.twice(V.x), V.x + V.x))`.

A local annotated assignment becomes an in-place MeTTa type claim rather than
being discarded:

```python
@m.define
def checked(value):
    result: int = value
    return result
```

Its body contains `(: $result Number)`. The value binds first and the type
premise then runs, so a known incompatible value produces no answer. Annotation
names resolve only from builtins, the function's globals and its closure;
annotation syntax cannot execute an arbitrary call or user subscript while the
function is compiled.

Unsupported constructs fail with the construct, source line, and a replacement direction. Definitions that only the engine can execute expose a `.py` twin that reports that boundary instead of failing with a Python name error. Function names follow the operation naming policy: the Python name is the MeTTa name, verbatim. Hyphens are the MeTTa convention and Python cannot spell one, so ask for a hyphenated name with `name=` rather than having it inferred.

## Facts already present in the source

Compilation keeps information Python has already parsed instead of asking for
decorator flags. A `Defined` value exposes `source_span`, `free_variables`, and
the derived `effect`; `pure` remains the compatibility projection that is true
only for `pureStructural`. Its `doc` comes from `ast.get_docstring`, so mutating
the function object's `__doc__` cannot change the source claim.

The same facts are ordinary data in `&metta`:

```metta
(source-span &my-space checked "example.py" 10 0 13 17)
(free-variable &my-space checked helper)
(effect checked pureStructural)
```

There is one source span per stacked clause and one free-variable fact per
captured name. Each clause joins the effects of the operations it calls, and
stacked clauses join again. The result is the strongest member of
`pureStructural < readOnlyLookup < nondeterministicReadOnly < writesState <
oracleIO`, the same law `EffectClass.compose` exposes for any operation plan.
An unclassified or host-observable call is classified conservatively rather
than making the fact disappear. Replacing a clause replaces these facts, and
clearing the definition space removes them.

## Exceptions, on the engine's own error algebra

`try`, `except`, `else`, `finally` and `raise` compile onto the algebra the
engine already has:

- `raise` produces an error through the prelude's `throw`, so it finishes the
  enclosing call and travels exactly as an engine-raised error.
- The try body runs under `catch`, which reifies a host exception and passes
  every other value through.
- `if-error` splits the lanes.
- Each arm asks `except`, which compares the carried live classes by identity
  and inheritance, so two unrelated classes with the same name stay distinct.
- An unmatched error re-throws past the rest, which is how Python skips it.

`raise ValueError("why")` stays data,
the term `(throw (ValueError "why"))`, and `except ValueError as e` binds
`error-payload`'s answer, a live instance when one can be reconstructed, so
`str(e)` reads as Python's would.

```python
@m.define
def guarded(x):
    try:
        return 10 // x
    except ZeroDivisionError:
        return S.Undefined
```

`finally` runs on every exit (success, a matched arm, an unmatched error,
a return) in Python's own order, before anything after the try continues.
Two loud edges: a `finally` that reads a name the try rebinds refuses
(the settled binding is not visible there), and `nonlocal` refuses because
a stored equation outlives the frame it would write.

## Dicts and sets are spaces

A dict literal lowers to `lib_dict`'s own image: a SPACE of `(key value)`
atoms, built by `dict-space`, which the library's header measured against
an opaque handle, a live view, and a native type before choosing. The
library imports itself with the definition. `d[k]` is `get-value`, `k in d`
is `dict-has` (a total True/False), `d[k] = v` is `dict-put`'s
replace-or-insert, `del d[k]` is `dict-remove`, `len(d)` is `dict-size`,
and `.keys()`, `.values()`, `.items()`, `.get()` are `get-keys`,
`dict-values`, `dict-pairs` and `get-value`. A set is a dict to `True`,
Python's own kinship, and `{k: f(k) for k in ...}` builds the pair
expression `dict-space` reads back. Every space door works on one: a dict
is matchable, mutable through `+=`, and queryable like anything else. A
missing key answers NOTHING, the space's own reading of absence; a dict
the Python side keeps mutating belongs behind `py({...})` or `view`.

## Pragmas and aliases

`global name` is a pragma: reads and writes go through the definition
module's own dict, carried into the equation as a grounded reference, so
a compiled write is visible to the module and a module rebind is visible
to the next application. `type X = int` is a rewrite rule, exactly as it
reads: the alias becomes an equation on its own name (a union alias
becomes several clauses, the language's own nondeterministic rewrite),
and annotations after it mention the alias. Generic `&`, `|`, `^`, `~`,
`<<`, `>>`, and `//` follow Python's corresponding operator protocols. Use
`fn.bit_and`, `fn.bit_or`, `fn.bit_xor`, `fn.bit_not`,
`fn.bit_shift_left`, `fn.bit_shift_right`, and `fn.floor_div` when the body
means the engine's exact integer family. And `alpha(x, y)` is the `=alpha`
test under the nearest name Python can spell; `Atom.alpha()` builds the same
term on the atom tier, and `fn["=alpha"]` stays the exact door.
