<!--
Purpose: distinguish Python term construction, live engine evaluation, and execution of compiled Python bodies.
Guarantees: each public spelling is assigned to the location and time where its code runs.
[tested: npm run docs:build and test_guides_keep_documentation_law_explainers;
commit=5fe3175632a6b60b3b54ca9125b75607ac82401a]
-->

# Where code runs

Assume `fact` is the function from [Write MeTTa in Python](./define.md).
`term = S.fact(6)` builds `(fact 6)` in Python. `m.eval(term)` evaluates that
term in the engine. `fact(6)` also evaluates through the space that owns the
definition. `fact.py(6)` calls the retained Python function and returns the
ordinary Python result.

| spelling | where it runs | when it runs |
|---|---|---|
| `S.fact(6)` | Python atom constructors | immediately, without an engine call |
| `m.eval(S.fact(6))` | the engine attached to `m` | when `eval` is called |
| `m.run("!(fact 6)")` | the reader, compiler, and engine attached to `m` | when `run` is called |
| `fact(6)` | the space that owns the decorated definition | when the decorated name is called |
| `fact.py(6)` | ordinary Python | when the retained Python twin is called |

## Staged term construction

`S`, `V`, `Expression`, atom operators, and symbol application construct
immutable atom values in the current Python thread. They do not look up a
function or consult a space. A term can therefore be built before an engine
exists, stored, inspected, and handed to a space later.

Staging ends only when you evaluate. `S.fact(6)` does not mean "call
fact". It means "construct an expression whose head is the symbol `fact`".

## Live evaluation

`Space.eval(term)` evaluates a term already built in Python. `Space.run(source)`
first reads source directives and then evaluates each `!` directive. Calling a
name produced by `@m.define` also evaluates: it sends its arguments to
the definition's owning space and returns all answers.

Live evaluation can branch, read or write spaces, and call registered Python
operations. A function registered with `@m.op` runs its Python callable only
when engine evaluation reaches that operation.

## Compiled Python bodies

`@m.define` reads and compiles the function's source when the decorator runs.
It installs MeTTa equations; it does not execute the body as ordinary Python
at decoration time. When a later engine application matches an equation, the
engine evaluates the lowered body. Loops, conditions, assignments, `yield`,
and supported calls therefore use their compiled MeTTa meanings at that time.

The original callable remains at `.py`. Calling `.py` skips the engine and
runs the Python body with Python values. Keep the two paths explicit in tests:
use `fact(6)` to test the compiled program and `fact.py(6)` to compare its
ordinary Python twin.
