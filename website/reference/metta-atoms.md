# `metta.atoms`

Source: `extensions/python/metta/atoms.py`.

> Expose MeTTa atoms, the S/V/G factories, parsing, and matching.

The entries below reproduce the source signatures and docstrings.

## `ground`

```python
def ground(value: Any) -> Grounded:
```

> Carry a Python value whole, whatever it is.
>
> This is the FFI boxing door. Structural wire conversion lives in
> :mod:`metta.wire`; ``ground([1, 2, 3])`` therefore carries one list by
> identity instead of turning it into an expression.

## `fresh`

```python
def fresh() -> Variable:
```

> Mint a variable for a library-authored pattern without name capture.

## `arrow`

```python
def arrow(*positions: Any) -> Expression:
```

> Build an arrow type as data, mapping Python types through annotations.

## `typed`

```python
def typed(subject: Any, type_: Any) -> Expression:
```

> Build ``(: subject type)`` as data; annotations are accepted as types.

## `if_`

```python
def if_(condition: Any, consequent: Any, alternative: Any = _OMITTED) -> Expression:
```

> Build either engine ``if`` arity; Python ``if`` lowers inside define.

## `not_`

```python
def not_(value: Any) -> Expression:
```

> Build a quoted or stored ``not`` term.

## `and_`

```python
def and_(*values: Any) -> Expression:
```

> Left-fold 2+ values through ``and``; retain its arity-0/1 partials.

## `or_`

```python
def or_(*values: Any) -> Expression:
```

> Left-fold 2+ values through ``or``; retain its arity-0/1 partials.

## `in_`

```python
def in_(member: Any, container: Any) -> Expression:
```

> Build a quoted or stored ``in`` term.

## `seg`

```python
def seg(variable: Any) -> Expression:
```

> Build the named segment ``(:seg $x)``, the variable's fifth face.
>
> A segment variable stands for a RUN of expression children rather than for
> one term, so ``space[(S.Order, seg(V.rest))]`` matches an Order of any
> length and each answer's ``rest`` column is the run it took. Bare ``...``
> is the anonymous spelling and every occurrence of it is its own variable; a
> named segment can repeat, and the second occurrence then has to take the
> same run.
>
> The fence is the law's own theorem, not caution: general sequence
> unification is infinitary (Kutsia, Journal of Symbolic Computation 42(3),
> 2007), so a pattern outside the three proved-finite fragments refuses and
> names the rule.

## `parse`

```python
def parse(source: str) -> Atom:
```

> Read one form of MeTTa source into an atom, evaluating nothing.
>
> Use ``metta.forms()`` for a whole source program. ``parse()`` deliberately
> refuses empty input and multiple top-level forms rather than selecting one
> silently.
>
> Backed by the engine's own reader, with one improvement over sread/2: the
> variable names the DCG collects are kept, so parse("(Parent $x Bob)")
> contains Variable('x') rather than a machine name, and the same pattern built
> with V.x compares equal.
>
> Crossed through apply() rather than once(). metta_py_parse/2 already has
> the functional shape, one ground input and one output, and every call that
> passes source text to eval(), run() or match() parses first, so this is a
> second crossing on top of the evaluation's own.

## `order_key`

```python
def order_key(atom: Atom) -> tuple:
```

> A sort key for atoms, in Prolog's standard order of terms.
>
>     sorted(atoms, key=order_key)
>
> Atom.__lt__ delegates to this key, so explicit and plain sorting agree.
> The language's list-shaped expressions compare child by child; length is
> reached only when one expression is a prefix of the other. Variables come
> before numbers, strings, opaque objects, the empty expression, symbols,
> and nonempty expressions
> .
>
> Two atoms that compare equal here are not necessarily the same atom: a key
> orders, `same_atom` decides identity.

## `substitute`

```python
def substitute(atom: Any, bindings: Mapping[str, Atom]) -> Atom:
```

> The atom with every bound VARIABLE replaced, keyed by variable name.
>
> The internal primitive, for callers that hold names rather than atoms: a
> result row's columns, and ``_match``'s directional bindings. An unbound
> variable stays itself, so a partial substitution is a narrower pattern
> rather than an error.
>
> ``Atom.subs`` is the public door and the one implementation. It is keyed by
> ATOM because a bare name cannot say which kind it means on a surface that
> has both: this function reads ``{"x": ...}`` as the VARIABLE $x while
> a ``bind()`` scope at the evaluation doors reads the same mapping as the SYMBOL x
> . Two
> meanings for one spelling is fine inside the library, where each caller
> knows which it holds, and is not something to publish.

## `unify`

```python
def unify(left: Any, right: Any, *more: Any) -> Mapping[Atom, Atom] | None:
```

> Unify atoms symmetrically, returning bindings or ``None``.
>
> Variables in any operand bind. Variadic means SIMULTANEOUS: every
> operand must agree under one substitution, folded through one shared
> binding store, so three rule heads unify at once the way two always
> did, and the pairwise call is the 2-ary case of the same signature.
> The returned substitution is normalized, so a chain such as
> ``x = y, y = a`` reports both names bound to ``a``. Anonymous ``_``
> occurrences remain fresh and bind nothing. This host matcher retains
> its historical no-occurs-check behavior; four-argument conditional
> unification is the engine form exposed by ``metta.unify``.
>
> Keyed by the VARIABLES themselves, which is what ``Atom.subs`` accepts, so
> a substitution this produces is one the library can apply. A bare name
> cannot say whether it means a variable or a symbol, and this language has
> both: ``bind({"x": 5})`` at the evaluation doors means the SYMBOL x.
