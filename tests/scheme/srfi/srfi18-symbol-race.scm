;; Regression test for issue #797:
;; The parent thread must not intern symbols into the shared symbol table
;; without holding symbol_mutex. Before the fix, GC.allocSymbol only locked
;; when called from a child GC (shared_symbols != null); the parent — whose
;; `symbols` field *is* the shared table the child aliases — interned with no
;; lock. A parent-side string->symbol whose put() rehashes the StringHashMap
;; (realloc + free of the bucket array) racing a live child thread's locked
;; get()/put() on the same table corrupts the map and panics ("reached
;; unreachable code") inside allocSymbol.
;;
;; Both threads intern many DISTINCT new symbols so the shared table rehashes
;; repeatedly on both sides at once — that broad, constant contention makes the
;; race fire reliably (crashes on every unfixed run here, ReleaseSafe and Debug
;; alike). With the fix both threads serialize on symbol_mutex and the script
;; prints OK.
;;
;; Note: symbols a *child* interns are not freed (child GCs skip trackObject) —
;; a separate, pre-existing leak, not what #797 is about. It is only observable
;; under the Debug leak-checking allocator on a *clean* exit, so it never shows
;; in CI: the unfixed run panics before teardown (no leak report), and the
;; fixed run passes (run-all.sh prints test output only on failure).

(import (scheme base) (scheme write) (srfi 18))

(define (spin n prefix)
  (let loop ((i 0))
    (if (< i n)
        (begin (string->symbol (string-append prefix (number->string i)))
               (loop (+ i 1)))
        'done)))

(define t (make-thread (lambda () (spin 1000 "child-"))))
(define started (thread-start! t))
(define parent-result (spin 1000 "parent-"))   ;; interns concurrently with child

(unless (and (eq? parent-result 'done)
             (eq? (thread-join! t) 'done))
  (display "FAIL: a thread did not complete")
  (newline)
  (exit 1))

(display "OK")
(newline)
