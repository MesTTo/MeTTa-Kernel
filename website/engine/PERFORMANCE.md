---
outline: [2, 3]
---

<!--
Purpose: publish the repository's PERFORMANCE.md as a site page without copying
  it.
Assumes: the page carries the source file's own name, the way the four beside it
  do, so any relative link the document writes to a sibling resolves here too.
Guarantees: the page is exactly the committed PERFORMANCE.md, whose figures come
  from tests/data/upstream-parity-baseline.json and are compared on every push by
  check.sh's parity-perf lane
  [tested: test_every_site_include_resolves; commit=WORKTREE]
-->

<!--@include: ../../PERFORMANCE.md-->
