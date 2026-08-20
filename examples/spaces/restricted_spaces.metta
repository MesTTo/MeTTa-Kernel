; Purpose: show curated execution bases and explicit capability grants.

;A restricted space retains ordinary computation and its own equations.
!(new-space &locked (restricted))
!(add-atom &locked (= (double $x) (* $x 2)))
!(test (evalc (double 21) &locked) 42)

;The file operation reaches a runtime refusal that catch can inspect.
!(test
   (if-error
      (catch
         (evalc
            (exists_file "examples/spaces/restricted_spaces.metta")
            &locked))
      refused
      answered)
   refused)

;A capability is granted explicitly when the space is created.
!(new-space &reader (restricted (grants file)))
!(test
   (evalc
      (exists_file "examples/spaces/restricted_spaces.metta")
      &reader)
   true)
