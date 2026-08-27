% A handler on the compiled-call-site dispatch seam, in a file for the same
% reason seam_provider.pl is: the hook is multifile and static, so it is
% contributed by consulting. lib/lib_memo/lib_memo.pl is the real instance of this.
%
% It records and then FAILS, which is the contract: failing means "I have no
% cached answer for this call", and the ordinary call proceeds.
:- multifile seam:dispatch_call/4.
:- dynamic plunit_dispatch_seen/1.

seam:dispatch_call(Function, _, _, _) :-
    ( plunit_dispatch_seen(Function)
      -> true
      ;  assertz(plunit_dispatch_seen(Function)) ),
    fail.
