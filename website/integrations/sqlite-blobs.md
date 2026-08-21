# SQLite BLOB images

The shipped SQLite example derives one provider from `bridge` declarations.
Its `documents.payload` column also shows how the same SQL value can cross a
context boundary as an opaque handle or as a structural MeTTa expression.

`attach_sqlite` declares the default explicitly:

```python
m.declare_image("&crm", "Blob", "opaque")
```

The resulting atom `(image &crm Blob opaque)` lives in `&petta` and has type
`ImageDecl`. Image policy is per type and per context. Another attached SQLite
space can therefore choose `transparent` for `Blob` without changing `&crm`.
The `_` type name supplies a fallback for types a context does not name.

## Read one field without projecting the payload

SQLite returns the binary column as the example's `Blob` object. Under the
opaque image, `TableBridge` carries that object as one grounded handle. A lazy
path runs after the surrounding `document` pattern matches and encodes only
the byte it reaches:

```python
payload = bytes(range(64)) * 4
provider.connection.execute(
    "INSERT INTO documents VALUES (?, ?)",
    ("manual", sqlite3.Binary(payload)),
)

rows = m.space("&crm").query(
    S.document(S.manual, path("data", 17, to=V.byte))
)
assert rows.to_dicts() == [{"byte": 17}]
```

The acceptance test replaces `Blob.__metta__` with a function that raises,
then runs this query. It still answers, proving the complete structural image
was not requested.

## Choose the structural image

Pass `blob_image="transparent"` when attaching a second context:

```python
transparent = attach_sqlite(m, "&archive", blob_image="transparent")
```

The same row then answers with `(Blob 0 1 2 ...)`. The acceptance test measures
both crossings with `space.stats().inferences`, takes the minimum of three
samples for each, and requires the transparent crossing to cost more than the
opaque handle for the same 4,096-byte payload. `auto` delegates the choice to
the standard constant-time size and replayability policy.

See [`petta.tables`](../reference/petta-tables.md) for the generic bridge and
[lazy paths](../reference/petta-paths.md) for attribute and key traversal.
