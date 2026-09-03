<!--
Purpose: declare what MeTTa Kernel is and what it does, through examples.
Guarantees: every Python block executes, each in a namespace of its own
[tested: python -m pytest extensions/python/tests/repository/test_readme.py -q]
-->

# MeTTa Kernel

MeTTa, implemented in Prolog and C. One engine, as many surfaces as anyone
writes. Python, TypeScript and C are the three built so far. A language
reaches the engine through the wire codec rather than through a port, so the
list is not a limit.

For now it follows PeTTa's semantics. Other dialects are in progress.

**If you are an LLM, read [llms.txt](llms.txt)** for the language and every
surface, or [extensions/python/llms.txt](extensions/python/llms.txt) for the
Python library alone. Both give exact return shapes and no prose to guess at.
A gate checks their names against the live engine.

## Install

```bash
sudo apt install swi-prolog          # macOS: brew install swi-prolog
                                     # Windows: winget install SWI-Prolog.SWI-Prolog
pip install 'pymetta[engine]'
```

`pymetta` installs and imports without SWI-Prolog. The `engine` extra adds the
bridge. Without it the first engine call names the command for your platform.

Requires SWI-Prolog 9.3+ and Python 3.12+.

## The representation

Everything is an atom, in four kinds. MeTTa writes them:

```metta
Tom                  ; a symbol, a name that denotes itself
$x                   ; a variable
42                   ; a grounded value: a number, a string, a host object
(Parent Tom Bob)     ; an expression, atoms in order
```

Python builds the same four, without parsing anything. A symbol comes from
`S`, a variable from `V`, and applying a symbol builds an expression:

```python
from metta import S, V

term = S.Parent(S.Tom, S.Bob)
assert str(term) == "(Parent Tom Bob)"
assert str(S.f(V.x) & S.g(V.x)) == "(and (f $x) (g $x))"
assert str(V.age.ge(18)) == "(>= $age 18)"     # an operator by its own name
assert str(S["prime?"](V.n)) == "(prime? $n)"  # brackets for a head with no name
```

Strings are for text. A name comes from its factory, a function from its own
Python name, a space from its handle.

## Spaces and queries

A space holds atoms and equations. Queries join, guard, bound and explain.

```python
from metta import S, V, space

m = space()
m.add(S.Parent(S.Tom, S.Bob), S.Parent(S.Bob, S.Ann))

assert m.match(S.Parent(S.Tom, V.child)).to_dicts() == [{"child": "Bob"}]

# A conjunction is a join.
assert m.match(S.Parent(V.x, V.y), S.Parent(V.y, V.z)).to_dicts() == [
    {"x": "Tom", "y": "Bob", "z": "Ann"}
]

m.add(S.Age(S.Tom, 62), S.Age(S.Bob, 40))
assert m.match(S.Age(V.p, V.n), where=V.n.ge(60)).to_dicts() == [
    {"p": "Tom", "n": 62}
]
assert len(m.match(S.Age(V.p, V.n), limit=1)) == 1

# Facts for one block only.
with m.assuming(S.Parent(S.Ann, S.Zoe)):
    assert m.match(S.Parent(S.Ann, V.c)).to_dicts() == [{"c": "Zoe"}]

# A prepared statement: the shape and its columns build once, then every
# solve() reuses them. given= adds facts for one solve and leaves nothing.
grand = m.prepare(S.Parent(V.x, V.y), S.Parent(V.y, V.z))
assert grand.solve().to_dicts() == [{"x": "Tom", "y": "Bob", "z": "Ann"}]
assert len(grand.solve(given=[S.Parent(S.Ann, S.Zoe)])) == 2
```

`m.eval(term)` evaluates a built term and answers every answer. `m.run(source)`
takes whole MeTTa programs as text. Prefer the built term when you have one: it
is knowledge already, where a string must be parsed first. `rows.why()`
explains an empty match. `m.derivation(atom)` builds the proof tree behind an
answer. Its premises execute, effects included; use `with m.speculative():`
when engine writes should be discarded, noting that external side effects
already performed cannot be rolled back.

## Writing MeTTa in Python

`@m.define` reads the function's source and lowers it into MeTTa equations,
which compile to Prolog clauses: saying it in Python costs no more per call
than saying it in MeTTa ([measured](EXTENDING.md#what-each-one-costs)).
`# ->` shows what each definition becomes. The three stack the way MeTTa
equations do, into one equation whose body is a first-match `case`:

```python
from metta import space

m = space()

@m.define
def fib(n=0):                          # -> the arm (0 0)
    return 0

@m.define
def fib(n=1):                          # -> the arm (1 1)
    return 1

@m.define
def fib(n):                            # -> ($n (+ (fib (- $n 1)) (fib (- $n 2))))
    return fib(n - 1) + fib(n - 2)

# the three together:
# (= (fib $n) (case $n ((0 0) (1 1) ($n (+ (fib (- $n 1)) (fib (- $n 2)))))))

assert fib(10) == [55]           # callable from Python, answers a list
assert fib.py(10) == 55          # and the Python twin stays callable
```

You can read exactly what your Python became:

```python
from metta import space

m = space()

@m.define
def fact(n: int) -> int:
    if n == 0:
        return 1
    return n * fact(n - 1)

assert str(fact.head) == "(fact $n)"
assert str(fact.body) == "(if (py-truthy (py-operator eq $n 0)) 1 (* $n (fact (- $n 1))))"
assert fact(5) == [120]
```

The subset is Python as Python means it: rebinding compiles through static
single assignment, `while` and `for` become tail-recursive equations in
constant stack, a generator compiles to nondeterminism, a lambda to `|->`,
comprehensions to `map-atom` and `filter-atom`, `try`/`except`/`finally` onto
the engine's error algebra, and dict and set literals into spaces.

What the vocabulary does not lower natively becomes a VISIBLE host island
inside the equation, run per application and never at decoration time;
`py(...)` spells that explicitly. The refusals that remain name their
construct, line and caret, and cite their ground in Python or in MeTTa.

## What it does that a library cannot

A function you wrote forwards runs backwards. `solve` takes the answer and
asks for the argument:

```python
from metta import S, V, space

m = space()

@m.define
def double(x: int) -> int:
    return 2 * x

assert double(5) == [10]                  # forwards, and callable from Python
assert m.solve(10, S.double(V.x)).x == 5  # backwards, no second definition
assert m.solve(5, V.p + 2).p == 3         # every operator solves for its slot
assert m.solve(12, V.q * 4).q == 3
```

Many answers is the normal case rather than an error:

```python
from metta import S, space

m = space()
assert sorted(a.value for a in m.eval(S.superpose((1, 2, 3)))) == [1, 2, 3]
```

The program is data. An equation is an atom, so adding one at run time changes
what the program means, and the equations are queryable like anything else:

```python
from metta import S, V, equation, space

m = space()
m.add(equation(S.price(V.x)).to(10))      # an equation is an atom you add
assert m.eval(S.price(S.apple)) == [10]

m.add(equation(S.price(S.apple)).to(3))   # a second one, at run time
assert sorted(a.value for a in m.eval(S.price(S.apple))) == [3, 10]

heads = {str(row.head) for row in m.match(equation(V.head).to(V.body))}
assert "(price apple)" in heads           # the program can read itself
```

Everything below builds on those three: the space holds both the facts and the
program, evaluation is matching, and nothing is closed to inspection.

## Three axes

A crossing between Python and the engine makes three independent choices.

| axis | poles | how you say it |
|---|---|---|
| where the body lives | CALLED, or LOWERED | `@m.pure` and friends, or `@m.define` |
| what the body may observe | pure, reads, writes, io | the decorator's name |
| what a value crosses as | transparent, or opaque | `transport="encoded"` or `"raw"` |

The first two are different questions and easy to confuse. Where the body
lives decides whether Python runs at all. What it may observe decides whether
the engine may cache it.

```python
import statistics

from metta import space

m = space()

# CALLED: the body stays Python and the engine calls it, so a Python library
# is simply in scope. The decorator says what it may observe, the one thing
# the engine cannot see for itself; transport="raw" hands it Python values.
@m.pure(transport="raw")
def spread(values) -> float:
    return statistics.pstdev(values)

# LOWERED: the body BECOMES equations. No Python at run time and no effect to
# declare, because now the engine can read the code -- a comprehension is
# MeTTa's own filter-atom and map-atom, written the way Python writes them.
@m.define
def loud(readings, limit: int):
    return [value for value in readings if value > limit]

assert list(m.fn.spread([1, 2, 3, 4]))[0].value == statistics.pstdev([1, 2, 3, 4])
assert str(loud((7, 12, 30), 10)[0]) == "(12 30)"
assert loud.effect == "pureStructural"         # derived, not declared
```

Four decorators, ordered, each admitting everything below it. Only `pure` may
be cached, memoised or tabled.

| decorator | what it may observe or change |
|---|---|
| `@m.pure` | nothing but its arguments; same answer forever |
| `@m.reads` | state that can change, without changing it |
| `@m.writes` | engine or host state |
| `@m.io` | an external oracle: clock, randomness, network, file |


```python
import metta
from metta import S, V, space

m = space()

@m.pure
def upto(n: int):
    yield from range(1, n + 1)

assert sorted(a.value for a in m.fn.upto(3)) == [1, 2, 3]

lifted = metta.reflection.match(S.effect(S.upto, V.e))
assert [str(row.e) for row in lifted] == ["nondeterministicReadOnly"]
```

`transport="raw"` composes with any of them and is 1.6x cheaper, at the cost of
the symbol/string distinction: symbols reach a raw operation as plain strings.

Measured, per crossing: letting the engine call out costs 19,557 retired
instructions against 96,771 for the host driving in, so a loop over many items
belongs in MeTTa. A transparent value costs four inferences per element and an
opaque one costs 12.31 whatever the size, so at a thousand elements the gap is
419x and still growing. `EXTENDING.md` prices all three and
`extensions/python/benchmarks/axes.py` reproduces the numbers.

## Async

```python
import asyncio
import metta
from metta import S, V

async def main():
    async with await metta.aio.connect() as m:
        await m.add(S.edge(S.a, S.b))
        rows = await m.match(S.edge(V.x, V.y))
        return rows.to_dicts()

assert asyncio.run(main()) == [{"x": "a", "y": "b"}]
```

The engine runs on its own thread and every call is awaitable.

## Parallel evaluation

```python
import metta
from metta import S, V, space

m = space()
m += [(S.Reading, S.north, 12), (S.Reading, S.south, 30)]

@m.define
def above(limit: int) -> int:
    return len(m.match(S.Reading(V.site, V.value), where=V.value.ge(limit)))

# Branches run on real threads over the one shared space, and answer in
# COMPLETION order, so `collapse` has nothing to do here.
assert sorted(a.value for a in m.parallel(S.above(10), S.above(20))) == [1, 2]

# A parallel MAP is a different promise: it keeps the INPUT's order.
assert str(m.eval(metta.par_map(S.above, (10, 20)))[0]) == "(2 1)"
```

`lib_thread` also carries futures (`spawn` answers a space), `await`, channels
with backpressure, pools, Linda-style waits and locks.

## Across processes

`serve` publishes this engine's spaces over HTTP; `attach` registers another
engine's space here as an ordinary space, so a query crosses the network the
way it crosses into a database.

```python
from metta import S, space, remote

m = space()
m.add(S.edge(S.a, S.b))

with remote.serve(m, spaces=[m.name]) as server:
    server.url          # another process attaches to this
```

```python
import metta
from metta import S, V, space, remote

server_space = space()
server_space.add(S.edge(S.a, S.b), S.edge(S.b, S.c))

# In ONE process the transport is a Gateway: janus holds the GIL across a
# Prolog call, so an HTTP attach here is refused with this remedy named.
metta.attach("&warehouse", remote.RemoteSpace(
    remote.Gateway(server_space, [server_space.name]), str(server_space.name)))
edges = metta.space("&warehouse").match(S.edge(V.x, V.y))
assert edges.to_dicts() == [{"x": "a", "y": "b"}, {"x": "b", "y": "c"}]
```

Bearer tokens, TLS and a per-request authorization hook are arguments to
`serve`. Answers stream a chunk at a time, so taking two answers costs two
answers' work whatever the space holds.

## Standing queries

A subscription is a query that stays, delivered inside the write that matched
it.

```python
from metta import S, V, space

m = space()
seen = []
m.subscribe(S.Alarm(V.what), seen.append)
m.add(S.Alarm(S.fire))

assert [str(event.atom) for event in seen] == ["(Alarm fire)"]
assert str(seen[0].bindings["what"]) == "fire"
```

## Spaces backed by anything

A space provider puts atoms wherever they already live: a SQL table, a
dataframe, a service, another engine. The engine keeps unification, so a
provider may over-approximate and stay correct.

```python
import metta
from metta import S, V
from metta.foreign import SpaceProvider

class Rows(SpaceProvider):
    def __init__(self, rows):
        self.rows = rows

    def atoms(self):
        return [S.user(i, name) for i, name in self.rows]

metta.attach("&catalogue", Rows([(1, "Ada"), (2, "Bob")]))
rows = metta.space("&catalogue").match(S.user(V.id, V.name))
assert rows.to_dicts() == [{"id": 1, "name": "Ada"}, {"id": 2, "name": "Bob"}]
```

Bound positions reach the provider as its `WHERE` clause, and a provider that
declares its filtering exact is handed the caller's bound to push down.
Worked instances ship for SQLite, DuckDB, Redis, C and TypeScript.

## Integrating a library

MeTTa's semantics already subsume what libraries are made of, so integration is
a mapping rather than machinery.

| the library has | it becomes |
|---|---|
| functions, methods | grounded functions; a call is a reduction |
| objects with state | grounded atoms with identity |
| tables, frames, indexes | spaces; a query is a match |
| dispatch (routes, handlers) | equations over one head |
| generators, search, retrieval | nondeterminism; each yield one answer |
| schemas, records, enums | constructor expressions and `(: ...)` declarations |

```python
import math
from metta import space
from metta.integrate import module_ops

m = space()
module_ops(m, math, ["sqrt", "gcd"], effect="pureStructural")
assert list(m.fn.sqrt(16.0)) == [4.0]
```

A package advertises itself through the `metta.integrations` entry-point group,
and `metta.integrate.discover(m)` finds it.

## Command line

```bash
python -m metta run program.metta        # run files, print each ! answer group
python -m metta repl                     # interactive loop
python -m metta serve kb.metta --port 8700
python -m metta lint program.metta       # nonzero exit on findings
python -m metta doc car-atom
```

## A motivating example

In 1986 Swanson found that fish oil might treat Raynaud's syndrome. No paper
said so. One literature reported that fish oil lowers blood viscosity; another,
which did not cite the first, reported that raised blood viscosity aggravates
Raynaud's. The conclusion followed from the two together, was stated by
neither, and went unnoticed partly because the two literatures did not share
vocabulary.

That problem needs both halves of a neurosymbolic system. This is
`extensions/python/examples/reasoning/literature_discovery.py`, which the gate
runs:

```python
import torch
from metta import TRUE, G, S, V, counting, prov, space
from metta.arrays import EmbeddingStore

m = space()

# Two literatures that never cite each other, and a red herring. Each claim
# carries the paper it came from. Nothing here states a conclusion.
for paper, agent, verb, target in [
    ("p1", "omega-3", "lowers", "blood-viscosity"),
    ("p2", "blood-viscosity", "aggravates", "raynaud"),
    ("p4", "omega-3", "lowers", "platelet-aggregation"),
    ("p5", "platelet-aggregation", "aggravates", "raynaud"),
    ("p3", "aspirin", "lowers", "inflammation"),
]:
    m.add_tagged_fact(S[paper], S.reports(S[agent], S[verb], S[target]))

# Swanson's ABC rule, tagged like any other source.
m.add_tagged_rule(
    S.abc,
    S.suggests(V.agent, V.condition),
    S.reports(V.agent, S.lowers, V.factor),
    S.reports(V.factor, S.aggravates, V.condition),
)

TERMS = {"omega-3": [0.90, 0.10, 0.0], "fish-oil": [0.88, 0.16, 0.0],
         "aspirin": [0.10, 0.90, 0.0], "blood-viscosity": [0.0, 0.10, 0.90]}
store = EmbeddingStore(m, name="terms", mirror=False)
for term, vector in TERMS.items():
    store.add(S[term], torch.tensor(vector))

class Like:
    """Unifies with whatever the embedding puts within `floor`. `match_` is the
    whole interface: no registration, and it composes with `unify`."""
    def __init__(self, key, floor=0.95):
        self.key, self.floor = key, floor
    def match_(self, other):
        for key, score in store.ranked(self.key, len(TERMS)):
            if str(key) == str(other) and float(score) >= self.floor:
                yield other

near_fish_oil = S.unify(G(Like(S.fish_oil)), V.agent, TRUE, S.superpose(()))

# Symbolically there is nothing. No paper contains the phrase.
assert m.match(S.reports(S.fish_oil, S.lowers, V.factor)).to_dicts() == []

# The same corpus, asked with a term the embedding can place. The join is the
# engine's; deciding that fish-oil IS omega-3 is the tensor's.
found = m.match(S.suggests(V.agent, S.raynaud), where=near_fish_oil, under=prov).one()
assert str(found.value) == "(suggests omega-3 raynaud)"

# How much independent support? The same question under a different algebra.
assert m.match(S.suggests(S["omega-3"], S.raynaud), under=counting).one() == 2

# Which papers? A provenance polynomial: `times` is joint use, `plus` is an
# alternative derivation. Read it as "the rule with p1 and p2, or with p4 and p5".
assert str(found.annotation) == (
    "(plus (times (times abc p1) p2) (times (times abc p4) p5))"
)
assert all(name in found.why().render() for name in ("abc", "p1", "p2", "p4", "p5"))
```

The answer is not a plausible sentence. It is a derivation naming `abc`, `p1`
and `p2`, which a reader can go and check.

The evidence is algebra, not bookkeeping. The same question under `counting`
says how many independent literature paths support the hypothesis; under `prov`
it says which papers, as a polynomial. Neither costs a line of tracking code,
because tags compose through the join the way the join composes [Green,
Karvounarakis and Tannen, *Provenance semirings*, PODS 2007].

Neither half works alone. A language model does not chain reliably over many
hops and cannot show its working; a symbolic prover cannot cross a vocabulary
gap where two names share nothing but their meaning. Here the embedding decides
what unifies and the engine decides what follows. The neural gate, the tagged
rule and the semiring sit in that one query, and none is a plugin: they are the
same seam.

## TypeScript

`extensions/node/` runs the engine inside Node over WebAssembly, so no
SWI-Prolog on the machine and no socket. The same three axes, spelled the way
TypeScript spells things. This is `extensions/node/examples/readme-snippet.ts`,
which the gate runs:

```ts
import { metta, S, type Term, V } from "metta-node";

const m = await metta();
m.add(S.parent(S.tom, S.bob), S.parent(S.bob, S.ann));

// Rows are keyed by the pattern's own variable names.
for await (const { child } of m.match(S.parent(S.tom, V.child))) {
  console.log(String(child));                   // bob
}

// LOWERED: an ordinary function becomes one equation the engine holds, so the
// call crosses into no host at all.
const twice = m.define(function twice(n: number): number { return n * 2; });
console.log(String(await twice(21).one()));     // 42

// A generator body is traced into clauses; `yield*` asks, `yield` emits.
const grandparent = m.define(function* grandparent(x: Term) {
  const { y } = yield* m.match(S.parent(x, V.y));
  const { z } = yield* m.match(S.parent(y, V.z));
  return z;
});
console.log(String(await grandparent(S.tom).one()));   // ann

// CALLED: a function the engine calls back into mid-reduction, awaited when it
// answers with a promise. Its effect is read off the function, not declared.
m.op(async function fetchJson(url: string) { return (await fetch(url)).json(); });
console.log(m.effectOf("fetch-json"));          // oracleIO

m.dispose();
```

## C

`extensions/cmetta/` embeds the engine through SWI's foreign interface. It has
the same two ways to define, and C reaches the lowered one through the
preprocessor: Python lowers by reading a function's `__code__` and Node by
reading its `toString()`, while `#` is C's own access to its source. From
`extensions/cmetta/examples/lower.c`:

```c
#define MT_SHORTHAND
#include <cmetta.h>

/* CALLED: the engine crosses into C, so the effect class must be declared. */
mt_def(m, (mt_op){ .name = "triple", .arity = 1,
                   .effect = MT_PURE, .fn = op_triple });

/* LOWERED: C tokens the compiler already saw, installed as equations. No
   quoting, no escaped newlines, and unbalanced parentheses are a COMPILE
   error rather than a runtime one. */
mt_lower(m, (twice $x), (* 2 $x));
mt_lower(m, (fib $n), (if (< $n 2) $n
                          (+ (fib (- $n 1)) (fib (- $n 2)))));

/* One body, two languages: the operators are parameters, so the same source
   expands to C in one mode and to MeTTa tokens in the other. */
#define POLY(ADD, MUL, x)  ADD(MUL(3, x), 1)
static int64_t poly(int64_t x) { return POLY(C_ADD, C_MUL, x); }
mt_lower(m, (poly $x), POLY(M_ADD, M_MUL, $x));
```

`examples/` beside it carries `hello`, `ops`, `lower` and `stream`, each built
and run by the gate.

## Backends

`sh build.sh` builds the MORK backend, which gives MORK-backed atom spaces over
[trueagi-io/MORK](https://github.com/trueagi-io/MORK) and
[Adam-Vandervorst/PathMap](https://github.com/Adam-Vandervorst/PathMap). FAISS
atom-vector spaces come from a MeTTa library the engine fetches on request:

```metta
!(git-import! "https://github.com/patham9/faiss_ffi" "build.sh")
```

## Why "kernel"

Because the point is what plugs into it. Anything you want to use lands on
one of three seams rather than needing a fork. (Not to be confused with the
three axes above, which are the choices a single crossing makes.)

**Lower it.** Host code BECOMES equations. `@m.define` compiles a Python body
into MeTTa the engine can read, specialise and match on, and a translator
rule adds syntax that costs nothing at run time.

**Extend it.** The engine CALLS your code. A Python function, a Prolog
predicate, a C foreign predicate or a reader token class each become an
ordinary MeTTa function or literal, priced from 0.02 to 3.87 microseconds a
call depending on how far the value travels.

**Back it.** The atoms LIVE somewhere else. A space is an interface, so
SQLite, DuckDB, NetworkX, a live Python object, another process or a whole
`&mork` store can BE a space, and a query against one joins with a native
one.

The third is the one people underestimate, and it is the smallest: a space is
an INTERFACE, so anything that can list its atoms is one. [Spaces backed by
anything](#spaces-backed-by-anything) above is the whole of it. Write a class
with one method, and a SQL table or a dataframe or a service answers `match`
like a native space and joins with one.

## What the examples show

**[`examples/`](examples/) is the book for learning MeTTa itself.** Its 233
programs are ordered as a reading list, chapter by chapter from the first
answer to a reasoner you can serve, and the directory names ARE the order.
Every file runs and checks itself under the gate, and a law is enforced
rather than promised: a file may use only constructs an earlier number
introduced, so reading top to bottom never meets something unexplained.
[`examples/README.md`](examples/README.md) is its table of contents.

**[`extensions/python/examples/language-feature-examples/`](extensions/python/examples/language-feature-examples/)
is the reference for how to write this library idiomatically.** It is 219
runnable programs, one per MeTTa example, and the gate runs each against the
MeTTa it mirrors: they agree on the stored equations AND the answers, so
neither side can drift into a spelling that merely looks right. Find the
construct in `examples/`, open the file of the same name here, and the Python
beside it is the way to say it. They go deeper than this page can:

| chapter | what it demonstrates |
|---|---|
| arithmetic that runs backwards | `+ - * /` as relations, then CLP(FD) constraints when rearrangement runs out, then a named refusal |
| changing the equations | a program that specialises and removes its own definitions at run time |
| many answers | superposition, collapse, bounded and committed searches |
| types | parametric, recursive and dependent types |
| a reasoner you can serve | constructive negation, a dependently-typed backward chainer, PLN deduction, weak unification, the Scallop programs |
| performance | a million atoms across five index shapes, memoisation and tabling, four million-step kernels |
| transactions and worlds | a counter five threads share, state cells, arbitrary MeTTa run on write, admission pools |
| events and standing queries | subscriptions delivered inside the write that matched them |
| spaces backed by anything | a space in C, a builtin in C, SQL and DuckDB providers |
| extending the engine | translator rules, MeTTa written in MeTTa, Prolog underneath |

## Documentation

- [EXTENDING.md](EXTENDING.md), nine extension points ordered by measured cost.
- [KERNEL.md](KERNEL.md), which forms the translator gives meaning to, and why.
- [CODEC.md](CODEC.md), the wire every atom crosses on.
- [DEVELOPING.md](DEVELOPING.md), gates and measurement rules.
- [CONTRIBUTING.md](CONTRIBUTING.md), what a contribution has to be.
- [SECURITY.md](SECURITY.md), how to report a vulnerability privately.
- [CHANGELOG.md](CHANGELOG.md), what changed.

`extensions/python/examples/` holds runnable, self-verifying integrations that
the test suite runs, so they cannot drift.

### Citing

Cite PeTTa, whose semantics this engine follows, and this repository for the
engine and its surfaces. GitHub's "Cite this repository" button reads
[CITATION.cff](CITATION.cff), which carries both.

```bibtex
@software{petta,
  author = {Hammer, Patrick},
  title  = {PeTTa},
  url    = {https://github.com/patham9/PeTTa},
  note   = {The MeTTa implementation whose semantics this engine follows}
}

@software{metta_kernel,
  author  = {MesTTo},
  title   = {MeTTa Kernel},
  url     = {https://github.com/MesTTo/MeTTa-Kernel},
  version = {0.6.0}
}
```

### Licence

MIT. See [LICENSE](LICENSE) for the notices it carries, and
[CITATION.cff](CITATION.cff) for citation metadata.
