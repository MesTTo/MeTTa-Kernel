# `petta_soft`

Source: `petta_soft/petta_soft/__init__.py`.

> Purpose: the Python face of lib_soft, weak unification in Sessa's sense,
> BUILT ON the petta library's public surface rather than into it: every call
> here goes through run, add, eval, atoms and the public atom API, which is
> the point, a soft-reasoning layer any user could have written.
> install() imports the library into a space; similar() declares symbol
> closeness as ordinary (similar a b degree) facts the equations read;
> link_store() materializes those facts from an EmbeddingStore's cosine
> neighborhoods, the neural-theorem-proving move with the similarities kept
> inspectable in the space rather than buried in a vector index; score() is a
> fast Python mirror of (soft-score ...), differentially fuzzed against the
> MeTTa one so the two can never quietly drift; and prove()/prove_all() are
> goal-directed soft REASONING: backward chaining over the space's facts and
> Horn-shaped equations with soft unification at every step, degrees
> aggregated by minimum, answering Proof objects that carry the bindings, the
> overall similarity, and every step. That is the shape of End-to-End
> Differentiable Proving (Rocktaschel and Riedel, arXiv 1705.11040) and Braid
> (Kalyanpur et al., arXiv 2011.13354), running over the same (similar ...)
> facts and embedding links the rest of lib_soft reads.
> Open Obligations:
>   To Do: None
>   Hacks: None
>   Future Enhancements: None

The entries below reproduce the source signatures and docstrings.

## `install`

```python
def install(m) -> None:
```

> lib_measure and lib_soft into this space; soft-match and soft-best
> become available wherever the space's programs run.

## `similar`

```python
def similar(m, a: Any, b: Any, degree: float) -> None:
```

> Declare two symbols close to a degree; sym-sim reads both ways.

## `link_store`

```python
def link_store(m, store, threshold: float = 0.5, top_k: int = 5) -> int:
```

> Materialize (similar ...) facts from an embedding store: for every
> stored key, its top_k cosine neighbors at or above the threshold.
> Answers how many facts landed. The similarities become space atoms any
> rule can read, soft-match's sym-sim first among them.

## `similar_pattern`

```python
def similar_pattern(m, pattern: str, symbol: Any, degree: float) -> int:
```

> Declare a symbol family intensionally: every distinct symbol
> occurring in the space whose name the regex matches becomes similar
> to `symbol` at `degree`, materialized as the same (similar ...)
> facts link_store lands, sym-sim reading them both ways. Answers how
> many facts landed. Regex is matching applied at the symbol level the
> soft matcher softens, so a pattern names a family the way an
> embedding store names a neighborhood.
>
>     soft.similar_pattern(m, r"^grandpa-", "grandfather-of", 0.9)

## `score`

```python
def score(
    pattern: Atom,
    atom: Atom,
    similarities: Mapping[tuple[str, str], float] | None = None,
    _bindings: dict[str, Atom] | None = None,
) -> float:
```

> (soft-score pattern atom) in Python: a variable binds at one and its
> LATER occurrences stand as what it bound, soft recursion included,
> exactly as the engine's let leaves the variable bound; expressions
> recurse under minimum, symbols consult the similarity map both ways
> (identity is one), grounded values stay crisp. Kept exactly equivalent
> to the MeTTa equations by a differential fuzz.

## `ProofStep`

```python
class ProofStep:
```

> One inference: what the current goal soft-unified with (a stored
> fact, an equation's head, or an evaluated guard), at which degree.

## `Proof`

```python
class Proof:
```

> One way the goal holds: the bindings its variables took, the overall
> similarity (the minimum over every step, the fuzzy t-norm), and the
> steps themselves, printable for audit.

### `Proof.depth`

```python
def depth(self) -> int:
```

No docstring is defined.

## `prove_all`

```python
def prove_all(
    m,
    goal: Any,
    threshold: float = 0.5,
    max_depth: int = 10,
    similarities: Mapping[tuple[str, str], float] | None = None,
) -> list[Proof]:
```

> Every proof of the goal at or above the threshold, best first.
>
> Backward chaining: a goal holds if it soft-unifies with a stored fact,
> or with a rule's head whose body conjuncts then hold in turn; a ground
> guard whose head is an engine function evaluates through the engine and
> holds at degree one when it answers true. Degrees aggregate by minimum
> down the whole proof, and every soft unification must clear the
> threshold, Braid's rule. Proofs come back sorted by similarity.

## `prove`

```python
def prove(
    m,
    goal: Any,
    threshold: float = 0.5,
    max_depth: int = 10,
    similarities: Mapping[tuple[str, str], float] | None = None,
) -> Proof | None:
```

> The best proof of the goal, or None: tensor-theorem-prover's own
> contract, the highest-similarity proof among all found.
