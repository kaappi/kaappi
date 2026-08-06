;;; Large-index bounds checking across the vector-like accessors, and the
;;; cross-tier regression probe for kaappi#1912.
;;;
;;; Natively this is an ordinary regression test: an index far beyond any
;;; container's length must raise, whether or not its low 32 bits happen to be
;;; in range.
;;;
;;; It is also the WASM cross-tier probe. Before #1912 was fixed, index
;;; arguments were @intCast to usize INSIDE the bounds comparison, and usize
;;; is u32 on wasm32, so 2^32+1 wrapped to 1 before the check, passed it, and
;;; aliased element 1 — a silent wrong read, and for vector-set! a silent
;;; wrong WRITE to a valid-but-unintended element. Measured (wasmtime 46.0.0,
;;; v0.22.1):
;;;
;;;     (vector-ref v 4294967297)   native: raised   wasm32: 11
;;;     (vector-set! v 4294967297 99) then (vector-ref v 1)
;;;                                 native: 11       wasm32: 99
;;;
;;; The fix (primitives.fixnumIndexInBounds) compares in u64 BEFORE narrowing
;;; to usize, and every case below now raises identically on both tiers — the
;;; file's KNOWN_DIFFS entry in run-wasm-differential.sh was deleted when the
;;; tiers agreed again.
;;;
;;; The 2^32+9 line is the discriminating control that makes this attributable
;;; to low-32-bit truncation rather than to a missing bounds check: its low 32
;;; bits are 9, which still exceeds the length 4, so it raises on BOTH tiers
;;; (it raised even before the fix).
;;;
;;; Deliberately import-free so it runs on every tier — which is why this is
;;; the one file in the corpus that signals failure with a bare `(exit 1)`
;;; rather than the SRFI-64 epilogue every other file uses (kaappi#2116).
;;; `(import (srfi 64))` would make the WASM leg fail at library load
;;; (kaappi#2108, no .sld on WASM), and run-wasm-differential.sh classifies
;;; that as LIBDIFF — dropping this file from the cross-tier comparison it
;;; exists for. The printed lines are unchanged and remain the cross-tier
;;; comparison channel; the exit status is the native verdict layered on top.

(define v (vector 10 11 12 13))
(define s (make-string 4 #\a))
(string-set! s 0 #\a) (string-set! s 1 #\b) (string-set! s 2 #\c) (string-set! s 3 #\d)
(define bv (bytevector 10 11 12 13))
(define rt (%make-record-type "large-index-probe" 3))
(define r (%make-record rt 1 2 3))
(define nv (%make-numeric-vector 's8 4 7))

(define (try thunk) (guard (e (#t 'raised)) (thunk)))

;; Every accessor must raise for 2^32+1 (whose low 32 bits ARE in range for a
;; 4-element container — the truncation case) and for the 2^32+9 control
;; (whose low 32 bits are out of range — the missing-bounds-check case).
(define cases
  (list
    (cons "vector-ref"         (lambda (i) (vector-ref v i)))
    (cons "vector-set!"        (lambda (i) (vector-set! v i 99)))
    (cons "string-ref"         (lambda (i) (string-ref s i)))
    (cons "string-set!"        (lambda (i) (string-set! s i #\X)))
    (cons "bytevector-u8-ref"  (lambda (i) (bytevector-u8-ref bv i)))
    (cons "bytevector-u8-set!" (lambda (i) (bytevector-u8-set! bv i 99)))
    (cons "substring"          (lambda (i) (substring s i (+ i 1))))
    (cons "vector-swap!"       (lambda (i) (vector-swap! v i 0)))
    (cons "vector-copy!"       (lambda (i) (vector-copy! v i (vector 9 9))))
    (cons "bytevector-copy!"   (lambda (i) (bytevector-copy! bv i (bytevector 9 9))))
    (cons "string-copy!"       (lambda (i) (string-copy! s i "xy")))
    (cons "string-take"        (lambda (i) (string-take s i)))
    (cons "string-drop"        (lambda (i) (string-drop s i)))
    (cons "string-replace"     (lambda (i) (string-replace s "X" i (+ i 1))))
    (cons "take"               (lambda (i) (take '(1 2 3) i)))
    (cons "split-at"           (lambda (i) (split-at '(1 2 3) i)))
    (cons "%record-ref"        (lambda (i) (%record-ref r i rt)))
    (cons "%record-set!"       (lambda (i) (%record-set! r i 9 rt)))
    (cons "%numeric-vector-ref"    (lambda (i) (%numeric-vector-ref nv i)))
    (cons "%numeric-vector-set!"   (lambda (i) (%numeric-vector-set! nv i 1)))))

(for-each
  (lambda (case)
    (let ((name (car case)) (thunk (cdr case)))
      (display (list name "2^32+1" (try (lambda () (thunk 4294967297)))))
      (newline)
      (display (list name "2^32+9" (try (lambda () (thunk 4294967305)))))
      (newline)))
  cases)

;; The write side is the serious half: after a rejected set!, every element
;; must be untouched.  (The cases above all raised, so the containers below
;; are pristine.)
(define elt1 (vector-ref v 1))
(display (list 'set-2^32+1 'elt1 elt1))
(newline)

;; Native verdict. On wasm32 this file's lines must match byte-for-byte (the
;; differential harness compares stdout), and the exit status is the native
;; verdict layered on top.
(define failures 0)
(define (check ok name)
  (if (not ok)
      (begin
        (set! failures (+ failures 1))
        (display "FAIL: ")
        (display name)
        (newline))))

(for-each
  (lambda (case)
    (let ((name (car case)) (thunk (cdr case)))
      (check (eq? (try (lambda () (thunk 4294967297))) 'raised)
             (string-append name " 2^32+1 must raise"))
      (check (eq? (try (lambda () (thunk 4294967305))) 'raised)
             (string-append name " 2^32+9 must raise"))))
  cases)

(check (= elt1 11) "vector element 1 must be untouched by the rejected set!")
(check (eq? (string-ref s 1) #\b) "string element 1 must be untouched")
(check (= (bytevector-u8-ref bv 1) 11) "bytevector element 1 must be untouched")
(check (= (%record-ref r 1 rt) 2) "record field 1 must be untouched")
(check (= (%numeric-vector-ref nv 1) 7) "numeric-vector element 1 must be untouched")

;; In-range sanity: the same accessors still work at a legal index.
(check (= (vector-ref v 1) 11) "in-range vector-ref still works")
(check (string=? (substring s 1 3) "bc") "in-range substring still works")
(check (equal? (take '(1 2 3) 2) '(1 2)) "in-range take still works")

(if (> failures 0) (exit 1))
