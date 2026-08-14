# `petta.results`

Source: `python/petta/results.py`.

> Purpose: query results as rows. A Rows is a mutable sequence of Row tuples, one per
> answer, with the query's variable names as columns and attribute access per
> column, so rows drop into unpacking, DataFrame constructors and pattern
> matching without a helper in between.
> Guarantees:
>   - Rows with the same columns share one bounded cached Row subclass [tested
>     test_row_classes_are_reused_and_bounded]
>   - slicing, copying, concatenation, and repetition preserve Rows and its
>     columns [tested test_rows_sequence_operations_preserve_columns]
>   - every mutation validates row width and preserves the named Row type
>     [tested test_rows_mutations_preserve_invariants]
>   - Row and Rows pickle through stable module-level rebuild functions rather
>     than dynamic class names [tested test_rows_copy_and_pickle_protocols]
>   - terminal representations bound both rows and individual values and state
>     the omitted row count [tested test_rows_repr_is_bounded_and_recursive]
> Open Obligations:
>   To Do: None
>   Hacks: None
>   Future Enhancements: None

The entries below reproduce the source signatures and docstrings.

## `Row`

```python
class Row(tuple):
```

> One answer: a tuple whose fields are the query's variable names.
>
> The column names live on a per-query subclass rather than on the
> instance, because a tuple subclass with empty slots has nowhere to put
> per-instance state.

### `Row.asdict`

```python
def asdict(self) -> dict[str, Any]:
```

> Return this row as a column-to-value mapping.

## `Rows`

```python
class Rows(UserList[Row]):
```

> Every answer to a query, in the order the engine produced them.
>
> Sequence operations retain this type and its columns. ``rows["name"]``
> projects a column, while integer and slice indexing follow a normal list.

### `Rows.insert`

```python
def insert(self, i: int, item: Iterable[Any]) -> None:
```

No docstring is defined.

### `Rows.append`

```python
def append(self, item: Iterable[Any]) -> None:
```

No docstring is defined.

### `Rows.extend`

```python
def extend(self, other: Iterable[Iterable[Any]]) -> None:
```

No docstring is defined.

### `Rows.copy`

```python
def copy(self) -> Rows:
```

No docstring is defined.

### `Rows.column`

```python
def column(self, name: str) -> list[Any]:
```

> Return one named column as a list.

### `Rows.first`

```python
def first(self) -> Row | None:
```

> The first row, or None when there are no answers: the tolerant
> accessor, SQLAlchemy's own naming.

### `Rows.one`

```python
def one(self) -> Row:
```

> THE row, when the query is asserted to have exactly one answer;
> none or several raise naming the count, so a lookup that silently
> picked an arbitrary row cannot hide.

### `Rows.build`

```python
def build(self, column: str, cls: type) -> list[Any]:
```

> One column's atoms rebuilt as instances of cls, through the
> two-way translator: typed rows, one call.

### `Rows.table`

```python
def table(self) -> dict[str, list[Any]]:
```

> The columns as a dict of plain values, the one shape every
> DataFrame constructor takes: pl.DataFrame(rows.table()),
> pd.DataFrame(rows.table()). Grounded values unwrap to Python;
> symbols and structure become their text.

### `Rows.to_df`

```python
def to_df(self):
```

> The rows as a pandas DataFrame, DuckDB's own conversion naming.
> pandas is the caller's dependency; its absence raises naming the
> need, and table() stays the constructor-agnostic shape.

### `Rows.to_pl`

```python
def to_pl(self):
```

> The rows as a polars DataFrame; the polars twin of to_df().
