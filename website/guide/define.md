# Write MeTTa in Python

`@m.define` compiles a Python function into MeTTa equations. Calling the decorated name evaluates through its owning space, the ordinary Python function remains available as `.py`, and `S.name(...)` builds a term explicitly.

```python
@m.define
def fact(n):
    if n == 0:
        return 1
    return n * fact(n - 1)


check("equations run", m.run("!(fact 6)"), [[720]])
check("the Python twin agrees", fact.py(6), 720)
check("calling the name evaluates", fact(6), [720])
check("the S door builds the term", str(S.fact(6)), "(fact 6)")
```

Repeated definitions stack as MeTTa clauses. Literal defaults become head patterns, and the compiler derives first-match guards:

```python
@m.define
def fib(n=0):
    return 0

@m.define
def fib(n=1):
    return 1

@m.define
def fib(n):
    return fib(n - 1) + fib(n - 2)   # m.run("!(fib 10)") -> [[55]]
```

The subset includes rebinding, `while`, `for`, nested definitions, generators, lambdas, comprehensions, indexing, slicing, formatted strings, and `match(...)` against the running space. Generators compile to nondeterminism. Lowercase names in match patterns bind as variables.

`yield from call(...)` delegates directly only when the compiler knows the
callee is nondeterministic, including self-recursive generators. A call whose
result might instead be iterable data is refused at compile time. Write
`yield call(...)` to delegate its engine answers, or bind returned iterable
data and then `yield from` that value.

## Rules as ordinary atoms

`@rules` gives each generator parameter a rule-local MeTTa variable. Calls to
defined objects stage only while the generator is collected, so the result is
a list of ordinary equation atoms you can inspect, match, and add:

```python
@rules
def arithmetic(value):
    yield equation(S.via_rule(value)).to(twice(value))


m.add(*arithmetic)
```

`equation(lhs).to(rhs)` keeps both halves on one static Python type. It is
sugar for the container door, which remains first-class:
`m.add(S["="](S.twice(V.x), V.x + V.x))`.

A local annotated assignment becomes an in-place MeTTa type claim rather than
being discarded:

```python
@m.define
def checked(value):
    result: int = value
    return result
```

Its body contains `(: $result Number)`. The value binds first and the type
premise then runs, so a known incompatible value produces no answer. Annotation
names resolve only from builtins, the function's globals and its closure;
annotation syntax cannot execute an arbitrary call or user subscript while the
function is compiled.

Unsupported constructs fail with the construct, source line, and a replacement direction. Definitions that only the engine can execute expose a `.py` twin that reports that boundary instead of failing with a Python name error. Function names follow the operation naming policy: the Python name is the MeTTa name, verbatim. Hyphens are the MeTTa convention and Python cannot spell one, so ask for a hyphenated name with `name=` rather than having it inferred.

## Facts already present in the source

Compilation keeps information Python has already parsed instead of asking for
decorator flags. A `Defined` value exposes `source_span`, `free_variables`, and
the derived `pure` value. Its `doc` comes from `ast.get_docstring`, so mutating
the function object's `__doc__` cannot change the source claim.

The same facts are ordinary data in `&petta`:

```metta
(source-span &my-space checked "example.py" 10 0 13 17)
(free-variable &my-space checked helper)
(effect checked immutable)
```

There is one source span per stacked clause and one free-variable fact per
captured name. The immutable effect exists only while every live clause calls
local functions, Python lowerings, constructors, or functions already declared
immutable. A call that reads a space, prints, mutates, or has no purity claim
removes that effect fact. Replacing a clause replaces these facts, and clearing
the definition space removes them.
