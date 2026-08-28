;; Fixture for srfi-241-202-bundle-2391.sh: the standalone-binary smoke for
;; the er-macro-transformer re-port of SRFI 241/202 (kaappi#2391). One line
;; per lifted capability; the driving script diffs the bundled binary's
;; whole output against the interpreter's (the oracle).
;;
;; Deliberately NOT added to the shared bundle-replay fixture: that fixture's
;; .sbc bytes must stay independent of the srfi .sld search path, and its
;; three scripts assert lines of their own.
(import (scheme base) (scheme write) (srfi 241) (srfi 202))

;; kaappi#2391 lifts 1+2: compound subpattern under an ellipsis, and a
;; mandatory pattern after it.
(display "2391-a: ")
(write (match '((1 2) (3 4) (5 6) end)
         (((,a ,b) ... ,tail) (list a b tail))))
(newline)

;; kaappi#2391 lift 3: the ellipsis-aware quasiquote inside a clause body.
(display "2391-b: ")
(write (match '(1 2 3) ((,x ... ,y) `(prefix ,x ... suffix ,y))))
(newline)

;; kaappi#2391: SRFI 202 with a vector pattern claw, a guard claw, and a
;; values-collecting claw in one and-let*.
(display "2391-c: ")
(write (and-let* ((`#(,hi ,lo) (vector 9 4))
                  ((> hi lo))
                  ((values q r) (floor/ hi lo)))
         (list hi lo q r)))
(newline)
