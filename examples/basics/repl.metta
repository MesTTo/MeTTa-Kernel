;A console, in a dozen lines.
;
;(read-form!) reads until the brackets balance, so a form may span as many
;lines as it likes and a blank line re-prompts rather than erroring. (readln!)
;could not do either: it is one line, one form, so typing (= (f $x) and
;pressing enter was a syntax error instead of a continuation.
;
;The decision is (sread-command $text), which answers (complete $term),
;incomplete, or raises, and has no I/O in it at all. That is CPython's split
;between InteractiveInterpreter and InteractiveConsole, and it is why a
;Jupyter kernel or an editor integration can share this answer without
;sharing this loop.

;A definition is STORED; anything else is evaluated and printed.
;
;The test is on the HEAD SYMBOL, and the two spellings that look more natural
;both fail. `(case $form (((= $h $b) ...) ...))` reads `=` as unification
;rather than as a pattern, and `(== $form (quote (= $h $b)))` compares against
;the quote form itself; each answers "other" for every input. is-expr guards
;car-atom, which a bare symbol would otherwise trip over.
;
;%Undefined% for the RETURN, because a console prints whatever it gets and the
;answer's type is the program's business, not this loop's. Declaring the
;return Atom instead makes the body come back as data: (console-step (+ 1 2))
;answers the case term itself rather than 3.
;
;Atom for the PARAMETER: a console's input arrives as WRITTEN. Without it the
;argument is evaluated on the way in, so (= (f $x) (+ $x 1)) runs its own body
;with $x unbound and refuses with "+ ran backwards with more than one unknown"
;instead of being stored.
(: console-step (-> Atom %Undefined%))
(= (console-step $form)
   (if (and (is-expr $form) (== (car-atom $form) =))
       (add-atom &self $form)
       (println! (eval $form))))

(= (console)
   (let $form (read-form!)
        (if (== $form end_of_file)
            (empty)
            (let $done (console-step $form) (console)))))

!(console)
