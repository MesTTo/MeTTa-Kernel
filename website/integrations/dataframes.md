<!--
Purpose: show how metta.tables.add and Rows bridge tabular data in both directions.
Guarantees: table ingestion examples use the satellite function rather than the removed Space method.
[tested: npm run docs:build; commit=f88aa8be03cb64cb59d3307515ded8701f418321]
-->

# Dataframes

PeTTa crosses the dataframe boundary in both directions. `metta.tables.add(m, head, source)` turns each input row into one fact. Query results keep named columns as `Rows`, then `table`, `to_df`, and `to_pl` expose shapes used by Python dataframe libraries.

## Read a table into a space

The engine-controls example creates relation facts from ordinary rows, queries them, and converts the result to Polars when it is installed:

```python
tables.add(m, "edge", [(i, i + 1) for i in range(200)])
rows = m.match(S.edge(V.a, V.b), S.edge(V.b, V.c), timeout=30.0)
check("a generous bound changes nothing", len(rows), 199)

with m.stats() as s:
    m.match(S.edge(V.a, V.b), S.edge(V.b, V.c))
check("the stats block counts the engine steps spent", s.inferences > 100)

with m.capture() as output:
    groups = m.run("!(println! (hello world)) !(+ 1 2)")
check("captured print output", "(hello world)" in output.text)
check("the answers still arrive beside it", groups[1], [3])

try:
    import polars  # noqa: F401

    check("rows cross into a polars frame", rows.to_pl().columns, ["a", "b", "c"])
except ImportError:
    print("  (polars is not installed; rows.table() is the plain dict)")
```

Mappings provide column names and values. Polars frames use their row iterator. Invalid sources are refused:

```python
def test_add_table_reads_any_tabular_source(m):
    added = tables.add(m, "edge", {"src": [S.a, S.b], "dst": [S.b, S.c]})
    assert added == 2
    assert len(m.match(S.edge(V.x, V.y))) == 2

    polars = pytest.importorskip("polars")
    frame = polars.DataFrame({"name": ["ada", "bob"], "age": [36, 41]})
    assert tables.add(m, "person", frame) == 2
    rows = m.match(S.person(V.name, V.age))
    assert {(r["name"], r.age) for r in rows} == {("ada", 36), ("bob", 41)}
    with pytest.raises(TypeError):
        tables.add(m, "bad", 7)
```

Pandas input is supported by the implementation through `itertuples(index=False)`. No current test or example passes a pandas frame into `tables.add`, so that statement is source-backed, not test-backed.

Ragged mappings fail before they can leave partial facts:

```python
def test_add_table_refuses_ragged_columns(m):
    with pytest.raises(ValueError):
        tables.add(m, "edge", {"src": [S.a, S.b, S.c], "dst": [S.b]})
    assert m.match(S.edge(V.x, V.y)) == []
```

## Turn rows into dataframe inputs

`Rows.table()` returns a plain mapping of column names to decoded values:

```python
def test_rows_table_is_the_dataframe_shape(m):
    m.add(S.Age(S.Tom, 62), S.Age(S.Bob, 40))
    rows = m.match(S.Age(V.who, V.n))
    table = rows.table()
    assert table in ({"who": ["Tom", "Bob"], "n": [62, 40]}, {"who": ["Bob", "Tom"], "n": [40, 62]})
```

`to_pl()` constructs the Polars frame directly:

```python
def test_rows_to_pl_builds_the_polars_frame(m):
    pytest.importorskip("polars")

    tables.add(m, "score", [("ada", 3), ("bob", 5)])
    rows = m.match(S.score(V.who, V.points))
    frame = rows.to_pl()
    assert frame.columns == ["who", "points"]
    assert frame["points"].to_list() == [3, 5]
    assert frame["who"].to_list() == ["ada", "bob"]
```

`to_df()` either constructs pandas output or names the missing dependency:

```python
def test_rows_to_df_builds_or_names_the_need(m):
    tables.add(m, "score", [("ada", 3)])
    rows = m.match(S.score(V.who, V.points))
    if importlib.util.find_spec("pandas") is None:
        with pytest.raises(ImportError, match="pandas"):
            rows.to_df()
    else:
        assert rows.to_df()["points"].tolist() == [3]
```

Zero-column results preserve their row count in dataframe objects. A plain dict cannot represent nonempty rows with no columns, so `table()` refuses that case:

```python
def test_nonempty_zero_column_rows_refuse_table_but_frames_keep_row_count():
    rows = Rows((), [(), ()])
    with pytest.raises(ValueError, match="nonempty zero-column"):
        rows.table()

    pandas = pytest.importorskip("pandas")
    polars = pytest.importorskip("polars")
    assert isinstance(rows.to_df(), pandas.DataFrame)
    assert rows.to_df().shape == (2, 0)
    assert isinstance(rows.to_pl(), polars.DataFrame)
    assert rows.to_pl().shape == (2, 0)


def test_empty_zero_column_rows_remain_an_empty_table():
    assert Rows((), []).table() == {}
```

Continue with [Run and query](../guide/run-query), [`metta.tables.add`](../reference/metta-tables#add), [`Rows.table`](../reference/metta-results#rows-table), [`Rows.to_df`](../reference/metta-results#rows-to-df), and [`Rows.to_pl`](../reference/metta-results#rows-to-pl).
