# Guide

The guide covers the runtime surface one feature at a time. The
tutorials teach the ideas in order; these pages go deeper and stand
alone, so read whichever one answers your question.

- [Install and first steps](./getting-started.md) installs the package and runs the first program.
- [Atoms, operators, and terms](./atoms-terms.md) builds every atom kind in Python, operators included.
- [Run and query](./run-query.md) explains `run` for source, `eval` for terms, and `query` for joins over facts.
- [Python functions in MeTTa](./python-functions.md) registers callables as MeTTa functions, with generators as nondeterminism.
- [Write MeTTa in Python](./define.md) compiles Python function bodies into equations with `@m.define`.
- [Spaces](./spaces.md) selects, creates, pools, and drops named spaces.
- [The contract](./contract.md) explains how backends attach by declaration: fidelity, sources, errors, writes, annotations, and `explain`.
- [Jupyter notebooks](./notebook.md) walks the executed notebook tour.
- [Pettorch](./pettorch.md) connects PyTorch through the public integration surface.
