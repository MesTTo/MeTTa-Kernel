# `petta.remote`

Source: `python/petta/remote.py`.

> Purpose: spaces across processes, the multi-context reading: each engine
> is a context, serve() exposes its spaces over HTTP speaking the same tagged
> wire the local boundary speaks, connect() answers a transport, and attach()
> registers a remote engine's space here as a foreign space, so
> (match &remote (users $id $n) ...) crosses the network exactly as it
> crosses into DuckDB. The shape is SingularityNET's DAS gateway (a single
> transport method carrying {space, pattern} and answering atoms) and
> metta-wam's metta_server, translated onto petta's own SpaceProvider
> protocol; the engine keeps unification for itself, so a remote answer is
> speed and reach, never trust.
> Guarantees:
>   - serve compares Bearer credentials with hmac.compare_digest before
>     consulting the authorization callback [tested
>     test_bearer_token_uses_constant_time_comparison]
>   - connect refuses non-HTTP URLs and refuses credentials over plain HTTP
>     [tested test_remote_connect_refuses_non_http_urls,
>     test_remote_connect_refuses_credentials_over_http]
>   - serve reports worker startup failure before accepting requests and close
>     waits for both owned threads to finish [tested
>     test_remote_serve_reports_worker_startup_failure,
>     test_remote_close_waits_for_worker_detach]
>   - the HTTP boundary rejects ambiguous lengths, oversized bodies, and
>     non-object JSON with a response instead of dropping the connection
>     [tested test_remote_server_rejects_malformed_request_bodies]
>   - RemoteSpace claims every capability the wire carries and refuses
>     subscribe, because the wire carries no event and a watcher would hear
>     only this process's own writes [measured 2026-08-19: an attached space
>     delivered the one atom this process wrote and nothing for the atom the
>     server added] [tested
>     test_remote_space_claims_subscribe_only_if_the_channel_exists]
> Owns:
>   - Server owns the HTTP loop and its attached-engine worker until close()
>     joins both [tested test_remote_close_waits_for_worker_detach]
> Fails when:
>   - a program wants to watch a remote space. There is no event channel to
>     build that on, so the capability is refused rather than half-kept; the
>     refusal names polling and bridge() as the two routes that do work
> Open Obligations:
>   To Do: None
>   Hacks: None
>   Future Enhancements: None

The entries below reproduce the source signatures and docstrings.

## `Request`

```python
class Request:
```

> What an authorize hook decides about: who is asking, what they ask
> for, and which space they name. A hook given the headers alone could
> not tell a read from a write, so read-only was inexpressible.

## `RemoteSpace`

```python
class RemoteSpace(SpaceProvider):
```

> A space served by another engine, reached through a transport.
>
> match sends the pattern's wire form and decodes the instantiated
> atoms the remote engine's own match answered; add and remove write
> through; atoms enumerates. The local engine unifies every candidate
> against the local pattern, so a lying or stale remote can only cost
> time, not soundness.
>
> It does NOT subscribe, and that is the one capability the base class
> would have given it for free. See can_run.

### `RemoteSpace.can_run`

```python
def can_run(self, capability: str, /, **request: Any) -> bool:
```

> Everything the wire carries, and not subscribe.
>
> SpaceProvider derives subscribe from add and remove, and for a space
> whose every change goes through this process that inference is
> exact: the engine's own write hooks are the event source. A remote
> space is the one shape where it fails, because its contents change
> on the server, which is the whole reason it is remote. The wire has
> four operations, match, enumerate, add and remove, and none of them
> carries an event, so a watcher here hears only the writes this
> process made and silently misses every other one [measured
> 2026-08-19: an attached space delivered the one atom this process
> wrote and nothing for the atom the server added].
>
> A capability is a promise about a space rather than a list of
> methods, so the honest answer is no until the channel exists.

### `RemoteSpace.refusal`

```python
def refusal(self, capability: str, /, **_request: Any) -> str | None:
```

No docstring is defined.

### `RemoteSpace.match`

```python
def match(self, pattern: Atom, *, limit: int | None = None) -> Iterator[Atom]:
```

> Candidates for a pattern; `limit` crosses as the wire's optional
> `bound` field. Sending it is sound whatever the server does: a
> server that honors it exactly saves the work, one that ignores it
> over-answers, and the local engine re-unifies and truncates either
> way. Whether it is honored is advertised in
> `server_capabilities()`.

### `RemoteSpace.server_capabilities`

```python
def server_capabilities(self) -> dict[str, Any]:
```

> The server's own advertisement from GET /health: `capabilities`
> names the seam operations it admits, so a client can ask before
> writing, and `bound` says whether /match honors the bound field
> exactly. A transport built by connect() knows its URL; a
> hand-built transport must carry its own `health` callable, or
> this refuses rather than guessing.

### `RemoteSpace.atoms`

```python
def atoms(self) -> Iterator[Atom]:
```

No docstring is defined.

### `RemoteSpace.add`

```python
def add(self, atom: Atom) -> None:
```

No docstring is defined.

### `RemoteSpace.add_many`

```python
def add_many(self, atoms: list[Atom]) -> None:
```

> One request carries the batch, the engine's own bulk-door law on
> the wire: a batch is a transport optimisation and never a semantic
> one, and the engine already routes only plain stores through it.

### `RemoteSpace.remove`

```python
def remove(self, atom: Atom) -> bool:
```

No docstring is defined.

## `connect`

```python
def connect(
    url: str,
    timeout: float = 30.0,
    *,
    token: str | None = None,
    headers: dict[str, str] | None = None,
    ssl_context: Any = None,
) -> Transport:
```

> The HTTP transport for a serve()d engine: one POST per operation,
> JSON both ways, errors surfaced with the remote's own message.
>
> token sends Bearer authentication, headers adds anything else a
> deployment needs (an API key, a tenant id), and ssl_context is
> Python's own ssl.SSLContext for https urls, certificate pinning
> included, so the transport composes with whatever security the
> serving side asks for. Only absolute http and https URLs are accepted.
> Credentials require https.

## `attach`

```python
def attach(m, name: str, url_or_transport: Any, remote_space: str = '&self') -> RemoteSpace:
```

> Register a remote engine's space here under a local name.
>
> petta.remote.attach(m, "&hq", "http://127.0.0.1:8700")
> m.run('!(match &hq (users $id $n) $n)')

## `Server`

```python
class Server:
```

> This engine's spaces, served. close() stops accepting.

### `Server.close`

```python
def close(self, timeout: float = _SERVER_TIMEOUT) -> None:
```

> Stop accepting, detach the engine worker, and join both threads.

## `serve`

```python
def serve(
    m,
    host: str = '127.0.0.1',
    port: int = 0,
    spaces: list[str] | None = None,
    *,
    token: str | None = None,
    authorize: Callable[[Request], bool] | None = None,
    ssl_context: Any = None,
) -> Server:
```

> Expose this engine's spaces over HTTP; port 0 picks a free one.
>
> Every operation answers for the space the request names, restricted
> to `spaces` when given. Security is the caller's to define, library
> fashion: token requires Bearer authentication, authorize is the
> general hook (a Request in, carrying the operation, the space and
> the headers, and a verdict out, so read-only, per-space and
> per-tenant policies all fit), and ssl_context, Python's own
> ssl.SSLContext with a certificate loaded, serves TLS directly;
> anything heavier still composes behind a fronting proxy. match runs
> the engine's own match with the pattern as its template, so the
> instantiated atoms cross, and the caller's engine re-unifies them.
>
> A context is a PROCESS: serving and attaching within one process
> cannot join through the local engine, because one runtime lock guards
> both sides of that call and the serving thread would wait on the very
> evaluation that is waiting on it. Two engines, two processes, is the
> deployment this exists for; in-process, spaces already share the
> engine and need no wire.
