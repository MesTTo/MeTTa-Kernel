"""Purpose: expose the existing Python py-eq and py-truthy definitions to plunit.

Assumes:
  - ``petta._prelude.pythonic`` remains the conversion used by the registered
    Python operations.
Guarantees:
  - inputs are decoded by the production wire decoder before Python equality
    or truth is applied [tested: shim_python_scalar_semantics; commit=WORKTREE]
Fails when:
  - called with a value outside the production wire format.
"""

from petta._atom_wire import _atom_from_wire
from petta._prelude import pythonic


def py_eq_wire(left, right):
    """Run the exact expression installed as py-eq over two production wires."""
    return pythonic(_atom_from_wire(left)) == pythonic(_atom_from_wire(right))


def py_truthy_wire(value):
    """Run the exact expression installed as py-truthy over a production wire."""
    return bool(pythonic(_atom_from_wire(value)))
