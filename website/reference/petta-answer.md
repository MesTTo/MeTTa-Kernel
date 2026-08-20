# `petta.answer`

Source: `bindings/python/petta/answer.py`.

> Purpose: the explicit answer a provider or operation may yield in place
> of a plain atom: bindings for the query's variables, an optional explicit
> value, a residue and an annotation. The wire form is ["a", theta, residue,
> k] with an optional trailing value, and it is transport-agnostic: the
> Python side sends it over janus, a remote backend sends the same shape
> over its own pipe, and a Prolog-side provider needs none of it because
> unification is already the binding step.
> Guarantees:
>   - to_wire() emits exactly the seam's answer form, theta as
>     [[name, atom-wire], ...] pairs with $-stripped names
>     [tested 2026-08-17: test_answer_wire_form_is_exact].
>   - Construction validates shapes eagerly, so a malformed answer fails at
>     the yield site it was written, not inside an engine callback
>     [tested 2026-08-17: test_answer_validates_eagerly].
> Open Obligations:
>   To Do: None
>   Hacks: None
>   Future Enhancements: None.

The entries below reproduce the source signatures and docstrings.

## `Answer`

```python
class Answer:
```

> One explicit answer: theta binds the query's variables, and the
> atoms of the answer stay derivable as theta applied to the pattern.
>
> A provider may yield one from match() in place of a plain atom, and a
> non-raw operation may return or yield one; the two forms mix freely in
> one stream. `value` is an explicit answer atom: a provider's value is
> unified with the query pattern under theta (the candidate-with-
> bindings form), and an operation's value is what the call reduces to,
> `()` when omitted, the relational reading. This is Hyperon's
> execute_bindings, an answer atom together with the bindings it is
> returned under.
>
> `residue` and `k` complete the wire form; the engine's support for
> them lands by phase, and until it does a non-default value is a loud
> error rather than a silently dropped one.
>
> Theta values are encoded with the standard value encoder: atoms pass
> through, scalars become their atoms, and a value needing a registered
> projection should be projected by the author.

### `Answer.to_wire`

```python
def to_wire(self) -> list:
```

No docstring is defined.

## `Bindings`

```python
class Bindings(Answer):
```

> The theta-only shorthand: Bindings({"x": 3}) answers by binding.
