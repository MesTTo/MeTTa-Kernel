<!--
Purpose: explain array protocol operations and embedding retrieval through canonical atoms and Space handles.
Guarantees: synchronous examples use space(), ground(), Expression, and wire.decode.
[tested: npm run docs:build; commit=f88aa8be03cb64cb59d3307515ded8701f418321]
-->

# Arrays and embeddings

PeTTa gives conforming array libraries one MeTTa operation vocabulary. DLPack recognizes array objects and transfers values between libraries. `array-api-compat` supplies the operation namespace. DLPack is not the operation API.

## Use one operation set

Install the array layer with a constructor default. Operations still dispatch from the array argument's own library:

```python
try:
    import numpy
    import array_api_compat  # noqa: F401
except ImportError:
    skip("numpy and array-api-compat are needed")

from petta import Expression, S, V, arrays, ground, space, wire

m = space()
arrays.install(m, default=numpy)

check("matmul over numpy",
      m.run("!(t-tolist (matmul (tensor ((1.0 2.0))) (tensor ((3.0) (4.0)))))"),
      [[Expression(Expression(11.0))]])
(types,) = m.run("!(collapse (get-type (tensor (1.0))))")
check("protocol typing", S.DLTensor in list(types[0]))

array = numpy.arange(4.0)
m.add(S.holds(ground(array)))
check("identity through the space", wire.decode(m.query(S.holds(V.a))[0].a) is array)

try:
    import torch
    left, right = numpy.ones((2, 2), dtype=numpy.float32), torch.ones(2, 2)
    m.add(S.pair(ground(left), ground(right)))
    (out,) = m.run("!(t-item (t-sum (match (context-space) (pair $a $b) (matmul $a $b))))")
    check("mixed numpy@torch via DLPack", float(out[0]), 8.0)
```

Arrays cross a space by identity. The `DLTensor` protocol type lets one type declaration admit arrays from several libraries.

Explicit conversion uses `t-as`. Mixed binary operations convert the right operand to the left operand's library:

```python
def test_cross_library_conversion_via_dlpack(am):
    pytest.importorskip("torch")
    space = am.space()
    space.add(S.np_vec(ground(numpy.array([1.0, 2.0], dtype=numpy.float32))))
    (group,) = space.run(
        "!(t-dtype (t-as (match (context-space) (np_vec $v) $v) torch))"
    )
    assert "float32" in str(group[0])


def test_mixed_library_binary_op_converts_rightward(am):
    torch = pytest.importorskip("torch")
    left = numpy.ones((2, 2), dtype=numpy.float32)
    right = torch.ones(2, 2)
    space = am.space()
    space.add(S.pairT(ground(left), ground(right)))
    (group,) = space.run(
        "!(t-item (t-sum (match (context-space) (pairT $a $b) (matmul $a $b))))"
    )
    assert float(group[0]) == 8.0
```

## Retrieve nearby values

An `EmbeddingStore` owns copied vectors and returns nearest keys in score order:

```python
def test_embedding_store_runs_on_numpy(am):
    space = am.space()
    store = arrays.EmbeddingStore(space, name="npk")
    store.add(S.dog, numpy.array([1.0, 0.0, 0.0]))
    store.add(S.cat, numpy.array([0.9, 0.1, 0.0]))
    store.add(S.car, numpy.array([0.0, 0.0, 1.0]))
    (group,) = space.run("!(collapse (npk-knn (tensor (1.0 0.0 0.0)) 2))")
    (pairs,) = group
    assert [p[0] for p in pairs] == [S.dog, S.cat]
    scores = [float(p[1]) for p in pairs]
    assert scores == sorted(scores, reverse=True)
```

Give the store its own matching logic when similarity should run inside `unify`. An object with `match_` participates as any grounded atom does, binding the variable it was handed to the nearest key:

```python
try:
    import numpy
except ImportError:
    skip("numpy is not installed")

from petta import Bindings, Expression, Grounded, S, V, space  # noqa: E402
from petta.arrays import EmbeddingStore  # noqa: E402

m = space()
store = EmbeddingStore(m, name="vec", mirror=False)
store.add(S.espresso, numpy.array([0.9, 0.1, 0.0]))
store.add(S.latte, numpy.array([0.8, 0.3, 0.0]))
store.add(S.granite, numpy.array([0.0, 0.1, 0.9]))

class Nearest:
    def match_(self, other):
        query, out = other.children[0], other.children[1]
        key, _score = next(iter(store.ranked(query, 1)))
        yield Bindings({out: key})

(best,) = m.eval(Expression(S.unify, Grounded(Nearest()), Expression(S.espresso, V.k), V.k, S.none))
check("nearest neighbour", best, S.espresso)
```

Adding the same key replaces its vector. The store copies inputs so later caller mutation does not change stored data:

```python
def test_embedding_store_replaces_duplicate_keys_and_owns_vectors(metta):
    with petta.space() as space:
        store = arrays.EmbeddingStore(space, name="replace-emb")
        original = numpy.array([1.0, 0.0])
        store.add(S.same, original)
        original[:] = [0.0, 1.0]
        assert store.vector_for(S.same).tolist() == [1.0, 0.0]

        replacement = numpy.array([0.0, 1.0])
        store.add(S.same, replacement)
        assert len(store) == 1
        assert store.keys() == [S.same]
        assert store.vector_for(S.same).tolist() == [0.0, 1.0]
        assert len(space.query(S.embedding(S.same, V.vector))) == 1
```

Vectors must be finite, nonzero, one-dimensional, and the same width. Retrieval requires a positive integer `k`:

```python
@pytest.mark.parametrize(
    ("vector", "message"),
    [
        (numpy.array([[1.0, 0.0]]), "one-dimensional"),
        (numpy.array([numpy.nan, 1.0]), "finite"),
        (numpy.array([numpy.inf, 1.0]), "finite"),
        (numpy.array([0.0, 0.0]), "nonzero"),
    ],
)
def test_embedding_store_validates_added_vectors(metta, vector, message):
    with petta.space() as space:
        store = arrays.EmbeddingStore(space, name="validated-emb")
        with pytest.raises(ValueError, match=message):
            store.add(S.bad, vector)


def test_embedding_store_requires_one_width_and_positive_integer_k(metta):
    with petta.space() as space:
        store = arrays.EmbeddingStore(space, name="bounded-emb")
        store.add(S.good, numpy.array([1.0, 0.0]))
        with pytest.raises(ValueError, match="width must be 2"):
            store.add(S.wide, numpy.array([1.0, 0.0, 0.0]))
        for invalid in (0, -1):
            with pytest.raises(ValueError, match="positive integer"):
                list(store.ranked([1.0, 0.0], invalid))
        for invalid in (True, 1.5, "1"):
            with pytest.raises(TypeError, match="positive integer"):
                list(store.ranked([1.0, 0.0], invalid))
        with pytest.raises(ValueError, match="width must be 2"):
            list(store.ranked([1.0, 0.0, 0.0], 1))
```

Continue with [Custom matching](../reasoning/matchers-measure) and [`petta.arrays`](../reference/petta-arrays).
