<!--
Purpose: explain Python operation registration, type declarations, context injection, records, and property tests.
Guarantees: examples use Space.op and canonical atom constructors without compatibility aliases.
[tested: npm run docs:build; commit=WORKTREE]
-->

# Python functions as MeTTa functions

`@m.op` registers a Python callable as a MeTTa function. The signature sets its arities. A generator function is nondeterministic, with one MeTTa answer per yield.

```python
@m.op
def double(x: int) -> int:
    return 2 * x                     # !(double 21) -> 42

@m.op
def upto(n: int):
    yield from range(1, n + 1)       # !(collapse (upto 3)) -> (1 2 3)
```

Annotations become declarations in the running space. A `TypeVar` produces a parametric type variable. A `Union` produces one arrow for each member, which the engine reads as superposed declarations. `Callable[[int], int]` maps to a function arrow, and a typed tuple maps element by element. `Annotated[int, "metres"]` keeps `Number` in the arrow and also publishes the matchable claim `(Annotated Number "metres")`, so two values of the same runtime type can carry distinct semantic metadata.

A dataclass, enum, or plain class in a signature becomes a declared type. Its field annotations determine the constructor declaration. Translation is two-way: enums project to symbols, structured objects can project to constructor expressions, and answers can rebuild Python instances.

Defaults register every accepted positional arity. A Python `None` produces no answer unless the integration wrapper uses the engine's effect convention. `m.unregister_op(name)` removes every arity registered under that name.

An `Atom` parameter changes evaluation order; it is not merely a static hint.
The compiler passes that argument as written, before reduction. An
unconstrained parameter receives the evaluated value:

```python
@m.op
def anyatom(term: petta.Atom) -> petta.Atom:
    return term

@m.op
def anyval(term):
    return term
```

With `(= (side) 42)`, `!(anyatom (side))` answers `(side)`, while
`!(anyval (side))` answers `42`. Use `Atom` when the operation intentionally
implements syntax or a control form.

An operation that wants to query the knowledge base does not have to close over `m`. Annotate a parameter as `petta.MeTTa` and the engine fills it, FastAPI's `Depends` read with the house convention that the annotation is the request:

```python
@m.op
def related(term, engine: petta.MeTTa):
    for row in engine.self.query(Expression(S.link, term, V.x)):
        yield row[0]                 # !(related a) never passes the engine
```

The injected engine is bound to the calling context's space, so an operation invoked from a program running in another space queries that space, which is the `&self` reading and what lets one operation compose across spaces without a space argument. The slot never counts toward MeTTa arities or the declared arrow, and only operations that ask pay for the weaving.

See [`petta.ops`](../reference/petta-ops) for annotation mapping and registration, and [`petta.convert`](../reference/petta-convert) for object projection and rebuilding.

## Declaring a data class without a function

Signatures are one road into the type registry; `@petta.record` is the direct one. Stack it on a dataclass, NamedTuple, or Enum and the class converts both ways, its `(: ...)` declarations land in the default space, and it works as a `cast` and `query(into=)` target:

```python
@petta.record
@dataclass
class Edge:
    a: str
    b: str

m = petta.space()
m.query("(: Edge $t)")               # [(-> String String Edge)]
m.query("(Edge $a $b)", into=Edge)   # [Edge(a=..., b=...)] once stored
m.query(V.edge, into=Edge)            # rebuild each complete (Edge ...) atom
```

The decorator does not boot the engine. Conversion registers immediately, so an unregistrable class fails at the decorator rather than at first use, but the declarations are engine-side atoms and land the moment an engine exists: on the first `MeTTa()` construction, or immediately if one is already running. That is what lets `record` sit at module import time in a library that may never start an engine at all.

`cast` checks admission and narrows; it does not construct. Building instances from answers is `query(into=Edge)`, `rows.build(Edge)`, or `petta.convert.build(atom, Edge)`.

## Property-test what you build

`petta.testing` exports the hypothesis strategies this library fuzzes itself with. The generators carry engine truths worth not rediscovering: which names the tokeniser reads back whole, that `true` and `True` are one term on the engine so their spellings canonicalize, and which numbers the printer round-trips. The library's own suite imports the public module as `from petta import testing as pt` and builds its generators from it:

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
    assert petta.wire.from_wire(atom.to_wire()) == atom
```

`atoms(ground=True)` drops variables for space-content generators, `expressions()` roots every example at the shape spaces store, and hypothesis is only imported when a strategy is built, so the module costs nothing at import. The complete surface is in [`petta.testing`](../reference/petta-testing).
