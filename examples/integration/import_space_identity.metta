!(bind! &import-space-a (new-space))
!(bind! &import-space-b (new-space))

!(import! &import-space-a _fixtures/imports/overhaul/space_payload)
!(import! &import-space-b _fixtures/imports/overhaul/space_payload)

!(test (collapse (match &import-space-a (import-space-marker) present)) (present))
!(test (collapse (match &import-space-b (import-space-marker) present)) (present))

; Each importing space runs its own copy, once: one identity per space.
!(test (collapse (metta (import-space-function) %Undefined% &import-space-a)) (one-result))
!(test (collapse (metta (import-space-function) %Undefined% &import-space-b)) (one-result))

; And the caller itself imported nothing, so here the name stays data:
; an alias import admits nothing into the running context.
!(test (collapse (import-space-function)) ((import-space-function)))
