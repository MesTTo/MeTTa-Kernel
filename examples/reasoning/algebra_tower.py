"""Purpose: run the lawless declared-algebra witness.
Assumes: execute with PeTTa's documented Python environment and ``PETTA_PATH``.
Guarantees: the witness uses ``declare_algebra`` plus ordinary tagged facts
  [tested: test_a_declared_algebra_without_laws_answers_in_order_and_unfused;
  commit=496643acc4104702e76e7d325e9ffac8c0cc08c1]
"""  # noqa: D205, D415 -- the file contract is one continuous invariant

from petta import MeTTa, S, V


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

if __name__ == "__main__":
    main()
