<!--
Purpose: Record the complete narrow-core surface disposition and the mechanical rewrite map for the example twins and follow-on tracks.
Assumes: Baseline inventories are taken from a142938d563aef099878c49daaeb3d33939bbc49, before the Fork 4 surface collapse. [source: git show a142938d563aef099878c49daaeb3d33939bbc49:bindings/python/petta; commit=f88aa8be03cb64cb59d3307515ded8701f418321]
Guarantees: Every one of the baseline 90 public MeTTa attributes and 152 public petta names has exactly one disposition below. [measured: 90 numbered method rows and 152 grouped root names; command=$CHECK_PY inventory check; fixture=ai-narrow-core-renames.md; commit=f88aa8be03cb64cb59d3307515ded8701f418321]
Open Obligations:
  To Do: Rewrite the protected twin corpus from the table below in its sibling track. [measured: 448 findings over 204 twinned examples; command=$CHECK_PY bindings/python/tools/twin_coverage.py; fixture=unmodified bindings/python/tests/twins; commit=f88aa8be03cb64cb59d3307515ded8701f418321]
  Hacks: None.
  Future Enhancements: Regenerate the protected `llms.txt` after the sibling surface tracks settle. [measured: 16 stale claims; command=GATE_ONLY=1 sh check.sh; fixture=CHECK_PY is the required project interpreter and llms.txt is unmodified; commit=f88aa8be03cb64cb59d3307515ded8701f418321]
-->

# Narrow-core surface ledger

This ledger is the handoff for Fork 4. It separates two changes that history can otherwise make look like one:

1. The implementation decomposition was completed before this fork. Query objects, definitions, execution, persistence, eager query decoding, and diagnostics were extracted by `4bb2076f0c9ccb6c667587673a05e82c05ac1eea`, `b0f277e10f69a40d84680d44404fd34bf696e4b7`, `9f717225fddf4da9f2dfe018fea2570495a447a6`, `20d85944d9acd77da75dbee6ffd4a2552431a74c`, `ef13979ef0839b06c274d146765bcad2cf95b013`, and `fba09900057318c369c90310d6f75ab28b558e43` respectively.
2. Fork 4 supersedes the compatibility-facade decision retained by those commits. It narrows `MeTTa`, puts storage and query verbs on `Space`, moves specialist names into lazy satellites, and deletes superseded doors without aliases.

The inventories below are pinned to `a142938d563aef099878c49daaeb3d33939bbc49`; the final measurements are from the completed Fork 4 functional tree.

## Twin-visible rewrite table

The table is mechanical guidance for the separate twin rewrite. “Removed” means there is deliberately no compatibility alias.

| Old spelling or use | New spelling or use | Reason |
|---|---|---|
| `MeTTa()` when a space handle is required | `MeTTa().self` | `MeTTa` is now the runtime context; `.self` is its default `Space` handle. |
| `MeTTa("&name")` | `MeTTa().space("&name")` | Named-space selection belongs to the context, not context construction. |
| `m.space_name` | `m.name` | A handle uses Python's ordinary short name property. |
| `m.space(name)` on a space handle | `ctx.space(name)` or `petta.space(name)` | Space lookup and creation moved to the context/factory door. |
| `m.new_space(name)` | `petta.space(name)` or `ctx.space(name)` | One space-creation door replaces the redundant constructor verb. |
| `m.new_space()` / `fresh_space()` | `petta.space()` | An omitted name requests a fresh space through the same door. |
| `connect(...)` | `petta.attach(name, backing, ...)` | Attachment and connection share one backing-directed entry point. |
| `m.register_space(provider, name)` | `petta.attach(name, provider)` | Provider instances are a `space` backing, not an engine registration API. |
| `m.unregister_space(name)` | `petta.space(name).drop()` | The owned handle performs its own lifecycle verb. |
| `petta.das...` | `petta.space(backing=url, ...)` | DAS was a second remote-space door and is deleted. |
| `petta.persistent...` | `petta.space(journal=...)` | Persistence is a backing option; the public module door is deleted. |
| `m.add_table(head, data)` | `petta.tables.add(m, head, data)` | Bulk tabular ingestion belongs to the lazy tables satellite. |
| `m.count()` | `len(m)` | Space handles implement Python's container protocol. |
| `m.register_op(...)` | `m.op(...)` or `@m.op(...)` | `op` is the single short grounding door. |
| `m.unregister(...)` | `m.unregister_op(...)` | The ambiguous alias is deleted; the surviving verb names its subject. |
| `m.run(source, using={...})` | `with m.bind(**values): m.run(source)` | Ambient bindings are scoped by a context manager rather than a special run keyword. |
| `m.one(...)` | answer cardinality API from Track 1 | Scalar answer selection is removed from the space facade; no alias is retained. |
| `m.first(...)` | answer cardinality API from Track 1 | Scalar answer selection is removed from the space facade; no alias is retained. |
| `m.stream(...)` | answer iteration API from Track 1 | Iteration belongs to the answer object; the old method is private only for internals. |
| `m.disassemble(name)` | removed; internal diagnostics use `_disassemble` | Engine disassembly is not a public storage/query primitive. |
| `capture=` / `residuals=` / `atomic=` run options | `with m.capture()`, answer residuals, or `with m.atomic()` | Execution policy is represented by scopes and answer objects, not keyword modes. |
| `m.save(space, path)` | `kb.save(path)` | Persistence is a verb on the handle being saved. |
| `object_view(...)` | `view(...)` | The shorter protocol name replaces the prose helper. |
| `parse_all(source)` | `petta.forms(source)` | The collection door names the result, while `parse` continues to parse one form. |
| `DECLINE` / `Decline` | `NotReducible` | One exception-shaped refusal type replaces the sentinel/type pair. |
| `Expr` | `Expression` | Public atom types use complete Python class names. |
| `Gnd` | `Grounded` | Public atom types use complete Python class names. |
| `Sym` | `Symbol` | Public atom types use complete Python class names. |
| `Var` | `Variable` | Public atom types use complete Python class names. |
| `MettaName` | `Symbol` | A MeTTa name is represented by the ordinary symbol type. |
| `SpaceName` | `Handle` | A space reference is an executable grounded handle, not an opaque name alias. |
| `REFLECTION_SPACE` | `petta.reflection` | The public value is a handle, not a string constant. |
| `default_engine()` | `petta.engine()` | The process context has one concise public accessor. |
| `backend_info()` | `petta.engine().info()` | Engine metadata is queried from the context it describes. |
| `val(x)` | `ground(x)` or `G(x)` | One construction verb owns Python-to-atom grounding. |
| top-level `encode(x)` for construction | `ground(x)` or `G(x)` | Atom construction is distinct from transport encoding. |
| top-level `encode(x)` for transport | `petta.wire.encode(x)` | Wire transport lives in the lazy wire satellite. |
| top-level `decode(x)` | `petta.wire.decode(x)` | Wire transport lives in the lazy wire satellite. |
| top-level `atom_from_wire(x)` | `petta.wire.atom_from_wire(x)` | Wire transport lives in the lazy wire satellite. |
| `expr(...)` | `Expression(...)` or the ruled factory family | The abbreviated factory is deleted with the abbreviated type. |
| `sym(...)` | `S[...]` | Symbols use the existing namespace factory. |
| `var(...)` | `V[...]` | Variables use the existing namespace factory. |
| `alpha_eq(a, b)` | `a.alpha_eq(b)` | Equality-like behavior belongs to the atom. |
| `is_ground(a)` | `not a.vars` | Groundness is the absence of variables. |
| `map_atoms(a, f)` | `a.map(f)` | Structural traversal belongs to the atom. |
| `variables(a)` | `a.vars` | Variable discovery is an atom property. |
| `pretty(a)` | `repr(a)` | Python's representation protocol is the display door. |
| `bridge(...)` | a declaration/fold or the `+=` pipe | The callable bridge duplicated composition mechanisms. |
| root `cast(...)` | `kb.cast(...)` | Casting depends on the target space and its declarations. |
| root `fn(name)` | `kb.fn.<name>` or the current handle function namespace | Function resolution depends on a space handle. |
| `register_object_repr_protocol(...)` | `petta.integrate.register_repr(...)` | The long protocol-prose name is deleted in favor of the existing integration registry. |
| `unregister_object_repr_protocol(...)` | unregister through `petta.integrate` | Representation integration has one owning satellite; no root alias remains. |
| root `AlgebraDeclarationError`, `AlgebraEvaluation`, `AlgebraEvaluationError`, `AlgebraLawError`, `AlgebraOperationError`, `AlgebraRequirementError`, `Amplitude`, `DeclaredAlgebra`, `LinearEvidenceError`, `PlanDecision`, `RateDeclarationError`, `TaggedAnswer`, `tagged_fact`, `tagged_rule` | the same member under `petta.algebra` | Algebra is a lazy specialist surface. |
| root `AssertionFailure`, `CompileError`, `EngineError`, `InferenceLimitError`, `Interrupted`, `MettaOperationError`, `MettaResultError`, `MettaSyntaxError`, `ResourceLimitError`, `SourceNotFound`, `SpaceCapabilityError`, `StrictError`, `SubscriberError`, `TimeLimitError` | the same class under `petta.errors` | Only `PettaError` remains a root headline. |
| root `Adder`, `Clearer`, `CustomMatch`, `Enumerable`, `Matcher`, `Remover` | the same protocol under `petta.foreign` | Provider protocols live with foreign-space integration. |
| root `Event`, `EventStream`, `Fold`, `Subscription` | `petta.events.*` or `petta.subscribe.Subscription` | Event machinery is a lazy satellite surface. |
| root `Builtin`, `Derivation`, `Fact`, `Step`, `Truncated` | the same type under `petta.derivation` | Proof details are loaded only when requested. |
| root `Attr`, `Key`, `Path`, `path` | the same member under `petta.paths` | Path-specific names no longer crowd or confuse the root. |
| root `DefinitionFacts`, `SourceSpan` | the defining module | Definition implementation details are not root constructors. |
| root `CastError` | `petta.casting.CastError` | Casting details belong to the lazy casting satellite. |
| root `Boot` | `petta.manifest.Boot` | Manifest details belong to the lazy manifest satellite; root `boot` remains. |
| root `SaveFormat` | `petta.vocabularies.SaveFormat` | Persistence vocabulary details are specialist names. |
| root `engine_thread` | `petta.parallel.engine_thread` | Thread controls belong to the parallel satellite. |
| root `OPERATOR_LOWERINGS`, `OperatorLowering`, `order_key` | the atom specialist module | Atom conversion policy is not part of the narrow root. |
| root `register_object_repr`, `unregister_object_repr` | `petta.integrate.register_repr` and its integration counterpart | Representation registration converges on the integration satellite. |
| root `Row`, `Rows` | removed from the root; Track 1 owns the answer-shape replacement | Query result internals are not root constructors. |
| root `Cursor`, `EngineProfile`, `Prepared` | returned/internal handle types | Callers receive these values but do not construct them from the root. |
| advertised `petta.janus` | removed from `dir(petta)` and `__all__`; retained only as hidden `python.petta` wrapper state | Upstream's 81-line wrapper accesses the state directly, but it is not a PeTTa-library headline. |
| leaked root module attributes `answer`, `atoms`, `define`, `errors`, `ops`, `results` | import the concrete submodule explicitly | Core implementation modules are not advertised root exports. |
| leaked root names `functools`, `importlib`, `logging`, `sys` | removed | These were accidental imports, never APIs. |

## All 90 baseline `MeTTa` public attributes

The baseline count is 88 public methods/properties plus the public aliases `op` and `unregister`. Every row below assigns one final owner.

| # | Baseline name | Disposition | Final owner or replacement |
|---:|---|---|---|
| 1 | `space_name` | Move and rename to handle | `Space.name` |
| 2 | `space` | Keep as context primitive | `MeTTa.space(...)`; the old handle-to-handle use is gone |
| 3 | `space_names` | Move to handle | `Space.space_names()` |
| 4 | `new_space` | Delete public door; keep implementation private | `petta.space(...)`, `MeTTa.space(...)`, internal `Space._new_space(...)` |
| 5 | `drop` | Move to handle | `Space.drop()` |
| 6 | `run` | Move to handle | `Space.run(...)` |
| 7 | `profile` | Move to handle | `Space.profile(...)` |
| 8 | `profile_extension` | Move to handle | `Space.profile_extension(...)` |
| 9 | `save` | Move to handle | `Space.save(path, ...)` |
| 10 | `load` | Move to handle | `Space.load(path, ...)` |
| 11 | `parse` | Move to handle/root primitive | `Space.parse(...)` and root `parse(...)` |
| 12 | `register_token` | Move to handle | `Space.register_token(...)` |
| 13 | `unregister_token` | Move to handle | `Space.unregister_token(...)` |
| 14 | `add` | Move to handle primitive | `Space.add(...)` and container `+=` |
| 15 | `add_table` | Move to lazy helper | `petta.tables.add(space, head, data)` |
| 16 | `remove` | Move to handle primitive | `Space.remove(...)` and container `-=` |
| 17 | `atoms` | Move to handle | `Space.atoms()` and iteration |
| 18 | `count` | Delete method | `len(space)` |
| 19 | `cast` | Move to handle | `Space.cast(...)` |
| 20 | `trace` | Move to handle and retain context scope | `Space.trace(...)` / `MeTTa.trace(...)`, with lazy trace machinery |
| 21 | `lint` | Move to handle with lazy satellite | `Space.lint()` loads `petta.lint` on demand |
| 22 | `copy` | Move to handle | `Space.copy()` |
| 23 | `digest` | Move to handle | `Space.digest()` |
| 24 | `clear` | Move to handle | `Space.clear()` |
| 25 | `query` | Move to handle primitive unchanged | `Space.query(...)` |
| 26 | `stream` | Delete public method; retain internal helper | Internal `Space._stream(...)`; Track 1 owns public answer iteration |
| 27 | `assuming` | Move to handle | `Space.assuming(...)` |
| 28 | `transaction` | Move to handle and retain context scope | `Space.transaction(...)` / `MeTTa.transaction(...)` |
| 29 | `limits` | Move to handle and retain context scope | `Space.limits(...)` / `MeTTa.limits(...)` |
| 30 | `capture` | Move to handle and retain context scope | `Space.capture()` / `MeTTa.capture()`; the `capture=` mode is gone |
| 31 | `atomic` | Move to handle and retain context scope | `Space.atomic()` / `MeTTa.atomic()`; the `atomic=` mode is gone |
| 32 | `speculative` | Move to handle and retain context scope | `Space.speculative()` / `MeTTa.speculative()` |
| 33 | `strict` | Move to handle and retain context scope | `Space.strict()` / `MeTTa.strict()` |
| 34 | `batch` | Move to handle | `Space.batch()` |
| 35 | `transactional` | Move to handle | `Space.transactional(...)` |
| 36 | `prepare` | Move to handle | `Space.prepare(...)` |
| 37 | `eval` | Move to handle primitive unchanged | `Space.eval(...)` |
| 38 | `parallel` | Move to handle with lazy satellite | `Space.parallel(...)` loads parallel support on demand |
| 39 | `hyperpose` | Move to handle | `Space.hyperpose(...)` |
| 40 | `pool` | Move to handle with lazy satellite | `Space.pool(...)` loads parallel support on demand |
| 41 | `eval_status` | Move to handle | `Space.eval_status(...)` |
| 42 | `run_status` | Move to handle | `Space.run_status(...)` |
| 43 | `one` | Delete public method; retain internal helper | Internal `Space._one(...)`; Track 1 owns scalar answer selection |
| 44 | `first` | Delete public method; retain internal helper | Internal `Space._first(...)`; Track 1 owns scalar answer selection |
| 45 | `stats` | Move to handle and retain context scope | `Space.stats()` / `MeTTa.stats()` |
| 46 | `register_op` | Rename | `Space.op(...)` / `MeTTa.op(...)` |
| 47 | `unregister_op` | Move to handle and retain context scope | `Space.unregister_op(...)` / `MeTTa.unregister_op(...)` |
| 48 | `op` | Keep as grounding primitive | `Space.op(...)` / `MeTTa.op(...)` is the single registration spelling |
| 49 | `unregister` | Delete alias | Use the explicit `unregister_op(...)` verb |
| 50 | `builtins` | Move to handle | `Space.builtins()` |
| 51 | `is_function` | Move to handle | `Space.is_function(...)` |
| 52 | `is_function_here` | Move to handle | `Space.is_function_here(...)` |
| 53 | `arities` | Move to handle | `Space.arities(...)` |
| 54 | `disassemble` | Delete public method; retain diagnostic privately | Internal `Space._disassemble(...)` |
| 55 | `register_prolog` | Retain on context and move operational use to handle | `MeTTa.register_prolog(...)` / `Space.register_prolog(...)` |
| 56 | `register_foreign_library` | Retain on context and move operational use to handle | `MeTTa.register_foreign_library(...)` / `Space.register_foreign_library(...)`, with lazy foreign support |
| 57 | `register_library_path` | Retain on context and move operational use to handle | `MeTTa.register_library_path(...)` / `Space.register_library_path(...)` |
| 58 | `unregister_prolog` | Retain on context and move operational use to handle | `MeTTa.unregister_prolog(...)` / `Space.unregister_prolog(...)` |
| 59 | `subscribe` | Move to handle with lazy satellite | `Space.subscribe(...)` loads subscription support on demand |
| 60 | `events` | Move to handle with lazy satellite | `Space.events()` loads event support on demand |
| 61 | `prolog` | Retain on context and move operational use to handle | `MeTTa.prolog()` / `Space.prolog()` |
| 62 | `derivation` | Move to handle with lazy satellite | `Space.derivation(...)` loads derivation details on demand |
| 63 | `why` | Move to handle diagnostic | `Space.why(...)` |
| 64 | `define` | Keep as context primitive and handle verb | `MeTTa.define(...)` / `Space.define(...)` |
| 65 | `cache` | Move to handle definition helper | `Space.cache(...)` |
| 66 | `type` | Move to handle definition helper | `Space.type(...)` |
| 67 | `fn` | Move to handle function namespace | `Space.fn(...)` pending the sibling factory-namespace pass |
| 68 | `integrate` | Move to handle with lazy satellite | `Space.integrate(...)` loads `petta.integrate` on demand |
| 69 | `register_space` | Delete public method; retain runtime plumbing privately | `petta.attach(...)` / `MeTTa.space(backing=...)`; internal `Space._register_space(...)` |
| 70 | `unregister_space` | Delete public method; retain runtime plumbing privately | `Space.drop()`; internal `Space._unregister_space(...)` |
| 71 | `declare_handles` | Move to handle unchanged | `Space.declare_handles(...)` |
| 72 | `declare_annotations` | Move to handle unchanged | `Space.declare_annotations(...)` |
| 73 | `declare_algebra` | Move to handle unchanged, lazy algebra implementation | `Space.declare_algebra(...)` |
| 74 | `add_tagged_fact` | Move to handle, lazy algebra implementation | `Space.add_tagged_fact(...)` |
| 75 | `add_tagged_rule` | Move to handle, lazy algebra implementation | `Space.add_tagged_rule(...)` |
| 76 | `declare_image` | Move to handle unchanged | `Space.declare_image(...)` |
| 77 | `evaluate_algebra` | Move to handle, lazy algebra implementation | `Space.evaluate_algebra(...)` |
| 78 | `sample_rates` | Move to handle, lazy algebra implementation | `Space.sample_rates(...)` |
| 79 | `declare_source` | Move to handle unchanged | `Space.declare_source(...)` |
| 80 | `declare_on_error` | Move to handle unchanged | `Space.declare_on_error(...)` |
| 81 | `declare_merge` | Move to handle unchanged | `Space.declare_merge(...)` |
| 82 | `declare_context` | Move to handle unchanged | `Space.declare_context(...)` |
| 83 | `declare_agenda` | Move to handle unchanged | `Space.declare_agenda(...)` |
| 84 | `declare_reaction` | Move to handle unchanged | `Space.declare_reaction(...)` |
| 85 | `declare_admits` | Move to handle unchanged | `Space.declare_admits(...)` |
| 86 | `declare_capacity` | Move to handle unchanged | `Space.declare_capacity(...)` |
| 87 | `declare_writes` | Move to handle unchanged | `Space.declare_writes(...)` |
| 88 | `declare_emits` | Move to handle unchanged | `Space.declare_emits(...)` |
| 89 | `declare_events` | Move to handle unchanged | `Space.declare_events(...)` |
| 90 | `runtime` | Keep on context and expose through handle | `MeTTa.runtime` / `Space.runtime` |

Count check: **90 rows**, matching the baseline public `dir(MeTTa)` count.

## All 152 baseline root names

The groups are mutually exclusive. Their counts sum to **152**.

| Disposition | Count | Baseline names | Final owner |
|---|---:|---|---|
| Keep at root | 26 | `Answer`, `Atom`, `Bindings`, `Config`, `Defined`, `Handle`, `MeTTa`, `PeTTa`, `PettaError`, `S`, `SpaceProvider`, `Undefined`, `V`, `add`, `boot`, `config`, `current_space`, `equation`, `eval`, `parse`, `query`, `record`, `remove`, `rules`, `run`, `unify` | Narrow root; `boot` and `SpaceProvider` may resolve lazily. |
| Direct replacement | 25 | `DECLINE`, `Decline`, `Expr`, `Gnd`, `Sym`, `Var`, `MettaName`, `SpaceName`, `REFLECTION_SPACE`, `default_engine`, `backend_info`, `val`, `encode`, `expr`, `sym`, `var`, `alpha_eq`, `is_ground`, `map_atoms`, `variables`, `pretty`, `bridge`, `cast`, `fn`, `space` | Replaced by the canonical doors in the twin table. Here `space` is the leaked module attribute, replaced by the callable factory. |
| Lazy satellite modules | 21 | `aio`, `algebra`, `arrays`, `casting`, `convert`, `derivation`, `events`, `foreign`, `integrate`, `lint`, `manifest`, `parallel`, `paths`, `remote`, `spaces`, `structures`, `subscribe`, `tables`, `testing`, `trace`, `vocabularies` | Preserve module identity, loaded through module `__getattr__`; add the new `wire` satellite. |
| Algebra members | 14 | `AlgebraDeclarationError`, `AlgebraEvaluation`, `AlgebraEvaluationError`, `AlgebraLawError`, `AlgebraOperationError`, `AlgebraRequirementError`, `Amplitude`, `DeclaredAlgebra`, `LinearEvidenceError`, `PlanDecision`, `RateDeclarationError`, `TaggedAnswer`, `tagged_fact`, `tagged_rule` | `petta.algebra.*`; remove root reexports. |
| Detailed errors | 14 | `AssertionFailure`, `CompileError`, `EngineError`, `InferenceLimitError`, `Interrupted`, `MettaOperationError`, `MettaResultError`, `MettaSyntaxError`, `ResourceLimitError`, `SourceNotFound`, `SpaceCapabilityError`, `StrictError`, `SubscriberError`, `TimeLimitError` | `petta.errors.*`; retain only `PettaError` at root. |
| Provider protocols | 6 | `Adder`, `Clearer`, `CustomMatch`, `Enumerable`, `Matcher`, `Remover` | `petta.foreign.*`; retain lazy root headline `SpaceProvider`. |
| Event types | 4 | `Event`, `EventStream`, `Fold`, `Subscription` | `petta.events.*` and `petta.subscribe.Subscription`. |
| Derivation types | 5 | `Builtin`, `Derivation`, `Fact`, `Step`, `Truncated` | `petta.derivation.*`. |
| Path types | 4 | `Attr`, `Key`, `Path`, `path` | `petta.paths.*`; avoid the `pathlib.Path` collision at root. |
| Definition details | 2 | `DefinitionFacts`, `SourceSpan` | The definition module, not root. |
| Casting detail | 1 | `CastError` | `petta.casting.CastError`. |
| Manifest detail | 1 | `Boot` | `petta.manifest.Boot`; retain only lazy `boot` at root. |
| Vocabulary detail | 1 | `SaveFormat` | `petta.vocabularies.SaveFormat`. |
| Wire functions | 2 | `atom_from_wire`, `decode` | `petta.wire.*`. |
| Parallel detail | 1 | `engine_thread` | `petta.parallel.engine_thread`. |
| Atom specialist surface | 5 | `OPERATOR_LOWERINGS`, `OperatorLowering`, `order_key`, `register_object_repr`, `unregister_object_repr` | Atom specialist/integration modules, not root. Representation registration converges on `petta.integrate.register_repr`. |
| Query sibling surface | 2 | `Row`, `Rows` | Remove root reexports; Track 1 owns their replacement. |
| Internal space result types | 3 | `Cursor`, `EngineProfile`, `Prepared` | Returned/internal handle types, not root constructors. |
| Core-module attribute leaks | 6 | `answer`, `atoms`, `define`, `errors`, `ops`, `results` | Remain importable concrete submodules but disappear from curated `dir(petta)`. |
| Accidental standard-library leaks | 4 | `functools`, `importlib`, `logging`, `sys` | Remove through private imports and exact `__dir__`. |
| Upstream special case | 1 | `janus` | Retain hidden module state for the upstream `python.petta` wrapper; exclude it from `dir(petta)` and `__all__`. |
| Delete module | 1 | `das` | Dissolve into `space(backing=url, ...)`. |
| Delete public module door | 1 | `persistent` | The specific kill wins over the earlier satellite list; persistence is `space(journal=...)`. |
| Delete protocol pair | 2 | `register_object_repr_protocol`, `unregister_object_repr_protocol` | No aliases; `petta.integrate` owns representation registration. |

Count check: `26 + 25 + 21 + 14 + 14 + 6 + 4 + 5 + 4 + 2 + 1 + 1 + 1 + 2 + 1 + 5 + 2 + 3 + 6 + 4 + 1 + 1 + 1 + 2 = 152`.

The final root also advertises canonical replacement names and the public lazy satellites. Therefore the final count is not the baseline “keep” count alone.

## Eager-import analysis

At the pinned baseline, a fresh `import petta` loaded **58** package modules:

```text
petta
_api_types _atom_namespace _atom_wire _atoms_core _callbacks _config
_contract _convert_build _convert_project _convert_registry
_define_context _define_expression _define_facts _define_loops
_define_statements _define_twins _documentation _engine _lint_analysis
_lint_model _object_fields _operator_lowerings _ops _optional
_parameterized _prelude _source_forms _space_definitions
_space_diagnostics _space_execution _space_objects _space_persistence
_space_query _tokens _type_annotations _version
algebra answer atoms casting convert define derivation errors events
foreign integrate lint ops paths results rules space structures
subscribe trace vocabularies
```

The shortest observed core-to-satellite chains were:

```text
petta -> algebra
petta -> integrate
petta -> events -> structures
petta -> _api_types -> vocabularies
petta -> _engine -> _callbacks -> events
petta -> _engine -> _callbacks -> foreign -> vocabularies
petta -> space -> algebra
petta -> space -> integrate
petta -> space -> subscribe
petta -> space -> trace
petta -> space -> lint
petta -> space -> casting
petta -> results -> convert
petta -> ops -> convert
```

`parallel` was not runtime-eager, although static analysis saw `space -> parallel` through type-checking and method-local imports. The important finding is that deleting root reexports alone cannot create real laziness. `_engine.py` eagerly imported `_callbacks` and `_prelude`; `_callbacks` imported events and foreign; and the old `space.py` imported nearly every satellite. Fork 4 must break those chains as well as use PEP 562 at the root.

The lazy-root invariant is:

- `__all__` is the explicit advertised surface.
- `__dir__()` returns exactly `sorted(__all__)`, so it cannot expose private imports or cause a load.
- `__getattr__()` imports the real module or object and preserves identity; it does not return a proxy.
- Satellite modules import concrete core modules instead of resolving through the facade.
- Importing a satellite before or after attribute access returns the same object.
- The callable `petta.space` cannot be overwritten by a physical `petta.space` submodule.
- Unknown attributes raise the normal `module 'petta' has no attribute 'name'` error.

## Design research

The root follows [PEP 562](https://peps.python.org/pep-0562/): module-level `__getattr__` resolves only advertised lazy objects, while `__dir__` returns the curated surface. The implementation returns real imported objects, never proxies. The production precedents inspected were [SciPy's pinned initializer](https://github.com/scipy/scipy/blob/840e1a413c39b90d599ce560d0fbcb9b45290b41/scipy/__init__.py#L68-L113) and [NumPy's pinned initializer](https://github.com/numpy/numpy/blob/1f90bbb55e65e7de68921bc3f1a2d94492fdf689/numpy/__init__.py#L682-L758). [source: PEP 562 and the two pinned upstream initializers; commit=f88aa8be03cb64cb59d3307515ded8701f418321]

The private normalized `Expression` construction path follows Python's established immutable-value reconstruction boundary: validated internal state may allocate with `__new__` without re-running a coercing public initializer. CPython's [pickle implementation](https://github.com/python/cpython/blob/main/Lib/pickle.py) and [pickle documentation](https://github.com/python/cpython/blob/main/Doc/library/pickle.rst?plain=1) use that distinction. [source: the linked CPython primary sources; commit=f88aa8be03cb64cb59d3307515ded8701f418321]

## Measurements and gate evidence

| Metric | Baseline `a142938d` | Fork 4 functional tree | Change |
|---|---:|---:|---:|
| `MeTTa` public attributes | 90 | 20 | -70 (-77.8%) |
| public names in `dir(petta)` | 152 | 61 | -91 (-59.9%) |
| `petta.__all__` entries | 132 | 62 | -70 (-53.0%) |
| modules loaded by fresh `import petta` | 58 | 9 | -49 (-84.5%) |
| import-time minimum | 37.862 ms | 11.114 ms | -70.6% |
| import-time median | 39.644 ms | 12.021 ms | -69.7% |

The final nine fresh `python -S -X importtime -c 'import petta'` cumulative samples were `13.529, 11.114, 12.490, 12.021, 11.718, 12.773, 11.678, 11.425, 12.652 ms`. A fresh import loaded only `petta`, `_atom_namespace`, `_atom_wire`, `_atoms_core`, `_config`, `_operator_lowerings`, `_version`, `atoms`, and `errors`; calling `dir(petta)` loaded no additional module. [measured: 9 modules, 11.114 ms minimum, and 12.021 ms median on 2026-08-22; command=PYTHONPATH=bindings/python $CHECK_PY -S -X importtime -c 'import petta'; fixture=nine fresh processes after concurrent repository gates exited; commit=f88aa8be03cb64cb59d3307515ded8701f418321]

Verification receipts:

- The M7 public-surface, deletion, lazy-identity, space-collision, unknown-attribute, and upstream-boundary tests are **5 passed**. They assert the literal `90 -> 20` and `152 -> 61` metrics, absence through `dir`, `vars`, and `getattr`, both satellite import orders, repeated identity, and that `python.petta` is the canonical package. [tested: $CHECK_PY -m pytest bindings/python/tests/test_m7_narrow_core.py -q; commit=f88aa8be03cb64cb59d3307515ded8701f418321]
- The maintained non-twin Python suite is **1,842 passed, 45 skipped, 29 deselected**. [tested: $CHECK_PY -m pytest bindings/python/tests --ignore=bindings/python/tests/twins -k 'not twin_coverage' -q; commit=f88aa8be03cb64cb59d3307515ded8701f418321]
- The upstream PeTTa package's own seven tests pass against this worktree when isolated from its source package path. This exercises the legacy `CONSULTED`/`janus` seam, `src/main.pl` runtime, two source-string methods, original CLI command, and optional MORK preload. [tested: PYTEST_DISABLE_PLUGIN_AUTOLOAD=1 PYTHONPATH=<worktree>:<worktree>/bindings/python $CHECK_PY -m pytest <isolated-symlinks-to-PeTTa-base/python/tests> -q; commit=f88aa8be03cb64cb59d3307515ded8701f418321]
- MORK remains **19 passed, 1,893 deselected** when the protected twins are excluded. Before the surface change, the required prerequisite command measured **19 passed, 1,911 deselected**. [tested: $CHECK_PY -m pytest bindings/python/tests --ignore=bindings/python/tests/twins -k mork -q; commit=f88aa8be03cb64cb59d3307515ded8701f418321]
- Import-linter analyzed **78 files and 241 dependencies**; all three contracts are kept: `atoms is the base layer`, `leaf modules do not import the facade`, and the new `core does not import satellites`. [tested: PYTHONPATH=bindings/python lint-imports --config pyproject.toml; commit=f88aa8be03cb64cb59d3307515ded8701f418321]
- The controlled instruction gate passes all 15 cases. Two pins changed: `alpha-unique` from `3,523,597,315` to `3,614,095,753` instructions (+2.568%) despite engine inferences falling from `3,302,020` to `3,301,865`, and `subscription-dispatch` from `46,004,734` to `46,902,661` (+1.952%) for one normalized `Expression` allocation per delivered write. The baseline records both attribution samples and the rejected alternative. [tested: cd bindings/python && $CHECK_PY -m benchmarks.check_instructions; commit=f88aa8be03cb64cb59d3307515ded8701f418321]
- The exact `GATE_ONLY=1 CHECK_PY=<project interpreter> sh check.sh` result is green in every gate except `pytest` and `llms`. The `pytest` failures are exclusively the protected twins described below. `llms.txt` is also protected and contains 16 now-stale surface claims; its sibling update must remove nine dead `MeTTa` methods, four dead root/module doors, the old `space.py` path and page count, and replace its lazy-module inventory. [measured: 57 gate lanes run, 55 passed and 2 protected-file lanes failed; command=GATE_ONLY=1 sh check.sh; fixture=CHECK_PY is the required project interpreter and twins and llms.txt are unmodified; commit=f88aa8be03cb64cb59d3307515ded8701f418321]

## Measured protected-twin breakage

The twin lane is intentionally red and no file under `bindings/python/tests/twins` was changed. The coverage report measured **448 findings over all 204 twinned examples**; **22 of 223 example files** remain twinned and passing, covering **178 of 1,094 claims**. [measured: 448 findings over 204 twinned examples on 2026-08-22; command=$CHECK_PY bindings/python/tools/twin_coverage.py; fixture=unmodified bindings/python/tests/twins; commit=f88aa8be03cb64cb59d3307515ded8701f418321]

Every break belongs to one of these mechanical families, all represented in the rewrite table above:

| Twin-visible break | Required sibling rewrite |
|---|---|
| Imports of `Expr`, `Gnd`, `Sym`, `Var`, `expr`, `sym`, `var`, `val`, `alpha_eq`, `order_key`, `REFLECTION_SPACE`, detailed root errors, or other retired root names | Import the canonical class/satellite where needed and use `Expression`, `S[...]`, `V[...]`, `ground`, atom methods/properties, or `petta.reflection`. |
| Calls to removed `MeTTa`/`Space` facade verbs such as `space`, `new_space`, `space_name`, `one`, `first`, `stream`, `count`, `register_op`, and `disassemble` | Select `ctx.space(...)`, use handle properties/protocols and `op`, or adopt the answer API owned by Track 1 as the first table specifies. |
| Python string literals passed as implicit symbols or grounded values | Spell names with `S[...]` and data with `ground(...)`; the source scanner reports every ambiguous literal. |
| Twin instruction budgets changed by the smaller runtime image | Re-run and pin each affected twin after its source rewrite; do not restore deleted API solely to retain an old cost image. |

The exact pytest gate sees seven collection errors because protected twins import `expr`, `val`, or `alpha_eq`. Its three runtime failures are the two legacy raw-string findings in `constraint_domains.py`, the `identity.metta` twin's lower `2,198` instruction count against its old `2,289` pin, and `spaces3.metta` importing deleted `expr`. The exact `-k mork` command therefore stops at those same seven collection errors, while the non-twin MORK selection remains 19/19. [measured: 7 collection errors and 3 twin-coverage failures; command=$CHECK_PY -m pytest bindings/python/tests -k mork -q and the exact gate command above; fixture=unmodified bindings/python/tests/twins; commit=f88aa8be03cb64cb59d3307515ded8701f418321]
