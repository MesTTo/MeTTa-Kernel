# `petta.das`

Source: `python/petta/das.py`.

> Purpose: first-class client for the Distributed Atomspace (DAS): the
> command-router protocol, HTTP and WebSocket with JSON both ways. query()
> streams STI-ordered answers back as petta atoms, DAS's MeTTa text read
> straight into terms and petta's $-variables rendered as DAS's %-sigil;
> count() runs the same query in the router's count mode and answers the
> server's own total; cancel() stops an execution mid-stream; execute()
> passes any router command through (evolution, link_creation, context),
> parameters validated server-side. DASSpace registers a connection as a
> read-only space provider, so match and joins over DAS answers run the
> engine's own unification. Loading knowledge is das-cli's job, and every
> write path says so instead of pretending.
> Open Obligations:
>   To Do: None
>   Hacks: None
>   Future Enhancements: None

The entries below reproduce the source signatures and docstrings.

## `DASError`

```python
class DASError(PettaError):
```

> A DAS request failed, or an answer could not be read.

## `DASAnswer`

```python
class DASAnswer:
```

> One STI-ordered answer: variable bindings as petta atoms, the
> matched expressions themselves, and the attention numbers.

## `DAS`

```python
class DAS:
```

> A connection to a DAS command router.
>
> das = petta.das.DAS("http://localhost:40009")
> das.ping()
> for answer in das.query(S.Similarity(S['"human"'], V.x)):
>     print(answer["x"], answer.importance)

### `DAS.ping`

```python
def ping(self) -> bool:
```

> Whether a command router answers at this url.

### `DAS.execute`

```python
def execute(self, command: str, params: dict) -> str:
```

> Start any router command and answer its execution id. The
> server validates parameters; unknown ones refuse loudly there.

### `DAS.status`

```python
def status(self, execution_id: str) -> dict:
```

No docstring is defined.

### `DAS.cancel`

```python
def cancel(self, execution_id: str) -> None:
```

No docstring is defined.

### `DAS.query`

```python
def query(self, *patterns: Any, max_answers: int | None = None,
          unique: bool = False, **extra: Any) -> list[DASAnswer]:
```

> Run a pattern query and collect its STI-ordered answers.
> Several patterns compose as (and ...), DAS's own query tree, so
> the conjunction runs server-side. Extra keyword arguments pass
> through to the router's query parameters verbatim.

### `DAS.count`

```python
def count(self, *patterns: Any, **extra: Any) -> int:
```

> The router's count mode: the server's own total, no answers
> shipped.

## `DASSpace`

```python
class DASSpace(SpaceProvider):
```

> A DAS connection as a read-only petta space: match answers the
> expressions DAS matched, and the engine unifies them, so joins mix
> DAS candidates with native facts. Knowledge loads through das-cli;
> the write paths say so.

### `DASSpace.match`

```python
def match(self, pattern: Atom):
```

No docstring is defined.

### `DASSpace.add`

```python
def add(self, atom: Atom) -> None:
```

No docstring is defined.

### `DASSpace.remove`

```python
def remove(self, atom: Atom) -> bool:
```

No docstring is defined.
