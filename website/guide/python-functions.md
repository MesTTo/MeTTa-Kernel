<!--
Purpose: explain Python operation registration, compiled host islands, effect and type declarations, context injection, and property tests.
Guarantees: examples classify every Space.op with a canonical EffectClass, use Space.define and canonical atom constructors without compatibility aliases, and mark every inline host crossing with py(expr).
[tested: npm run docs:build, test_effect_class_is_the_public_five_rank_join_lattice,
test_define_wires_the_declarative_dance, and test_guides_keep_documentation_law_explainers;
commit=3cfbe0d7417b1c453c2dc12d47e2e47e7de461f7]
-->

# Python functions as MeTTa functions

`@m.op` registers a Python callable as a MeTTa function. The signature sets its arities. A generator function is nondeterministic, with one MeTTa answer per yield.

```python
from metta.vocabularies import EffectClass


@m.op(effect=EffectClass.pureStructural)
def double(x: int) -> int:
    return 2 * x                     # !(double 21) -> 42

@m.op(effect=EffectClass.nondeterministicReadOnly)
def upto(n: int):
    yield from range(1, n + 1)       # !(collapse (upto 3)) -> (1 2 3)
```

Every registration requires effect metadata. New code passes it through
`effect=`; an existing `(effect name class)` declaration atom remains a
compatibility input. The ordered choices are
`pureStructural`, `readOnlyLookup`, `nondeterministicReadOnly`, `writesState`,
and `oracleIO`; missing metadata refuses before registration and names all five
remedies. Choose the strongest behavior the callable may perform. A generator
or generator inverse must be at least `nondeterministicReadOnly`.

Every operation reflects one canonical `(effect name class)` row in `&metta`.
`EffectClass.compose(step.effect for step in plan)` computes a composed plan's
class from those reflected values by taking its strongest member. The retired
input spellings remain accepted only for migration: `immutable` maps to
`pureStructural`, `stable` to
`readOnlyLookup`, and `volatile` to `oracleIO`.

Annotations become declarations in the running space. A `TypeVar` produces a parametric type variable. A `Union` produces one arrow for each member, which the engine reads as superposed declarations. `Callable[[int], int]` maps to a function arrow, and a typed tuple maps element by element. `Annotated[int, "metres"]` keeps `Number` in the arrow and also publishes the matchable claim `(Annotated Number "metres")`, so two values of the same runtime type can carry distinct semantic metadata.

A dataclass, enum, or plain class in a signature becomes a declared type. Its field annotations determine the constructor declaration. Translation is two-way: enums project to symbols, structured objects can project to constructor expressions, and answers can rebuild Python instances.

Defaults register every accepted positional arity. A Python `None` produces no
answer; effect metadata describes observation and does not change the answer
shape. `m.unregister_op(name)` removes every arity registered under that name.

An `Atom` parameter changes evaluation order; it is not merely a static hint.
The compiler passes that argument as written, before reduction. An
unconstrained parameter receives the evaluated value:

```python
@m.op(effect=EffectClass.pureStructural)
def anyatom(term: metta.Atom) -> metta.Atom:
    return term

@m.op(effect=EffectClass.pureStructural)
def anyval(term):
    return term
```

With `(= (side) 42)`, `!(anyatom (side))` answers `(side)`, while
`!(anyval (side))` answers `42`. Use `Atom` when the operation intentionally
implements syntax or a control form.

An operation that wants to query the knowledge base does not have to close over `m`. Annotate a parameter as `metta.MeTTa` and the engine fills it, FastAPI's `Depends` read with the house convention that the annotation is the request:

```python
@m.op(effect=EffectClass.nondeterministicReadOnly)
def related(term, engine: metta.MeTTa):
    for row in engine.self.match(Expression(S.link, term, V.x)):
        yield row[0]                 # !(related a) never passes the engine
```

The injected engine is bound to the calling context's space, so an operation invoked from a program running in another space queries that space, which is the `&self` reading and what lets one operation compose across spaces without a space argument. The slot never counts toward MeTTa arities or the declared arrow, and only operations that ask pay for the weaving.

See [`metta.ops`](../reference/metta-ops) for annotation mapping and registration, and [`metta.convert`](../reference/metta-convert) for object projection and rebuilding.

## Cross into Python inside a compiled body

A compiled `@m.define` body is an atom program, and anything in it the
vocabulary does not lower natively crosses as a HOST ISLAND: an applicable
grounded atom holding the author's own expression, run once per engine
application. Nothing is hidden: the island sits in the equation as data,
`m.lint()` sees it, and nothing host-side runs at decoration time.
Use an operation when the host behavior has a reusable name. Use `py(expr)`
when you want the boundary SPELLED at that one call site:

```python
from metta import py


@m.define
def status(url):
    return py(requests.get(url).status_code)
```

The decorator does not run `requests.get`. The marked expression runs once per
engine application with that application's current `url`, and the definition's
derived effect is `oracleIO`. Outside a compiled body, `py(value)` is an
identity function, so `status.py(url)` remains the ordinary Python twin.

An unmarked call such as `requests.get(url)` islands exactly as the marked
form does: the same expression, the same application-time run, the same
`oracleIO` classification. What still refuses at decoration time is a name
that resolves NOWHERE. A typo is Python's own NameError ground, and a
compile-time refusal beats a runtime one. The two named boundaries remain
the better spellings where they fit: an `@metta.op(effect=...)` gives the
behavior a reusable name, and `py(...)` marks a one-off crossing as chosen
rather than incidental.

`m.lint()` reports `host-island-in-loop` when an island sits in a `for`,
`while`, or comprehension body. Each iteration crosses the engine/host
boundary. Move invariant work before the loop, batch it, or use a named
operation when the repeated crossing is deliberate.

## Declaring a data class

`Space.define` accepts classes as well as functions. Stack it on a dataclass, NamedTuple, or Enum and the class converts both ways, its `(: ...)` declarations land in that space, and it works as a `cast` and `match(into=)` target:

```python
@m.define
@dataclass
class Edge:
    a: str
    b: str

m.match("(: Edge $t)")               # [(-> String String Edge)]
m.match("(Edge $a $b)", into=Edge)   # [Edge(a=..., b=...)] once stored
m.match(V.edge, into=Edge)            # rebuild each complete (Edge ...) atom
```

Declaration is context-relative and immediate: an unregistrable class fails at the decorator, and its declarations land in the same space that owns the decorator. There is no process-global class registry or second root decorator.

`cast` checks admission and narrows; it does not construct. Building instances from answers is `match(into=Edge)`, `rows.build(Edge)`, or `metta.convert.build(atom, Edge)`.

Records update by replacement. On the Python 3.12 floor,
`changed = edge.__replace__(b="new")` returns a new `Edge` and leaves `edge`
unchanged. Constructing `Edge(edge.a, "new")` is the explicit longhand. Python
3.13 adds the general spelling `copy.replace(edge, b="new")`; it uses the same
`__replace__` protocol and also returns a new record. Projecting the replacement
back to MeTTa produces a new constructor term rather than mutating a stored
term.

An attribute docstring written immediately after a field is source-only.
`@m.define` reads that source and includes the field text in the emitted
`(@doc ...)` atom. CPython does not attach the text to the runtime field. A
slots field such as `Order.total` therefore has
`Order.total.__doc__ is None`, and a plain field may have no class attribute at
all. Read the emitted `@doc` data; do not use `field.__doc__` as the
documentation door.

## Property-test what you build

`metta.testing` exports the hypothesis strategies this library fuzzes itself with. The generators carry engine truths worth not rediscovering: which names the tokeniser reads back whole, that `true` and `True` are one term on the engine so their spellings canonicalize, and which numbers the printer round-trips. The library's own suite imports the public module as `from metta import testing as pt` and builds its generators from it:

```python
_name = pt.names()
_numbers = pt.numbers()
_strings = pt.texts()
_atoms = pt.atoms
```

A property over your own translator or operation is then one decorator:

```python
@given(_atoms())
def test_python_wire_round_trip(atom):
    assert metta.wire.from_wire(atom.to_wire()) == atom
```

`atoms(ground=True)` drops variables for space-content generators, `expressions()` roots every example at the shape spaces store, and hypothesis is only imported when a strategy is built, so the module costs nothing at import. The complete surface is in [`metta.testing`](../reference/metta-testing).
