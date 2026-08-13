# petta-soft

Sessa's weak unification and goal-directed soft proving (the End-to-End
Differentiable Proving and Braid reading), layered on the `petta`
library's public surface: `similar()` declares closeness as ordinary
facts, `score()` mirrors the engine's `soft-score` equations exactly
(held equal by a differential fuzz), and `prove()`/`prove_all()` answer
`Proof` objects with substitutions, similarity and every step.

Built ON the library, not into it: every call goes through `run`, `add`,
`eval`, `atoms` and the public atom API. The engine-side equations live
in the PeTTa tree as `lib/lib_soft.metta`.
