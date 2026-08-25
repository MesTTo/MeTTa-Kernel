# `metta.results`

Source: `bindings/python/metta/results.py`.

> Purpose: expose eager query rows and lazy immutable evaluation answers.
>
> A Rows is a mutable sequence of Row tuples, one per query answer, while
> Answers progressively caches one evaluation source for replay, projections,
> and exact-cardinality reads.
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
>   - a one-column Rows rebuilds constructor expressions through build(cls),
>     and rows_into selects that path for match(into=cls) [tested:
>     test_a_constructor_expression_rebuilds_through_the_query_door;
>     commit=f88aa8be03cb64cb59d3307515ded8701f418321]
>   - Rows.to_dicts returns one Python-native mapping per row, including empty
>     mappings for zero-column rows [tested test_rows_to_dicts_returns_plain_records]
>   - eager query results explain empty pattern, join, and guard outcomes [tested
>     test_query_rows_explain_empty_results]
>   - error_answer recognizes (Error ...) by head symbol alone, so quoted and
>     nested errors stay data, and raise_for_errors chains when clean [tested
>     test_raise_for_errors_chains_when_clean_and_raises_one_plainly]
>   - every Answers iterator replays one shared prefix, and caller-variable
>     projections and slices stay Answers [tested:
>     test_answers_are_lazy_cached_and_cardinality_aware,
>     test_answers_project_caller_variables_and_slices_stay_answers;
>     commit=2d4d4583c2d82e90bb21a7e8671842f126edd4f4]
>   - evaluation values and their caller-binding rows are parallel faces of one
>     Answers cursor [tested: test_calls_keep_values_and_binding_rows;
>     commit=18b1135167d60396c41e63e42ded2f66d0eb1900]
>   - private item replay lets a deferred algebra route preserve those rows
>     without probing the engine when its Answers view is constructed [tested:
>     test_tagged_derivations_flow_through_match_and_reinterpret_without_requery;
>     commit=c7468b2789746bcf95c4bacc0e2d517ec4d972fa]
>   - an Answers view crossing into a term observes exact-one cardinality and
>     encodes that answer as the operand [tested:
>     test_answer_views_observe_when_used_as_operands; commit=18b1135167d60396c41e63e42ded2f66d0eb1900]
>   - Rows and Answers project caller variables by attribute, Variable key, or
>     exact string key
>     [tested: test_rows_share_the_answer_projection_contract; commit=18b1135167d60396c41e63e42ded2f66d0eb1900]
>   - len on an untouched engine-backed Answers view uses its engine count door
>     without populating the Python cache [tested:
>     test_len_counts_an_unmaterialised_view_engine_side; commit=18b1135167d60396c41e63e42ded2f66d0eb1900]
>   - a count source may decline a second evaluation, in which case len
>     materializes the held cursor once [tested:
>     test_effectful_relational_candidates_run_once_per_yield_on_fresh_list;
>     commit=6917bef7ca902671999eafcae3a7a86db8f69723]
>   - one(default=) distinguishes absence from multiplicity for both eager and
>     lazy faces, while first without a default never returns None [tested:
>     test_query_answers_complete_the_lazy_projection_protocol; commit=b1de70215dd3f0c9d5437558c57c5911c13948b5]
> Open Obligations:
>   To Do: None
>   Hacks: None
>   Future Enhancements: None.

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
> Sequence operations retain this type and its columns. ``rows.name``,
> ``rows[V.name]``, and ``rows["name"]`` project a column, matching Answers,
> while integer and slice indexing follow a normal list.

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
def first(self, *, default: Any = _MISSING) -> Row | Any:
```

> Return the first row, or the caller's explicit default.

### `Rows.one`

```python
def one(self, *, default: Any = _MISSING) -> Row | Any:
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
>     m.match(pattern).raise_for_errors()
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
>
> One of nine observability doors: metta.derivation answers HOW a
> result was derived, and prepare(...).explain() answers what a
> query will do before it runs; the guide's observability page maps
> the family.

### `Rows.build`

```python
def build(self, column: str | type, cls: type | None = None) -> list:
```

> Rebuild constructor atoms through the two-way translator.
>
> ``build(column, cls)`` projects a named column. ``build(cls)`` is the
> query reconstruction door when exactly one column holds complete
> constructor expressions.

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
>     m.match(pattern).pipe(clean).pipe(score, weight=2)

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

## `Answers`

```python
class Answers(Sequence[T]):
```

> A replayable view over an answer source whose size is not yet known.
>
> Pulling is progressive. Each iterator starts at answer zero, reads the
> shared prefix already computed, and advances the single source only when
> it reaches the frontier. The sequence has no mutation methods.

### `Answers.columns`

```python
def columns(self) -> tuple[str, ...]:
```

> Caller-variable names available for projection.

### `Answers.rows`

```python
def rows(self) -> Answers[Row]:
```

> The caller-binding row paired with each evaluation answer.

### `Answers.build`

```python
def build(self, *args: Any) -> list[Any]:
```

> Materialize, then rebuild one column through Rows.build.

### `Answers.to_dicts`

```python
def to_dicts(self) -> list[dict[str, Any]]:
```

> Materialize as plain column-to-value records.

### `Answers.table`

```python
def table(self) -> dict[str, list[Any]]:
```

> Materialize as a column mapping.

### `Answers.to_df`

```python
def to_df(self):
```

> Materialize as a pandas DataFrame.

### `Answers.to_pl`

```python
def to_pl(self):
```

> Materialize as a polars DataFrame.

### `Answers.pipe`

```python
def pipe(self, fn: Callable[..., Any], *args: Any, **kwargs: Any) -> Any:
```

> Materialize and pass the eager Rows face to ``fn``.

### `Answers.raise_for_errors`

```python
def raise_for_errors(self) -> Self:
```

> Raise stored error cells after materializing the row view.

### `Answers.why`

```python
def why(self) -> str:
```

> Explain an empty query after materializing it.

### `Answers.one`

```python
def one(self, *, default: Any = _MISSING) -> Any:
```

> Return at most one decoded value, defaulting only on absence.

### `Answers.first`

```python
def first(self, *, default: Any = _MISSING) -> Any:
```

> Return the first decoded value, or the caller's explicit default.
