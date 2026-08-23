# Jupyter notebooks

The executed [notebook tour](https://github.com/trueagi-io/PeTTa/blob/python-library/notebooks/tour.ipynb) starts with Python atoms, keeps Python and MeTTa in one session, and ends with a rendered derivation tree.

Load the extension in an ordinary Python kernel. `use(m)` points the cell magic at an existing `MeTTa` instance, so Python calls and MeTTa cells read and write the same space:

```python
%load_ext metta.ipython
from metta.ipython import use

use(m)
```

Start a cell with `%%metta` to run the rest of that cell as MeTTa source. The magic prints one line for each directive and returns the structured answer groups as the cell value:

```python
%%metta
!(+ 1 2)
(Parent Zoe Lia)
!(match (context-space) (Parent $parent $child) ($parent $child))
```

Without `use(m)`, the extension creates its own default `MeTTa` runtime. A space name after `%%metta` targets that named space for one cell.
