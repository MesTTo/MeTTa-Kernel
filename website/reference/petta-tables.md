# `petta.tables`

Source: `bindings/python/petta/tables.py`.

> Purpose: derive a whole table-backed space provider from MeTTa bridge
> declarations, so the contract is rewrite rules and both directions of
> the boundary fall out of matching them. The module is petta.tables
> because a subscription bridge is already the standing bridge RULE between two
> spaces (petta.subscribe.bridge); the two are the same idea at two
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
> [source: the GRACE report,
> gsd.uwaterloo.ca/sites/default/files/GRACE-report-ICMT09.pdf; TRIP2 did
> it with Prolog rules, Wadler's views are the in/out pair], and the lens
> round-trip laws are what check_space_provider verifies against the
> derived claims.
>
> Declarations may live in &petta, ctx-scoped like every other contract
> atom: `declare(m, "&crm", "(bridge (edge $a $b) (row edges ...))")`
> writes `(bridge &crm (edge $a $b) (row edges ...))` there, MeTTa source
> can add the same atom itself, and `TableBridge.from_context(m, "&crm",
> connection)` reads every one back, so a program carries its schema as
> knowledge and the attach is one line.
>
> Guarantees:
>   - tagged atom cells preserve explicit s and p species instead of applying
>     process-local engine provenance [tested:
>     test_space_handles_are_term_operands_and_round_trip; commit=WORKTREE]
>   - a database row becomes an atom from its typed cell values; plain text is
>     always a symbol, NULL is Grounded(None), and a structured value is one tagged
>     TEXT cell carrying the atom wire rather than the source parser [tested:
>     test_a_row_value_becomes_an_atom_without_being_reparsed;
>     commit=f88aa8be03cb64cb59d3307515ded8701f418321]
>   - a cell PeTTa wrote reads back as the atom it wrote, whatever the driver
>     and the image catalog do to the database's own values: _is_atom_cell
>     keeps the tag in the text domain, out of reach of a row_factory that
>     adapts binary cells, and _ImageCodec answers it before any image
>     [tested: test_a_nonground_compound_downgrades_and_removal_still_unifies;
>     commit=f88aa8be03cb64cb59d3307515ded8701f418321]
>   - the whole pattern family is filtered exactly where SQL can express
>     it: ground positions become comparisons, a repeated variable becomes
>     the equality it demands (column to column, or column to the declared
>     head literal), and a variable head constrains nothing [tested
>     test_the_kit_certifies_the_pushdown_claim]
>   - a nonground compound below a column variable downgrades pushdown to
>     inexact instead of overclaiming, and removal falls back to
>     unification so it still means what remove-atom means everywhere
>     [tested test_a_nonground_compound_downgrades_and_removal_still_unifies]
>   - writes are refused unless the atom grounds every column, because a
>     row of NULLs standing for variables would silently weaken removal
>     [tested test_a_nonground_add_is_refused]
>   - an atom every shape refuses, or two shapes admit, is refused naming
>     the shapes [tested test_an_ambiguous_add_is_refused_naming_both]
>   - TableBridge.from_context applies `(image <ctx> <Type> <setting>)` to
>     each of the database's own row values before it crosses, keeping opaque
>     objects as handles and projecting transparent objects [tested:
>     test_an_opaque_blob_column_is_reached_by_a_lazy_path_without_crossing;
>     commit=f88aa8be03cb64cb59d3307515ded8701f418321]
> Decides:
>   - declarations are trusted code, not user data: table and column
>     names are interpolated into SQL, so a bridge declaration belongs in
>     the program the way a schema does
> Open Obligations:
>   To Do: None
>   Hacks: None
>   Future Enhancements: None

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
> &petta, so a schema declared from MeTTa source, or by declare()
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

> Write one ctx-scoped bridge declaration into &petta, where explain
> and any program can read the schema, and from_context will.
