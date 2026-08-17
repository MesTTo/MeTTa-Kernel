# `petta.results`

Source: `python/petta/results.py`.

> Purpose: query results as rows. A Rows is a mutable sequence of Row tuples, one per
> answer, with the query's variable names as columns and attribute access per
> column, so rows drop into unpacking, DataFrame constructors and pattern
> matching without a helper in between. Eager query results retain their
> patterns so an empty result can explain itself on demand.
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
>   - Rows.build preserves its requested class as the list element type [tested
>     test_target_type_overloads_preserve_the_requested_class]
>   - Rows.to_dicts returns one Python-native mapping per row, including empty
>     mappings for zero-column rows [tested test_rows_to_dicts_returns_plain_records]
>   - eager query results explain empty pattern, join, and guard outcomes [tested
>     test_query_rows_explain_empty_results]
>   - error_answer recognizes (Error ...) by head symbol alone, so quoted and
>     nested errors stay data, and raise_for_errors chains when clean [tested
>     test_raise_for_errors_chains_when_clean_and_raises_one_plainly]
> Open Obligations:
>   To Do: None
>   Hacks: None
>   Future Enhancements: None

The entries below reproduce the source signatures and docstrings.

## `error_answer`

```python
def error_answer(answer: object, *, space: str | None = None) -> MettaResultError | None:
```

> The structured exception for an `(Error ...)` answer, or None.
>
> The head symbol alone decides, MeTTa's own shape `(Error culprit
> reason)`, so a quoted or nested error stays data.

## `raise_error_answers`

```python
def raise_error_answers(
    answers: Iterable[object],
    *,
    space: str | None = None,
    target: object = None,
) -> None:
```

> Raise the first `(Error ...)` member of answers, if any.
>
> The check every single-value door runs before decoding: an error
> among the answers is the evaluation reporting failure, and failure
> outranks a count. The target rides as a note, so the traceback names
> the call without the message growing.

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

### `Rows.raise_for_errors`

```python
def raise_for_errors(self) -> Self:
```

> Raise when any cell carries an `(Error ...)` atom; answer self
> otherwise, so the call chains.
>
>     m.query(pattern).raise_for_errors()
>
> Query rows are BINDINGS, not evaluation answers, so a stored
> error record stays data through every Rows door, one() and
> first() included; this is the explicit bridge for callers who
> want the raise_for_status reading. One error raises it plainly,
> several raise one ExceptionGroup carrying each.

### `Rows.why`

```python
def why(self) -> str:
```

> Explain why this eager query returned no rows.
>
> The explanation reads the space's current state. A nonempty result
> has nothing to explain, and a manually constructed or transformed
> Rows has no query to inspect, so both uses fail loudly.

### `Rows.build`

```python
def build(self, column: str, cls: type[_BuildT]) -> list[_BuildT]:
```

> One column's atoms rebuilt as instances of cls, through the
> two-way translator: typed rows, one call.

### `Rows.to_dicts`

```python
def to_dicts(self) -> list[dict[str, Any]]:
```

> Return one Python-native column-to-value mapping per row.

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

### `Rows.pipe`

```python
def pipe(self, fn: Callable[..., Any], *args: Any, **kwargs: Any) -> Any:
```

> fn(self, *args, **kwargs), pandas' chaining shape, so a
> pipeline reads left to right instead of inside out:
>
>     m.query(pattern).pipe(clean).pipe(score, weight=2)

## `rows_into`

```python
def rows_into(rows: Rows, cls: type) -> list:
```

> Each row as one cls instance, matched by field name: sqlite3's
> row_factory reading, over the existing conversion machinery. A field
> annotated with a registered class builds through the two-way
> translator; a primitive annotation decodes and is CHECKED, so a
> symbol landing in an int field is an error at the door rather than
> a surprise downstream; an unannotated field decodes plainly.
