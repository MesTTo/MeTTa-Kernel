!(import! &self _fixtures/imports/overhaul/duplicate)
!(import! &self ./_fixtures/imports/overhaul/./duplicate.metta)
!(import! &self _fixtures/imports/overhaul/cycle_a)

!(test (collapse (duplicate-import-result)) (loaded-once))
!(test (cycle-a) a)
!(test (cycle-b) b)
