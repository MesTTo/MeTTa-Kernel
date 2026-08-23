"""Purpose: run the lawless, rate, linear, and amplitude algebra witnesses.

Assumes: execute with PeTTa's documented Python environment and ``PETTA_PATH``.
Guarantees:
  - the lawless witness uses ``algebra`` plus ordinary tagged facts
    [tested: test_a_declared_algebra_without_laws_answers_in_order_and_unfused;
    commit=7ae3103aee78e947d23c5872e3db23c28ad7fe1c]
  - a local seed selects ordinary tagged alternatives reproducibly [tested:
    test_declared_rates_make_seeded_selection_match_their_distribution;
    commit=7ae3103aee78e947d23c5872e3db23c28ad7fe1c]
  - the linear witness refuses a second spend of one fact occurrence [tested:
    test_a_linear_algebra_refuses_the_second_spend_of_one_premise;
    commit=7ae3103aee78e947d23c5872e3db23c28ad7fe1c]
  - amplitude use names the missing fence and exact opposite paths cancel after
    the fence lands [tested:
    test_amplitudes_interfere_inside_the_fragment_and_are_refused_outside;
    commit=7ae3103aee78e947d23c5872e3db23c28ad7fe1c]
"""

from metta import (
    AlgebraRequirementError,
    Amplitude,
    LinearEvidenceError,
    MeTTa,
    S,
    V,
    decode,
    parse,
)


def main() -> None:
    """Print the two unfused tags and the withheld optimization."""
    metta = MeTTa()
    metta.algebra(
        "demo-lawless", combine="pair", extend="pair", zero=S.none, one=S.unit
    )
    with metta.new_space() as program:
        program.add_tagged_fact(S.first, S.answer(S.same))
        program.add_tagged_fact(S.second, S.answer(S.same))
        result = program.evaluate_algebra(S.answer(V.x), algebra="demo-lawless")
        print("lawless", [str(answer.tag) for answer in result.answers], result.plan)

    metta.algebra(
        "demo-rates", combine="+", extend="*", zero=0, one=1
    )
    with metta.new_space() as program:
        program.add_tagged_fact(parse("(rate 1)"), S.branch(S.slow))
        program.add_tagged_fact(parse("(rate 3)"), S.branch(S.fast))
        draws = program.sample_rates(
            S.branch(V.x), algebra="demo-rates", draws=20, seed=7
        )
        print("rates", [str(answer) for answer in draws])

    metta.algebra(
        "demo-linear",
        combine="max",
        extend="+",
        zero=0,
        one=0,
        requires=("linear",),
    )
    with metta.new_space() as program:
        program.annotations(
            program.space_name, "demo-linear", capabilities=("linear",)
        )
        program.add_tagged_fact(1, S.token(S.only))
        program.add_tagged_rule(0, S.spend_twice, S.token(S.only), S.token(S.only))
        try:
            program.evaluate_algebra(S.spend_twice, algebra="demo-linear")
        except LinearEvidenceError as refusal:
            print("linear", refusal)

    metta.register_op(
        lambda left, right: left + right, name="amplitude-add", raw=False
    )
    metta.register_op(
        lambda left, right: left * right, name="amplitude-multiply", raw=False
    )
    with metta.new_space() as program:
        try:
            program.annotations(program.space_name, "amplitude")
        except AlgebraRequirementError as refusal:
            print("outside fence", refusal)
        program.annotations(
            program.space_name,
            "amplitude",
            capabilities=("finite", "contractive", "staged"),
        )
        program.add_tagged_fact(Amplitude(1), S.detect(S.dark))
        program.add_tagged_fact(Amplitude(-1), S.detect(S.dark))
        result = program.evaluate_algebra(S.detect(S.dark), algebra="amplitude")
        print("amplitude", decode(result.answers[0].tag))

if __name__ == "__main__":
    main()
