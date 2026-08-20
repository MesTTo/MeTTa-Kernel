# `petta.persistent`

Source: `bindings/python/petta/persistent.py`.

> Purpose: fixed-schema fact spaces backed by SWI persistency journals.
> The provider keeps native MeTTa facts in typed dynamic predicates, writes
> every change through library(persistency), and replays the journal when a
> new provider attaches to the same path. On attach, an incomplete final
> record is copied to ``<journal>.tail`` and removed only when every earlier
> newline-terminated record validates. Earlier corruption is refused.
> Guarantees:
>   - removal subtracts ONE stored fact and journals one `retract(Fact)` for
>     it, the same multiset law a native space obeys, so a provider swap does
>     not change what `remove-atom` means
>     [tested: test_a_persistent_space_subtracts_one_fact_like_a_native_one;
>     commit=dcfc20be4933c19140ccb5759291401d13058301]
>   - constructor failure releases its path claim and any unattached reusable
>     module [tested: test_constructor_failure_releases_path_and_unattached_module;
>     commit=dcfc20be4933c19140ccb5759291401d13058301]
>   - terminal-tail recovery syncs the backup file and its directory before
>     truncating the journal
>     [tested: test_tail_backup_is_durable_before_truncation; commit=dcfc20be4933c19140ccb5759291401d13058301]
>   - EVERY proper prefix of a record classifies as an incomplete tail and is
>     recovered, and a tail carrying its terminating full stop is refused
>     instead of truncated [measured: 7 of 18 truncation points were refused;
>     command=pytest tests/test_persistent.py -q -p no:benchmark;
>     fixture=all prefixes of assert(edge(a,b)).; commit=dcfc20be4933c19140ccb5759291401d13058301] [tested:
>     test_every_truncation_point_of_the_torn_tail_classifies,
>     test_a_terminated_record_is_refused_rather_than_truncated;
>     commit=dcfc20be4933c19140ccb5759291401d13058301]
> Owns resources:
>   - PersistentFactSpace owns one process path claim, one generated module,
>     and one journal attachment until close or constructor rollback
>     [tested: test_detached_modules_are_reused_without_weakening_path_claims;
>     commit=dcfc20be4933c19140ccb5759291401d13058301]
> Guarded by:
>   - _STATE_LOCK protects active paths and the module pool; each provider's
>     _call_lock serializes journal operations
>     [tested: test_detached_modules_are_reused_without_weakening_path_claims;
>     commit=dcfc20be4933c19140ccb5759291401d13058301]
> Open Obligations:
>   To Do: None
>   Hacks: None
>   Future Enhancements: None.

The entries below reproduce the source signatures and docstrings.

## `PersistentFactSpace`

```python
class PersistentFactSpace(SpaceProvider):
```

> A fixed-schema fact space backed by an append-only text journal.
>
> Facts are limited to the declared heads and arities. Every argument must
> be a native value carried by PeTTa's wire: a number, symbol, string, or
> boolean. Live Python objects and nested expressions are refused because
> they cannot survive journal replay.
>
> The journal is schema-bound. Generated memory mutations run inside
> transaction/1, so an append error rolls them back. Journal I/O itself is
> not transactional, so any updater error makes the provider refuse later
> writes until it is closed, checked, and reopened. Compound writes and
> matching reads use a mutex unique to the generated Prolog module. Only one
> process may own a journal path at a time. This class also refuses a second
> live attachment to the same path within the current process.
>
> `sync` picks the write-sync mode, performance by default: "none" (the
> default) buffers journal writes, the fastest mode; a clean close()
> flushes everything, and only a crash loses the buffered tail. When a
> write matters mid-run, flush() is the on-demand checkpoint: it pushes
> the tail to disk right then, whatever the mode. The standing modes
> are the safety ladder: "flush" flushes the stream after every write,
> so facts survive the death of this process; "close" also closes the
> file after every write, the slowest mode, whose extra promise is a
> journal always consistent for external editing. Measured on this
> machine at 3000 adds: none 169k adds/s, flush 166k, close 86k, so
> per-write crash safety costs about two percent and the always-closed
> journal costs half.

### `PersistentFactSpace.match`

```python
def match(self, pattern: Atom) -> Iterator[Atom]:
```

No docstring is defined.

### `PersistentFactSpace.atoms`

```python
def atoms(self) -> Iterator[Atom]:
```

No docstring is defined.

### `PersistentFactSpace.add`

```python
def add(self, atom: Atom) -> None:
```

No docstring is defined.

### `PersistentFactSpace.remove`

```python
def remove(self, atom: Atom) -> bool:
```

No docstring is defined.

### `PersistentFactSpace.clear`

```python
def clear(self) -> None:
```

> Remove every stored fact while keeping the declared schema.

### `PersistentFactSpace.sync`

```python
def sync(self) -> None:
```

> Reload journal changes that are safe to apply to this attachment.

### `PersistentFactSpace.flush`

```python
def flush(self) -> None:
```

> Push buffered journal writes to disk right now, whatever the
> sync mode: the on-demand checkpoint for the fast default.

### `PersistentFactSpace.compact`

```python
def compact(self) -> None:
```

> Ask library(persistency) to garbage-collect obsolete actions.

### `PersistentFactSpace.close`

```python
def close(self) -> None:
```

> Detach the journal, clear its facts, and return its module for reuse.
