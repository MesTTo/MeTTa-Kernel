# `metta.convert`

Source: `bindings/python/metta/convert.py`.

> Purpose: public two-way conversion facade and registration API.
> Guarantees:
>   - public names preserve the metta.convert import surface after directional
>     module cuts [tested test_build_reverses_the_projection,
>     test_registered_custom_type_round_trips]
>   - type registrations can be removed without leaving constructor or name
>     ownership behind [tested
>     test_type_registration_can_be_removed_and_its_name_reclaimed]
> Open Obligations:
>   To Do: None
>   Hacks: None
>   Future Enhancements: None.

The entries below reproduce the source signatures and docstrings.

