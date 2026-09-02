# The wire codec

Every atom that leaves the engine, and every atom that reaches it from
outside, crosses as a tagged array. This page is that format, written for
somebody adding a binding in a language MeTTa has never been used from.
Implement what is here, run `tests/codec/corpus.json` against your
implementation, and your codec speaks what the two shipped ones speak.

Two encodings ship. The **janus tagged form** carries the arrays as SWI's
own term conversion between the engine and Python, in one process. The
**remote JSON wire** carries the same arrays as JSON bytes over HTTP, which
is what `metta.remote.serve()` and `metta.remote.connect()` put on a socket
and what the TypeScript reference server in
`extensions/python/examples/integration/typescript_space/` answers. They are one
grammar with two concrete encodings and two profiles, and the difference
between the profiles is exactly what each transport can carry.

The engine's reader and writer are one authority and they are not part of
this format. `sread/2`, `sread_with_names/3` and `swrite/2` in
`engine/parser.pl` relate MeTTa source text to engine terms; a binding reaches
text through them rather than growing a second reader. What this page
specifies is the step after that, between an engine term and something
another language can hold.

## How this page is kept

The prose here is written by hand. Every table of tags, profiles and cases
is generated from `tests/codec/corpus.json` by `extensions/python/tools/codecdoc.py`,
and the gate fails if the checked-in tables and the corpus disagree, so the
document and the kit cannot drift apart. Regenerate with
`python extensions/python/tools/codecdoc.py --write`.

Generating the whole page from R19's MeTTaIL presentations was tried first,
because one authority for spec and kit is the right instinct and the
`.mettail` format carries labelled BNF productions. It loses, measured
2026-08-20 on three counts. `tests/mettail/metta.mettail`, the MeTTa
presentation, carries no `::=` annotation at all: its fourteen declarations
are abstract, of the form `term AtomExpr : Atom -> Atom`, and the four
presentations that do carry `::=` are `rholang`, `togl`, `rho-hub` and
`set-binders`, which present a calculus's surface syntax and not a transport
encoding. Those presentations describe the OBJECT language, an evaluator's
instructions, while the tags here are metatype markers plus two host escapes
plus three frames, which is a different layer. And both the presentations
and the tool that reads them live outside this repository, so a page only
regenerable from an absent checkout would be two authorities rather than
one. The corpus wins because it is the artefact the kit actually runs.

## A term is a tagged array

A wire term is an array of exactly two elements, a tag and a payload. The
tag is a one-character string naming what the payload is, the tag set is
closed, and a tag is a claim about its payload rather than a label on it: a
payload outside the class its tag names makes the term malformed, and a
decoder refuses it rather than coercing it into something.

    term    ::= [tag, payload]
    tag     ::= "s" | "g" | "n" | "b" | "v" | "e" | "p" | "o" | "h"
    payload ::= text | exact-integer | float | boolean-text | [term, ...] | host-value

Two shapes break the two-element rule and both are named below: an outbound
`h` carries three elements, and the frames carry three, four or five.

<!-- generated: tags -->
| tag | class | payload | what it is |
|---|---|---|---|
| `s` | term | text | a symbol: a name that denotes itself |
| `g` | term | text | a grounded value carried as text; a string crosses this way |
| `n` | term | exact integer or float | a grounded Number or BigInt; signed-i64 width fixes an integer's language type |
| `b` | term | "true" or "false" | a grounded boolean; the engine writes true and false, and reads True and False as the same two constants |
| `v` | term | text | a variable, the payload an identity within this term |
| `e` | term | array of terms | an expression, its children in order; the empty one is unit |
| `p` | term | ampersand-prefixed text | an executable space reference carried by its portable engine name; the tag is a species and an ampersand name that is no space keeps s |
| `o` | term | host reference | a live host value crossing by reference, in process only |
| `h` | term | registry id, and its printed text outbound | a native engine value held by reference |
| `u` | frame | term and why | an answer whose truth is undefined under the well-founded semantics |
| `a` | frame | theta, residue, k, and optionally a value | an answer together with the bindings it is returned under |
| `x` | frame | end, declined, or error with a term | stream control: exhaustion, no answer at all, or a failure kept as a value |
<!-- end generated -->

Nine of those are term tags and three are frames. The seven `s g n b v e o`
were fixed in the 2026-08-13 design; `h` was added afterwards for native
engine values, `p` for executable space references, and the frames grew with
the answer protocol.

A symbol is not a string. `["s", "foo"]` and `["g", "foo"]` are different
atoms, `foo` the name and `"foo"` the text, and folding them together is the
ambiguity the tags exist to remove. A boolean is not a symbol either:
`["b", "true"]` is the constant, `["s", "True"]` is a name that happens to
spell it, and they do not match each other.

`["e", []]` is unit, the empty expression. It is not a missing value and not
the empty string, which is `["g", ""]`.

`["p", "&kb"]` carries an executable space reference by its engine name. The
name is portable; decoding resolves it to the receiving runtime's `Space`
handle. A malformed payload is refused rather than becoming a symbol or
silently naming another kind of term.

## The question `p` asks, and what it costs

`p` is a **species** tag, exactly as `s` and `n` and `b` are: it says what the
atom IS, and a decoder builds a space handle from it where `s` builds a
symbol. So the question an encoder must ask is the language's own species
question, and the engine already owns it. `get-metatype` answers `Grounded`
for a space and `Symbol` for a name that merely looks like one, and the clause
that decides it is `metta_space_operand/1`
(`engine/metta/types.pl`, `metatype_of(X, 'Grounded') :- atom(X),
metta_space_operand(X)`). That is the test both shipped seats ask, so
`get-metatype` and the wire cannot disagree about an atom.

The payload is text beginning with `&`, which is how the engine mints a space
name and what its doors require of one a program writes. A **parametric**
space is named by a ground expression rather than an atom, and it crosses as
that expression, `e`, because a `p` payload is text.

**The ampersand alone decides nothing**, and this is the part a new binding
gets wrong. `&not-a-space` reads as an ordinary atom; nothing has created a
space under that name, so it crosses as `["s", "&not-a-space"]` and
`get-metatype` calls it a `Symbol`. The engine reuses the `&` spelling for
things that are not spaces at all: a `State` cell is `&state-#0`, which is
`Grounded` for a different reason and is no space. An encoder that read the
prefix instead of asking would send both across as space handles.

There is a wider test next to it, `metta_space_name/1`, which is what the
builtin `(is-space ...)` answers, and it is deliberately not this. It asks
whether a space OPERATION may take this name, and because a space is created
on demand the answer is yes for every `&` name, `&not-a-space` and `&state-#0`
included. That is the right answer to "may I write here" and the wrong answer
to "what is this".

**The price, stated plainly.** A space's species depends on whether it exists,
so the same atom crosses as `s` before anything creates a space under its name
and as `p` afterwards. `metta.space("&kb")` in Python hands back a handle
immediately, but the engine has no space under `&kb` until something writes to
it, so `&kb` coming back out of an evaluation before that write is a `Symbol`.
That is the engine's create-on-demand model showing through and it is what
`get-metatype` reports too. A conformance corpus therefore has to name either
a space that exists in every runtime, as `space-handle` does with `&self`, or
one no runtime creates, as `symbol-ampersand` does.

Both shipped seats ask this one question, per atom, and neither holds a list
of names. The Python host asks it in `metta_py_encode/2` while encoding; the C
seat, which has no wire and reads engine terms directly, asks it through
`metta_c_space_operand/1` while decoding.

## Variables are identities, not names

A `v` payload identifies a cell within its own term. Two occurrences of the
same payload in one term are two occurrences of one variable; two different
payloads are two different variables. Nothing else follows from it: it is
not a display name, it does not have to survive a crossing, and two terms
that differ only by a consistent renaming of their `v` payloads are the same
term.

That is why the conformance kit compares wire terms up to a bijection on
`v` payloads and byte-exactly everywhere else. Both shipped encoders satisfy
the law and they spell it differently, which is the point.
`metta_py_encode/2` writes a process-local machine identity, so a variable
comes out as something like `["v", "_18756"]`; `metta_py_encode_named/3` and
`metta_py_parse/2`, which is what `metta.parse()` calls, write the source
name, so the same variable comes out as `["v", "x"]`. Sending a display name
where an identity is wanted was measured breaking round-trip identity and
aliasing two distinct answer variables that happened to share a spelling, so
a binding that keeps names must keep them as identities.

One payload is reserved. `["v", "_"]` means "a fresh variable here", exactly
as `$_` does in source, so two of them constrain nothing and never share. It
is the one place the wire is not an identity, and no encoder writes it:
reading `$_` mints an identity instead. A codec that decodes into its host's
own variables resolves `_` and gives two distinct variables back; a codec
that carries wire terms to a store keeps the payload. Both are conformant
and the corpus says which by asking the driver.

## Number and BigInt are exact, or refused

MeTTa has two numeric types. A float and an integer in the inclusive signed
i64 range have type `Number`. An integer below -9223372036854775808 or above
9223372036854775807 has type `BigInt`. The reader uses the same signed decimal
syntax for both, and SWI keeps every integer value unbounded underneath, so
arithmetic can cross the boundary in either direction without changing its
value behavior.

Both integer types use `n`. The exact payload determines the language type.
A second tag would duplicate that information and add a mismatched
tag-and-width refusal class. A codec MUST NOT admit an integer it cannot hold
exactly. If your transport's numbers are
binary64, `["n", 9007199254740993]` has to be refused, naming the literal,
because a store that rounds an atom answers a different atom later. The
TypeScript reference server does this from `JSON.parse`'s reviver, which can
see the source text of each literal and so can tell an integer it would round
from one it would not. The Python end holds the value exactly and accepts it.
Both conform because the rule is about exactness rather than range.

An integer and a float are different atoms even when they have the same
mathematical value. `!(== 1.0 1)` answers `False`, so `["n", 1]` and
`["n", 1.0]` are different terms. A transport with one host number kind has
to carry the distinction some other way or refuse the value. JavaScript is
the case that bites: `JSON.stringify(1.0)` writes `1`, so an integral float
stored through a JSON parser with a single Number kind comes back as an
integer. That is the same failure as rounding a wide integer, with a
different cause.

The Python binding carries Prolog integers as Python `int` through Janus.
Measured 2026-08-20 with Python 3.14.4, janus-swi 1.5.3 and SWI 10.1.13, the
signed-i64 boundaries and `2^127 + 12345` crossed exactly in both directions.
The Node binding uses JavaScript `BigInt` for every Prolog integer and
JavaScript `number` for every Prolog float. Its private bridge carries their
canonical decimal text before constructing either host value. Measured
2026-08-20 with Node 22.22.1 and swipl-wasm 8.0.6, the same values crossed
exactly in both directions. Raw swipl-wasm returns a JavaScript `Number`
through `2^53 - 1` and a `BigInt` from `2^53` onward, so the binding does not
use that changing host representation as the wire contract.

Floats are the value, not a spelling. The two shipped printers disagree
about where exponent form begins, so the same float prints `1.0e+10` from
the engine and `10000000000.0` from the Python side; the wire carries
neither, it carries the number.

A non-finite float is carried by an encoding that has a spelling for one and
refused by an encoding that does not. The janus form carries infinity and
NaN; JSON has no literal for either, so both ends of the JSON wire refuse
them rather than inventing one.

A rational has no tag. The engine has rationals, the wire does not, and
`["n", "1/3"]` is a malformed term rather than a rational in disguise.

## Host values and native handles

`["o", ...]` carries a live host value by reference. The value never
crosses; handing the reference back reaches the very same object, so
identity, mutation and accessor calls all see one thing. Only an in-process
encoding can carry it, which is why it is outside the core profile.

`["h", ...]` carries a native engine value, a C blob, the same way. Both
sides preserve `["h", id, text]`: the registry id returns the value to the
engine, and the text lets a host decode and print its opaque reference. The
engine ignores the text when resolving the id. A stale id is an existence
error naming it, never a fresh or empty value, because release is explicit
on the host side and silence would turn a released handle into a wrong answer.

## The text seam

Text and wire are related through the engine's reader and writer, and the
relation is not a bijection. Three things are worth knowing before a binding
assumes it is.

The wire is strictly more expressive than the text form. `["s", "a b"]` is
an ordinary symbol and it has no text spelling: printed, it reads back as
two forms rather than one. The same holds for a name that reads as a number,
a variable, a string or a boolean, so `42`, `$x`, `True`, `a"b` and `a;b`
are all encodable symbols with no round trip through text.
`metta_symbol_writable/1` is the engine's own answer to that question and
`metta_unwritable_symbol/2` answers it for a whole term, including for the
numbers with no readable spelling.

Booleans have two spellings and both are correct. Source says `True` and
`False`, the wire payload says `"true"` and `"false"`. The reader also
accepts lowercase source, so `true` reads as the boolean and writes back as
`True`; the term round-trips and the text does not.

The engine's writer prints a non-finite float as `inf`, `-inf` or `NaN`, the
forms Hyperon's Rust `f64` Display prints, and a rational as `1r3`. Each of
those reads back as a SYMBOL of that spelling rather than as the number, so
the value prints faithfully and still does not round-trip, which is why the
text seam refuses the whole class rather than storing something that comes
back different.

`sread_with_names/3` is the reader a binding wants: it reads one form and
answers the variable names it bound, which is what makes
`["v", "x"]` rather than `["v", "_18756"]` possible on the way in.

## Frames

A frame is not an atom. It carries an atom or a stream event, it appears
where an answer is expected, and a position asking for an atom refuses one.

    ["u", term, why]                     an undefined-truth answer
    ["u", term, why, residual]           with the residual program
    ["a", theta, residue, k]             an answer with its bindings
    ["a", theta, residue, k, value]      with an explicit value
    ["x", "end"]                         the stream is exhausted
    ["x", "declined"]                    no answer at all, which is failure
    ["x", "error", term]                 a failure kept as a value

    theta   ::= [[name, term], ...]      may be []
    residue ::= term | true              true means nothing was left over
    k       ::= term | null              null means the degenerate annotation

`k` is the answer's ALGEBRA CARRIER: what it weighs under the declared
semiring, which is `3` under `counting`, a probability under `prob`, a cost
under `tropical`, and a whole provenance expression under `prov`. The
carrier may therefore be a plain ground value or a structured one, and that
distinction is the ALGEBRA's rather than the wire's: both cross as an
ordinary `term`, so `["n", "3"]` is a counting carrier and
`["e", [["s", "plus"], ...]]` a provenance one. This line used to read
`scalar | term | null`, naming a third alternative that a binding author
would look for and not find: `scalar` was never defined here, and on the
wire it is not a separate shape.

`theta` binds the query's variables by name, and the names are the ones the
encoder wrote for those variables, so binding by name is binding the
caller's own variable. This is Hyperon's `execute_bindings` and LeaTTa's
`ReduceResult.okBind`: an answer atom together with the bindings it is
returned under. A `value` is the candidate-with-bindings reading and must
unify with the pattern under theta; an answer whose value contradicts its
theta drops, exactly as a non-unifying plain candidate does.

`residue` is the part of the goal the provider did not discharge. It decodes
against theta's own name table, so its variables ARE the query's, and the
engine evaluates it: each result that is not `false` contributes one
closure, and `false` drops the answer. An answer carrying a residue while
the caller's bound was pushed to the provider is refused loudly, because the
provider truncated at k and a residue can still drop answers after that.

An item in an answer stream may be a plain term or an `a` frame, and a
consumer accepts both interchangeably.

The frames are directional, which is why the corpus asks each codec only
about the ones its side reads. The engine writes `u` and the host reads it;
the host writes `a` and the engine reads it. Nothing shipped decomposes an
`x` frame into parts, so the corpus holds only the rule that one is not an
atom.

<!-- generated: profiles -->
| profile | tags | frames | what speaks it |
|---|---|---|---|
| core | `s` `v` `n` `g` `e` | none | The minimum vocabulary every storage provider must speak. |
| full | `s` `v` `n` `g` `e` `b` `p` `o` `h` | `u` `a` `x` | The extended host binding: core plus booleans, portable space references, host references, native handles, and the three frames. |
<!-- end generated -->

Every codec carries the core five. An encoding that cannot is not a codec
for this grammar, and the kit refuses to certify one that declares less.

## The conformance kit

`tests/codec/corpus.json` is the golden corpus, language-neutral JSON. It
ships inside the wheel beside the engine tree, so a third party certifying
their own codec installs the package rather than cloning the repository.

An implementation supplies up to four operations, each of which refuses by
raising whatever its host raises:

    roundtrip(wire)  decode into this host's own atom, then encode it back
    transport(wire)  serialise to the concrete encoding and parse it back
    read(text)       the engine's reader plus this codec's encoder
    render(wire)     decode, then print with the printer this binding ships

The first two are every codec's. The other two are a whole binding's: a
storage provider validates and carries wire terms and neither reads MeTTa
source nor prints an atom, so it declares no reader and no printer and runs
the two wire legs. The TypeScript reference server is exactly that shape.

An implementation also declares what it carries: its tag set, its frame set,
which printer column applies to it, whether its transport holds integers
exactly, whether it carries non-finite numbers, whether decoding resolves
the anonymous variable, and whether it can run MeTTa programs. Those
declarations are how a case lands in or out of scope, and `codec_plan`
reports both the legs it runs and the cases that fell out, rather than
dropping either quietly.

From Python:

```python
from metta.testing import check_codec, codec_plan

def test_my_codec_conforms():
    assert check_codec(MyCodec()) == []
```

From another language, read the corpus and drive the same four operations
against it. Two escapes exist because JSON cannot write what the wire can:
`{"$float": "inf"}` is that float and `{"$host": "opaque"}` is a value only
the host can mint, which the driver supplies for itself.

The corpus is hand-written from this page rather than generated from any
implementation, so passing it is evidence about a codec rather than a
restatement of one.

### Terms

<!-- generated: cases -->
| case | text | wire | written |
|---|---|---|---|
| `symbol` | `"foo"` | `["s", "foo"]` | `"foo"` |
| `symbol-non-ascii` | `"λ"` | `["s", "λ"]` | `"λ"` |
| `symbol-hyphenated` | `"car-atom"` | `["s", "car-atom"]` | `"car-atom"` |
| `space-handle` | `"&self"` | `["p", "&self"]` | `"&self"` |
| `symbol-ampersand` | `"&not-a-space"` | `["s", "&not-a-space"]` | `"&not-a-space"` |
| `space-in-expression` | `"(add-atom &self (f 1))"` | `["e", [["s", "add-atom"], ["p", "&self"], ["e", [["s", "f"], ["n", 1]]]]]` | `"(add-atom &self (f 1))"` |
| `string` | `"\"hi\""` | `["g", "hi"]` | `"\"hi\""` |
| `string-empty` | `"\"\""` | `["g", ""]` | `"\"\""` |
| `string-escapes` | `"\"a\\\"b\\\\c\\nd\\te\\rf\""` | `["g", "a\"b\\c\nd\te\rf"]` | `"\"a\\\"b\\\\c\\nd\\te\\rf\""` |
| `integer` | `"42"` | `["n", 42]` | `"42"` |
| `integer-negative` | `"-7"` | `["n", -7]` | `"-7"` |
| `integer-zero` | `"0"` | `["n", 0]` | `"0"` |
| `integer-i64-min` | `"-9223372036854775808"` | `["n", -9223372036854775808]` | `"-9223372036854775808"` |
| `integer-i64-max` | `"9223372036854775807"` | `["n", 9223372036854775807]` | `"9223372036854775807"` |
| `bigint-negative-boundary` | `"-9223372036854775809"` | `["n", -9223372036854775809]` | `"-9223372036854775809"` |
| `bigint-positive-boundary` | `"9223372036854775808"` | `["n", 9223372036854775808]` | `"9223372036854775808"` |
| `integer-beyond-double` | `"9007199254740993"` | `["n", 9007199254740993]` | `"9007199254740993"` |
| `integer-beyond-machine-word` | `"123456789012345678901234567890"` | `["n", 123456789012345678901234567890]` | `"123456789012345678901234567890"` |
| `float` | `"1.5"` | `["n", 1.5]` | `"1.5"` |
| `float-negative` | `"-0.25"` | `["n", -0.25]` | `"-0.25"` |
| `float-integral` | `"1.0"` | `["n", 1.0]` | `"1.0"` |
| `float-large-exponent` | `"1.0e10"` | `["n", 10000000000.0]` | `"10000000000.0"` |
| `float-small-exponent` | `"1.0e-300"` | `["n", 1e-300]` | `"1e-300"` |
| `float-infinity` |  | `["n", {"$float": "inf"}]` | `"inf"` |
| `float-negative-infinity` |  | `["n", {"$float": "-inf"}]` | `"-inf"` |
| `float-nan` |  | `["n", {"$float": "nan"}]` | `"NaN"` |
| `boolean-true` | `"True"` | `["b", "true"]` | `"true"` |
| `boolean-false` | `"False"` | `["b", "false"]` | `"false"` |
| `boolean-lowercase-source` | `"true"` | `["b", "true"]` | `"true"` |
| `variable` | `"$x"` | `["v", "x"]` | engine `"$_0"` / python `"$x"` |
| `expression-empty` | `"()"` | `["e", []]` | `"()"` |
| `expression` | `"(likes Ada Coffee)"` | `["e", [["s", "likes"], ["s", "Ada"], ["s", "Coffee"]]]` | `"(likes Ada Coffee)"` |
| `expression-nested` | `"(a (b (c d)))"` | `["e", [["s", "a"], ["e", [["s", "b"], ["e", [["s", "c"], ["s", "d"]]]]]]]` | `"(a (b (c d)))"` |
| `expression-every-tag` | `"(() \"s\" 1 True $v)"` | `["e", [["e", []], ["g", "s"], ["n", 1], ["b", "true"], ["v", "v"]]]` | engine `"(() \"s\" 1 true $_0)"` / python `"(() \"s\" 1 True $v)"` |
| `expression-repeated-variable` | `"(f $x $x)"` | `["e", [["s", "f"], ["v", "x"], ["v", "x"]]]` | engine `"(f $_0 $_0)"` / python `"(f $x $x)"` |
| `expression-distinct-variables` | `"(f $x $y)"` | `["e", [["s", "f"], ["v", "x"], ["v", "y"]]]` | engine `"(f $_0 $_1)"` / python `"(f $x $y)"` |
| `equation` | `"(= (double $x) (* $x 2))"` | `["e", [["s", "="], ["e", [["s", "double"], ["v", "x"]]], ["e", [["s", "*"], ["v", "x"], ["n", 2]]]]]` | engine `"(= (double $_0) (* $_0 2))"` / python `"(= (double $x) (* $x 2))"` |
| `variable-anonymous` |  | `["e", [["s", "f"], ["v", "_"], ["v", "_"]]]` | engine `"(f $_0 $_1)"` / python `"(f $_ $_)"` |
| `symbol-with-no-text-form` |  | `["s", "a b"]` | `"a b"` |
| `host-reference` |  | `["o", {"$host": "opaque"}]` |  |
| `expression-deep` |  | built, see the corpus |  |
<!-- end generated -->

### Refusals

<!-- generated: refusals -->
| case | operation | wire | why it is refused |
|---|---|---|---|
| `refuse-unknown-tag` | `roundtrip` | `["z", "x"]` | z names no tag, and the tag set is closed |
| `refuse-not-a-term` | `roundtrip` | `"foo"` | a wire term is a tagged array and never a bare value |
| `refuse-empty-term` | `roundtrip` | `[]` | a wire term carries a tag |
| `refuse-payload-missing` | `roundtrip` | `["s"]` | every term tag takes exactly one payload |
| `refuse-payload-extra` | `roundtrip` | `["s", "a", "b"]` | every term tag takes exactly one payload; the three-element form belongs to h alone |
| `refuse-symbol-payload-number` | `roundtrip` | `["s", 1]` | a tag is a claim about its payload: s carries text |
| `refuse-symbol-payload-array` | `roundtrip` | `["s", ["a"]]` | s carries text, and an array is not text however it prints |
| `refuse-string-payload-number` | `roundtrip` | `["g", 1]` | g carries text; a number belongs under n |
| `refuse-string-payload-object` | `roundtrip` | `["g", {"a": 1}]` | g carries text, not an arbitrary structure. A codec that admits one stores a value no other codec can read back. |
| `refuse-number-payload-text` | `roundtrip` | `["n", "1/3"]` | n carries a number. The engine has rationals and the wire has no spelling for one, so a rational is refused here rather than carried as its text. |
| `refuse-number-payload-boolean` | `roundtrip` | `["n", true]` | n carries a number; a boolean belongs under b |
| `refuse-variable-payload-number` | `roundtrip` | `["v", 1]` | v carries the identity as text |
| `refuse-boolean-payload-other` | `roundtrip` | `["b", "maybe"]` | b carries exactly true or false. Reading anything else as false answers a question nobody asked. |
| `refuse-boolean-payload-number` | `roundtrip` | `["b", 1]` | b carries exactly true or false; truthiness is not the rule here |
| `refuse-expression-payload-text` | `roundtrip` | `["e", "x"]` | e carries an array of wire terms |
| `refuse-expression-payload-number` | `roundtrip` | `["e", 1]` | e carries an array of wire terms |
| `refuse-expression-child-malformed` | `roundtrip` | `["e", [["z", "x"]]]` | a malformed child makes the whole term malformed; nothing decodes partially |
| `refuse-frame-in-atom-position` | `roundtrip` | `["a", [], true, null]` | an answer frame is not an atom, and the position asked for an atom |
| `refuse-stream-control-in-atom-position` | `roundtrip` | `["x", "end"]` | a stream-control frame is not an atom |
| `refuse-integer-beyond-exact-range` | `transport`, unless `exact_integers` | `["n", 9007199254740993]` | a transport whose numbers are binary64 rounds this, and a store that rounds an atom answers a different atom. Refuse the payload; never round it. |
| `refuse-non-finite-number` | `transport`, unless `non_finite` | `["n", {"$float": "inf"}]` | JSON has no literal for a non-finite number. An in-process encoding carries one; a JSON one refuses it rather than inventing a spelling. |
<!-- end generated -->

### Frames

<!-- generated: frames -->
| case | frame | wire | parts |
|---|---|---|---|
| `answer-bindings` | `a` | `["a", [["x", ["s", "a"]]], true, null]` | theta `[["x", ["s", "a"]]]`, residue `null`, k `null`, value `null` |
| `answer-empty-theta` | `a` | `["a", [], true, null]` | theta `[]`, residue `null`, k `null`, value `null` |
| `answer-with-value` | `a` | `["a", [["x", ["s", "a"]]], true, null, ["e", [["s", "edge"], ["s", "a"]]]]` | theta `[["x", ["s", "a"]]]`, residue `null`, k `null`, value `["e", [["s", "edge"], ["s", "a"]]]` |
| `answer-with-residue` | `a` | `["a", [["x", ["n", 4]]], ["e", [["s", ">"], ["v", "x"], ["n", 3]]], null]` | theta `[["x", ["n", 4]]]`, residue `["e", [["s", ">"], ["v", "x"], ["n", 3]]]`, k `null`, value `null` |
| `undefined-truth` | `u` | `["u", ["s", "p"], "tnot loop"]` | value `["s", "p"]`, why `"tnot loop"` |
<!-- end generated -->

### Answer transcripts

A transcript is a whole MeTTa program and the wire it answers: one group per
`!` directive, in source order, holding that directive's answers in order.
An empty group is a directive that answered nothing, which is not the same
as a directive that answered `()`.

<!-- generated: transcripts -->
| case | program | answer groups |
|---|---|---|
| `arithmetic` | `"!(+ 1 2)"` | `[[["n", 3]]]` |
| `bigint-arithmetic` | `"!(+ 9223372036854775807 1)"` | `[[["n", 9223372036854775808]]]` |
| `comparison` | `"!(== 1 2)"` | `[[["b", "false"]]]` |
| `nondeterminism` | `"!(superpose (1 2 3))"` | `[[["n", 1], ["n", 2], ["n", 3]]]` |
| `no-answers` | `"!(match &self (nothing-is-stored-here $x) $x)"` | `[[]]` |
| `string-in-expression` | `"!(\"hi\")"` | `[[["e", [["g", "hi"]]]]]` |
| `user-equation` | `"(= (codec-kit-double $x) (* $x 2))\n!(codec-kit-double 21)"` | `[[["n", 42]]]` |
| `two-directives` | `"!(+ 1 1)\n!(car-atom (a b))"` | `[[["n", 2]], [["s", "a"]]]` |
<!-- end generated -->

## Where the shipped encodings differ, and why

The janus form carries `b`, `o` and `h`, non-finite numbers and every frame,
because both ends are in one process and the transport is SWI's own term
conversion. The JSON wire carries the core five and nothing else: JSON has
no way to hold a host reference or a native handle at all, and the reference
TypeScript server refuses the `b` tag, so a term carrying a boolean is not
portable over that wire today. That is a real limit rather than a rounding
of one, and it is written down here so a binding does not discover it by
storing an atom that never comes back.

Running the corpus against the TypeScript reference server, which shares no
code with this package, turned up three divergences on first contact and all
three are pinned in
`extensions/python/tests/ch21_another_language_at_the_seam/test_codec_typescript.py`.
Two share one cause: `isWireAtom` validates the `g` tag with `case "g": return
true`, so `["g", 1]` and `["g", {"a": 1}]` are both stored there and both
refused by the metta-side codecs. The third is the number model:
`JSON.stringify(1.0)` writes `1`, so `["n", 1.0]` comes back as `["n", 1]`, and
`1.0` and `1` are different atoms. The first two are a check that server does
not make; the third is a limit any implementation over a single-Number-type
JSON parser has to answer for. That server is a reference implementation under
`extensions/python/examples/` rather than one of the two shipped codecs, so the
divergences are recorded rather than patched here.

The two shipped printers disagree about float exponent form and about NaN,
which the tables above pin, and about variables: the engine's printer
numbers them by first occurrence because an engine variable carries no name,
while a binding holding its own atoms prints the name it read. Neither is
wrong and a binding should expect its own.

## What the codec costs

A codec's cost is the term's SIZE, not a constant per crossing, and that is the
one performance fact a binding author has to design around. Encoding walks
every node; carrying a reference does not walk anything.

Measured on the in-process Python seat, one list returned per crossing, built
once so what is priced is the crossing rather than the construction
[measured 2026-08-29, `cd extensions/python && python -m benchmarks.axes`]:

| elements | encoded, instructions | encoded, inferences | by reference, instructions | by reference, inferences |
|---|---|---|---|---|
| 1 | 73,514 | 21.32 | 24,613 | 12.31 |
| 10 | 161,979 | 57.32 | 24,543 | 12.31 |
| 100 | 1,042,933 | 417.31 | 24,475 | 12.31 |
| 1,000 | 10,270,349 | 4,017.31 | 24,521 | 12.31 |

The encoded column is exactly four inferences per element plus a fixed 17.3.
The reference column is flat. At a thousand elements that is 419 times the
instructions, so the choice between them is a complexity class rather than a
constant factor.

That is what the `o` and `h` tags are for, and it is also their limit. Both
carry a value the receiving end never reads, so **only an in-process encoding
can use them**: they are outside the core profile precisely because a wire
cannot hold a live reference. A codec speaking the core five over a socket
always pays the walk, and a binding that wants the flat column has to be in the
same process as the engine.

The Node seat pins the wire legs themselves, and those figures are the whole
round trip rather than one direction [PINNED 2026-08-28,
`extensions/node/benchmarks/baseline.json`]. Fifty thousand atoms out through
`wireFromAtom` and `toTransport` and back through `fromTransport` and
`atomFromWire` cost 3,237,788,053 retired instructions, about 64,756 per atom
round trip. Twenty thousand interned expressions cost 3,418,787,433, about
170,939 per iteration; each iteration mints the expression TWICE so the run
exercises the table's miss path and its hit path, so the per-construction
figure is about half that. That seat runs SWI compiled to WebAssembly, so read
both as that runtime's numbers rather than as native ones.

**Inferences cannot decide a codec change, and this is where that bites
hardest.** Foreign code retires no inferences at all, so a codec moved from
Prolog into C looks free on the counter every other part of this engine is
measured by. A C wire encoder in this tree measured 526x faster on inferences
while CPU time said it was 1.8x SLOWER. The two wire rows above therefore pin
instructions and leave inferences null, because the engine is never asked; the
`host-op` row, whose cost is genuinely split across the boundary, pins both and
lets them decide different halves, at 40.61 inferences and about 449,008
instructions per yield over 2,000 yields. If you are changing a codec, measure
retired instructions or CPU seconds and pair them, as DEVELOPING.md requires.

Two cheaper things are worth knowing before optimising the walk. A refusal
costs nothing, so validating a payload's class is not a reason to skip
validation. And the corpus is the cheap way to find a divergence: running it
against the TypeScript reference server turned up three on first contact, which
is less work than discovering them from a stored atom that never came back.

## Related pages

`website/live/remote-protocol.md` is the HTTP protocol the JSON wire rides
on, the five operations and their refusal ladder.
`extensions/python/examples/integration/typescript_space/README.md` is the reference
server. `EXTENDING.md` section 6 is the in-process space seam, which carries
atoms without a wire at all, and its opening cost tables price the three axes a
crossing chooses between.
