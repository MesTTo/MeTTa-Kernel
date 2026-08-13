# Web routes

`petta.web` translates route dispatch into space operations. An app is a space. Its route table is facts. A request is a term. Dispatch reads the table on every request and unifies routes in registration order. Typed path converters either produce a value or yield a 422 response. No matching route yields 404.

Handlers are called by name through the engine. A Python operation and a MeTTa equation therefore use the same route table. Middleware wraps dispatch with the `request, call_next` shape.

The example registers Python routes, adds middleware, inspects route facts, then adds a route and handler from MeTTa:

```python
from _common import check, done

from petta import MeTTa, S, V, web

m = MeTTa().fresh_space()
app = web.router(m, name="app")


# The FastAPI shape: a decorator, a typed path parameter, a handler.
@app.get("/users/{id:int}")
def read_user(id):
    return f"user {id}"


@app.get("/users/{id:int}/karma")
def karma(id):
    return id * 10


check("a typed route", app.dispatch("GET", "/users/7"), web.Response(200, "user 7"))
check("params arrive converted", app.dispatch("GET", "/users/7/karma").body, 70)
check("no match is 404", app.dispatch("GET", "/nowhere").status, 404)
check("a refused parameter is 422", app.dispatch("GET", "/users/abc").status, 422)

# Middleware wraps dispatch, FastAPI's call_next reading.
@app.middleware
def bracket(request, call_next):
    response = call_next(request)
    return web.Response(response.status, f"[{response.body}]")


check("middleware composes", app.dispatch("GET", "/users/7").body, "[user 7]")

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
    web.Response(200, "[pong from metta]"),
)
done("15_web_routes")
```

See [`petta.web`](../reference/petta-web) for route registration, router inclusion, middleware, and response types.
