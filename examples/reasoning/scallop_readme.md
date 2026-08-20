# Scallop README witness

The executable neighbor transcribes the five examples in
[Scallop's README](https://github.com/scallop-lang/scallop/blob/668bfb6d45ce302fd4ffa7f29916baf3c7ce36ef/README.md)
at commit `668bfb6d45ce302fd4ffa7f29916baf3c7ce36ef`. Its expected values are the
README's printed values, not PeTTa-specific replacements.

| Scallop feature | PeTTa seam used by the witness |
|---|---|
| Whole-context provenance selection | Per-context algebra declarations whose operations and checked laws are catalog atoms (`MeTTa.declare_algebra`, P4.20) |
| `difftopkproofs` | Grounded DLPack tags under the declared gradient algebra, consumed by pettorch (P4.32) |
| Closed `count`, `min`, `max`, `sum`, `prod` aggregate list | `foldall` with an arbitrary reducer; a reducer may itself be an algebra's declared `combine` operation |
| Stratified negation | `not-provable` over a finite relation after its positive bindings are ground; the example states that safety obligation instead of assuming a static checker |
| `type Symbol <: usize` | The existing `:<` subtype declaration |
| `@file` CSV relation | `MeTTa.add_table` and a named catalog context |
| `add_relation`, `add_rule` | Structured `add`, `add_table`, and the declare family |
| `forward_function` | A registered operation or `pettorch.MettaModule` |

The following Scallop behavior remains filed rather than implied by these five
finite cases:

- General cyclic least-fixed-point recursion and its set-deduplicating search
  control remain P4.22. The acyclic path case terminates under ordinary PeTTa
  equations.
- PeTTa has no identical `@file` surface syntax. `add_table` provides the data
  seam through Python.
- PeTTa has no static stratification checker. Grounded-before-negated ordering
  is therefore an explicit program obligation.
- Scallop's Python builder API is not reproduced name for name. PeTTa exposes
  the more general atom, operation, table, and module surfaces listed above.

The animal example deliberately retains `unique`: the raw proof multiset has
four derivations while the Scallop relation has two values.
