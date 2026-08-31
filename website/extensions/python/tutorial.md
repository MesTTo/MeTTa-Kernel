<!--
Purpose: teach the PyMeTTa seat itself, which is a different job from the eight
  numbered tutorials: they teach the language and use Python as the notation,
  and this teaches the install, the first program, and the split install that is
  true of this seat and no other.
Assumes: the reader knows Python and nothing about MeTTa, and is on a machine
  with no SWI-Prolog yet.
Guarantees:
  - every fence was run against this checkout on 2026-08-29, and the outputs
    written beside them are what it printed
    [source: extensions/python/examples/basics/first_steps.py; commit=57f21ba9edf94bcf28cde11f938bce2c241a3709]
  - the two refusal messages are the engine's own words, not a paraphrase
    [source: extensions/python/metta/_engine.py:_no_engine; commit=57f21ba9edf94bcf28cde11f938bce2c241a3709]
  - the page is in the navigation and its links resolve
    [tested: test_every_site_page_is_reachable_from_the_navigation,
    npm run docs:build; commit=57f21ba9edf94bcf28cde11f938bce2c241a3709]
-->

# The PyMeTTa tutorial

Here is a whole program. It installs a rewrite and runs it, stores three facts,
and joins two patterns across them.

```python
from metta import MeTTa, S, V

m = MeTTa().space()

m.run("(= (double $x) (* $x 2))\n!(double 21)")
# [[Grounded(42)]]

m.add(S.Parent(S.Tom, S.Bob), S.Parent(S.Bob, S.Ann), S.Parent(S.Ann, S.Zoe))
m.match(S.Parent(V.gp, V.p), S.Parent(V.p, V.gc))
# [Row(gp=Tom, p=Bob, gc=Ann), Row(gp=Bob, p=Ann, gc=Zoe)]
```

Two commands get you there, and the order matters.

## SWI-Prolog first, then the package

MeTTa runs on SWI-Prolog. SWI-Prolog is a program rather than a Python package,
so pip cannot install it for you:

```sh
sudo apt install swi-prolog             # Linux, or your distribution's equivalent
brew install swi-prolog                 # macOS
winget install SWI-Prolog.SWI-Prolog    # Windows
```

Then the library, with the `engine` extra:

```sh
pip install 'pymetta[engine]'
```

The distribution is `pymetta` and the import name is `metta`. From a checkout,
`pip install '.[engine]'` does the same thing, and `METTA_PATH` pointed at a
clone uses that tree in place.

## Why the install splits in two

`pip install pymetta` on its own always succeeds, even on a machine with no
SWI-Prolog anywhere. That is deliberate, and it is the thing about this seat
that is not true of any other.

The `engine` extra is `janus_swi`, SWI-Prolog's own Python bridge. It is a C
extension that compiles against whichever SWI-Prolog is on the machine. If it
were an ordinary dependency, a plain `pip install pymetta` on a machine without
SWI would die inside somebody else's build step, and the error a user saw would
be the linker's: `ImportError: libswipl.so.9: cannot open shared object file`.
That names neither SWI-Prolog nor anything to do about it.

So the bridge is an extra, the install cannot fail that way, and the first call
that needs an engine is what tells you. With nothing in place:

```text
MeTTa runs on SWI-Prolog, which is a program rather than a Python package, so
pip cannot install it and there is no `swipl` on your PATH. Two steps, in this
order:

    sudo apt install swi-prolog   (or your distribution's equivalent)
    pip install 'pymetta[engine]'
```

With SWI-Prolog installed and only the bridge missing, which is where a plain
`pip install pymetta` leaves you:

```text
SWI-Prolog is installed at /usr/bin/swipl, and the Python bridge to it is not.
It is an extra, so that installing this package cannot fail inside its build:

    pip install 'pymetta[engine]'
```

Both messages name the exact command, and which one you get is read off the
machine rather than guessed: the difference is whether `swipl` is on your PATH.
A third message covers the case where the bridge is installed and was built
against a different SWI-Prolog than the one you now have, which is what
upgrading SWI after installing looks like, because pip reuses the wheel it
cached for you.

The wheel is pure Python, so there is nothing to compile and no platform build
to go wrong. The `platforms` job in `.github/workflows/checks.yml` installs it
on macOS and Windows against Python 3.12 and 3.14, and it installs it *before*
SWI-Prolog exists on the runner, because that is the state a new reader is in.
It then asserts the refusal above, installs SWI-Prolog, and boots the engine.

## The shortest spelling needs no instance

The module functions run over one lazily created default engine, which is the
shape `random` and `logging` already have:

```python
import metta

metta.add("(parent Tom Bob)")
metta.match("(parent Tom $x)")       # [Row(x=Bob)]
metta.run("!(+ 40 2)")               # [[Grounded(42)]]
```

`metta.engine()` hands the context over the moment you want control, and
`metta.space()` gives you a handle of your own. Every module function is one
line over the default context's handle, so nothing is lost by starting here.

## Terms are Python values, not strings

`S` mints symbols, `V` mints variables, and applying a symbol builds an
expression. None of it contacts the engine:

```python
from metta import S, V

S.Parent(S.Tom, S.Bob)      # (Parent Tom Bob)
V.x                         # $x
S.Parent(V.gp, V.p)         # (Parent $gp $p)
```

A string is for text, and for whole programs handed to `run`. A built term is
already knowledge; a string has to be parsed before it is.

## A space stores atoms and answers patterns

```python
from metta import S, V, space

m = space()
m.add(S.Parent(S.Tom, S.Bob), S.Parent(S.Bob, S.Ann))
m.match(S.Parent(V.x, V.y), S.Parent(V.y, V.z))
# [Row(x=Tom, y=Bob, z=Ann)]
```

Two patterns in one `match` is a join: `$y` is one variable across both, so a
row exists only where the same value satisfies each. A row is keyed by the
names you wrote, so `rows[0].y` reads the middle binding back by name rather
than by a child index.

## Two doors for a Python function

A Python function can become MeTTa two ways, and the choice is real rather than
a convenience and its longhand.

`@m.define` LOWERS the body: the function is read and installed as equations, so
the engine owns it and a call crosses into Python not at all.

```python
@m.define
def triple(x: int) -> int:
    return x * 3

m.eval(S.triple(7))                              # [Grounded(21)]
len(m.match(S["="](S.triple(V.x), V.body)))      # 1
```

The second line is the point. The definition became an ordinary `(= (triple $x)
(* $x 3))` atom in the space, so a pattern finds it and the engine can
type-check and specialise it. Nothing is opaque and nothing crosses back into
Python when the function is called.

`m.op` publishes a function the engine CALLS, for a body that has to stay
Python because it touches the network, holds a file, or wraps a library you are
not going to re-express:

```python
def shout(text: str) -> str:
    return text.upper()

m.op(shout, effect="pureStructural")
m.run('!(shout "hello")')                    # [[Grounded('HELLO')]]
```

The `effect=` is required, not advisory. The engine cannot see inside a called
function, so it has to be told what the function does before it can cache,
reorder, or roll back around it. Leaving it out refuses by name:

```text
TypeError: operation 'shout' requires effect= metadata; choose one of:
EffectClass.pureStructural, EffectClass.readOnlyLookup,
EffectClass.nondeterministicReadOnly, EffectClass.writesState,
EffectClass.oracleIO
```

Reach for `@m.define` when the body is expressible as MeTTa and `m.op` when it
is not. [Python functions in MeTTa](../../guide/python-functions.md) covers
both doors, the five effect classes, and crossing into Python from inside a
lowered body.

## The install is a command-line tool too

```sh
python -m metta run program.metta        # run a file, print each ! answer group
python -m metta repl                     # interactive, multi-line forms
python -m metta lint program.metta       # diagnostics; nonzero exit on findings
python -m metta doc car-atom             # a name's (@doc ...) documentation
```

Each subcommand exits nonzero on failure, so all of them script.

## Where to go next

The [eight numbered tutorials](../../tutorials/) teach MeTTa itself from here,
one idea at a time, starting with atoms and ending with a drawn reduction. The
[guide](../../guide/) is the same surface arranged by task. The
[PyMeTTa seat page](./) says what the seat is made of: the control file, the two
`entry/2` roles, and the one library it needs.
