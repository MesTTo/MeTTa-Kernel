# `metta.trace`

Source: `extensions/python/metta/_trace.py`.

> Purpose: the reduction trace as Python objects. m.trace(term) runs
> that term with every compiled MeTTa function wrapped engine-side, and
> answers TraceEvent records: a call carries the term entering reduction
> at its nesting depth, the matching exit carries the answer, and a call
> with no exit is a reduction that failed. Tracing wraps and unwraps per
> run, so it costs nothing when off; what is traced executes for real,
> writes included, exactly like a run.
> Guarantees:
>   - a term and the source that spells it trace identically, so the one
>     door that shows a reduction takes the argument every other door
>     takes [tested test_trace_takes_the_term_every_other_door_takes]
>   - traced source keeps run()'s real-write semantics while inheriting the
>     same speculative execution fence [tested:
>     test_every_public_execution_door_honours_speculative_policy;
>     commit=1262dd20ada9d5c799d9bdc4bdf5d2b859ca7a98]
> Open Obligations:
>   To Do: None
>   Hacks: None
>   Future Enhancements: None.

The entries below reproduce the source signatures and docstrings.

## `TraceEvent`

```python
class TraceEvent:
```

> One step: depth is the nesting level, kind is call or exit, term
> is what reduced, answer carries the exit's result and stays None on
> a call.

## `trace`

```python
def trace(space, source: Atom | str, max_events: int = 1000000) -> list[TraceEvent]:
```

> Run a term, or source, in this space under the engine's reduction trace.
>
> max_events bounds the recording: past it the trace raises instead
> of accumulating without limit, the same shape as the timeout and
> inference bounds elsewhere.
