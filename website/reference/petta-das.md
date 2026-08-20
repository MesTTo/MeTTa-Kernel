# `petta.das`

Source: `bindings/python/petta/das.py`.

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
>
> Two router dialects exist in the wild and both are spoken. Current
> sources take an enveloped {"command", "params"} request, MeTTa-text
> queries, and enveloped events; the deployed 1.2.0-rc images take a flat
> {"command_type", "command_text"} request, token-vector queries
> (LINK_TEMPLATE Expression ...), flat events whose answer chunks ride
> under "data", and answer handles without MeTTa text, verified against a
> live das-cli deployment. The dialect negotiates once per connection off
> the server's own 400 naming the missing legacy fields; anything else
> stays loud.
> Guarantees:
>   - DAS refuses non-HTTP endpoint URLs during construction [tested
>     test_das_refuses_non_http_urls]
>   - query and count return data only after a completed terminal event
>     and close the event stream before returning [tested
>     test_query_and_count_require_completed_terminal_event,
>     test_completed_query_closes_its_event_stream]
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

## `is_transport_failure`

```python
def is_transport_failure(error: BaseException) -> bool:
```

> Whether this DASError is the router being ABSENT rather than wrong.
>
> The trichotomy this draws became the seam's own error vocabulary and
> now lives in petta.errors; this name stays as the DAS spelling of it.
> A caller retries or gives up on a transport failure; a protocol error,
> a bad status or a malformed answer is the router being wrong and is
> not retryable, which is why this is not simply "did anything go wrong".

## `DASAnswer`

```python
class DASAnswer:
```

> One STI-ordered answer: variable bindings as petta atoms, the
> matched expressions themselves, the raw atom handles, and the
> attention numbers. A router that maps answers back to MeTTa text
> binds real terms; the deployed legacy routers answer handles only,
> which arrive as string values under the same names.

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

> Start any router command and answer its execution id, in the
> current sources' enveloped shape. The server validates
> parameters; unknown ones refuse loudly there. Legacy routers
> serve query() and count(), which negotiate the dialect.

### `DAS.status`

```python
def status(self, execution_id: str) -> dict:
```

> Return the router status for one execution.

### `DAS.cancel`

```python
def cancel(self, execution_id: str) -> None:
```

> Ask the router to cancel one execution.

### `DAS.query`

```python
def query(
    self,
    *patterns: Any,
    max_answers: int | None = None,
    unique: bool = False,
    **extra: Any,
) -> list[DASAnswer]:
```

> Run a pattern query and collect its STI-ordered answers.
> Several patterns compose as one server-side conjunction, DAS's
> own query tree. Extra keyword arguments pass through to the
> router's query parameters verbatim.

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

### `DASSpace.can_run`

```python
def can_run(self, capability: str, /, **request: Any) -> bool:
```

No docstring is defined.

### `DASSpace.refusal`

```python
def refusal(self, capability: str, /, **_request: Any) -> str | None:
```

> The one place this rule is written.
>
> It used to be written twice and only the worse spelling was
> reachable: _require_provider consults can_run BEFORE calling add, so
> the DASError bodies below never ran, and the caller was told "its
> DASSpace provider does not implement add", which is false on its face
> and says nothing about what to do instead.

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
