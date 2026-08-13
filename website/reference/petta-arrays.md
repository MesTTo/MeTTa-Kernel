# `petta.arrays`

Source: `python/petta/arrays.py`.

> Purpose: arrays as atoms for every library speaking the standard
> protocols, not one. Recognition is DLPack (__dlpack__), semantics are the
> Python array API standard reached through array-api-compat, so one operation
> set serves NumPy, PyTorch, CuPy, JAX, Dask and whatever conforms next, and a
> mixed-library call converts through from_dlpack. Arrays cross the boundary
> by reference with identity, DLTensor joins each array's own classes as a
> type, and printing shows shape, dtype and device whatever the library.
> Built entirely on the public integration interface; pettorch instantiates it
> with torch as the constructor default and proves nothing here is
> torch-shaped.
> Open Obligations:
>   To Do: None
>   Hacks: None
>   Future Enhancements: None

The entries below reproduce the source signatures and docstrings.

## `is_array`

```python
def is_array(x: Any) -> bool:
```

> Whether a value speaks DLPack, the exchange protocol array libraries share.

## `namespace_of`

```python
def namespace_of(x: Any):
```

> The array API namespace an array belongs to: its own library, wrapped.

## `data_of`

```python
def data_of(a: Any) -> Any:
```

> Nested expression of numbers to nested lists; grounded values unwrap.

## `install`

```python
def install(m, default: Any = None) -> list[str]:
```

> Register the array operation set on the shared engine.
>
> default names the library the constructors build in: a module, a module
> name, or None for NumPy. Every other operation dispatches on its
> argument's own namespace, so arrays from any conforming library flow
> through the same MeTTa functions, and a mixed binary call converts the
> right operand into the left's library through from_dlpack.

## `EmbeddingStore`

```python
class EmbeddingStore:
```

> Vectors by key, searchable from MeTTa, in whichever library the
> vectors arrive from.
>
>     store = petta.arrays.EmbeddingStore(m, name="emb")
>     store.add(S.dog, numpy.array([1.0, 0.0]))
>     m.run("!(collapse (emb-knn (tensor (1.0 0.0)) 1))")
>
> Cosine similarity over the array API's own operations; the matrix caches
> between writes. (name-knn $q $k) is nondeterministic retrieval, best
> first; (name-embed $key) answers the stored vector or nothing.

### `EmbeddingStore.add`

```python
def add(self, key: Any, vector: Any) -> None:
```

No docstring is defined.

### `EmbeddingStore.keys`

```python
def keys(self) -> list[Atom]:
```

No docstring is defined.

### `EmbeddingStore.vector_for`

```python
def vector_for(self, key: Any) -> Any:
```

No docstring is defined.

### `EmbeddingStore.ranked`

```python
def ranked(self, query: Any, k: int):
```

> (key atom, cosine) pairs best first: the raw retrieval every
> surface (knn, the matcher) formats its own way. With faiss present
> (or asked for), an exact IndexFlatIP over the normalized matrix
> answers, byte-agreeing with the argsort path by a differential
> test; argsort otherwise.

### `EmbeddingStore.matcher`

```python
def matcher(self, name: str = "semmatch", threshold: float = 0.0) -> str:
```

> This store as a first-class matcher: (name $q $key) scores a
> candidate by cosine, (name $q $unbound) generates best first, both
> answering (score value) pairs for the measure algebra. The
> embedding-similarity move of neural theorem proving, packaged.
