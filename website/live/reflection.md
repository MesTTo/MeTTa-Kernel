# Reflection and steering

The Python surface describes itself in the `&petta` space. Registered operations appear as `(op name arity kind)` facts. Functions compiled with `@m.define` appear as `(defined space name)`. Standing queries appear as `(subscription space pattern on)`. Each fact is removed when the operation, definition, or subscription is removed.

Because `&petta` is an ordinary space, MeTTa programs can inspect the Python integration with normal matching. The direction also reverses: a Python standing query on `&petta` can watch for control atoms written by a MeTTa program. The program then steers the integration through the same fact and subscription mechanisms used elsewhere.

Object reflection has a separate but compatible surface. `install_reflection_ops(m)` adds `py-attr` and the two-mode `py-field`. With a bound field name, `py-field` reads that field. With an unbound field name, it enumerates an object's fields as relation answers.

`metta.spaces.object_view(obj)` gives those fields storage semantics instead of operation semantics. The view emits live `(py-field obj name value)` atoms, joins with stored spaces through the ordinary `spaces.union` combinator, and maps added field atoms to `setattr`. Python mutation therefore changes the next match without another projection.

An integration can also register a reflector that lowers its own structure into facts. `metta.integrate.reflect(m, name, object)` chooses the registered reflector and returns the number of facts written.

Use [`metta.ops`](../reference/metta-ops) for operation reflection, [`metta.subscribe`](../reference/metta-subscribe) for standing queries, and [`metta.integrate`](../reference/metta-integrate) for object reflection.
