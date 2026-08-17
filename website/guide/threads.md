# Threads, tasks, and what pickles

Python's own documentation states, per type, what is atomic, what locks, and what a caller must serialize. This page is that statement for PeTTa. Every claim on it is pinned by a named test in the suite, so the guarantees are enforced rather than intended.

## One process, one home engine

A process holds one embedded Prolog runtime. The thread that first uses it holds the home engine, and every other bare thread's calls serialize on one lock around that engine, so calling any `MeTTa` method from any thread is safe and correct, just not parallel (`test_bare_threads_share_the_home_engine_serialized`). The lock choice is per OS thread and decided once, when a thread attaches an engine, not per call.

Real parallelism is a second engine, and there are three doors to one:

- `petta.engine_thread()` attaches an engine to the current thread for a block, releasing exactly what it attached (`test_engine_thread_owns_only_its_attachment`). Inside the block this thread's calls stop sharing the home lock; measured 1.94x, 3.90x and 7.26x at 2, 4 and 8 threads.
- `m.pool(workers=n)` owns n threads that each hold their own engine (`test_each_worker_holds_a_distinct_engine`), proves genuine overlap with a barrier rather than a clock (`test_pool_runs_work_concurrently`), answers `map` in input order however workers finish, and reports every failure, one plainly and several as one `ExceptionGroup` in input order (`test_map_raises_every_failure_in_input_order`).
- `m.parallel(...)` fans out INSIDE the engine through `concurrent_and/2`, one SWI thread per branch. Answers arrive in completion order, and there is deliberately no `inferences=` bound on it, because the counter counts the calling thread while the work runs in workers; an unenforceable bound is worse than an absent one.

Functions compile into shared modules, so an attached engine sees what the home engine compiled; only Prolog global variables are per engine, which is why the current-space scope below behaves.

## asyncio: one worker, contexts that travel

`AsyncMeTTa` puts every engine call on one dedicated worker thread and serializes requests whole, aiosqlite's architecture, so two tasks never interleave inside an evaluation. Scoped state travels correctly: `with m.limits(...)` and `m.batch()` ride `contextvars`, each request copies the submitting task's context, and the worker runs inside it, so a with-block on the event loop bounds engine work happening on another thread (`test_aio_scoped_limits_cross_to_the_worker`). Interpreter shutdown attempts every worker and reports the failures together (`test_aio_shutdown_handler_attempts_every_worker`).

The current-space context is not Python state at all: the engine tracks it in a Prolog global (`'$petta_module'`) set and restored around each evaluation, per engine and therefore per thread, so tasks sharing the aio worker cannot clobber each other's space. The one `threading.local` in the package is the per-thread lock choice above, and it is deliberately thread-keyed rather than a `ContextVar`: a Prolog engine attaches to an OS thread, so two tasks on one thread genuinely share one engine and must share its lock decision.

## Subscriptions, cursors, finalizers

Subscription state lives behind one registry lock, real locking rather than a bet on the GIL, so the queue and cancellation are safe under free-threaded Python too (`test_subscription_queue_is_thread_safe`, `test_subscription_cancel_is_thread_safe`). A callback runs synchronously inside the write that caused it, on the writing thread; `cancel()` waits for deliveries already in flight (`test_subscription_cancel_waits_for_inflight_delivery`), and `events()` blocks its consumer thread on a condition variable, ending at cancellation.

A `Cursor` is a Python iterator over an engine-held query: individual pulls serialize on the engine like every call, but the iteration protocol itself is a single-consumer affair, exactly as with every Python iterator, so share rows, not the cursor. An abandoned cursor is reaped by a finalizer that may run on whatever thread collection runs on, warning as it does (`test_abandoned_stream_warns_before_reaping`); a `Handle`'s `__del__` is likewise a best-effort release from an arbitrary thread, with explicit `release()` or a `with` block as the deterministic path.

A `RemoteSpace` client builds one stateless HTTP request per operation, so concurrent use is safe; the serving side runs every operation through one engine worker, interleaving whole operations (`test_threaded_clients_interleave_whole_operations`).

## What pickles

Serialization guarantees live here too, because they are the other half of "what crosses a boundary":

| object | pickles? | why |
|---|---|---|
| `Sym`, `Var`, `Expr`, `Gnd` of plain values | yes, by value | `test_atoms_pickle_by_value` |
| `Gnd` of a live object, `Handle`, `Box` | refuses, by design | process-local identity cannot cross (`test_process_local_grounded_values_refuse_pickle`) |
| `Rows` and `Row` | yes | `test_rows_copy_and_pickle_protocols` |
| `lint` `Finding` | yes, with a stable public identity | `test_finding_retains_public_pickle_identity` |
| `MeTTa`, cursors, subscriptions | no | live engine state; `save()`/`load()` persist a space, and the remote protocol's wire forms cross processes |
