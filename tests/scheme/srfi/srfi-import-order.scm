;; Regression test for issue #1010: GC during library include-load corrupted
;; compilation, so this exact import sequence failed with a CompileError
;; masked as "library not found: (srfi.158)".
;;
;; Two distinct GC holes conspired:
;;   1. compileNamedLet built its desugared lambda from fresh unrooted pairs
;;      across renameInBody (which allocates enough to trigger a collection
;;      on a large body such as gdelete-neighbor-dups in 158-impl.scm).
;;   2. handleTopLevelForm never rooted the (import ...) datum itself, so a
;;      collection during the library load could sweep the form mid-walk.
;;
;; The failure was a GC-timing window: it needed the heap state produced by
;; importing (scheme base)/(scheme write) and then (srfi 115) before
;; (srfi 158). Keep the sequence exactly as-is.
(import (scheme base) (scheme write))
(import (srfi 115))
(import (srfi 158))

;; The same window made importing (srfi 64) and (srfi 158) together fail
;; nondeterministically (~75% of runs). Import it too while the heap is warm.
(import (srfi 64))

(define pass 0)
(define fail 0)
(define (check name got expected)
  (if (equal? got expected) (set! pass (+ pass 1))
      (begin (set! fail (+ fail 1))
             (display "FAIL: ") (display name)
             (display " expected ") (write expected)
             (display " got ") (write got) (newline))))

;; Exercise the definition whose compilation was corrupted (a large
;; case-lambda containing a named let).
(check "gdelete-neighbor-dups"
  (generator->list (gdelete-neighbor-dups (generator 1 1 2 2 3 3 3 1)))
  '(1 2 3 1))

;; Exercise (srfi 115) to confirm the earlier import stayed intact.
(check "regexp-matches"
  (regexp-matches? '(+ alpha) "abc")
  #t)

(display "srfi-import-order: ")
(display pass)
(display " passed, ")
(display fail)
(display " failed")
(newline)
(when (> fail 0) (error "srfi-import-order tests failed"))
