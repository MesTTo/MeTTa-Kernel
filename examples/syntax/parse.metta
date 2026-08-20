!(test (parse "A") A)
!(test (parse "(R A B)") (R A B))
!(test (parse "(R A (S B C))") (R A (S B C)))
; quote retains its wrapper in LeaTTa types-meta/30_evaluation_control.metta;
; noeval holds the parsed expression without adding that wrapper.
!(test (parse "(* 2 21)") (noeval (* 2 21)))
!(test (parse "\"42\"") "42")
!(test (parse (repr "C:\\Users\\bob")) "C:\\Users\\bob")
!(test (parse (repr "say \"hi\"")) "say \"hi\"")
!(test (parse (repr "a\\nb")) "a\\nb")
