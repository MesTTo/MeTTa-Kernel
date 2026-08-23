# `metta.derivation`

Source: `bindings/python/metta/derivation.py`.

> Purpose: proof trees as Python objects. Parses the (derivation ...) atoms
> the shim's meta-interpreter produces into a tree of steps, facts and builtin
> leaves, records finite-depth truncation without confusing it with no proof,
> and renders the result as indented text or notebook HTML.
> Guarantees:
>   - Derivation.complete is false exactly when a Truncated node occurs
>     [tested test_depth_exhaustion_returns_a_partial_proof]
> Open Obligations:
>   To Do: None
>   Hacks: None
>   Future Enhancements: why-not trees for derivations that fail.

The entries below reproduce the source signatures and docstrings.

## `Fact`

```python
class Fact:
```

> A stored atom the proof rests on, and the space holding it.

### `Fact.render`

```python
def render(self, indent: int) -> str:
```

No docstring is defined.

## `Builtin`

```python
class Builtin:
```

> An engine-level goal the proof used, kept as the engine wrote it.

### `Builtin.render`

```python
def render(self, indent: int) -> str:
```

No docstring is defined.

## `Truncated`

```python
class Truncated:
```

> A finite proof budget ended before this engine goal was explained.

### `Truncated.render`

```python
def render(self, indent: int) -> str:
```

No docstring is defined.

## `Step`

```python
class Step:
```

> One equation firing: the call it answered and the equation used.

### `Step.render`

```python
def render(self, indent: int) -> str:
```

No docstring is defined.

## `Derivation`

```python
class Derivation:
```

> One complete proof of an answer.
>
> steps are the equations that fired in order; facts and rules list the
> leaves and equations involved, deduplicated, which is usually the part a
> reader wants first.

### `Derivation.from_atom`

```python
def from_atom(tree: Atom) -> Derivation:
```

> Parse the (derivation (answer Call Out) Steps...) atom.

### `Derivation.facts`

```python
def facts(self) -> list[Fact]:
```

No docstring is defined.

### `Derivation.rules`

```python
def rules(self) -> list[Atom]:
```

No docstring is defined.

### `Derivation.truncations`

```python
def truncations(self) -> list[Truncated]:
```

> Every point where a finite depth stopped this proof walk.

### `Derivation.complete`

```python
def complete(self) -> bool:
```

> Whether the tree explains the proof without a depth cutoff.
