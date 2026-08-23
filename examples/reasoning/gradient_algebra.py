"""Purpose: carry a two-rule provenance derivative into a pettorch module.

Assumes: PeTTa, PyTorch, and the sibling ``pettorch`` package are importable.
Guarantees: the result is the same live DLPack tensor whose backward pass
  reaches the source tag [tested:
  test_a_declared_gradient_algebra_propagates_derivatives_through_a_derivation;
  commit=7ae3103aee78e947d23c5872e3db23c28ad7fe1c]
"""

import pettorch
import torch

from petta import MeTTa, S, V, decode, val


def main() -> None:
    """Print the propagated value and derivative from the worked derivation."""
    metta = MeTTa()
    pettorch.install(metta)
    source = torch.tensor(2.0, requires_grad=True)
    scale = torch.tensor(3.0)
    one = torch.tensor(1.0)
    metta.algebra(
        "gradient-demo",
        combine="t+",
        extend="t*",
        zero=torch.tensor(0.0),
        one=one,
    )
    with metta.new_space() as program:
        program.add_tagged_fact(val(source), S.source(S.a))
        program.add_tagged_fact(val(scale), S.scale(S.a))
        program.add_tagged_rule(val(one), S.middle(V.x), S.source(V.x))
        program.add_tagged_rule(
            val(one), S.output(V.x), S.middle(V.x), S.scale(V.x)
        )
        answer = program.evaluate_algebra(
            S.output(S.a), algebra="gradient-demo"
        ).answers[0]
        result = decode(answer.tag)
        program.register_op(lambda: result, name="gradient-demo-result", raw=False)
        program.run("(= (gradient-demo-model) (gradient-demo-result))")
        module = pettorch.MettaModule(program, "gradient-demo-model")
        consumed = module()
        consumed.backward()
        print("value", consumed.item(), "gradient", source.grad.item())


if __name__ == "__main__":
    main()
