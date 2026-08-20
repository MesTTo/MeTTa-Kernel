; Purpose: demonstrate cataloged defaults and a per-function dispatch override.
; Guarantees:
;   - removing an override restores the declared default on an existing call.
;   [tested: test_every_dispatch_axis_is_readable_settable_and_defaulted; commit=WORKTREE]

(= (only-a A) hit)

!(test (only-a B) (only-a B))
!(add-atom &petta (dispatch-policy only-a NoMatchEnum NoMatchFail))
!(test (collapse (only-a B)) ())
!(remove-atom &petta (dispatch-policy only-a NoMatchEnum NoMatchFail))
!(test (only-a B) (only-a B))
