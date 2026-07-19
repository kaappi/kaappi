;; SRFI-260 — Generated Symbols conformance test.
;;
;; generate-symbol mints a fresh, unpredictable symbol on every call. The
;; defining property versus an uninterned symbol (SRFI 258) is write/read
;; invariance: a generated symbol printed and read back is eq? to the original.
;; Deterministic API-level behaviour is also covered in src/tests_srfi260.zig.

(import (scheme base) (scheme write) (scheme read)
        (scheme process-context) (srfi 64) (srfi 260))

(test-begin "srfi-260")

;; --- Basic shape ---------------------------------------------------------

(test-assert "generate-symbol returns a symbol" (symbol? (generate-symbol)))
(test-assert "accepts a pretty-name string" (symbol? (generate-symbol "pretty")))
(test-assert "symbol->string is a string"
  (string? (symbol->string (generate-symbol "p"))))

;; --- Freshness / identity ------------------------------------------------

(test-assert "two calls are distinct"
  (not (eq? (generate-symbol) (generate-symbol))))
(test-assert "same pretty-name still distinct"
  (not (eq? (generate-symbol "x") (generate-symbol "x"))))
(test-assert "a generated symbol is eq? to itself"
  (let ((g (generate-symbol))) (eq? g g)))
(test-assert "distinct from an ordinary interned symbol"
  (not (eq? (generate-symbol "g") 'g)))

;; A batch of generated symbols is pairwise distinct.
(define (all-distinct? lst)
  (cond ((null? lst) #t)
        ((memq (car lst) (cdr lst)) #f)
        (else (all-distinct? (cdr lst)))))
(test-assert "1000 generated symbols are pairwise distinct"
  (all-distinct?
   (let loop ((i 0) (acc '()))
     (if (= i 1000) acc (loop (+ i 1) (cons (generate-symbol) acc))))))

;; --- Write/read invariance (the key distinction from uninterned symbols) --

(test-assert "write/read round-trips to an eq? symbol"
  (let ((g (generate-symbol)) (out (open-output-string)))
    (write g out)
    (eq? g (read (open-input-string (get-output-string out))))))

(test-assert "write/read round-trips a pretty-named symbol"
  (let ((g (generate-symbol "counter")) (out (open-output-string)))
    (write g out)
    (eq? g (read (open-input-string (get-output-string out))))))

;; A generated symbol's name equals itself via string->symbol (interned).
(test-assert "string->symbol of the name is eq? to the symbol"
  (let ((g (generate-symbol)))
    (eq? g (string->symbol (symbol->string g)))))

;; --- Derived cond-expand feature id (#1649) ------------------------------

(test-equal "cond-expand srfi-260" 'yes
  (cond-expand (srfi-260 'yes) (else 'no)))

(let ((runner (test-runner-current)))
  (test-end "srfi-260")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
