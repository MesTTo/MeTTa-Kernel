# Multi-shot solving

clingo's changing-program vocabulary maps onto the existing space and query surface, and the mapping is small enough to be an example rather than a package module: `python/examples/16_multishot_solving.py` builds it in two short classes on the core calls alone. A `Part` is a parameterized program template grounded once per argument tuple, clingo's `#program`. An `External` is a fact whose truth toggles between solves and ends with `release()`, clingo's `#external`, which on an engine with no grounding step is exactly a togglable fact.

The world remains in the space between shots. Solving uses `query`, `prepare`, `assuming`, or `eval`. Grounding a part instantiates its template into the space, and grounding the same instantiation twice is refused, since it would duplicate the rules. Assigning a released external is a hard error.

The example's whole translation:

```python
class External:
    """A truth toggled between solves: present while True, gone while
    False, finished by release(). The handle owns its atom."""

    def __init__(self, m, atom) -> None:
        self._m, self._atom = m, atom
        self.value = False
        self.released = False

    def assign(self, value: bool) -> None:
        if self.released:
            raise RuntimeError(f"{self._atom} was released")
        if value and not self.value:
            self._m.add(self._atom)
        elif not value and self.value:
            self._m.remove(self._atom)
        self.value = bool(value)

    def release(self) -> None:
        if not self.released:
            self.assign(False)
            self.released = True


class Part:
    """A named program template, grounded once per instantiation: the
    template answers MeTTa source for its parameters, and grounding the
    same instantiation twice would duplicate its rules, so it refuses."""

    def __init__(self, m, name: str, template) -> None:
        self._m, self.name, self._template = m, name, template
        self.grounded: set[tuple] = set()

    def ground(self, *args) -> None:
        if args in self.grounded:
            raise RuntimeError(f"part {self.name!r} already grounded for {args!r}")
        self._m.run(self._template(*args))
        self.grounded.add(args)
```

The incremental loop grows reachability one step at a time until the goal proves, then toggles an external fact:

```python
m = MeTTa().fresh_space()

# The base part: a graph as tabular facts, and step zero of reachability.
m.add_table("edge", [(S.a, S.b), (S.b, S.c), (S.c, S.d)])
m.run("(= (reach a 0) True)")

# The step part, clingo's #program step(t): reach $x at t if some edge
# reaches it from a node already reached at t-1.
step = Part(
    m,
    "step",
    lambda t: f"(= (reach $x {t}) (match (context-space) (edge $y $x) "
              f"(once (reach $y {t - 1}))))",
)


def proved(goal: str, t: int) -> bool:
    return any(a == True for a in m.eval(m.parse(f"(reach {goal} {t})")))  # noqa: E712


# The multi-shot loop: solve, and if the goal is not yet proved, ground
# one more step and solve again. The world persists between shots.
horizon = 0
while not proved("d", horizon):
    horizon += 1
    step.ground(horizon)
check("the goal proves at the shortest horizon", horizon, 3)
check("grounded instantiations are tracked", step.grounded, {(1,), (2,), (3,)})

# Externals: truths toggled between solves. A blocked node cuts routes in
# the NEXT shot without regrounding anything.
blocked = External(m, S.blocked(S.c))
blocked.assign(True)
check(
    "the external is a fact while assigned",
    [str(r.x) for r in m.query(S.blocked(V.x))],
    ["c"],
)
blocked.assign(False)
check("and gone when withdrawn", m.query(S.blocked(V.x)), [])
blocked.release()
```

The paper behind the vocabulary is Gebser, Kaminski, Kaufmann and Schaub, "Multi-shot ASP solving with clingo" (arXiv 1705.09811). The example is the reference: everything it claims runs in the test suite.
