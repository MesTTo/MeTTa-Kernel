"""Purpose: run the lawless, rate, linear, and amplitude algebra witnesses.

Assumes: execute with PeTTa's documented Python environment and ``PETTA_PATH``.
Guarantees:
  - the lawless witness uses ``algebra`` plus ordinary tagged facts
    [tested: test_a_declared_algebra_without_laws_answers_in_order_and_unfused;
    commit=c7468b2789746bcf95c4bacc0e2d517ec4d972fa]
  - a local seed selects ordinary tagged alternatives reproducibly [tested:
    test_declared_rates_make_seeded_selection_match_their_distribution;
    commit=c7468b2789746bcf95c4bacc0e2d517ec4d972fa]
  - the linear witness refuses a second spend of one fact occurrence [tested:
    test_a_linear_algebra_refuses_the_second_spend_of_one_premise;
    commit=c7468b2789746bcf95c4bacc0e2d517ec4d972fa]
  - amplitude use names the missing fence and exact opposite paths cancel after
    the fence lands [tested:
    test_amplitudes_interfere_inside_the_fragment_and_are_refused_outside;
    commit=c7468b2789746bcf95c4bacc0e2d517ec4d972fa]
"""

from metta import (
    MeTTa,
    S,
    V,
    parse,
    wire,
)
from metta.algebra import AlgebraRequirementError, Amplitude, LinearEvidenceError


def main() -> None:
    """Print the two unfused tags and the withheld optimization."""
    context = MeTTa()
    metta = context.self
    metta.algebra(
        "demo-lawless", combine="pair", extend="pair", zero=S.none, one=S.unit
    )
    with context.space() as program:
        program.add_tagged_fact(S.first, S.answer(S.same))
        program.add_tagged_fact(S.second, S.answer(S.same))
        answers = list(program.match(S.answer(V.x), under="demo-lawless"))
        print("lawless", [str(answer.tag) for answer in answers], answers[0].plan)

    metta.algebra(
        "demo-rates", combine="+", extend="*", zero=0, one=1
    )
    with context.space() as program:
        program.add_tagged_fact(parse("(rate 1)"), S.branch(S.slow))
        program.add_tagged_fact(parse("(rate 3)"), S.branch(S.fast))
        draws = program.sample(S.branch(V.x), k=20, seed=7)
        print("rates", [str(answer) for answer in draws])

    metta.algebra(
        "demo-linear",
        combine="max",
        extend="+",
        zero=0,
        one=0,
        requires=("linear",),
    )
    with context.space() as program:
        program.annotations(
            program.name, "demo-linear", capabilities=("linear",)
        )
        program.add_tagged_fact(1, S.token(S.only))
        program.add_tagged_rule(0, S.spend_twice, S.token(S.only), S.token(S.only))
        try:
            list(program.match(S.spend_twice, under="demo-linear"))
        except LinearEvidenceError as refusal:
            print("linear", refusal)

    metta.op(
        lambda left, right: left + right,
        name="amplitude-add",
        effect="pureStructural",
    )
    metta.op(
        lambda left, right: left * right,
        name="amplitude-multiply",
        effect="pureStructural",
    )
    with context.space() as program:
        try:
            program.annotations(program.name, "amplitude")
        except AlgebraRequirementError as refusal:
            print("outside fence", refusal)
        program.annotations(
            program.name,
            "amplitude",
            capabilities=("finite", "contractive", "staged"),
        )
        program.add_tagged_fact(Amplitude(1), S.detect(S.dark))
        program.add_tagged_fact(Amplitude(-1), S.detect(S.dark))
        answers = list(program.match(S.detect(S.dark), under="amplitude"))
        print("amplitude", wire.decode(answers[0].tag))

if __name__ == "__main__":
    main()
