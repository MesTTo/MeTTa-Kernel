<!--
Purpose: teach the MeTTa-node seat itself: the install that needs no
  SWI-Prolog, how a program starts, and what running the engine on WebAssembly
  costs and buys. The eight numbered tutorials teach the language in Python;
  this teaches the seat.
Assumes: the reader knows TypeScript or JavaScript, has Node 22.18 or newer,
  and has no SWI-Prolog on the machine.
Guarantees:
  - every fence was run against this checkout on 2026-08-29, from the packed
    tarball installed into an empty project, and the outputs written beside
    them are what it printed
    [source: extensions/node/examples/readme-snippet.ts; commit=57f21ba9edf94bcf28cde11f938bce2c241a3709]
  - the capability table is the engine's own answer to
    m.engine.capabilities() on the WebAssembly build, not a list kept here
    [source: extensions/node/src/index.ts; commit=57f21ba9edf94bcf28cde11f938bce2c241a3709]
  - the page is in the navigation and its links resolve
    [tested: test_every_site_page_is_reachable_from_the_navigation,
    npm run docs:build; commit=57f21ba9edf94bcf28cde11f938bce2c241a3709]
-->

# The MeTTa-node tutorial

Here is a whole program. It stores two facts, walks the answers to a pattern,
and reduces a term.

```ts
import { metta, S, V, fn } from "metta-node";

const m = await metta();

m.add(S.parent(S.tom, S.bob), S.parent(S.bob, S.ann));

for await (const { child } of m.match(S.parent(S.tom, V.child))) {
  console.log(String(child));            // bob
}

console.log(String(await m.eval(fn.add(1, 2)).one()));   // 3

m.dispose();
```

Nothing else is installed to run that. No SWI-Prolog, no Python, no compiler,
no server.

## The install has no prerequisite

The engine here is [swipl-wasm](https://github.com/SWI-Prolog/npm-swipl-wasm),
the SWI-Prolog organisation's own WebAssembly build of SWI-Prolog, and it comes
down as an npm dependency like anything else. The whole install is npm, in a
directory with nothing else in it:

```sh
npm init -y
npm install /path/to/MeTTa-Kernel/extensions/node/metta-node-0.0.1-alpha.0.tgz
```

That second line takes the packed tarball, which is what `npm pack` inside
`extensions/node/` writes. The package is not on the public registry yet; when
it is, `npm install metta-node` is the same thing, and the name you import does
not change either way.

Node 22.18 or newer, which is what `package.json` declares.

Two things ride in that tarball besides the compiled JavaScript: `bridge.pl`,
the seat's Prolog half, and `_runtime/`, a copy of the engine tree and the
MeTTa libraries. Without the second one an installed package resolves `engine/`
against your project directory and fails looking for a folder you never made.

That install was run on a Windows laptop with no SWI-Prolog on it at all, from
a tarball in an empty `npm init` directory, and MeTTa answered.

## Answers are thenable, so you await them

An ask is a description. Nothing runs until something consumes it, and `await`
is what consumes it:

```ts
const ans = m.match(S.parent(V.x, S.bob));   // nothing has run yet
const rows  = await ans;                      // the whole answer set
const who   = await ans.one();                // exactly one, or a refusal
const maybe = (await ans.find()) ?? S.none;   // at most one, so ?? composes
```

`await` executing the query is the platform's own promise protocol rather than
an invented `.all()`, and it is where Drizzle and Kysely put execution too. One
catch: returning an `Answers` from an `async function` awaits it implicitly, so
the lazy handle does not survive an async return.

`for await` walks one answer at a time, and leaving the loop early closes the
cursor and destroys the engine behind it. So an endless generator is safe to
walk:

```ts
m.run("(= (from $n) (superpose ($n (from (+ $n 1)))))");

const seen: string[] = [];
for await (const answer of m.eval(S.from(1))) {
  seen.push(String(answer));
  if (seen.length === 5) break;         // the sixth is never computed
}
console.log(seen.join(" "));            // 1 2 3 4 5
```

## Terms are built, not spelled

`S` mints symbols, `V` mints variables, and applying a symbol builds an
expression. Nothing here contacts the engine:

```ts
S.parent                      // the symbol `parent`
S.parent(S.tom, S.bob)        // the expression `(parent tom bob)`
V.child                       // `$child`
```

A TypeScript identifier reaches MeTTa through TypeScript's own casing
convention, so `S.carAtom` is `car-atom`. An operator's head is punctuation,
which no casing map reaches, so `fn` consults an operator table first: `fn.add`
is `+` and `fn.gte` is `>=`. That is why the first program says `fn.add(1, 2)`
and not `S.add(1, 2)`, which would build `(add 1 2)` and find no equation for
it.

A built term is interned and frozen, so `===` on one is structural and `Set`
and `Map` are structural with it without either being reimplemented:

```ts
S.parent(S.tom, S.bob) === S.parent(S.tom, S.bob);   // true
new Set([S.parent(S.tom), S.parent(S.tom)]).size;    // 1
V.x === V.x;                                          // true
```

## A space is a collection

It means by `add`, `has`, `delete`, `size` and `clear` what `Set` means by
them:

```ts
const kb = m.space(S.kb);
kb.add(S.parent(S.tom, S.bob), S.parent(S.bob, S.ann));

kb.size;                              // 2
kb.has(S.parent(V.x, S.bob));         // true: a pattern asks the same question

const rows = await kb.match(S.parent(V.x, S.bob));
rows.map((r) => String(r.x));         // ["tom"]
```

Rows are keyed by the pattern's own variable names, so you destructure an
answer instead of counting children.

## Two doors for a TypeScript function

`m.define` LOWERS the body: it is read and installed as equations, so the
engine owns it and a call crosses into JavaScript not at all.

```ts
const twice = m.define(function twice(n: number): number {
  return n * 2;
});

String(await twice(21).one());        // 42
String(twice.equations[0]);           // (= (twice $n) (* $n 2))
```

`m.op` publishes a function the engine CALLS, for a body that has to stay
JavaScript, and it declares an effect class because the engine cannot see
inside it:

```ts
import { hostValue } from "metta-node";

const shout = m.op(function shout(text: string): string {
  return text.toUpperCase();
}, { effect: "pureStructural" });

hostValue(await shout("hello").one());  // HELLO
m.effectOf(shout);                      // pureStructural
```

`hostValue` unwraps a grounded answer back to the JavaScript value inside it.
`String()` on the same answer gives MeTTa's own rendering, `"HELLO"` with its
quotes, because that is what the atom is.

## What the WebAssembly build costs

The engine is a real SWI-Prolog, but a WebAssembly one, and three of its
optional libraries are not in that build. It says so itself rather than leaving
you to find out:

```ts
for (const c of m.engine.capabilities()) {
  console.log(c.capability, c.present, c.requires);
}
```

```text
concurrency         false   library(thread)
deadlines           false   library(time)
subprocess          false   library(process)
regex               true    library(pcre)
compressed-sources  true    library(zlib)
fast-cache          true    [library(fastrw),library(memfile)]
```

Each absent one has a host answer, because the platform already had the
concept. Concurrency is `metta-node/parallel`: `race`, `merge`, `parMap`,
`every`, `Channel` and `spawn`, each taking an `AbortSignal`. Deadlines are
`AbortSignal` as well:

```ts
await m.eval(S.from(1)).until(AbortSignal.timeout(50));
// throws TimeoutError: The operation was aborted due to timeout
```

Cancellation is checkpoint-granular. The engine is asked to stop between
answers, so one very long reduction runs to its next answer before it notices.
That is `fetch`'s own contract, said plainly.

## Where to go next

[The MeTTa-node seat page](./) is the full surface with worked examples: spaces
implemented in TypeScript, proofs as data, standing queries, the saga journal,
and the 27 subpaths that cost nothing unimported. `examples/gallery.ts` in the
installed package is five programs that use most of it and print what they got.
The [eight numbered tutorials](../../tutorials/) teach MeTTa itself; they are
written in Python, and every idea in them is the same idea here.
