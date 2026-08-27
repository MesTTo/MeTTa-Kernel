;The first program. There is no main, no declaration and no import: a file
;is a list of forms, and a form prefixed with ! is RUN when the reader
;reaches it. The engine prints what it answers.
;
;    sh run.sh examples/ch01-getting-started/01-hello.metta
;
;prints 42.
!(+ 40 2)

;A form without the ! is DATA. This one is stored, not run, and nothing is
;printed for it.
(the-answer 42)

;So the same text means two things depending on one character, and that is
;the whole of the directive. Chapter 5 comes back to why data and calls look
;alike; for now, ! means run.
!(+ 2 (* 2 20))
