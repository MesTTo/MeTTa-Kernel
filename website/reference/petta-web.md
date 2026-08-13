# `petta.web`

Source: `python/petta/web.py`.

> Purpose: the web-routing functor, FastAPI's semantics on the engine: an
> app is a space, the route table is facts, a request is a term, dispatch is
> unification in registration order, path parameters are variables with
> FastAPI's typed converters, the 404 is the absence of a match and the 422 a
> match whose parameter refuses its type. The facts are the single source of
> truth: dispatch reads the table back from the space every request, handlers
> are called BY NAME through the engine, so a Python function registered as
> an operation and a MeTTa equation added by a program dispatch identically,
> and a MeTTa program can read or extend the route table like any facts.
> Open Obligations:
>   To Do: None
>   Hacks: None
>   Future Enhancements: query strings and request bodies once a transport
>     integration needs them; today requests are method plus path, the
>     routing semantics themselves.

The entries below reproduce the source signatures and docstrings.

## `Response`

```python
class Response:
```

> What a dispatch answers: a status and a decoded body.

## `Route`

```python
class Route:
```

> One compiled route: the MeTTa pattern its fact carries, the casters
> its parameters run, and the handler name the engine will evaluate.

## `Router`

```python
class Router:
```

> Routes on a space, FastAPI-shaped.
>
>     app = web.router(m, name="app")
>
>     @app.get("/users/{id:int}")
>     def read_user(id):
>         return f"user {id}"
>
>     app.dispatch("GET", "/users/7")      # Response(200, 'user 7')
>
> The decorator registers the function as an ordinary operation and adds
> the fact (route app GET (users $id) read-user 0) to the space. dispatch
> reads its app's facts back in registration order, first match winning
> as in FastAPI, casts each parameter, and evaluates (read-user 7)
> through the engine. A MeTTa program that adds its own route fact naming
> an equation gets dispatched exactly the same way; several routers share
> one space without sharing tables, since each reads its own app name.

### `Router.route`

```python
def route(self, method: str, path: str) -> Callable:
```

> The general decorator; get/post/put/delete spell it per method.

### `Router.get`

```python
def get(self, path: str) -> Callable:
```

No docstring is defined.

### `Router.post`

```python
def post(self, path: str) -> Callable:
```

No docstring is defined.

### `Router.put`

```python
def put(self, path: str) -> Callable:
```

No docstring is defined.

### `Router.delete`

```python
def delete(self, path: str) -> Callable:
```

No docstring is defined.

### `Router.add_route`

```python
def add_route(self, method: str, path: str, handler: str) -> Route:
```

> A route for a handler the engine already answers: a registered
> operation or a MeTTa equation, named rather than imported.

### `Router.include`

```python
def include(self, other: "Router", prefix: str = "") -> None:
```

> Another router's routes, re-registered here under a prefix, the
> APIRouter nesting: the routes join this table in order, after the
> ones already registered, under this router's own app name.

### `Router.middleware`

```python
def middleware(self, fn: Callable) -> Callable:
```

> FastAPI-shaped middleware: fn(request, call_next) -&gt; Response,
> outermost first. request is the (method, path) pair.

### `Router.dispatch`

```python
def dispatch(self, method: str, path: str) -> Response:
```

> One request through the table: the routing semantics.

## `router`

```python
def router(m, prefix: str = "", name: str | None = None) -> Router:
```

> A router on this space; the module's one entry point.
