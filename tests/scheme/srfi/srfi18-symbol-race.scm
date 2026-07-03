;; Regression test for issue #797:
;; The parent thread must not intern symbols into the shared symbol table
;; without holding symbol_mutex. Before the fix, GC.allocSymbol only locked
;; when called from a child GC (shared_symbols != null); the parent — whose
;; `symbols` field *is* the shared table the child aliases — interned with no
;; lock. A parent-side string->symbol racing a live child thread's locked
;; put() could rehash the StringHashMap (realloc + free of the bucket array)
;; mid-access, corrupting the map and panicking ("reached unreachable code")
;; in allocSymbol's put. Reproduced 5/5 on the unfixed build.

(import (scheme base) (scheme write) (srfi 18))

;; Intern many *distinct* new symbols so the shared table repeatedly rehashes,
;; which is what triggers the race.
(define (spin n prefix)
  (let loop ((i 0))
    (if (< i n)
        (begin
          (string->symbol (string-append prefix (number->string i)))
          (loop (+ i 1)))
        'done)))

(define t (make-thread (lambda () (spin 200000 "child-"))))
(define started (thread-start! t))
(define parent-result (spin 200000 "parent-"))  ;; interns concurrently with child

(unless (and (eq? parent-result 'done)
             (eq? (thread-join! t) 'done))
  (display "FAIL: a thread did not complete")
  (newline)
  (exit 1))

(display "OK")
(newline)
