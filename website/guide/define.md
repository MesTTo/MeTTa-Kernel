# Write MeTTa in Python

`@m.define` compiles a Python function into MeTTa equations. The ordinary Python function remains available as `.py`, while calling the decorated name builds a term.

```python
@m.define
def fact(n):
    if n == 0:
        return 1
    return n * fact(n - 1)

m.run("!(fact 5)")       # [[120]]
fact.py(5)               # 120: the ordinary Python twin, kept callable
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
