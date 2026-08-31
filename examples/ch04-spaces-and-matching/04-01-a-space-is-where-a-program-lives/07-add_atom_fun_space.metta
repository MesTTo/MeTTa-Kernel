;; A function can answer a SPACE NAME, and the write lands in that space. The
;; name is a space the moment it is written to, so nothing has to create it
;; first, and it needs no prefix: upstream builds a space operation as
;; `Term =.. [Space, Rel|Args]`, so ANY symbol is a legal space name.
(= (space) my_space_name)

!(add-atom (space) (my test atom))
!(test (match (space) $a $a) (my test atom))

;; is-space asks the NARROWER question and still wants the & prefix, which is
;; upstream's own split rather than a contradiction: the doors read a bare
;; symbol that is-space calls false.
!(test (is-space my_space_name) False)
!(test (is-space &self) True)
