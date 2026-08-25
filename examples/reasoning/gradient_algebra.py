"""Purpose: carry a two-rule provenance derivative into a pettorch module.

Assumes: PeTTa, PyTorch, and the sibling ``pettorch`` package are importable.
Guarantees: the result is the same live DLPack tensor whose backward pass
  reaches the source tag [tested:
  test_a_declared_gradient_algebra_propagates_derivatives_through_a_derivation;
  commit=c7468b2789746bcf95c4bacc0e2d517ec4d972fa]
"""

import pettorch
import torch

from metta import MeTTa, S, V, ground, wire


def main() -> None:
    """Print the propagated value and derivative from the worked derivation."""
    context = MeTTa()
    metta = context.self
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
    with context.space() as program:
        program.add_tagged_fact(ground(source), S.source(S.a))
        program.add_tagged_fact(ground(scale), S.scale(S.a))
        program.add_tagged_rule(ground(one), S.middle(V.x), S.source(V.x))
        program.add_tagged_rule(
            ground(one), S.output(V.x), S.middle(V.x), S.scale(V.x)
        )
        answer = program.match(S.output(S.a), under="gradient-demo").one()
        result = wire.decode(answer.tag)
        program.op(
            lambda: result,
            name="gradient-demo-result",
            effect="pureStructural",
        )
        program.run("(= (gradient-demo-model) (gradient-demo-result))")
        module = pettorch.MettaModule(program, "gradient-demo-model")
        consumed = module()
        consumed.backward()
        print("value", consumed.item(), "gradient", source.grad.item())


if __name__ == "__main__":
    main()
