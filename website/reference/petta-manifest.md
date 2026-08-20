# `petta.manifest`

Source: `bindings/python/petta/manifest.py`.

> Purpose: deployment as knowledge. `petta.boot(path)` assembles an app
> from a MeTTa manifest of `(boot ...)` forms, each a thin declaration over
> one existing imperative call, and records every performed form in the
> booted space, so the deployment is queryable knowledge rather than dead
> config.
> Assumes:
>   - shim.pl petta_py_read_forms answers every form in a source without
>     compiling, storing, or running any [tested
>     test_a_manifest_neither_runs_nor_defines]
> Guarantees:
>   - the vocabulary is closed (load, attach, bridge, serve) and every form
>     is validated before ANY form performs; a bad manifest changes nothing
>     [tested test_every_problem_is_reported_before_anything_performs]
>   - forms perform in source order; a bridge name materializes at its
>     first bridge form carrying every declaration the manifest holds for
>     that name, so a later serve can name it [tested
>     test_bridge_declarations_gather_and_source_order_holds]
>   - each performed form lands as its own (boot ...) atom in the booted
>     space [tested test_load_and_serve_assemble_and_record]
> Owns: the servers its serve forms started. Boot.close() stops them, on
>   the failure path too; the engine and the registered providers stay,
>   because passive state belongs to the space story, not to the assembler.
> Decides: a manifest that fails mid-way keeps the writes its performed
>   prefix made, the same law the engine's own guards follow; the error
>   names the failing form and how many stood.
> Open Obligations:
>   To Do: None
>   Hacks: None
>   Future Enhancements: None.

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

## `boot`

```python
def boot(
    manifest: str | os.PathLike[str],
    *,
    m: MeTTa | None = None,
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
>     (boot (attach &crm "http://crm:8700"))      petta.remote.attach
>     (boot (bridge &db (edge $a $b) (row ...)))  petta.tables declare + bridge
>     (boot (serve (&self &crm) 8700))            petta.remote.serve
>
> The vocabulary is closed and validated whole before anything runs.
> Bridges name live database connections, which MeTTa source cannot
> carry, so every bridged name must appear in `connections`, and every
> connection must be claimed by a bridge. The remaining keywords are
> the serve policy petta.remote.serve documents: host, token,
> authorize, ssl_context apply to every server the manifest starts.
>
> Each performed form is stored as its own `(boot ...)` atom, so the
> running app answers `(match &self (boot $what) $what)` with its own
> topology. A manifest that fails mid-way keeps its performed prefix's
> writes and closes any servers it started; the error names the form.
