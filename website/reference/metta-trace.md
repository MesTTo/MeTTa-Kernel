# `metta.trace`

Source: `extensions/python/metta/_trace.py`.

> The reduction trace as Python objects. m.trace(term) runs
> that term with every compiled MeTTa function wrapped engine-side, and
> answers TraceEvent records: a call carries the term entering reduction
> at its nesting depth, the matching exit carries the answer, and a call
> with no exit is a reduction that failed. Tracing wraps and unwraps per
> run, so it costs nothing when off; what is traced executes for real,
> writes included, exactly like a run.

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
