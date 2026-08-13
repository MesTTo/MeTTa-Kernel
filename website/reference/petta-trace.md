# `petta.trace`

Source: `python/petta/trace.py`.

> Purpose: the reduction trace as Python objects. m.trace(source) runs
> source with every compiled MeTTa function wrapped engine-side, and
> answers TraceEvent records: a call carries the term entering reduction
> at its nesting depth, the matching exit carries the answer, and a call
> with no exit is a reduction that failed. Tracing wraps and unwraps per
> run, so it costs nothing when off; the source executes for real, writes
> included, exactly like a run.
> Open Obligations:
>   To Do: None
>   Hacks: None
>   Future Enhancements: None

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
def trace(space, source: str) -> list[TraceEvent]:
```

> Run source in this space under the engine's reduction trace.
