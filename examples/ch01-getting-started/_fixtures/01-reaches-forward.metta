;THE PERMANENT NEGATIVE CONTROL for tests/checks/check_cumulative_syntax.py.
;Do not fix this file. Fixing it deletes the lane.
;
;By its path this is a chapter-1 file, and it uses two constructs the corpus
;does not introduce until chapters 15 and 22. Every run of the lane scans it
;and requires the law to catch it; a run that finds nothing wrong here says
;the lane has stopped checking, and it fails rather than reporting a green it
;did not earn. That has happened in this tree before, which is why the control
;is a file in the corpus rather than a line in a test.
;
;It sits under _fixtures/, so every runner's own find excludes it: it is never
;executed, never counted as an example, and never used to derive the
;introduction table it violates.
!(test (hyperpose ((+ 1 1) (+ 2 2))) (2 4))
!(test (max 1 2) 2)
