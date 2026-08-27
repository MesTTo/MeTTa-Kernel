<!--
Purpose: connect in-memory routing, remote spaces, and multi-shot solving through the public narrow surface.
Guarantees: examples use canonical atoms, effect-classified Space.op, context.space(), and metta.tables.add.
[tested: npm run docs:build and test_unclassified_operation_refuses_with_all_five_effect_remedies; commit=3cfbe0d7417b1c453c2dc12d47e2e47e7de461f7]
-->

# HTTP, routes, and solver loops

Three seams share space operations but do different jobs:

- `web_routes.py` models FastAPI-shaped routing in memory. It does not import FastAPI and does not serve HTTP.
- `metta.remote` serves and attaches spaces over HTTP.
- `multishot_solving.py` maps clingo-shaped parts and externals onto MeTTa's space and evaluation surface. It is not a clingo binding or an ASP solver.

## Model a route table in a space

The in-memory route example stores route facts, matches paths in registration order, converts typed parameters, and evaluates the chosen handler:

```python
@dataclass(frozen=True)
class Response:
    status: int
    body: Any


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

    def get(self, path: str, *, effect: str) -> Callable:
        def wrap(fn: Callable) -> Callable:
            handler = fn.__name__.replace("_", "-")
            self._m.op(fn, name=handler, effect=effect)
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
        table = self._m.match(
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

The decorator shape registers Python handlers as operations. The route table remains facts, so MeTTa can query and extend it:

```python
m = MeTTa().space()
app = Router(m, "app")


# The FastAPI shape: a decorator, a typed path parameter, a handler.
@app.get("/users/{id:int}", effect="pureStructural")
def read_user(id):
    return f"user {id}"


@app.get("/users/{id:int}/karma", effect="pureStructural")
def karma(id):
    return id * 10


check("a typed route", app.dispatch("GET", "/users/7"), Response(200, "user 7"))
check("params arrive converted", app.dispatch("GET", "/users/7/karma").body, 70)
check("no match is 404", app.dispatch("GET", "/nowhere").status, 404)
check("a refused parameter is 422", app.dispatch("GET", "/users/abc").status, 422)

# The table is facts, so MeTTa reads it like any facts...
handlers = m.match(S.route(S.app, S.GET, V.p, V.h, V.k))
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

For a smaller routing model, equations provide dispatch and middleware directly:

```python
app = MeTTa().space()
app.run(
    '(= (route home) (Page 200 "Welcome"))\n'
    '(= (route about) (Page 200 "About us"))\n'
    "(= (route $other) (NotFound 404 $other))\n"
    "(= (handle $req) (once (route $req)))\n"
    "(= (logged $req) (let $res (handle $req) (Logged $req $res)))"
)
check("a route", app.run("!(handle home)"), [[Expression(S.Page, 200, "Welcome")]])
check("the 404", app.run("!(handle nowhere)"), [[Expression(S.NotFound, 404, S.nowhere)]])
check("middleware is composition", app.run("!(logged about)"),
      [[Expression(S.Logged, S.about, Expression(S.Page, 200, "About us"))]])
```

## Serve a space over HTTP

Actual HTTP transport belongs to `metta.remote`. The process-level test starts another engine, attaches its served space, joins remote and local facts, writes across the connection, and checks the allowlist:

```python
def test_remote_spaces_serve_attach_and_join(metta, tmp_path):
    """The other engine is a PROCESS, as deployment means it: a subprocess
    serves one space, this engine attaches it, and one local match joins
    remote rows with local facts across the wire."""
    script = Path(__file__).parent / "data" / "remote_server.py"
    child = subprocess.Popen(
        [sys.executable, str(script)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        env={**os.environ, "PYTHONPATH": os.pathsep.join(sys.path)},
    )
    local = metta.space()
    try:
        line = child.stdout.readline()
        assert line, child.stderr.read()
        info = json.loads(line)
        attached = metta.space(
            "&hq",
            backing=remote.RemoteSpace(remote.connect(info["url"]), info["space"]),
        )
        # A match crosses the wire, filtered by the remote engine's own match.
        assert local.run("!(match &hq (users 2 $n) $n)") == [["Bob"]]
        # And joins with local facts in ONE match, the multi-context point.
        local.run("(vip 1)")
        (group,) = local.run(
            "!(collapse (match (context-space) (vip $id) (match &hq (users $id $n) $n)))"
        )
        assert group == [Expression("Ada")]
        # Writes cross too, and the remote engine answers them back.
        local.run('!(add-atom &hq (users 3 "Cy"))')
        assert local.run("!(match &hq (users 3 $n) $n)") == [["Cy"]]
        local.run('!(remove-atom &hq (users 3 "Cy"))')
        assert local.run("!(collapse (match &hq (users 3 $n) $n))") == [[Expression()]]
        # A space outside the allowlist is refused with the remote's words.
        stray = remote.RemoteSpace(remote.connect(info["url"]), "&self")
        with pytest.raises(MettaError):
            list(stray.match(S.anything(V.x)))
        attached.drop()
    finally:
        child.terminate()
        child.wait(timeout=10)
        local.drop()
```

The helper named by that test is not copied here. The approved source excerpt is the top-level test itself.

`remote.serve` supports a bearer token and an authorization hook, and clients can send additional headers. Credentials never travel in the clear: attaching a token to a plain `http://` URL is refused at connect time, so a token reaches the wire only under TLS.

```python
def test_remote_auth_token_and_hook_requires_tls(metta):
    served = metta.space()
    served.add(S.fact(1))
    server = remote.serve(
        metta,
        spaces=[served.name],
        token="s3cret",
        authorize=lambda headers: headers.get("x-tenant") == "acme",
    )
    try:
        with pytest.raises(MettaError, match="credentials require an https URL"):
            remote.connect(server.url, token="s3cret", headers={"x-tenant": "acme"})
    finally:
        server.close()
        served.drop()
```

## Keep a world between solves

The multi-shot example borrows two clingo terms. An `External` owns one toggled fact. A `Part` owns a parameterized source template and refuses duplicate grounding:

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

The solve loop adds one reachability step at a time and reuses the same space between shots:

```python
m = MeTTa().space()

# The base part: a graph as tabular facts, and step zero of reachability.
tables.add(m, "edge", [(S.a, S.b), (S.b, S.c), (S.c, S.d)])
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
```

Toggling an external adds or removes one fact for the next solve. Releasing it makes later assignment an error:

```python
# Externals: truths toggled between solves. A blocked node cuts routes in
# the NEXT shot without regrounding anything.
blocked = External(m, S.blocked(S.c))
blocked.assign(True)
check(
    "the external is a fact while assigned",
    [str(r.x) for r in m.match(S.blocked(V.x))],
    ["c"],
)
blocked.assign(False)
check("and gone when withdrawn", m.match(S.blocked(V.x)), [])
blocked.release()
```

Continue with [Web routes](../live/web-routes), [Contexts and remotes](../live/contexts), [Multi-shot solving](../live/multishot), and [`metta.remote`](../reference/metta-remote).
