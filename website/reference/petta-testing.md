# `petta.testing`

Source: `bindings/python/petta/testing.py`.

> Purpose: hypothesis strategies for property-testing code built on this
> library, the pandas.testing reading: the exact generators the library's own
> suite fuzzes itself with, exported, so user operations, translators and
> spaces get tested against atoms the engine actually reads back. The
> filters encode engine truths worth not rediscovering: which characters the
> tokeniser reads back whole, that true/false ARE the boolean atoms so their
> symbol spellings canonicalize, and that `_` is the anonymous variable,
> fresh at every occurrence.
>
> The conformance surfaces live here too, one rung per audience:
> check_space_provider and check_codec run in process against an author's own
> object, SpaceComplianceSuite and GatewayComplianceSuite are pytest classes
> that run the engine's own expectations against a provider or a URL.
> Guarantees:
>   - check_space_provider holds match soundness and exact pushdown claims
>     to the whole pattern family of every stored atom, ground, opened and
>     repeated-variable, judged by two-way unifiability [tested:
>     test_a_repeated_variable_liar_is_caught_by_the_folded_pattern,
>     test_a_ground_only_matcher_is_caught_by_the_open_pattern;
>     commit=f88aa8be03cb64cb59d3307515ded8701f418321].
>   - check_twin consumes a Defined call's eager answer list exactly once
>     [tested: test_the_prolog_twin_is_checked_against_its_reference;
>     commit=f88aa8be03cb64cb59d3307515ded8701f418321].
>   - minted-space conformance recognizes decoded Space handles in provider
>     answers [tested: test_fabricated_space_identities_are_refused;
>     commit=WORKTREE]
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

> Symbol atoms with engine-readable names.

## `variables`

```python
def variables():
```

> Variable atoms with engine-readable names.

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

## `ground_atoms`

```python
def ground_atoms(max_leaves: int = 8):
```

> Atoms carrying no variables: what a store holds after matching.
> atoms(ground=True) under the name provider fuzzing reaches for.

## `patterns`

```python
def patterns(max_leaves: int = 8):
```

> Expression-rooted atoms guaranteed to carry at least one variable:
> the query side of match, built rather than filtered so hypothesis
> never discards an example.

## `check_space_provider`

```python
def check_space_provider(provider, *, atoms_to_store=None, source='repeated') -> list[str]:
```

> Prove a SpaceProvider before its users find out. Answers the checks run.
>
> The platform ships the conformance suite for its own extension points,
> which is the CSI sanity suite's reading, and JDBC's, and pytest's own
> `pytester`. Without it a downstream library learns its provider is wrong
> from a bug report.
>
>     from petta import testing
>
>     def test_my_provider_conforms():
>         testing.check_space_provider(MyProvider(rows))
>
> Three things are checked, and the second is the one worth having.
>
> **Every declared capability is reachable.** `can_run` may say yes to an
> operation whose method is absent, which is a registration-time mistake
> that otherwise surfaces as an AttributeError inside an engine callback.
>
> **Match over-approximates rather than under-approximates.** The seam's
> central soundness claim is that a provider may yield more than the pattern
> asks for, because the engine keeps unification, and may never yield less.
> Every stored atom vouches for a whole pattern family, itself, each
> position opened to a variable, and repeated-variable folds, and the
> provider's answers for each are compared with a brute-force unification
> scan of `atoms()`. A provider that filters too eagerly, or that only
> handles ground patterns, or whose filter treats a repeated variable's
> occurrences independently, fails here rather than answering wrongly in
> production. An exact pushdown claim is held to the same family.
>
> **A refusal names itself.** An operation the provider declines raises with
> a sentence rather than failing, so a caller learns what to do instead.
>
> `source` names the provider's consumption discipline, matching its
> (source ...) declaration. A linear provider is one-shot, so every
> check that consumes more than once is skipped and said so; repeated
> and peek providers are enumerated twice and the two enumerations must
> agree, which is the promise those words make.
>
> Raises AssertionError on the first violation, naming the provider class,
> the operation and the atom.

## `record_replay`

```python
def record_replay(provider):
```

> Wrap a provider so its answers append to a log, with the replayer.
>
> The CakeML-oracle shape for host-stateful contexts: an append-only
> log makes a nondeterministic context's run replayable, and the
> differential replays the log instead of demanding a determinism the
> world does not have. Returns (recording, replay) where `recording`
> stands in for the provider and `replay()` builds a provider serving
> the log verbatim.

## `check_replay`

```python
def check_replay(provider, patterns) -> list[str]:
```

> The ec_determ lane: for a fixed host state, evaluation is a
> function. Each pattern is matched live and recorded, then the log's
> replay must serve byte-identical answers, which is what makes a
> recorded session a differential oracle for a backend nobody can
> re-run.

## `check_minted_handles`

```python
def check_minted_handles(provider, registered=()) -> list[str]:
```

> The engine-minted-handles law: space identities are the engine's to
> mint, and a backend answers INTO spaces, never fabricates one.
>
> Every &-headed symbol in the provider's answers must be a space the
> engine registered; a fabricated one is the reference nobody can
> resolve, cheap to refuse now and expensive to chase after a program
> stores it. `registered` names the spaces this provider may mention.

## `check_twin`

```python
def check_twin(defined, cases) -> list[str]:
```

> Prove a definition and its Python twin answer the same. Answers the
> cases run.
>
> `@m.define` keeps the original Python reachable as `.py`, and
> `@m.define(prolog=...)` keeps it when the fast side is written in
> Prolog instead. Either way the pair is a differential oracle, and this
> runs it:
>
>     from petta import testing
>
>     def test_the_fast_one_still_agrees():
>         testing.check_twin(vec_dot, [((1, 2), (3, 4)), ((0,), (9,))])
>
> `cases` is an iterable of argument tuples. Drive it with hypothesis for
> a real sweep; `petta.testing` exports the strategies the library fuzzes
> itself with.
>
> A generator twin is compared answer by answer in order, since a
> generator compiles to nondeterminism and order is part of the answer. A
> twin that RAISES on a case requires the engine to answer nothing for
> it: a reference that has no answer and a fast side that invents one is
> the disagreement most worth catching.
>
> Raises AssertionError on the first case where they differ, naming the
> case and both answers.
