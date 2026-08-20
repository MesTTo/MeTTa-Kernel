"""Purpose: run the lawless, declared-rate, and linear algebra witnesses.
Assumes: execute with PeTTa's documented Python environment and ``PETTA_PATH``.
Guarantees:
  - the lawless witness uses ``declare_algebra`` plus ordinary tagged facts
    [tested: test_a_declared_algebra_without_laws_answers_in_order_and_unfused;
    commit=496643acc4104702e76e7d325e9ffac8c0cc08c1]
  - a local seed selects ordinary tagged alternatives reproducibly [tested:
    test_declared_rates_make_seeded_selection_match_their_distribution;
    commit=f95becb09e1d83fbb7bfd083fdb5b8b3f84ee225]
  - the linear witness refuses a second spend of one fact occurrence [tested:
    test_a_linear_algebra_refuses_the_second_spend_of_one_premise;
    commit=ab469c3679ab778c91ac73f14797af746a1ea87d]
"""  # noqa: D205, D415 -- the file contract is one continuous invariant

from petta import LinearEvidenceError, MeTTa, S, V, parse


def main() -> None:
    """Print the two unfused tags and the withheld optimization."""
    metta = MeTTa()
    metta.declare_algebra(
        "demo-lawless", combine="pair", extend="pair", zero=S.none, one=S.unit
    )
    with metta.new_space() as program:
        program.add_tagged_fact(S.first, S.answer(S.same))
        program.add_tagged_fact(S.second, S.answer(S.same))
        result = program.evaluate_algebra(S.answer(V.x), algebra="demo-lawless")
        print("lawless", [str(answer.tag) for answer in result.answers], result.plan)

    metta.declare_algebra(
        "demo-rates", combine="+", extend="*", zero=0, one=1
    )
    with metta.new_space() as program:
        program.add_tagged_fact(parse("(rate 1)"), S.branch(S.slow))
        program.add_tagged_fact(parse("(rate 3)"), S.branch(S.fast))
        draws = program.sample_rates(
            S.branch(V.x), algebra="demo-rates", draws=20, seed=7
        )
        print("rates", [str(answer) for answer in draws])

    metta.declare_algebra(
        "demo-linear",
        combine="max",
        extend="+",
        zero=0,
        one=0,
        requires=("linear",),
    )
    with metta.new_space() as program:
        program.add_tagged_fact(1, S.token(S.only))
        program.add_tagged_rule(0, S.spend_twice, S.token(S.only), S.token(S.only))
        try:
            program.evaluate_algebra(S.spend_twice, algebra="demo-linear")
        except LinearEvidenceError as refusal:
            print("linear", refusal)

if __name__ == "__main__":
    main()
