# `metta.remote`

Source: `extensions/python/metta/remote.py`.

> Spaces across processes, the multi-context reading: each engine
> is a context, serve() exposes its spaces over HTTP speaking the same tagged
> wire the local boundary speaks, connect() answers a transport, and RemoteSpace over it is the backing metta.attach() registers
> registers a remote engine's space here as a foreign space, so
> (match &remote (users $id $n) ...) crosses the network exactly as it
> crosses into DuckDB. The shape is SingularityNET's DAS gateway (a single
> transport method carrying {space, pattern} and answering atoms) and
> metta-wam's metta_server, translated onto metta's own SpaceProvider
> protocol; the engine keeps unification for itself, so a remote answer is
> speed and reach, never trust.
> Owns:
>   - Server owns the HTTP loop and its attached-engine worker until close()
>     joins both
>   - a Gateway owns every cursor ask/next/stop holds open, one engine each,
>     released by close(), by the stream ending, or by the idle deadline

The entries below reproduce the source signatures and docstrings.

## `Request`

```python
class Request:
```

> What an authorize hook decides about: who is asking, what they ask
> for, and which space they name. A hook given the headers alone could
> not tell a read from a write, so read-only was inexpressible.

## `RemoteCursor`

```python
class RemoteCursor:
```

> A remote answer stream: `/ask` opened it, `/next` pulls the next
> chunk, `/stop` releases it.
>
> Space.stream()'s Cursor with a wire under it, and the same discipline:
> iterate it, close() it, or leave its with-block. Exhaustion releases
> the server's cursor and stays ordinary iterator exhaustion; an
> explicit close is the separate state that refuses further pulls.
>
>     with space.stream(pattern) as answers:
>         for atom in answers:
>             if wanted(atom):
>                 break          # the server computes nothing further
>
> `batch` is how many answers one crossing carries. One is the fully
> lazy reading and the protocol's default; raising it trades an answer
> that may go unwanted for a saved round trip, the same choice a
> database driver's fetch size makes.

### `RemoteCursor.close`

```python
def close(self) -> None:
```

> Release the server's cursor; idempotent, and distinct from
> exhaustion, which released it already.
>
> The token survives a failed /stop and the cursor stays open, because
> a close that discarded it first could never release the server's
> cursor afterwards: every later close returned at the flag while the
> server held the engine to its idle deadline.

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
> `batch` chooses how match() retrieves answers, and the choice is the one
> match() and stream() make in-process. Left None, match() is the eager
> /match: one crossing carrying the whole answer set, which is what a
> space whose answers fit in an HTTP body wants. Set to a count, match()
> rides the ask/next/stop lifecycle in chunks of that size, so a caller
> that stops early stops the server's work with it and an answer set
> larger than one body still crosses.
>
> It does NOT subscribe, and that is the one capability a provider has to
> promise rather than implement. See delivers.

### `RemoteSpace.delivers`

```python
def delivers(self) -> tuple[str, str] | None:
```

> Nothing: the wire carries no event.
>
> The wire has four operations, match, enumerate, add and remove, and
> none of them carries an event, while a remote space's contents change
> on the server, which is the whole reason it is remote. So a watcher
> here would hear only the writes this process made and silently miss
> every other one. Declaring nothing is what refuses the subscription; the
> sentence below is what a caller reads.

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
>
> One crossing carries the whole answer set unless this space was
> built with a `batch`, in which case the ask/next/stop lifecycle
> carries it a chunk at a time and an engine that stops pulling
> stops the server.

### `RemoteSpace.stream`

```python
def stream(
    self,
    pattern: Atom,
    *,
    batch: int = _DEFAULT_BATCH,
    limit: int | None = None,
) -> RemoteCursor:
```

> The lazy method: answers pulled a chunk at a time, so taking two
> of a large enumeration costs the server two answers' work instead
> of the whole join's.
>
> match() remains eager, matching the in-process split between match()
> and stream(). Reach for this to take answers
> until you have seen enough, or when the answer set is larger than
> one HTTP body.
>
> `limit` is the wire's `bound` and carries the same advice it
> carries on match(): a server that can honor it exactly stops at
> the count, one that cannot ignores it and over-answers. It is not
> truncated again here, because a server may answer candidates
> rather than answers, and cutting an over-approximated stream at
> the count is the under-approximation the protocol forbids. The
> first ask crosses when the cursor is built, as the in-process
> cursor opens its engine when it is built.

### `RemoteSpace.server_capabilities`

```python
def server_capabilities(self) -> dict[str, Any]:
```

> The server's own advertisement from GET /health: `capabilities`
> names the protocol operations it admits, so a client can ask before
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

> Store one atom on the serving side.
>
> A transport TIMEOUT means UNKNOWN, not failed: the server may
> still be processing the request when the client stops waiting, so
> a mutation behind a timeout can have committed. Exactly-once
> delivery needs idempotency keys and server-side deduplication,
> which the remote protocol does not carry yet; until it does,
> re-checking with a read is the caller's disambiguation.

### `RemoteSpace.add_many`

```python
def add_many(self, atoms: list[Atom]) -> None:
```

> One request carries the batch, the engine's own bulk-write law on
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

## `Gateway`

```python
class Gateway:
```

> This engine's spaces as the protocol's server side, transport-free.
>
> Call it with (operation, payload) and it answers the reply dict, which
> is the shape `Transport` has on the client side, so both halves of the
> wire carry one signature. serve() wraps a Gateway in the bundled HTTP
> server; mount one on the framework a deployment already runs, or call
> it directly, which is how a test watches the engine's own counters
> while the protocol runs, an HTTP server answering on a thread of its
> own.
>
> A Gateway OWNS the cursors ask/next/stop hold open, so close() it when
> the process is done with it. Server.close() does that for the one
> serve() made.
>
> It serializes NOTHING of its own: serve() runs every call on one
> attached-engine worker, and a Gateway called directly runs on the
> calling thread, so a caller that shares one across threads owns that
> arrangement.

### `Gateway.health`

```python
def health(self) -> dict:
```

> The transport-side spelling of GET /health, so a Gateway is a
> drop-in Transport and RemoteSpace.server_capabilities() can ask
> one the same question it asks a connected server.

### `Gateway.cursor_space`

```python
def cursor_space(self, token: object) -> str | None:
```

> Which space an open cursor's answers come from, so a transport
> can hand its authorization hook the space /next and /stop are
> really about; None once the cursor is gone.

### `Gateway.close`

```python
def close(self) -> None:
```

> Release every cursor still open, and the engine behind each.

## `Server`

```python
class Server:
```

> This engine's spaces, served. close() stops accepting.
>
> A context manager, because it owns a socket, an accept thread and an
> engine worker, which is more than any other handle in this library and
> exactly the shape Python spells `with`. `metta.space()` and
> `metta.aio.connect()` are already `with`-able; a server that had to be
> closed by hand was the one resource whose leak on an exception path was
> silent.

### `Server.close`

```python
def close(self, timeout: float = _SERVER_TIMEOUT) -> None:
```

> Stop accepting, detach the engine worker, join both threads, and
> release every answer cursor a client left open.
>
> The cursors go LAST, once nothing can pull from them: each holds an
> engine, and a client that walked away from a stream would otherwise
> leave one behind until the idle deadline that no longer has a server
> to fire on.

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
    cursor_idle: float = _CURSOR_IDLE,
    cursor_limit: int = _CURSOR_LIMIT,
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
> `cursor_idle` and `cursor_limit` bound the ask/next/stop lifecycle's
> server-side state: how long a cursor nobody pulls from survives, and
> how many live at once before a further ask is refused. The defaults
> are pengines' own, 300 seconds and a ceiling.
>
> A context is a PROCESS: serving and attaching within one process
> cannot join through the local engine, because one runtime lock guards
> both sides of that call and the serving thread would wait on the very
> evaluation that is waiting on it. Two engines, two processes, is the
> deployment this exists for; in-process, spaces already share the
> engine and need no wire. Gateway is the same protocol with no
> transport under it, for a test or a framework that wants the
> operations without a socket.
