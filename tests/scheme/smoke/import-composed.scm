(import (scheme base) (scheme write))

(define pass 0)
(define fail 0)
(define (check name got expected)
  (if (equal? got expected) (set! pass (+ pass 1))
      (begin (set! fail (+ fail 1))
             (display "FAIL: ") (display name)
             (display " expected ") (write expected)
             (display " got ") (write got) (newline))))

;; prefix + only (composed import): imported as s:car, s:cdr
(import (prefix (only (scheme base) car cdr) s:))
(check "prefix+only car" (s:car (cons 1 2)) 1)
(check "prefix+only cdr" (s:cdr (cons 1 2)) 2)

;; except: import everything except car/cdr
(import (except (scheme base) car cdr))
(check "except cons" (cons 'a 'b) '(a . b))

;; rename
(import (rename (scheme base) (car first) (cdr rest)))
(check "rename first" (first '(10 20 30)) 10)
(check "rename rest" (rest '(10 20 30)) '(20 30))

(display pass) (display " passed, ") (display fail) (display " failed")
(newline)
(if (> fail 0) (error "composed import tests failed" fail))
