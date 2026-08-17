# Python functions as MeTTa functions

`@m.register_op` registers a Python callable as a MeTTa function. The signature sets its arities. A generator function is nondeterministic, with one MeTTa answer per yield. `@m.op` is the same decorator under a shorter name, kept so existing code and notebooks keep running.

```python
@m.register_op
def double(x: int) -> int:
    return 2 * x                     # !(double 21) -> 42

@m.register_op
def upto(n: int):
    yield from range(1, n + 1)       # !(collapse (upto 3)) -> (1 2 3)
```

Annotations become declarations in the running space. A `TypeVar` produces a parametric type variable. A `Union` produces one arrow for each member, which the engine reads as superposed declarations. `Callable[[int], int]` maps to a function arrow, and a typed tuple maps element by element.

A dataclass, enum, or plain class in a signature becomes a declared type. Its field annotations determine the constructor declaration. Translation is two-way: enums project to symbols, structured objects can project to constructor expressions, and answers can rebuild Python instances.

Defaults register every accepted positional arity. A Python `None` produces no answer unless the integration wrapper uses the engine's effect convention. `m.unregister_op(name)` removes every arity registered under that name.

See [`petta.ops`](../reference/petta-ops) for annotation mapping and registration, and [`petta.convert`](../reference/petta-convert) for object projection and rebuilding.

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
    assert from_wire(atom.to_wire()) == atom
```

`atoms(ground=True)` drops variables for space-content generators, `expressions()` roots every example at the shape spaces store, and hypothesis is only imported when a strategy is built, so the module costs nothing at import. The complete surface is in [`petta.testing`](../reference/petta-testing).

## The other direction: a MeTTa function as a Python callable

`m.fn(name)` answers any engine function as an ordinary Python callable, and the object speaks the whole function protocol, answering from MeTTa's own declarations. `__doc__` reads the space's `(@doc name ...)` atom, so `help(m.fn("inc"))` shows the documentation written in MeTTa, and a builtin answers from the engine's own register with no import. `inspect.signature()` reads the declared arrow, one positional-only parameter per arrow slot with the type as its annotation; a name with no arrow answers an honest `(*args)`. `.type` is the declared type atom or `None`, and `.equations` answers the stored `(= ...)` atoms, live rather than as a snapshot:

```python
m.run("(: inc (-> Number Number))")
m.run("(= (inc $x) (+ $x 1))")
f = m.fn("inc")
inspect.signature(f)     # (x1: 'Number', /) -> 'Number'
f.equations              # [Expr('(= (inc $_1) (+ $_1 1))')]
```

Because the object is an ordinary callable, `functools.partial(m.fn("add"), 10)` composes with stdlib machinery, which is the whole bound-method story; there is deliberately no `__defaults__`, because MeTTa has no default arguments.

`.compiled`, also reachable as `m.disassemble(name)`, answers the Prolog clauses the name compiled to, one listing per registered arity. Homoiconicity shows the source for free, since `(= ...)` atoms are data; this is the other half, what the engine actually runs for a call, the same debuggability bytecode's `dis` gives Python:

```python
print(m.disassemble("inc"))
# inc(A, B) :-
#     +(A, 1, B).
```

Watching a function change is a subscription, because a function is a set of equations and equations are atoms: `m.subscribe("(= (inc $x) $body)", callback, on="both")` fires on every equation added or removed for the name, bindings included, which is the function-watcher story with no new machinery.
