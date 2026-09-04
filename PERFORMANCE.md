# Performance against PeTTa

This engine runs a typical example program for about a third of the retired
instructions upstream PeTTa needs. That is measured on the same files by the
same harness, and the measurement runs in CI, so this page can be checked rather
than believed.

Everything below comes from `tests/data/upstream-parity-baseline.json`, which
the `parity-perf` gate lane compares against on every push.

## What is compared

Upstream is [`trueagi-io/PeTTa`](https://github.com/trueagi-io/PeTTa) at
`ae66fa8`, checked out beside this repository. The corpus is this repository's
own `examples/`, 251 programs, run byte-identically by both engines: the same
file, no rewriting, no dialect shims. 149 of them are measured, being the ones
the pinned upstream checkout can also run.

The counter is `perf stat -e instructions:u`, retired user-space instructions,
taken as the minimum of three runs and **net of each engine's own boot**. Wall
clock is not used and neither is CPU time. Instructions are what they are
whatever else the machine is doing, and this project has burned real time on
wall-clock numbers that turned out to be a busy box rather than a change.

Each engine's inference count is recorded beside its instructions and has to
agree across the three runs, or the row does not count at all.

## The headline

Of the 142 comparable rows:

| | |
|---|---|
| median, ours ÷ upstream | **0.379x** |
| geometric mean | **0.355x** |
| cheaper than upstream on | **125 of 142 (88%)** |

Spread out:

| | programs | |
|---|---|---|
| 10x or more cheaper | 20 | 14% |
| 3x to 10x cheaper | 35 | 25% |
| 1x to 3x cheaper | 70 | 49% |
| up to 2x dearer | 14 | 10% |
| 2x or more dearer | 3 | 2% |

Seven of the 149 measured rows are not comparable: subtracting the boot leaves
them at or below zero, which is what a three-line program does. They are
excluded rather than reported as a negative.

## Where the totals disagree with the median

Summed across the whole comparable corpus:

| | instructions |
|---|---|
| this engine | 549,522,280,393 |
| upstream PeTTa | 380,258,571,038 |
| ratio | **1.445x** |

So the median program is about 2.6x cheaper here and the corpus total is 1.4x
dearer. Both are true and neither is the interesting one on its own. A sum over
programs of wildly different size is a statement about the largest few, and the
largest few are where this engine currently loses. The median is what a program
picked off the shelf costs; the total is what the tail costs.

## Where it loses, by name

| program | ours ÷ upstream |
|---|---|
| `ch22-.../22-01-logic-programs/04-nilbc.metta` | 12.66x |
| `ch08-data/.../15-roman.metta` | 4.01x |
| `ch18-performance/.../09-tabling_fib.metta` | 3.23x |
| `ch05-.../04-specialize.metta` | 1.82x |
| `ch06-many-answers/08-permutations.metta` | 1.77x |

`nilbc` is root-caused rather than explained away, and the analysis is in
`tests/checks/check_upstream_parity.py` beside the waiver. Argument type
checking is 99.4% of that example, 306,132,002 inferences against 1,866,723 with
the check stubbed out, and it became so in one commit: routing typing decisions
through the typing-rule registry took the file from 44,327,926 inferences to
236,070,644. Reverting that commit's `engine/metta.pl` hunks at that commit
restores 44,328,446, so the attribution is a measurement and not a reading of
the diff. It is open.

Twenty-one rows carry a waiver like that one. A waiver is a row whose regression
is understood and recorded; it is not a row that stopped being measured, and the
lane still prints it on every run.

## Where it wins

The largest wins are on control flow and on programs that collapse many answers,
which is where the translator compiles a form that upstream interprets:

| program | ours ÷ upstream |
|---|---|
| `ch06-many-answers/03-collapse.metta` | 0.049x |
| `ch09-types/05-meta_types.metta` | 0.051x |
| `ch07-control-flow/.../04-if3.metta` | 0.051x |
| `ch07-control-flow/.../05-if4.metta` | 0.052x |
| `ch07-control-flow/.../02-if.metta` | 0.052x |

## Reproducing it

```sh
git clone https://github.com/trueagi-io/PeTTa ../PeTTa-upstream
python tests/checks/check_upstream_parity.py
```

The script measures both engines over the corpus and compares against the
committed baseline. `--rebaseline` rewrites the baseline from a fresh
measurement, which is how the numbers on this page were produced, and
`--frozen` compares without remeasuring.

`perf` must be available and `perf_event_paranoid` low enough to read counters
without privileges.

## What these numbers do not say

They are retired instructions on one corpus of small-to-medium programs on one
machine, not a benchmark suite for reasoning workloads, and not a claim about
programs unlike these. They say nothing about memory, about concurrency, or
about how either engine behaves at a scale the corpus does not reach.

Correctness is not measured here at all. The examples assert their own answers
and both engines run them under the gate, so a program that got faster by
answering differently would fail there rather than show up as a win on this
page.
