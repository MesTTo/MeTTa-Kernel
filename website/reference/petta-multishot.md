# `petta.multishot`

Source: `python/petta/multishot.py`.

> Purpose: clingo's multi-shot solving vocabulary on the engine (Gebser,
> Kaminski, Kaufmann, Schaub, "Multi-shot ASP solving with clingo", arXiv
> 1705.09811): programs that change between solves without rebuilding the
> world. A Part is a named, parameterized program template grounded once per
> instantiation, clingo's #program directive; an External is an atom whose
> truth toggles cheaply between solves via assign and ends with release,
> clingo's #external. On an engine with no grounding step an external is
> exactly a togglable fact and grounding a part is exactly instantiating its
> template into the space, which is the honest translation; the solve side of
> the loop is the query surface the space already has, m.query, m.prepare and
> m.assuming. One divergence, deliberate: assigning a released external is a
> hard error here where clingo makes it a silent noop.
> Open Obligations:
>   To Do: None
>   Hacks: None
>   Future Enhancements: None

The entries below reproduce the source signatures and docstrings.

## `External`

```python
class External:
```

> One togglable truth: present while assigned True, absent while
> False, finished by release().
>
>     query1 = multishot.external(m, S.query(1))
>     query1.assign(True)
>     ... m.query(...) ...
>     query1.assign(False)          # next solve sees a different world
>     query1.release()              # permanently gone

### `External.atom`

```python
def atom(self) -> Atom:
```

No docstring is defined.

### `External.value`

```python
def value(self) -> bool:
```

No docstring is defined.

### `External.released`

```python
def released(self) -> bool:
```

No docstring is defined.

### `External.assign`

```python
def assign(self, value: bool) -> None:
```

> Set the truth for the solves that follow; idempotent.

### `External.release`

```python
def release(self) -> None:
```

> End the external: false from here on, permanently.

## `external`

```python
def external(m, atom: Any) -> External:
```

> Declare an atom external: initially false, toggled by assign.

## `Part`

```python
class Part:
```

> One named program template, grounded once per instantiation.
>
>     step = multishot.part(m, "step", lambda t: f"""
>         (= (reach $x {t}) (and (reach $y {t - 1}) (edge $y $x)))
>     """)
>     step.ground(1)
>     step.ground(2)
>     step.ground(1)     # error: this instantiation already grounded
>
> The template answers MeTTa source or an iterable of atoms for its
> parameters; grounding adds it to the space. Grounding one
> instantiation twice would duplicate its rules, the multi-shot
> discipline clingo's documentation warns about, so it is refused.

### `Part.ground`

```python
def ground(self, *args: Any) -> None:
```

No docstring is defined.

### `Part.grounded`

```python
def grounded(self) -> set[tuple]:
```

> Every instantiation grounded so far.

## `part`

```python
def part(m, name: str, template: Callable[..., Any]) -> Part:
```

> Declare a parameterized program part, clingo's #program.
