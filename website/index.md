<!--
Purpose: state what MeTTa Kernel is, show it working, and route to the four things a reader can want.
Guarantees: the Python block runs as written against the shipped surface.
[tested: npm run docs:build; commit=WORKTREE]
-->

# MeTTa Kernel

MeTTa, implemented in Prolog and C. You write Python; it becomes rules the
engine can run, query, and reason over.

```sh
sudo apt install swi-prolog     # or: brew install swi-prolog
pip install 'pymetta[engine]'
```

## What it looks like

```python
from metta import MeTTa, S, V, match

m = MeTTa().self
m.add(S.parent(S.Tom, S.Bob), S.parent(S.Bob, S.Ann), S.parent(S.Ann, S.Zoe))

@m.define
def ancestor(x):
    yield match(S.parent(x, V.y), V.y)                # a parent, or
    yield ancestor(match(S.parent(x, V.y), V.y))      # an ancestor of one

ancestor(S.Tom)          # [Bob, Ann, Zoe]
```

Three things happened there that ordinary Python does not do.

**The function became rules.** `@m.define` read the source of `ancestor` and
installed two equations. The body never ran as Python. `ancestor.py` still
holds the original callable if you want to run it that way.

**Two `yield`s are two rules, not two items.** The engine tries both and
returns every answer either one produces. Recursion terminates because the
second rule stops finding parents, not because a loop counter ran out.

**A pattern is a question.** `match(S.parent(x, V.y), V.y)` asks the space for
every `y` that `x` is a parent of. Write two patterns and you get a join:

```python
m.match(S.parent(V.a, V.b), S.parent(V.b, V.c))
# [Row(a=Tom, b=Bob, c=Ann), Row(a=Bob, b=Ann, c=Zoe)]
```

The same rules are reachable as MeTTa source, because they are the same rules:

```python
m.run("!(ancestor Tom)")     # [[Bob, Ann, Zoe]]
```

## Where to go

**[Tutorials](./tutorials/01-atoms-and-expressions)** if this is new. Eight of
them, one idea each, starting from what an atom is.

**[Guide](./guide/getting-started)** if you are building something. Installing,
querying, writing rules, spaces, threads, and what to do when a query returns
nothing.

**[Reference](./reference/)** for exact signatures.

**[Engine](./engine/)** to work on MeTTa Kernel itself, or to put a fourth
language on top of it. Python, TypeScript and C are the three surfaces built so
far, each reaching the engine through a documented wire format rather than a
hand-written port.
