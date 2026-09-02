# `metta.manifest`

Source: `extensions/python/metta/manifest.py`.

> Deployment as knowledge. `metta.boot(path)` assembles an app
> from a MeTTa manifest of `(boot ...)` forms, each a thin declaration over
> one existing imperative call, and records every performed form in the
> booted space, so the deployment is queryable knowledge rather than dead
> config.
> Owns: the servers its serve forms started. Boot.close() stops them, on the
>   failure path too, and one that refuses to stop does not strand the
>   servers after it: every close is attempted and the failures travel
>   together.
>   The engine and the registered providers stay, because passive state
>   belongs to the space story, not to the assembler.

The entries below reproduce the source signatures and docstrings.

## `Boot`

```python
class Boot:
```

> The assembled app: the engine, and the servers the manifest started.
>
> A context manager, closing what boot itself started: every server.
> Registered providers and loaded knowledge stay, they are space state.

### `Boot.close`

```python
def close(self) -> None:
```

> Stop every server the manifest started.
>
> The ones behind a server that refuses to stop are included; one refusal
> raises on its own and several raise as a group, the shape
> metta.remote.Server.close()
> already gives a caller.

## `boot`

```python
def boot(
    manifest: str | os.PathLike[str],
    *,
    m: Space | None = None,
    connections: Mapping[str, Any] | None = None,
    host: str = '127.0.0.1',
    token: str | None = None,
    authorize: Callable[[_remote.Request], bool] | None = None,
    ssl_context: Any = None,
) -> Boot:
```

> Assemble an app from a manifest of (boot ...) forms.
>
> Each form is sugar for exactly one existing call, performed in source
> order against `m` (a fresh engine when none is given):
>
>     (boot (load "rules.metta"))                 m.load, manifest-relative
>     (boot (attach &crm "http://crm:8700"))      metta.attach + RemoteSpace
>     (boot (bridge &db (edge $a $b) (row ...)))  metta.tables declare + bridge
>     (boot (serve (&self &crm) 8700))            metta.remote.serve
>
> The vocabulary is closed and validated whole before anything runs.
> Bridges name live database connections, which MeTTa source cannot
> carry, so every bridged name must appear in `connections`, and every
> connection must be claimed by a bridge. The remaining keywords are
> the serve policy metta.remote.serve documents: host, token,
> authorize, ssl_context apply to every server the manifest starts.
>
> Each performed form is stored as its own `(boot ...)` atom, so the
> running app answers `(match &self (boot $what) $what)` with its own
> topology. A manifest that fails mid-way keeps its performed prefix's
> writes and closes any servers it started; the error names the form.
