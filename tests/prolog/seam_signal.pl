% A library's own control signal, contributed the way a library contributes
% to any of the engine's static multifile seams: by consulting a file. A
% runtime assertz raises "No permission to modify static procedure".
%
% Without this, a cancellation a library raises is swallowed by the first
% recovery catch it meets and the program continues as though nothing
% happened, which is what the engine's own limit signals used to do before
% control_exception/1 existed.
:- multifile control_exception/1.

control_exception(plunit_seam_cancelled).
