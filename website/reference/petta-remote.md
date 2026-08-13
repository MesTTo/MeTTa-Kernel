# `petta.remote`

Source: `python/petta/remote.py`.

> Purpose: spaces across processes, the multi-context reading: each engine
> is a context, serve() exposes its spaces over HTTP speaking the same tagged
> wire the local boundary speaks, connect() answers a transport, and attach()
> registers a remote engine's space here as a foreign space, so
> (match &amp;remote (users $id $n) ...) crosses the network exactly as it
> crosses into DuckDB. The shape is SingularityNET's DAS gateway (a single
> transport method carrying {space, pattern} and answering atoms) and
> metta-wam's metta_server, translated onto petta's own SpaceProvider
> protocol; the engine keeps unification for itself, so a remote answer is
> speed and reach, never trust.
> Open Obligations:
>   To Do: None
>   Hacks: None
>   Future Enhancements: authentication and TLS termination belong to a
>     fronting proxy for now; the protocol itself is deliberately one JSON
>     POST per operation.

The entries below reproduce the source signatures and docstrings.

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

### `RemoteSpace.match`

```python
def match(self, pattern: Atom) -> Iterator[Atom]:
```

No docstring is defined.

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

### `RemoteSpace.remove`

```python
def remove(self, atom: Atom) -> bool:
```

No docstring is defined.

## `connect`

```python
def connect(url: str, timeout: float = 30.0) -> Transport:
```

> The HTTP transport for a serve()d engine: one POST per operation,
> JSON both ways, errors surfaced with the remote's own message.

## `attach`

```python
def attach(m, name: str, url_or_transport: Any, remote_space: str = "&self") -> RemoteSpace:
```

> Register a remote engine's space here under a local name.
>
> petta.remote.attach(m, "&amp;hq", "http://127.0.0.1:8700")
> m.run('!(match &amp;hq (users $id $n) $n)')

## `Server`

```python
class Server:
```

> This engine's spaces, served. close() stops accepting.

### `Server.close`

```python
def close(self) -> None:
```

No docstring is defined.

## `serve`

```python
def serve(m, host: str = "127.0.0.1", port: int = 0, spaces: list[str] | None = None) -> Server:
```

> Expose this engine's spaces over HTTP; port 0 picks a free one.
>
> Every operation answers for the space the request names, restricted
> to `spaces` when given (an allowlist is the whole access model here;
> front anything public with a real proxy). match runs the engine's own
> match with the pattern as its template, so the instantiated atoms
> cross, and the caller's engine re-unifies them.
>
> A context is a PROCESS: serving and attaching within one process
> cannot join through the local engine, because one runtime lock guards
> both sides of that call and the serving thread would wait on the very
> evaluation that is waiting on it. Two engines, two processes, is the
> deployment this exists for; in-process, spaces already share the
> engine and need no wire.
