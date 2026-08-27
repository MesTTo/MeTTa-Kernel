# Contributing to MeTTa

This page is the contract: what a contribution has to be, the one command that
decides whether it is ready, and how a release happens. The mechanics around
it live elsewhere and are not repeated here. Setting up an interpreter and
measuring a Python change are in [DEVELOPING.md](DEVELOPING.md), and the
engine's own build, suites and measurement rules are in
[tests/prolog/README.md](tests/prolog/README.md).

## Alpha

Versions are `0.y.z` under [SemVer](https://semver.org/spec/v2.0.0.html) and
every release is labelled alpha. Expect a breaking change at each one, which
is what major version zero means and not a departure from it. MeTTa itself is
alpha, and an implementation of an alpha language that promised a stable
surface would be promising something it does not control.

So a change that breaks a published surface is allowed at any release, and
backwards compatibility is not on its own a reason to keep a worse design.
What is asked instead is that the changelog entry says what broke, in enough
detail that a reader can tell whether their own program is affected.

1.0 waits on two conditions and takes whichever lands later. This
repository's own surfaces have to settle, meaning the names its extension
seams go by and the contract a language binding implements, and MeTTa itself
has to leave alpha upstream.

## What a contribution is

An atomic pull request on a gate-green tree.

Atomic means one logical change. It stands on its own, it builds and passes
on its own, and its message says what changed and why. Two unrelated fixes
are two pull requests, and a fix plus the reformatting done on the way past
it is not one change.

Gate-green means `GATE_ONLY=1 sh check.sh` passes on the tree you are
proposing, every lane of it, on an interpreter you name in the pull request.
A green subset is not evidence, because the lanes catch different things and
the ones a change is least expected to touch are the ones that catch it.

Every code file the change adds or touches carries an obligation header, and
every non-obvious claim in that header carries an evidence tag. The header's
open obligations are at zero when the change lands, which is `None` on all
three lines, or the pull request says why one of them cannot be.

There is no contributor license agreement. This repository is MIT, in
[LICENSE](LICENSE), and a contribution is offered under those terms. Nothing
further is asked of you.

## The gate

One command runs everything:

```sh
sh check.sh                          # both tiers
GATE_ONLY=1 sh check.sh              # the blocking tier, what CI blocks on
sh check.sh ruff mypy                # named lanes only
CHECK_PY=/path/to/python sh check.sh # pick the interpreter
```

There are two tiers and they mean different things. A GATE lane must pass:
its failure is recorded and the script exits nonzero. A REPORT lane prints
its findings and never fails the run.

A REPORT tier is not a softened gate. Nothing is silenced there and
everything it finds is printed. Each REPORT lane is a burn-down surface with
a backlog behind it, and it becomes a GATE the moment that backlog clears.
Adding a finding to a REPORT lane pushes that day further away, so treat its
output as failing for the file you touched even though the script forgives
it.

`.github/workflows/checks.yml` runs the same script on every push and every
pull request, so the gate you run locally is the gate that answers on the
pull request.

## Where the tests live

The Python suite runs from the repository root, with the root and the
configuration made explicit:

```sh
python -m pytest bindings/python/tests/ -q --rootdir=bindings/python -c bindings/python/pyproject.toml
```

The engine's suites are PlUnit files under `tests/prolog/`. Run one from
inside that directory:

```sh
cd tests/prolog
swipl -g "set_test_options([format(log)]), run_tests" -t halt parser.plt
```

The `cd` is load-bearing and its absence is easy to misread. Each suite
consults `../../engine/metta.pl` from an initialization goal, and an
initialization goal resolves a relative path against the working directory at
run time, not against the file. Started from the repository root, the same
command fails every test in the file with `Unknown procedure:
plunit_<unit>:swrite/2`, and the line that says why is a single
`source_sink '../../engine/metta.pl' does not exist` above the first failure.

The MeTTa corpus under `examples/` is self-checking and each file runs as a
program. `sh test.sh` runs the examples the shell suite covers and takes each
process's exit status as the verdict. The shell regressions under
`tests/regression/` cover process behaviour and multi-process state that a
single PlUnit engine cannot represent.

A behaviour change carries its test in the tier that matches it, in the same
commit as the change.

## Obligation headers and evidence tags

Source files in this tree open with a header that records contract and
evidence rather than intent, written in the file's own comment syntax:

```prolog
% Purpose: compile MeTTa expressions and equations into executable Prolog.
% Assumes:
%   - '$skip_list'(-Length, +List, -Tail) reports the tail a list spine ends
%     in without instantiating it [source 2026-08-19: SWI-Prolog 10.1.13
%     /usr/lib/swi-prolog/library/error.pl:311-315, not_a_list/2].
% Guarantees:
%   - User get-type equations extend the deduplicating type boundary through
%     get_type_rule/2 [tested 2026-08-15: translator_type_extensions].
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None
```

`Purpose` and `Open Obligations` are always there. `Assumes`, `Guarantees`,
`Fails when`, `Owns`, `Guarded by` and `Decides` are written when the file's
own code calls for them: a file that starts a thread or opens a resource
needs `Owns`, one that holds a lock needs `Guarded by`, one that fixes a
constant on the operator's behalf needs `Decides`. A field that would say
nothing is left out.

Four tags carry the evidence, and each has to bring what it claims:

- `[measured 2026-08-14: 2.05x]`, a number with a date, so the claim can go
  stale and be seen to have gone stale.
- `[tested 2026-08-15: translator_type_extensions]`, naming a test, a PlUnit
  unit, a named check, a shell suite, an example or a path that exists, that
  can report a failure, and that a runner executes.
- `[source 2026-08-19: swi-prolog.org/pldoc/...]`, a date or a reference, a
  URL or a `file:line`.
- `[assumed 2026-08-14: ...]`, a claim nobody has verified.

`assumed` is the load-bearing one. It costs nothing to write and it is the
only thing that makes an unverified claim visible as one, so use it rather
than stating an unverified claim in the same voice as a measured fact. It is
deliberately unchecked, because demanding evidence for it would push authors
straight back into that voice.

The other three are checked. `tests/checks/check_evidence_tags.py` runs as the
`evidence` GATE lane, reads only, and needs no engine. It exists because
thirteen `tested` claims in this tree named tests that had never existed in
its history, and nothing anywhere would have said so.

That lane answers three of the four questions a citation raises: whether the
target exists, whether it can fail, and whether a runner executes it. It
cannot answer the fourth, which is whether the target tests the particular
guarantee it is cited for. That one is yours.

## Commits

One commit is one logical change, with a message that says what changed and
why rather than what file moved. Keep every commit independently buildable.

A commit that changes behaviour updates the matching test and the public
documentation in the same commit, and adds its entry under `## [Unreleased]`
in [CHANGELOG.md](CHANGELOG.md) when the change is user-facing.

## Releases

A release is a tag on a gate-green tree, every lane, and nothing else. The
release notes are the changelog's newest block, unedited: the `## [Unreleased]`
heading becomes the version and the date, a new empty `## [Unreleased]` opens
above it, the compare links at the foot of the file move with it, and the
block that was just closed is what the tag publishes.

Releasing is therefore mechanical. Nothing about a release is written at
release time, because the entry that describes a change was written in the
commit that made it, when the reason was still in front of somebody.
