<!--
Purpose: explain the executable route-table example built from Space operations and canonical atoms.
Guarantees: the shown router uses Space.op and canonical atom names.
[tested: npm run docs:build; commit=WORKTREE]
-->

# Web routes

Web routing translates into space operations, and the translation is small enough to be an example rather than a package module: `bindings/python/examples/integration/web_routes.py` builds FastAPI's routing semantics in some eighty lines on the core surface alone. An app is a space. Its route table is facts. A request is a term. Dispatch reads the facts back per request and unifies routes in registration order. Typed path converters run after the structural match, so a parameter refusing its type is a 422 while no matching route is a 404. Handlers are called by name through the engine, which is why a route a MeTTa program adds, naming an equation as its handler, serves through the very same table as the Python decorators.

The example's router, whole:

```python
class Router:
    """Routes on a space. The decorator registers the handler as an
    ordinary operation and adds the fact (route app GET (users $id)
    handler k); dispatch reads the facts back per request, so a route a
    MeTTa program added serves identically. Handler operation names are
    process-wide, the engine's own rule for functions."""

    def __init__(self, m, name: str) -> None:
        self._m = m
        self.name = name
        self._casters: dict[int, tuple] = {}
        self._count = 0

    def get(self, path: str) -> Callable:
        def wrap(fn: Callable) -> Callable:
            handler = fn.__name__.replace("_", "-")
            self._m.op(fn, name=handler)
            self.add_route("GET", path, handler)
            return fn

        return wrap

    def add_route(self, method: str, path: str, handler: str) -> None:
        segments, casters = [], []
        for segment in path.strip("/").split("/"):
            if segment.startswith("{") and segment.endswith("}"):
                name, _, converter = segment[1:-1].partition(":")
                segments.append(Variable(name))
                casters.append(CASTERS[converter or "str"])
            else:
                segments.append(Symbol(segment))
        self._casters[self._count] = tuple(casters)
        self._m.add(
            Expression(S.route, S[self.name], S[method], Expression(segments),
                 S[handler], self._count)
        )
        self._count += 1

    def dispatch(self, method: str, path: str) -> Response:
        request = Expression([Symbol(s) for s in path.strip("/").split("/") if s])
        table = self._m.query(
            Expression(S.route, S[self.name], S[method.upper()],
                 V.pattern, V.handler, V.k)
        )
        matched = False
        for row in sorted(table, key=lambda r: int(wire.decode(r.k))):
            pattern = row.pattern
            if not isinstance(pattern, Expression) or len(pattern) != len(request):
                continue
            bindings = unify(pattern, request)
            if bindings is None:
                continue
            matched = True
            casters = self._casters.get(
                int(wire.decode(row.k)),
                tuple(str for c in pattern.children if isinstance(c, Variable)),
            )
            try:
                values = [
                    caster(str(bindings[name]))
                    for name, caster in zip(pattern.vars, casters, strict=True)
                ]
            except (ValueError, TypeError):
                continue  # the parameter refused; a later route may accept
            answers = self._m.eval(Expression(Symbol(str(row.handler)),
                                        *[wire.encode(v) for v in values]))
            body = answers[0] if answers else None
            return Response(200, wire.decode(body) if isinstance(body, Grounded) else body)
        return Response(422 if matched else 404,
                        "unprocessable" if matched else "not found")
```

And the demonstration it verifies, typed parameters through MeTTa-added routes:

```python
@app.get("/users/{id:int}")
def read_user(id):
    return f"user {id}"


@app.get("/users/{id:int}/karma")
def karma(id):
    return id * 10


check("a typed route", app.dispatch("GET", "/users/7"), Response(200, "user 7"))
check("params arrive converted", app.dispatch("GET", "/users/7/karma").body, 70)
check("no match is 404", app.dispatch("GET", "/nowhere").status, 404)
check("a refused parameter is 422", app.dispatch("GET", "/users/abc").status, 422)

# The table is facts, so MeTTa reads it like any facts...
handlers = m.query(S.route(S.app, S.GET, V.p, V.h, V.k))
check("the table is facts", sorted(str(r.h) for r in handlers), ["karma", "read-user"])

# ...and extends it: a route whose handler is a MeTTa equation, added by a
# MeTTa program, dispatching through the very same table.
m.run('(= (pong) "pong from metta")')
m.run("!(add-atom (context-space) (route app GET (ping) pong 99))")
check(
    "a MeTTa-added route serves",
    app.dispatch("GET", "/ping"),
    Response(200, "pong from metta"),
)
```

The example is the reference: everything it claims runs in the test suite. Grow it toward whatever your application needs, more verbs, converter registries, router nesting, middleware; each is a few lines on the same core calls.
