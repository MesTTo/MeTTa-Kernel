# `metta.tables`

Source: `extensions/python/metta/tables.py`.

> Derive a whole table-backed space provider from MeTTa bridge
> declarations, so the contract is rewrite rules and both directions of
> the boundary fall out of matching them. The module is metta.tables
> because a subscription bridge is already the standing bridge RULE between two
> spaces (metta.subscribe.bridge); the two are the same idea at two
> boundaries, a declared correspondence the engine keeps live.
>
>     (bridge (edge $a $b) (row edges (a $a) (b $b)))
>
> One pattern pair relates an atom shape to a table shape. Matched
> left-to-right a query becomes WHERE and an add becomes INSERT; matched
> right-to-left a row becomes the atom. A provider takes a SCHEMA, any
> number of declarations: a schema is a set of rewrite rules the way a
> function is a set of equations, so a query answers the union of every
> shape it admits, exactly as overlapping equations answer together. The
> one place the equation reading is deliberately NOT copied is add: a
> ground atom two shapes admit is refused naming both, because storing
> it twice would invent an occurrence, and a multiset must not.
>
> This is the bidirectional-transformations literature's third approach,
> writing the consistency relation and deriving both transformations
> , and the lens
> round-trip laws are what check_space_provider verifies against the
> derived claims.
>
> Declarations may live in &metta, ctx-scoped like every other contract
> atom: `declare(m, "&crm", "(bridge (edge $a $b) (row edges ...))")`
> writes `(bridge &crm (edge $a $b) (row edges ...))` there, MeTTa source
> can add the same atom itself, and `TableBridge.from_context(m, "&crm",
> connection)` reads every one back, so a program carries its schema as
> knowledge and the attach is one line.

The entries below reproduce the source signatures and docstrings.

## `add`

```python
def add(space: Any, head: Any, data: Any) -> int:
```

> Add a tabular source to a space as ``(head column...)`` facts.

## `Executes`

```python
class Executes(Protocol):
```

> The slice of a DB-API connection the bridge stands on.

### `Executes.execute`

```python
def execute(self, sql: str, parameters: Any = ..., /) -> Any:
```

No docstring is defined.

### `Executes.commit`

```python
def commit(self) -> None:
```

No docstring is defined.

### `Executes.rollback`

```python
def rollback(self) -> None:
```

No docstring is defined.

## `TableBridge`

```python
class TableBridge(SpaceProvider):
```

> Every provider operation derived from the declarations; nothing in
> here is specific to any table.

### `TableBridge.from_context`

```python
def from_context(cls, m: Any, name: str, connection: Executes) -> TableBridge:
```

> The provider for every `(bridge <name> <shape> <row>)` atom in
> &metta, so a schema declared from MeTTa source, or by declare()
> below, becomes a provider in one line.

### `TableBridge.atoms`

```python
def atoms(self) -> Iterator[Atom]:
```

No docstring is defined.

### `TableBridge.match`

```python
def match(self, pattern: Atom, *, limit: int | None = None) -> Iterator[Atom]:
```

No docstring is defined.

### `TableBridge.pushdown`

```python
def pushdown(self, pattern: Atom) -> str:
```

No docstring is defined.

### `TableBridge.add`

```python
def add(self, atom: Atom) -> None:
```

No docstring is defined.

### `TableBridge.remove`

```python
def remove(self, pattern: Atom) -> bool:
```

No docstring is defined.

### `TableBridge.clear`

```python
def clear(self) -> None:
```

No docstring is defined.

### `TableBridge.begin`

```python
def begin(self) -> None:
```

No docstring is defined.

### `TableBridge.commit`

```python
def commit(self) -> None:
```

No docstring is defined.

### `TableBridge.rollback`

```python
def rollback(self) -> None:
```

No docstring is defined.

## `declare`

```python
def declare(m: Any, name: str, declaration: Atom | str) -> Atom:
```

> Write one ctx-scoped bridge declaration into &metta, where explain
> and any program can read the schema, and from_context will.
