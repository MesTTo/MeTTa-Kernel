; Purpose: demonstrate cataloged defaults and a per-function dispatch override.
; Guarantees:
;   - removing an override restores the declared default on an existing call.
;   [tested: test_every_dispatch_axis_is_readable_settable_and_defaulted; commit=0d90e628b1f90c4b4464a2907efcb357d74b13d3]

; A function that HAS equations but whose call matches none of them answers
; NOTHING. That is NoMatchEnum's default, NoMatchFail, and it is what upstream
; does: it compiles each equation to a Prolog clause, so a call with no
; matching clause simply has nowhere to go.
(= (only-a A) hit)

!(test (collapse (only-a B)) ())

; NoMatchOriginal is the other choice: keep the call as written, which is what
; an expression whose head means nothing here already does. Naming it for one
; function changes that function and nothing else.
!(add-atom &metta (dispatch-policy only-a NoMatchEnum NoMatchOriginal))
!(test (only-a B) (only-a B))

; Removing the override restores the cataloged default on the same call.
!(remove-atom &metta (dispatch-policy only-a NoMatchEnum NoMatchOriginal))
!(test (collapse (only-a B)) ())
