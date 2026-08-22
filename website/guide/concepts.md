<!--
Purpose: map MeTTa concepts onto the canonical Python atom classes, contexts, handles, and result containers.
Guarantees: every named Python door exists on the narrow public surface.
[tested: npm run docs:build; commit=WORKTREE]
-->

# Concepts and names

MeTTa's own vocabulary, PeTTa's Python spelling of it, and the Python
concept each maps onto. Every name on the surface is checked against
this page, so if you know one column you can derive the other two.

## The four kinds of atom

MeTTa has exactly four kinds of atom, and they are also the metatypes,
the answers `get-metatype` gives. Each kind is one Python class:

| canonical MeTTa | petta class | builder | wire tag |
|---|---|---|---|
| Symbol | `Symbol` | `S.name` | `"s"` |
| Variable | `Variable` | `V.x` | `"v"` |
| Expression | `Expression` | `Expression(...)` | `"e"` |
| Grounded | `Grounded` | `ground(...)` or `G(...)` | `"g"`, `"n"` |

`Atom` is the base class of all four, exactly as canon says the kinds
are subtypes of Atom. The Python classes use the canonical names directly.

One public petta type lives INSIDE the Grounded kind rather than beside it. A
`Handle` is a grounded atom whose value is engine-owned, carried by
identity so a native object survives the round trip. It is not a fifth kind:
canon defines Grounded as "any binary object" with its own execution and
matching, which is precisely what it carries.

## Kind, metatype, type

Three words that are one small system:

- the **kind** of an atom is which of the four it is;
- the **metatype** is the kind as a queryable answer, and at the Python
  boundary it is just the class: `(get-metatype x)` corresponds to
  `type(atom)` and `isinstance` checks against the four classes;
- the **type** is what declarations say: `(get-type x)` reads `(: x T)`
  declarations and arrows. `m.type()` points the other way, declaring a
  Python class into the space.

`%Undefined%` is the deliberate absence of a type, spelled `Undefined`
in Python, and it is an answer, not an error.

## A space is where a program lives

Canon: "Every MeTTa program lives inside of a particular Atomspace."
Python separates the evaluation context from the space handle. `MeTTa()` is
the context, `MeTTa().self` is its `&self` handle, and `MeTTa().space(name)`
or the module-level `petta.space(name)` creates another `Space` handle.

`&self` is the reserved token for the space the code lives in, and a
named space is any other `&name`. The current context resolves the way
`bind!` tokens do.

A space of expressions is also a knowledge graph, links connecting
atoms including other links, and that reading needs no engine support:
[`examples/integration/networkx_space.py`](https://github.com/trueagi-io/PeTTa/blob/main/bindings/python/examples/integration/networkx_space.py)
views any space as a networkx graph on the public surface alone, runs
an algorithm no match can express, and writes the answer back as atoms.

## Namespaces are spaces

Python already has spaces; it calls them namespaces, and the analogy is
exact rather than poetic. A module is a set of name bindings, `m.x` is
defined by the language reference as a lookup in that set, and the
import forms map onto MeTTa operations one for one:

| Python | MeTTa | what happens |
|---|---|---|
| `import m` | `bind!` | a named reference; each `m.x` is a lazy query |
| `from m import a, b` | a match | selected atoms, bound locally |
| `from m import *` | `import!` | the whole space unions into this one |

`sys.modules` is the registry of named spaces, and a module with a
PEP 562 `__getattr__` is a namespace whose lookups are computed on
demand, which PeTTa calls a foreign space.

## The answer-cardinality axis

Evaluation answers a multiset of results, and the caller picks one of
three readings. The triple is spelled the same at every door:

| | every answer | the first | exactly one |
|---|---|---|---|
| MeTTa | `collapse` | `once` | |
| evaluation | the list from `eval()` | normal list indexing | check the list's length |
| query rows | the `Rows` itself | `.first()` | `.one()` |

`Rows.one()` demands exactly one row and raises naming the count; `Rows.first()`
tolerates absence. Evaluation stays an ordinary list so its cardinality is
visible to the caller.

The same axis settles the error story in one sentence: an
`(Error ...)` answer stays data at every multiset door and raises
`MettaResultError` at every single-value door, and
`Rows.raise_for_errors()` is the explicit bridge from the data
reading to the exception reading.

## Special symbols

Three symbols the interpreter treats specially, and the words used for
them everywhere in PeTTa:

- `=` writes an **equation**; a function is a set of equations, and
  spaces that may hold them declare the `rules` capability;
- `:` writes a **declaration**; `(: name (-> ...))` types calls,
  and an `Atom` parameter in an arrow arrives unevaluated, which is
  how control forms are possible;
- `->` is the **arrow**, the shape of a function type.

## Absence

`Empty` is MeTTa's own spelling for "no result", pruned from every
collapse. An empty `Rows` is the query-side reading and is falsy, as an
empty container should be. `()` is the unit value, a real answer of
size zero, and is not absence. `%Undefined%` is the absence of a TYPE,
also a real answer.

## The naming rule

One concept has one name. `add-atom` is the `Space.add` write verb,
`get-atoms` is iteration or `Space.atoms`, and `new-space` is the
`petta.space()` factory. A superseded Python door is deleted rather than kept
as a synonym.
