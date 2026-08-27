;; A function can answer a SPACE NAME, and the write lands in that space. The
;; name is a space the moment it is written to, so nothing has to create it
;; first; the & prefix is what makes it a space name rather than an ordinary
;; symbol, which is the same rule evalc and is-space state.
(= (space) &my_space_name)

!(add-atom (space) (my test atom))
!(test (match (space) $a $a) (my test atom))
