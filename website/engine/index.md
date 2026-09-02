<!--
Purpose: route readers to the four engine-level documents the repository keeps
  at its root and this section publishes.
Assumes: each page here includes its root document rather than copying it, so
  this index describes documents whose text lives one directory up from the site.
Guarantees: every document named here has a page in this section
  [tested: test_every_site_page_is_reachable_from_the_navigation; commit=a7d2f292004fe06d7671b7931cfc2ce4620b7b35]
-->

# The engine

The rest of this site is written from the Python surface looking in. These four
pages are written from the engine looking out: what its extension points are and
what each costs, which forms it gives meaning to and why, the wire every atom
crosses on, and how to work on the repository itself.

Each page is the repository document of the same name, published here rather
than copied, so the version you read is the committed one.

- [Extending the engine](./extending) is the map of nine extension points,
  ordered by measured cost. A translator rule, a C foreign predicate and a
  Prolog grounded predicate all cost about what a MeTTa function costs; a Python
  operation costs the janus crossing. The page also covers reader token classes,
  space providers, atom hooks, custom matchers, and the `extension.pl` control
  file that makes a folder under `extensions/` an extension the engine reads.
- [The kernel](./kernel) is the ledger of the 58 heads the translator gives a
  meaning of their own, each classified against minimal MeTTa's state-free
  structural core as a counterpart, a follow-up, or a divergence this engine
  chose. A head fused into the compiler rather than expressed as a prelude rule
  has to say what the fusion buys, with numbers.
- [The wire codec](./codec) is the tagged form every atom crosses in, and
  what a new binding in a new language has to implement.
- [Developing](./developing) is the contributor side: the interpreter and
  SWI-Prolog versions, `check.sh` and what its two tiers mean, and the
  measurement rules that decide whether a performance claim is evidence.

The extension points themselves are declared in `engine/ext_points.pl`, each with the kind
of thing it is (event, ownership, declaration, service), and that file is the
contract. [The contract](../guide/contract.md) covers the same attachment story
from the backend author's side, in the guide's voice.

