# `petta.testing`

Source: `python/petta/testing.py`.

> Purpose: hypothesis strategies for property-testing code built on this
> library, the pandas.testing reading: the exact generators the library's own
> suite fuzzes itself with, exported, so user operations, translators and
> spaces get tested against atoms the engine actually reads back. The
> filters encode engine truths worth not rediscovering: which characters the
> tokeniser reads back whole, that true/false ARE the boolean atoms so their
> symbol spellings canonicalize, and that `_` is the anonymous variable,
> fresh at every occurrence.
> Open Obligations:
>   To Do: None
>   Hacks: None
>   Future Enhancements: None

The entries below reproduce the source signatures and docstrings.

## `names`

```python
def names():
```

> Symbol and variable names PeTTa's tokeniser reads back whole: no
> whitespace, parens or quotes, none of the characters that mean
> something else at the front, and never the boolean spellings (the
> engine holds its booleans as those very atoms, so True and true are
> one term there and a round trip canonicalizes) or the anonymous `_`
> (fresh at every occurrence by contract, so it never shares).

## `symbols`

```python
def symbols():
```

> Sym atoms with engine-readable names.

## `variables`

```python
def variables():
```

> Var atoms with engine-readable names.

## `numbers`

```python
def numbers():
```

> Numbers the engine's printer round-trips: integers within the
> tagged-integer range, floats without NaN (never compares equal) or
> infinity (prints as a symbol), both printer limits, not carried bugs.

## `numpy_scalars`

```python
def numpy_scalars():
```

> NumPy integer and real scalar values accepted by PeTTa's Number type.
>
> NumPy is optional. Install ``petta[arrays,test]`` before requesting this
> strategy.

## `texts`

```python
def texts():
```

> Strings as the engine stores them; NUL is the one exclusion.

## `grounded`

```python
def grounded():
```

> Grounded atoms over numbers, booleans and strings.

## `atoms`

```python
def atoms(max_leaves: int = 8, *, ground: bool = False):
```

> Whole atoms: symbols, variables (unless ground=True), grounded
> values, and expressions recursively over all of them; max_leaves is
> hypothesis's own size knob for the recursion.
>
>     from hypothesis import given
>     from petta import testing
>
>     @given(testing.atoms())
>     def test_my_translator_round_trips(atom):
>         assert decode(encode(atom)) == atom

## `expressions`

```python
def expressions(max_leaves: int = 8, *, ground: bool = False):
```

> Non-empty expression-rooted atoms, the shape spaces store.
