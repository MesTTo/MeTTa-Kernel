% Purpose: name a foreign space WITHOUT the '&' prefix, so the space-name scan
%   in tests/prolog/static_checks.pl can be shown to see one before its clean
%   result is accepted.
% Assumes: consulted and then unload_file/1'd by that scan alone. It is a FILE
%   rather than assertz'd clauses because seam:foreign_space/1 is multifile and
%   STATIC, so a runtime assertz raises "No permission to modify static
%   procedure"; tests/prolog/seam_provider.pl records the same constraint.
% Guarantees: exactly one clause, on one seam, naming one atom that no other
%   file in this repository names, so a scan that reports this name is
%   reporting this plant and nothing else.
% Fails when: left loaded. The name it plants is one metta_space_operand/1
%   answers no about, which is the defect the scan exists to refuse.

:- multifile seam:foreign_space/1.

seam:foreign_space('static-check-space-without-ampersand').
