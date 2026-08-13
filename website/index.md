---
layout: home

hero:
  name: "PeTTa Python"
  text: "Compose Python and MeTTa"
  tagline: "Atoms, queries, integrations, live systems, and neural relations on one runtime surface."
  actions:
    - theme: brand
      text: Get started
      link: /guide/getting-started
    - theme: alt
      text: API reference
      link: /reference/

features:
  - title: Python terms and queries
    details: Build atoms as Python values, run MeTTa source, and query spaces with joins, guards, assumptions, and prepared shapes.
    link: /guide/atoms-terms
  - title: Open reasoning
    details: Add matchers, weighted relations, soft unification, and goal-directed proofs without changing the term language.
    link: /reasoning/matchers-measure
  - title: Live systems
    details: Treat subscriptions, routes, and incremental solving as operations over spaces and facts.
    link: /live/standing-queries
  - title: PeTTorch
    details: Keep tensors and autograd graphs intact while MeTTa rules route models and define forward passes.
    link: /pettorch/tensors
---

# One language for several paradigms

MeTTa is built to be a lingua franca. Each PeTTa integration translates another paradigm's semantics into MeTTa's own: routing becomes unification over facts, multi-shot solving becomes parts and toggled truths, validation becomes declarations, tables become facts, and neural predicates become weighted relations. Once translated, the paradigms compose with each other in one substrate.

The translation keeps the concepts visible. A web route is a fact a program can query. A subscription is a standing query over a space. An array keeps its host identity while operations follow the array API. A neural classifier answers the same weighted pairs that the measure algebra consumes.

| Integration concept | MeTTa reading |
|---|---|
| functions and methods | grounded functions whose calls reduce |
| tables, caches, and populations | spaces queried by matching |
| generators, search, and retrieval | nondeterministic answers |
| schemas and records | constructor expressions with declarations |
| routes and handlers | facts plus unification in registration order |
| model outputs | weighted relations over classes |

Start with [install and first steps](./guide/getting-started), then follow the sidebar by the kind of system you are translating.
