# `petta.results`

Source: `python/petta/results.py`.

> Purpose: query results as rows. A Rows is a list of Row tuples, one per
> answer, with the query's variable names as columns and attribute access per
> column, so rows drop into unpacking, DataFrame constructors and pattern
> matching without a helper in between.
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

No docstring is defined.

## `Rows`

```python
class Rows(list):
```

> Every answer to a query, in the order the engine produced them.
>
> A list, so len, iteration, indexing and slicing behave as expected;
> columns names the variables. column(name) projects one column out.

### `Rows.column`

```python
def column(self, name: str) -> list[Any]:
```

No docstring is defined.

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
