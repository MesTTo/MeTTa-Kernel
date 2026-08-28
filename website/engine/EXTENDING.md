---
outline: [2, 3]
---

<!--
Purpose: publish the repository's EXTENDING.md as a site page without copying it.
Assumes: VitePress resolves an @include path against this file's directory, so
  the target is the repository root's own document and there is one copy of it.
Guarantees: the page is exactly the committed EXTENDING.md, so the measured cost
  table the extcost gate pins is the table a reader sees
  [tested: test_every_site_include_resolves; commit=WORKTREE]
-->

<!--@include: ../../EXTENDING.md-->
