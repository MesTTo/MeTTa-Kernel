<!--
Purpose: explain Python operation registration, type declarations, context injection, and property tests.
Guarantees: examples use Space.op, Space.define, and canonical atom constructors without compatibility aliases.
[tested: npm run docs:build and test_define_wires_the_declarative_dance;
commit=cff2e7f319bd2212f0c2d74f8d5fe5be3ac693b5]
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
def anyatom(term: metta.Atom) -> metta.Atom:
    return term

@m.op
def anyval(term):
    return term
```

With `(= (side) 42)`, `!(anyatom (side))` answers `(side)`, while
`!(anyval (side))` answers `42`. Use `Atom` when the operation intentionally
implements syntax or a control form.

An operation that wants to query the knowledge base does not have to close over `m`. Annotate a parameter as `metta.MeTTa` and the engine fills it, FastAPI's `Depends` read with the house convention that the annotation is the request:

```python
@m.op
def related(term, engine: metta.MeTTa):
    for row in engine.self.match(Expression(S.link, term, V.x)):
        yield row[0]                 # !(related a) never passes the engine
```

The injected engine is bound to the calling context's space, so an operation invoked from a program running in another space queries that space, which is the `&self` reading and what lets one operation compose across spaces without a space argument. The slot never counts toward MeTTa arities or the declared arrow, and only operations that ask pay for the weaving.

See [`metta.ops`](../reference/metta-ops) for annotation mapping and registration, and [`metta.convert`](../reference/metta-convert) for object projection and rebuilding.

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
