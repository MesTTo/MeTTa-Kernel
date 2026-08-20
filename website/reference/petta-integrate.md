# `petta.integrate`

Source: `bindings/python/petta/integrate.py`.

> Purpose: the interface any Python library implements to work deeply with
> PeTTa, and the toolkit that makes implementing it a page of code rather than
> a project. An integration is a module with install_petta(m), an object with
> name and install(m), or an entry point in the petta.integrations group; the
> toolkit covers the capabilities an integration is made of: bulk operations
> from a module, an instance's methods as operations, protocol-based typing
> and printing, two-way value translation, structure reflected into facts,
> spaces backed by the library's own storage, and reflective py-field
> reasoning over any object.
> Assumes:
>   - inspect.signature reports unsupported callables with TypeError and
>     unavailable signatures with ValueError [source 2026-08-14:
>     https://docs.python.org/3/library/inspect.html#inspect.signature]
> Guarantees:
>   - protocol type, formatter, conversion, and reflector registrations have
>     exact removal counterparts [tested
>     test_protocol_and_reflector_registrations_can_be_removed,
>     test_type_registration_can_be_removed_and_its_name_reclaimed]
>   - installation idempotence ends with the lifetime of its space [tested
>     test_dropped_space_name_reinstalls_integrations]
>   - discovery refuses duplicate names, missing dependencies, and named
>     dependency cycles, and installs acyclic entries in topological order
>     [tested: test_each_remaining_annotation_shape_refuses_or_carries;
>      commit=ff4ac16f07a6e373e79ed0eae0a4c2d64cb92550]
> Owns:
>   - _INSTALLED retains one target per live space and integration name;
>     MeTTa.drop releases every record for that space [tested
>     test_dropped_space_name_reinstalls_integrations]
> Guarded by:
>   - _INSTALLED_LOCK serializes integration installation and invalidation
>     [tested test_dropped_space_name_reinstalls_integrations]
>   - _REFLECTOR_LOCK protects reflector registrations [tested
>     test_protocol_and_reflector_registrations_can_be_removed]
> Open Obligations:
>   To Do: None
>   Hacks: None
>   Future Enhancements: None

The entries below reproduce the source signatures and docstrings.

## `Integration`

```python
class Integration(Protocol):
```

> What integrate() accepts beyond a module: a name and an installer.

### `Integration.install`

```python
def install(self, m) -> None:
```

No docstring is defined.

## `integrate`

```python
def integrate(m, target: Any) -> str:
```

> Install an integration on a space, idempotently per (space, name).
>
> target may be: a module (or dotted module name) defining install_petta(m),
> an Integration object, or the name of an installed package's entry point
> in the petta.integrations group. Returns the integration's name.
>
> Idempotence is per SPACE, because equations and facts an installer
> writes land in the space it was handed: installing into a second space
> installs again there. Operations are process-wide either way, and
> re-registering them is the registry's ordinary replacement.

## `installed`

```python
def installed() -> dict[tuple[str, str], Any]:
```

> (space, integration name) -> the installed target.

## `entry_points`

```python
def entry_points(group: str = SPACES_GROUP) -> dict[str, metadata.EntryPoint]:
```

> The names installed packages advertise for one group, UNLOADED:
> asking imports nothing and registers nothing, so discovery is free to
> call and the app keeps deciding what loads.

## `load_entry_point`

```python
def load_entry_point(name: str, /, *args: Any, group: str = SPACES_GROUP, **kwargs: Any) -> Any:
```

> Load one advertised entry point by name, calling a callable target
> with the given arguments, the factory contract:
>
>     m.register_space(integrate.load_entry_point("duck"), "&duck")
>     m.register_library_path(
>         integrate.load_entry_point("nars", group=integrate.LIBRARIES_GROUP),
>         "nars",
>     )
>
> A petta.spaces target is a provider class or factory; a
> petta.libraries target answers the directory of sources the package
> ships. A non-callable target answers as-is, the module-level-instance
> form, and refuses arguments it cannot take. An unknown name refuses,
> listing what IS installed, so a typo reads as one.

## `discover`

```python
def discover(m) -> list[str]:
```

> Install advertised integrations after satisfying PETTA_REQUIRES.

## `module_ops`

```python
def module_ops(
    m,
    module: Any,
    names: Iterable[str] | None = None,
    *,
    prefix: str | None = None,
    rename: dict[str, str] | None = None,
    raw: bool = True,
    typed: bool = False,
) -> list[str]:
```

> Selected callables of any module as MeTTa functions, in one call.
>
>     petta.integrate.module_ops(m, math, ["sqrt", "floor", "gcd"])
>     m.run("!(sqrt 16.0)")
>
> Underscores read as hyphens, a prefix namespaces the lot, and rename
> overrides per function. Callables only; anything else named raises.

## `wrap_callable`

```python
def wrap_callable(m, name: str, target: Callable, *, arities: list[int] | None = None):
```

> One callable, any callable, as a MeTTa function under a chosen name.
>
> The instance behind a bound method or a callable object crosses nothing:
> the closure holds it, so identity and state stay Python's. The served
> arities are the signature's own reachable positional counts; a callable
> whose signature cannot be inspected, or that is variadic, names its
> call forms with arities=[...] rather than being served invented ones.

## `wrap_object`

```python
def wrap_object(m, name: str, obj: Any, methods: dict[str, str] | Iterable[str]) -> Any:
```

> An instance's methods as operations: (name-method args...).
>
>     petta.integrate.wrap_object(m, "db", connection,
>                                 {"execute": "db-query!", "close": "db-close!"})
>
> methods maps Python method names to MeTTa spellings, or lists names to
> mangle by the usual rule. A method returning None answers True, the
> engine's own convention for an effectful builtin, since a Python method
> returning None almost always is one. The object itself also lands in the
> space as (wrapped name &lt;obj>), so rules can enumerate what is wrapped.

## `register_object_type`

```python
def register_object_type(predicate: Callable[[Any], bool], name: str) -> None:
```

> A protocol as a type: objects satisfying predicate get name as an
> additional get-type candidate, beyond their own classes.
>
>     register_object_type(lambda x: hasattr(x, "__dlpack__"), "DLTensor")

## `unregister_object_type`

```python
def unregister_object_type(predicate: Callable[[Any], bool], name: str) -> None:
```

> Remove the latest exact protocol type registration.

## `register_repr`

```python
def register_repr(predicate: Callable[[Any], bool], formatter: Callable[[Any], str]) -> None:
```

> How objects satisfying a protocol print when stored as atoms.

## `unregister_repr`

```python
def unregister_repr(predicate: Callable[[Any], bool], formatter: Callable[[Any], str]) -> None:
```

> Remove the latest exact protocol formatter registration.

## `register_reflector`

```python
def register_reflector(
    predicate: Callable[[Any], bool],
    fn: Callable[[Any, str, Any], int],
) -> None:
```

> fn(m, name, obj) writes facts about obj into m and returns the count.

## `unregister_reflector`

```python
def unregister_reflector(
    predicate: Callable[[Any], bool],
    fn: Callable[[Any, str, Any], int],
) -> None:
```

> Remove the latest reflector matching both callables exactly.

## `reflect`

```python
def reflect(m, name: str, obj: Any) -> int:
```

> Lower an object's structure into facts, by whichever reflector claims it.

## `facts`

```python
def facts(m, atoms: Iterable[Any]) -> int:
```

> Bulk facts into a space; returns how many.

## `install_reflection_ops`

```python
def install_reflection_ops(m) -> list[str]:
```

> (py-attr $obj $name) and the two-mode (py-field $obj $name $?): the
> smallest thing that turns calling Python into reasoning about a Python
> object. With the field name bound, py-field is getattr; unbound, it
> enumerates the object's fields and yields (name value) pairs, one answer
> per field, which is the mode a function cannot offer and a relation can.
