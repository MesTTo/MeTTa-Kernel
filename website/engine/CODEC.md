---
outline: [2, 3]
---

<!--
Purpose: publish the repository's CODEC.md as a site page without copying it.
Assumes: EXTENDING.md's closing table links CODEC.md as a sibling, so this page
  carries the source file's own name and that relative link resolves here too.
Guarantees: the page is exactly the committed CODEC.md, whose tables the
  codec-doc gate regenerates from tests/codec/corpus.json
  [tested: test_every_site_include_resolves; commit=WORKTREE]
-->

<!--@include: ../../CODEC.md-->
