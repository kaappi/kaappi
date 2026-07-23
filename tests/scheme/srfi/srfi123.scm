;; SRFI-123 (Generic accessor and modifier operators) conformance tests
;; Run directly: zig-out/bin/kaappi --lib-path lib tests/scheme/srfi/srfi123.scm

(import (scheme base) (scheme process-context) (srfi 64)
        (srfi 123) (srfi 69) (srfi 111))

(test-begin "srfi-123")

;;; --- ref on pairs: car, cdr, and non-negative integer index ---
(test-equal 'a (ref '(a b c) 'car))
(test-equal '(b c) (ref '(a b c) 'cdr))
(test-equal '(b c . d) (ref '(a b c . d) 'cdr))
(test-equal 'a (ref '(a b c) 0))
(test-equal 'b (ref '(a b c) 1))
(test-equal 'c (ref '(a b c . d) 2))

;; invalid field for a pair is an error
(test-equal #t (guard (e (#t #t)) (ref '(a b c) 'bogus) #f))

;;; --- ref on vectors ---
(test-equal 20 (ref #(10 20 30) 1))
(test-equal 10 (ref #(10 20 30) 0))

;;; --- ref on strings ---
(test-equal #\b (ref "abc" 1))
(test-equal #\a (ref "abc" 0))

;;; --- ref on bytevectors (always 8-bit unsigned; no SRFI-4 here) ---
(test-equal 2 (ref (bytevector 0 1 2 3) 2))
(test-equal 0 (ref (bytevector 0 1 2 3) 0))

;;; --- ref on hash tables: the one sparse built-in type ---
(define ht (make-hash-table))
(hash-table-set! ht "foo" "Foobar.")
(test-equal "Foobar." (ref ht "foo"))
(test-equal "Foobar." (ref ht "foo" 'not-found))
(test-equal 'not-found (ref ht "missing" 'not-found))

;; absent key with no default is an error
(test-equal #t (guard (e (#t #t)) (ref ht "missing") #f))

;;; --- ref on SRFI 111 boxes: field must be the symbol * ---
(test-equal 42 (ref (box 42) '*))
(test-equal #t (guard (e (#t #t)) (ref (box 42) 'bogus) #f))

;;; --- spec fidelity: supplying a default for a non-sparse type errors ---
(test-equal #t (guard (e (#t #t)) (ref '(0 1 2) 3 'default) #f))
(test-equal #t (guard (e (#t #t)) (ref #(1 2 3) 0 'default) #f))

;;; --- no applicable type at all ---
(test-equal #t (guard (e (#t #t)) (ref 42 'x) #f))

;;; --- ref* / ~ chained access (2-3 levels deep) ---
(define nested (vector (list 'a (box 99)) #(1 2 3)))
(test-equal 99 (ref* nested 0 1 '*))
(test-equal 99 (~ nested 0 1 '*))
(test-equal 2 (~ nested 1 1))
(test-equal 'a (ref* nested 0 0))

;; ref* with a single field behaves exactly like ref
(test-equal 'a (ref* '(a b c) 0))
(test-equal 'a (~ '(a b c) 0))

;; chaining through a hash table (existing key succeeds; ref* never
;; supplies a default, so a missing key mid-chain is an error)
(define ht2 (make-hash-table))
(hash-table-set! ht2 'a (vector 1 2 3))
(test-equal 2 (ref* ht2 'a 1))
(test-equal #t (guard (e (#t #t)) (ref* ht2 'missing-key 1) #f))

;;; --- set! integration ---
;; Kaappi's compiler desugars (set! (proc args...) val) into
;; ((setter proc) args... val) whenever `setter` is in scope; (srfi 123)
;; re-exports SRFI 17's `setter`/`getter-with-setter`, so this works with
;; just (import (srfi 123)) — no separate (srfi 17) import needed.

;; (set! (ref object field) value)
(let ((v (vector 1 2 3)))
  (set! (ref v 1) 99)
  (test-equal #(1 99 3) v))

(let ((p (list 1 2 3)))
  (set! (ref p 'car) 'x)
  (test-equal '(x 2 3) p))

(let ((p (list 1 2 3)))
  (set! (ref p 1) 'y)
  (test-equal '(1 y 3) p))

(let ((s (string-copy "abc")))
  (set! (ref s 1) #\x)
  (test-equal "axc" s))

(let ((bv (bytevector 0 0 0)))
  (set! (ref bv 1) 42)
  (test-equal (bytevector 0 42 0) bv))

(let ((bx (box 1)))
  (set! (ref bx '*) 2)
  (test-equal 2 (unbox bx)))

(let ((ht3 (make-hash-table)))
  (set! (ref ht3 "k") "v")
  (test-equal "v" (hash-table-ref ht3 "k")))

;; (set! (~ object f1 f2 f3) value) -- 2-deep chained setter
(let* ((inner (box 1))
       (outer (vector 'x inner)))
  (set! (~ outer 1 '*) 42)
  (test-equal 42 (unbox inner)))

(let* ((p (list 1 2 3))
       (v (vector p 'other)))
  (set! (~ v 0 1) 99)
  (test-equal '(1 99 3) p))

;; (set! (~ object f1 f2 f3) value) -- 3-deep chained setter
(let* ((leaf (box 5))
       (mid (vector leaf))
       (top (list mid)))
  (set! (~ top 0 0 '*) 77)
  (test-equal 77 (unbox leaf)))

;; ref*'s setter also works when accessed programmatically via (setter ref*)
(let* ((leaf (box 5))
       (mid (vector leaf))
       (top (list mid)))
  ((setter ref*) top 0 0 '* 88)
  (test-equal 88 (unbox leaf)))

;;; --- register-getter-with-setter!: extend the dispatch with a new type ---
(define-record-type <point>
  (make-point x y)
  point?
  (x point-x set-point-x!)
  (y point-y set-point-y!))

(define (%point-ref object field)
  (case field
    ((x) (point-x object))
    ((y) (point-y object))
    (else (error "point-ref: invalid field" field))))

(define (%point-set! object field value)
  (case field
    ((x) (set-point-x! object value))
    ((y) (set-point-y! object value))
    (else (error "point-set!: invalid field" field))))

(register-getter-with-setter!
 point? (getter-with-setter %point-ref %point-set!) #f)

(define pt (make-point 3 4))
(test-equal 3 (ref pt 'x))
(test-equal 4 (ref pt 'y))

;; set! through a custom-registered getter
(set! (ref pt 'x) 10)
(test-equal 10 (point-x pt))

;; ref* / ~ through a custom-registered type
(define holder (vector pt))
(test-equal 4 (ref* holder 0 'y))
(set! (~ holder 0 'y) 20)
(test-equal 20 (point-y pt))

(let ((runner (test-runner-current)))
  (test-end "srfi-123")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
