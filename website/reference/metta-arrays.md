# `metta.arrays`

Source: `extensions/python/metta/arrays.py`.

> Arrays as atoms for every library speaking the standard
> protocols, not one. Recognition is DLPack (__dlpack__), semantics are the
> Python array API standard reached through array-api-compat, so one operation
> set serves NumPy, PyTorch, CuPy, JAX, Dask and whatever conforms next, and a
> mixed-library call converts through from_dlpack. Arrays cross the boundary
> by reference with identity, DLTensor joins each array's own classes as a
> type, and printing shows shape, dtype and device whatever the library.
> Built entirely on the public integration interface; pettorch instantiates it
> with torch as the constructor default and proves nothing here is
> torch-shaped.

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
>
> Every installed name has one or more arrow declarations. Constructors
> with optional or variadic dimensions have one arrow per accepted arity.
>
> broadcast-shape is the CLP(FD) relation over shape expressions. It can
> compute a result before any tensor exists, infer an unknown input
> dimension from a required result, or reject incompatible shapes:
>
>     !(let True (broadcast-shape (4 1) (3) $shape) $shape)  ; (4 3)
>     !(let True (broadcast-shape ($d 1) (1 3) (4 3)) $d)   ; 4
>     !(broadcast-shape (2 3) (4 3) (4 3))                  ; no answer
>
> t-shape remains observation of an existing tensor. Use broadcast-shape
> when compatibility or inference must happen before materialisation.

## `EmbeddingStore`

```python
class EmbeddingStore:
```

> Vectors by key, searchable from MeTTa, in whichever library the
> vectors arrive from.
>
>     store = metta.arrays.EmbeddingStore(m, name="emb")
>     store.add(S.dog, numpy.array([1.0, 0.0]))
>     m.run("!(collapse (emb-knn (tensor (1.0 0.0)) 1))")
>
> Cosine similarity uses the array API's own operations, and the matrix
> caches between writes. add() has map semantics: adding an existing key
> replaces its vector in its first-seen position. (name-knn $q $k) is
> nondeterministic retrieval, best first; (name-embed $key) answers the
> stored vector or nothing. Public operation names route through equations
> in this space to unique internal operations, so the same store name in a
> different space cannot retarget this store.

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
> answers, byte-agreeing with the array path by a differential test.
> NumPy-like namespaces use argpartition for the candidate set;
> namespaces exposing only the Array API use argsort.
