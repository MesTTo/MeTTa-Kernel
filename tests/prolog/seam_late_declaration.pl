% Purpose: stand in for a library that introduces a seam of its own, loaded
%   after the engine has finished booting.
% Assumes:
%   - consulted from a test, never from the engine's own load list, because
%     the whole point is that it arrives late
% Guarantees:
%   - declaring ext_point_kind/2 for a predicate this file defines publishes
%     that predicate, which is what engine/ext_points.pl's listener on the
%     multifile declaration is for
%     [tested: a_seam_declared_in_a_later_file_is_exported; commit=8fa9d546b3eebf3424ef1d667feab40c6b0f32ae]
% Open Obligations:
%   To Do: None
%   Hacks: None
%   Future Enhancements: None

:- multifile ext_point_kind/2.

% The definition comes first deliberately: a declaration for a predicate that
% does not exist yet is skipped rather than exported, so a file that declares
% before it defines relies on the engine's boot sweep instead, which a library
% loaded at run time has already missed.
plunit_late_declared_service(reached).
ext_point_kind(plunit_late_declared_service/1, service).
