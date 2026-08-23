<!--
Purpose: route readers to the supported live-system guides.
Guarantees: every listed guide describes a currently shipped public API.
[tested: npm run docs:build; commit=f88aa8be03cb64cb59d3307515ded8701f418321]
-->

# Live systems

A space is not only storage: writes can drive callbacks, engines can
serve engines, and the event loop can keep running while the engine
thinks. These pages cover the surface that keeps a system live.

- [Standing queries](./standing-queries.md) watches a space and delivers matching writes.
- [Reflection and steering](./reflection.md) reads the surface's own description from the `&petta` space.
- [Web routes](./web-routes.md) builds FastAPI's routing semantics as facts and unification.
- [Multi-shot solving](./multishot.md) grounds program parts incrementally and toggles externals between solves.
- [Contexts and remotes](./contexts.md) connects spaces with bridge rules and engines with `metta.remote`.
- [Deployment as knowledge](./boot.md) assembles an app from a manifest of `(boot ...)` atoms.
- [The loop stays live](./async.md) moves engine calls onto a worker thread behind an async interface.
