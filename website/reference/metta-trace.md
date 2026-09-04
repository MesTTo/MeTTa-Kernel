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

## `Trace`

```python
class Trace(list):
```

> The events, and whether the bound stopped the recording early.
>
> A list, because that is what a trace IS and every consumer wants to
> iterate it, index it and take its length. `truncated` is the one thing a
> plain list cannot say, and it has to be said: the bound is a COUNT and the
> memory an event costs is its term's size, so the honest answer to "trace
> this if it is cheap" is a prefix that admits to being one.

## `trace`

```python
def trace(
    space,
    source: Atom | str,
    max_events: int | None = None,
    *,
    timeout: float | None = None,
    inferences: int | None = None,
) -> Trace:
```

> Run a term, or source, in this space under the engine's reduction trace.
>
> max_events bounds the RECORDING. Past it the recording STOPS and the
> result's `truncated` is True, so what was already recorded is answered
> rather than discarded: through 2026-09-03 the bound raised, which threw
> away every event and charged the full memory of the bound for no answer.
>
> timeout and inferences bound the RUN, the same pair every evaluating door
> takes and the same scoped `m.limits()` default behind them. The two bounds
> are independent because they stop different things: a program can retire
> millions of inferences inside a handful of recorded events, and through
> 0.7.1 this door passed no limits at all, so `with m.limits(inferences=100)`
> let a traced program run 209,322 of them to completion
> .
