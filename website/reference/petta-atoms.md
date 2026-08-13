# `petta.atoms`

Source: `python/petta/atoms.py`.

> Purpose: atoms as Python values, and the tagged wire encoding that carries
> them across janus without losing their metatype. A symbol and a grounded
> string both reach Python as str under janus's own conversion, booleans arrive
> as text, and containers are rewritten term-shaped, so every value crossing the
> boundary travels tagged instead: s symbol, g string, n number, b boolean,
> v variable, e expression, o object reference. Python operators on atoms
> build terms, so V.age &gt;= 18 is the expression (&gt;= $age 18), while grounded
> values keep ordinary value semantics.
> Open Obligations:
>   To Do: None
>   Hacks: None
>   Future Enhancements: None

The entries below reproduce the source signatures and docstrings.

## `Box`

```python
class Box:
```

> Holds one Python value so it crosses the boundary by reference.
>
> janus rewrites more than containers on the way in: lists, tuples, dicts,
> sets, bytes and None become Prolog terms, and anything speaking the
> sequence protocol, a NumPy array included, explodes into a list of
> element objects. Which types convert is janus's decision, not ours, so
> every opaque value crosses boxed, uniformly, and every consuming surface
> unboxes: from_wire, raw operation arguments and results, and the
> engine's typing through py_object_type_names/2. A caller never sees a
> box; it exists only on the wire and inside the engine.
>
> Boxes are INTERNED per object identity through boxed(): one live object
> always crosses as the same box, so a stored atom and a later query meet
> in the same reference and unification by identity means identity. The
> intern table holds boxes weakly: a box lives exactly as long as
> something references it (an atom in a space does, through janus), and a
> dropped object costs nothing forever after.

## `boxed`

```python
def boxed(value: Any) -> Box:
```

> THE box for this object, minted on first crossing, stable while any
> reference to it lives anywhere, engine included.

## `register_object_repr`

```python
def register_object_repr(kind: type, fn: Callable[[Any], str]) -> None:
```

> Teach grounded values of one type how to print.

## `register_object_repr_protocol`

```python
def register_object_repr_protocol(
    predicate: Callable[[Any], bool], fn: Callable[[Any], str]
) -> None:
```

> Teach grounded values satisfying a predicate how to print.

## `Atom`

```python
class Atom:
```

> Base class. Atoms are immutable, hashable, and compare structurally.

### `Atom.eq`

```python
def eq(self, other: Any) -> "Expr":
```

> The equality TERM, (== self other); == itself compares atoms.

### `Atom.ne`

```python
def ne(self, other: Any) -> "Expr":
```

No docstring is defined.

### `Atom.to_wire`

```python
def to_wire(self) -> list:
```

No docstring is defined.

### `Atom.metatype`

```python
def metatype(self) -> str:
```

No docstring is defined.

## `Sym`

```python
class Sym(Atom):
```

> A symbol: a name that denotes itself. Coffee, likes, &amp;self.
>
> A symbol is not a string: Sym('foo') == 'foo' is False on purpose,
> because 'foo' the text and foo the name are different atoms in MeTTa,
> and folding them together is the ambiguity the wire encoding removes.

### `Sym.to_wire`

```python
def to_wire(self) -> list:
```

No docstring is defined.

### `Sym.metatype`

```python
def metatype(self) -> str:
```

No docstring is defined.

## `Var`

```python
class Var(Atom):
```

> A variable: a hole a match may fill. $x in source.

### `Var.to_wire`

```python
def to_wire(self) -> list:
```

No docstring is defined.

### `Var.metatype`

```python
def metatype(self) -> str:
```

No docstring is defined.

## `Gnd`

```python
class Gnd(Atom):
```

> A grounded value: a host value carried whole.
>
> Strings, numbers and booleans have native PeTTa terms. Anything else
> crosses as an object reference, stays the same object on the way back,
> and unifies by identity, which is the equality the engine applies to it.
>
> Equality is ergonomic on purpose: a grounded primitive compares equal to
> its raw Python value, so run("!(+ 1 2)") answers compare with == 3.
> True stays distinct from 1 the way MeTTa keeps Bool and Number apart.
> A symbol never equals a string; that distinction is the point.

### `Gnd.to_wire`

```python
def to_wire(self) -> list:
```

No docstring is defined.

### `Gnd.metatype`

```python
def metatype(self) -> str:
```

No docstring is defined.

## `Expr`

```python
class Expr(Atom):
```

> An expression: an ordered sequence of atoms. (likes Ada Coffee).
>
> Sequence-shaped, so Python's own idioms apply: expr[0] is car-atom,
> len(expr) is size-atom, and case [head, *args] destructures it. None of
> that costs an engine call.

### `Expr.to_wire`

```python
def to_wire(self) -> list:
```

No docstring is defined.

### `Expr.metatype`

```python
def metatype(self) -> str:
```

No docstring is defined.

### `Expr.head`

```python
def head(self) -> Atom | None:
```

No docstring is defined.

### `Expr.args`

```python
def args(self) -> tuple[Atom, ...]:
```

No docstring is defined.

## `encode`

```python
def encode(value: Any) -> Atom:
```

> Turn a Python value into an atom.
>
> Open by design: a class you own implements __metta__; a class you do not
> own is taught through encode.register, which is functools.singledispatch.
> Anything unregistered without __metta__ is carried whole as a grounded
> object, the same rule the engine itself applies to a host value.

## `decode`

```python
def decode(atom: Any) -> Any:
```

> Unwrap grounded values to Python, recursively, leaving structure alone.
>
> A Gnd becomes its value, an Expr becomes an Expr of decoded children
> only when asked (this returns the expression as is), and symbols and
> variables stay atoms. Named for what it does; results already compare
> ergonomically without it, so it is never on a default path.

## `from_wire`

```python
def from_wire(wire: Any) -> Atom:
```

> Rebuild an atom from the tagged wire form janus delivered.
>
> Iterative, because expression depth is data and must not meet Python's
> recursion ceiling; strict, because a malformed payload is a boundary
> bug that must surface rather than coerce.

## `sym`

```python
def sym(name: str) -> Sym:
```

> A symbol by name, for names that are not Python identifiers.

## `var`

```python
def var(name: str) -> Var:
```

> A variable by name.

## `val`

```python
def val(value: Any) -> Gnd:
```

> Carry a Python value whole, whatever it is.
>
> MeTTa has no list type: encode([1, 2, 3]) is the expression (1 2 3), so
> petta.val([1, 2, 3]) is how to say this particular list is one grounded
> value. It crosses by reference, comes back as the same object, and
> unifies by identity.

## `expr`

```python
def expr(*children: Any) -> Expr:
```

> An expression from parts, each encoded.

## `parse`

```python
def parse(source: str) -> Atom:
```

> Read one form of MeTTa source into an atom, evaluating nothing.
>
> Backed by the engine's own reader, with one improvement over sread/2: the
> variable names the DCG collects are kept, so parse("(Parent $x Bob)")
> contains Var('x') rather than a machine name, and the same pattern built
> with V.x compares equal.

## `variables`

```python
def variables(atom: Atom) -> list[str]:
```

> Variable names in an atom, in first-appearance order. Iterative:
> depth is data.

## `is_ground`

```python
def is_ground(atom: Atom) -> bool:
```

> True when the atom carries no variables.

## `alpha_eq`

```python
def alpha_eq(a: Atom, b: Atom) -> bool:
```

> Equality up to consistent renaming of variables, PeTTa's =alpha.
>
> A named function rather than ==, because two atoms must not compare
> differently depending on which variable names they happen to carry.

## `unify`

```python
def unify(pattern: Any, atom: Any) -> Mapping[str, Atom] | None:
```

> Match a pattern against an atom, returning bindings or None.
>
> One-way: variables on the pattern side bind; a variable on the atom side
> matches only the same variable. No occurs check, matching SWI's default
> and therefore the engine's.
