% Purpose: the seam side of the C store: four multifile clauses that make
%   '&cstore' a space whose atoms live in cstore.c, crossing as the
%   engine's own text.
% Assumes:
%   - cstore.so sits beside this file and was built with the README's
%     swipl-ld line; loading without it raises, because half built is an
%     error where not built is a skip (the example's own guard decides)
% Guarantees:
%   - only published services are called: swrite/2, sread/2 and
%     metta_unwritable_symbol/2, the text seam EXTENDING.md declares
%   - no match clause, deliberately: enumerate is declared, so the engine
%     filters the enumeration against a bound pattern itself, and
%     unification never leaves the engine
%   - removal is by unification over the enumeration and takes ONE
%     occurrence, so it means what remove-atom means everywhere; the store
%     itself only ever compares exact text
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

:- metta_extension(cstore_example, [version('1.0.0')]).

:- use_module(library(shlib)).
:- prolog_load_context(directory, Dir),
   directory_file_path(Dir, 'cstore.so', Artefact),
   use_foreign_library(Artefact, install_cstore).

:- multifile seam:foreign_space/1.
:- multifile seam:foreign_capability/2.
:- multifile seam:foreign_add/2.
:- multifile seam:foreign_remove/3.
:- multifile seam:foreign_atoms/2.
:- multifile seam:foreign_clear/1.

seam:foreign_space('&cstore').

seam:foreign_capability('&cstore', add).
seam:foreign_capability('&cstore', remove).
seam:foreign_capability('&cstore', enumerate).
seam:foreign_capability('&cstore', clear).

%Being a shared library is a text problem: a symbol the grammar cannot
%read back must be refused where it is written, not stored and lost.
seam:foreign_add('&cstore', Atom) :-
    (   metta_unwritable_symbol(Atom, Bad)
    ->  throw(error(domain_error(cstore_text_symbol, Bad),
                    context('add-atom'/3,
                            'that name cannot cross a text boundary')))
    ;   swrite(Atom, Text),
        cstore_add(Text)
    ).

%Removal takes ONE stored occurrence that UNIFIES with the pattern, the
%multiset subtraction remove-atom is everywhere, and answers whether one
%was there. Unification happens here; the store removes an exact line.
%
%\+ Atom \= Pattern rather than Atom = Pattern, so the pattern comes back
%as it went in: remove-atom answers unit, not a binding.
%
%cstore_remove_text/2 is asked for 1 rather than handed a free variable
%because the enumeration walks a snapshot: another thread may take the
%line between finding it and removing it, and then nothing was removed
%here and the answer has to say so.
seam:foreign_remove('&cstore', Pattern, Removed) :-
    (   once(( cstore_text(Text),
               sread(Text, Atom),
               \+ Atom \= Pattern )),
        cstore_remove_text(Text, 1)
    ->  Removed = true
    ;   Removed = false
    ).

seam:foreign_atoms('&cstore', Atom) :-
    cstore_text(Text),
    sread(Text, Atom).

seam:foreign_clear('&cstore') :-
    cstore_clear.
