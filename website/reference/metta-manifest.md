# `metta.manifest`

Source: `extensions/python/metta/manifest.py`.

> Purpose: deployment as knowledge. `metta.boot(path)` assembles an app
> from a MeTTa manifest of `(boot ...)` forms, each a thin declaration over
> one existing imperative call, and records every performed form in the
> booted space, so the deployment is queryable knowledge rather than dead
> config.
> Assumes:
>   - shim.pl metta_py_read_forms answers every form in a source without
>     compiling, storing, or running any [tested
>     test_a_manifest_neither_runs_nor_defines]
>   - metta.remote._refuse_this_process holds the registry of this process's
>     live servers, takes the addresses a caller is about to serve, and raises
>     MettaError for a URL either set covers; the manifest calls it rather than
>     repeating it [source: metta/remote.py _refuse_this_process;
>     commit=WORKTREE]
>   - metta.remote._raise_failures raises one failure on its own and several
>     as a BaseExceptionGroup, the shape Server.close() already gives a
>     caller [source: metta/remote.py _raise_failures; commit=WORKTREE]
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
>   - manifest space operands accept decoded Space handles as well as the
>     legacy symbol spelling [tested: test_load_and_serve_assemble_and_record;
>     commit=4e2398075da67bb2cbcc123a9fc1e078ecac6fbf]
>   - an attach form is refused whether it stands above or below the serve
>     form that binds its port, because the whole manifest is validated before
>     any of it runs [tested:
>     test_a_manifest_that_attaches_before_it_serves_is_refused;
>     commit=WORKTREE]
>   - an attach form meets the same refusal the direct attach door applies,
>     because it calls it: a URL this process serves is refused instead of
>     attached [measured 2026-08-30: the manifest attached it where the direct
>     door refused it, and the first match then stalled 30.0s, the whole
>     transport timeout, before failing with a message naming neither the
>     cause nor the remedy] [tested:
>     test_a_manifest_cannot_attach_a_space_this_process_serves;
>     commit=WORKTREE]
>   - a form whose effect performed and whose (boot ...) record raised is
>     reported as exactly that, never as a form that performed nothing
>     [tested: test_a_failed_record_reports_the_effect_that_performed;
>     commit=WORKTREE]
> Owns: the servers its serve forms started. Boot.close() stops them, on the
>   failure path too, and one that refuses to stop does not strand the
>   servers after it: every close is attempted and the failures travel
>   together [tested: test_every_server_closes_even_when_one_refuses,
>   test_a_cleanup_failure_travels_beside_the_boot_failure; commit=WORKTREE].
>   The engine and the registered providers stay, because passive state
>   belongs to the space story, not to the assembler.
> Decides: a manifest that fails mid-way keeps the writes its performed
>   prefix made, the same law the engine's own guards follow; the error
>   names the failing form, which half of it performed, and how many stood.
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
