<!--
Purpose: show lossless projection and reconstruction for Pydantic models.
Guarantees: examples construct atoms through the canonical Expression type.
[tested: npm run docs:build; commit=f88aa8be03cb64cb59d3307515ded8701f418321]
-->

# Pydantic models both ways

PeTTa projects structured Python values into constructor expressions, keeps the declarations that describe their fields, and rebuilds Python objects from those atoms. Pydantic models use the same seam as dataclasses and plain annotated classes.

Start with a model whose fields are a string and a number:

```python
def test_pydantic_models_project_like_dataclasses():
    pydantic = pytest.importorskip("pydantic")

    class Reading(pydantic.BaseModel):
        sensor: str
        value: float

    projected = project(Reading(sensor="t1", value=21.5))
    assert projected.atom == Expression(S.Reading, "t1", 21.5)
    assert "(: Reading (-> String Number Reading))" in set(
        map(str, projected.declarations)
    )
    rebuilt = build(projected.atom, Reading)
    assert isinstance(rebuilt, Reading) and rebuilt.value == 21.5
    # The rebuild runs through the model itself, so validation runs where
    # pydantic runs it: a field refusing its type is pydantic's own error.
    with pytest.raises(pydantic.ValidationError):
        build(Expression(S.Reading, "t1", S.tall), Reading)
```

`project` produces `(Reading "t1" 21.5)` and a constructor declaration. `build` sends the decoded fields back through Pydantic, so Pydantic owns validation on the return path.

Aliases do not replace Python attribute names during rebuilding:

```python
def test_pydantic_alias_fields_rebuild(metta):
    pydantic = pytest.importorskip("pydantic")

    class Wire(pydantic.BaseModel):
        internal: int = pydantic.Field(alias="external")
        model_config = pydantic.ConfigDict(populate_by_name=True)

    projected = project(Wire(external=7))
    rebuilt = build(projected.atom, Wire)
    assert isinstance(rebuilt, Wire) and rebuilt.internal == 7
```

The integration uses Pydantic 2's `model_fields` and `model_validate(..., by_name=True)` APIs. Pydantic is optional and has no PeTTa packaging extra, so install Pydantic separately before using this path.

Projection refuses extra fields because dropping them would make the round trip lossy:

```python
def test_pydantic_extra_fields_are_refused_by_name():
    pydantic = pytest.importorskip("pydantic")

    class ExtraRejectModel(pydantic.BaseModel):
        value: int
        model_config = pydantic.ConfigDict(extra="allow")

    value = ExtraRejectModel(value=1, retained=2, also_retained=3)
    with pytest.raises(
        TypeError, match=r"extra fields would be lost \(also_retained, retained\)"
    ):
        project(value)
```

Once projected, the constructor fields are ordinary MeTTa structure. The Python-objects example queries one field and rebuilds the original class:

```python
projected = project(Robot("R2", Mood.calm))
check("projection", str(projected.atom), '(Robot "R2" calm)')
m.add(*projected.declarations, projected.atom)
m.add(project(Robot("HAL", Mood.stormy)).atom)

rows = m.match(S.Robot(V.name, S.stormy))
check("match on parts", str(rows[0].name), '"HAL"')

rebuilt = build(projected.atom)
check("rebuild", isinstance(rebuilt, Robot) and rebuilt.mood, Mood.calm)
```

Continue with [Python functions as MeTTa functions](../guide/python-functions), [`project`](../reference/metta-convert#project), [`build`](../reference/metta-convert#build), and [`Rows.build`](../guide/run-query).
