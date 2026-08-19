<!-- CONTRIBUTING.md is where every line of this comes from. -->

## What changes, and why

<!--
One logical change. If there are two, there are two pull requests.
Say what a reader of the diff cannot see: the reason, and what you ruled out.
-->

## How it was checked

<!--
Name the interpreter you ran the gate on, and say what the change's own test
is. A green subset is not evidence: the lanes catch different things, and the
one a change is least expected to touch is the one that catches it.
-->

- [ ] `GATE_ONLY=1 sh check.sh` passes on this tree, every lane
- [ ] the behaviour change carries its test, in the tier that matches it
- [ ] every file added or touched has an obligation header whose open
      obligations are `None`, or this pull request says why one cannot be
- [ ] every non-obvious claim in those headers carries an evidence tag
- [ ] a user-facing change has its entry under `## [Unreleased]` in
      `CHANGELOG.md`, and a breaking one says what breaks
