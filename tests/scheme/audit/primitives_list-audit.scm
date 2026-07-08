;; Audit tests for src/primitives_list.zig — R7RS 6.4 list utilities, map,
;; for-each, boolean=?/symbol=?, features, string->symbol.
;; Audit campaign Phase 2.9 (#1137). Complements r7rs-tests.scm §6.4 and
;; tests/scheme/srfi/srfi1*.scm.
;; Run directly and read the printed counts — run-all.sh only sees exit codes.

(import (scheme base) (scheme write) (scheme char))
(import (chibi test))

(test-begin "primitives_list audit")

;;; --- list-ref ---
(test 'c (list-ref '(a b c d) 2))
;; R7RS 6.4 example: index computed via exact/round
(test 'c (list-ref '(a b c d) (exact (round 1.8))))
(test 'a (list-ref '(a) 0))
;; R7RS: "The list argument can be circular"
(test 2 (let ((l (list 1 2 3)))
          (set-cdr! (cddr l) l)      ; l = #0=(1 2 3 . #0#)
          (list-ref l 7)))           ; 7 mod 3 = 1 → 2
(test 'caught (guard (e (#t 'caught)) (list-ref '(a b c) 3)))
(test 'caught (guard (e (#t 'caught)) (list-ref '(a b c) -1)))
(test 'caught (guard (e (#t 'caught)) (list-ref '(a b c) 1.0)))
(test 'caught (guard (e (#t 'caught)) (list-ref '() 0)))
;; improper list: ok while the index stays within the pair spine
(test 'b (list-ref '(a b . c) 1))
(test 'caught (guard (e (#t 'caught)) (list-ref '(a b . c) 2)))

;;; --- list-tail ---
(test '(c d) (list-tail '(a b c d) 2))
(test '(a b c) (list-tail '(a b c) 0))
(test '() (list-tail '(a b c) 3))
(test 'c (list-tail '(a b . c) 2))     ; k cdrs on an improper spine
(test 'caught (guard (e (#t 'caught)) (list-tail '(a b) 3)))
(test 'caught (guard (e (#t 'caught)) (list-tail '(a b) -1)))
(test 'caught (guard (e (#t 'caught)) (list-tail '(a b) 0.5)))

;;; --- list-set! ---
;; R7RS 6.4 example
(test '(one two three)
    (let ((ls (list 'one 'two 'five!)))
      (list-set! ls 2 'three)
      ls))
(test 'caught (guard (e (#t 'caught)) (list-set! (list 1 2) 2 'x)))
(test 'caught (guard (e (#t 'caught)) (list-set! (list 1 2) -1 'x)))
(test 'caught (guard (e (#t 'caught)) (list-set! '() 0 'x)))
;; R7RS 6.4: (list-set! '(0 1 2) 1 "oops") => error ("constant list").
(test 'caught (guard (e (#t 'caught)) (list-set! '(0 1 2) 1 "oops")))

;;; --- list-copy ---
(test '(1 8 2 8) (list-copy '(1 8 2 8)))
;; R7RS 6.4 example: copy is mutable, original untouched
(test '((3 8 2 8) (1 8 2 8))
    (let* ((a '(1 8 2 8))
           (b (list-copy a)))
      (set-car! b 3)
      (list b a)))
(test '() (list-copy '()))
(test 42 (list-copy 42))                      ; non-list returned unchanged
(test '(1 2 . 3) (list-copy '(1 2 . 3)))      ; improper: final cdr preserved
(test #f (let ((a (list 1 2))) (eq? a (list-copy a))))
;; "It is an error if obj is a circular list" — kaappi raises (catchable)
(test 'caught (guard (e (#t 'caught))
                (let ((l (list 1 2 3)))
                  (set-cdr! (cddr l) l)
                  (list-copy l))))

;;; --- make-list ---
(test '(3 3) (make-list 2 3))
(test 2 (length (make-list 2)))
(test '() (make-list 0))
(test 'caught (guard (e (#t 'caught)) (make-list -1)))
(test 'caught (guard (e (#t 'caught)) (make-list 1.5)))
(test 'caught (guard (e (#t 'caught)) (make-list "2")))

;;; --- memq / memv / member ---
;; R7RS 6.4 examples
(test '(a b c) (memq 'a '(a b c)))
(test '(b c) (memq 'b '(a b c)))
(test #f (memq 'a '(b c d)))
(test #f (memq (list 'a) '(b (a) c)))
(test '((a) c) (member (list 'a) '(b (a) c)))
(test '("b" "c") (member "B" '("a" "b" "c") string-ci=?))
(test '(101 102) (memv 101 '(100 101 102)))
;; memv uses eqv?: exactness distinguishes, bignums/rationals compare by value
(test #f (memv 1.0 '(1)))
(test #f (memv 0.0 '(-0.0)))
(test '(1/3) (memv 1/3 (list 1/3)))
(test (list (expt 2 100)) (memv (expt 2 100) (list (expt 2 100))))
;; member uses equal?
(test '((1 2)) (member '(1 2) '((0 1) (1 2))))
;; empty list
(test #f (memq 'a '()))
(test #f (member 'a '()))
;; comparator gets (obj elem): with < the first element greater than 4 wins
(test '(8 2) (member 4 '(1 3 8 2) <))
;; comparator errors propagate
(test 'caught (guard (e (#t 'caught)) (member 1 '(1 2) (lambda (a b) (error "boom")))))
(test 'caught (guard (e (#t 'caught)) (member 1 '(1 2) "not-a-proc")))
;; improper and circular lists raise catchable errors
(test 'caught (guard (e (#t 'caught)) (memq 'z '(a b . c))))
(test 'caught (guard (e (#t 'caught))
                (let ((l (list 'a 'b 'c)))
                  (set-cdr! (cddr l) l)
                  (memq 'z l))))
(test 'caught (guard (e (#t 'caught))
                (let ((l (list 1 2 3)))
                  (set-cdr! (cddr l) l)
                  (member 'z l))))

;;; --- assq / assv / assoc ---
;; R7RS 6.4 examples
(test '(a 1) (assq 'a '((a 1) (b 2) (c 3))))
(test '(b 2) (assq 'b '((a 1) (b 2) (c 3))))
(test #f (assq 'd '((a 1) (b 2) (c 3))))
(test #f (assq (list 'a) '(((a)) ((b)) ((c)))))
(test '((a)) (assoc (list 'a) '(((a)) ((b)) ((c)))))
(test '(2 4) (assoc 2.0 '((1 1) (2 4) (3 9)) =))
(test '(5 7) (assv 5 '((2 3) (5 7) (11 13))))
(test #f (assoc 'z '()))
;; comparator gets (obj (car pair))
(test '(8 x) (assoc 4 '((1 a) (3 b) (8 x)) <))
(test 'caught (guard (e (#t 'caught)) (assoc 1 '((1 a)) (lambda (a b) (error "boom")))))
(test 'caught (guard (e (#t 'caught)) (assoc 1 '((1 a)) 42)))
;; non-pair alist entry raises
(test 'caught (guard (e (#t 'caught)) (assq 'a '(not-a-pair))))
(test 'caught (guard (e (#t 'caught)) (assoc 'z '((a 1) . tail))))
;; circular alist raises (catchable)
(test 'caught (guard (e (#t 'caught))
                (let ((al (list (list 'a 1) (list 'b 2))))
                  (set-cdr! (cdr al) al)
                  (assq 'z al))))

;;; --- map (R7RS 6.10) ---
(test '(b e h) (map cadr '((a b) (d e) (g h))))
(test '(1 4 27 256 3125) (map (lambda (n) (expt n n)) '(1 2 3 4 5)))
(test '(5 7 9) (map + '(1 2 3) '(4 5 6)))
;; terminates on shortest list
(test '(11 22) (map + '(1 2) '(10 20 30)))
(test '() (map + '()))
;; one circular + one finite list: must terminate at the finite one
(test '(11 22 31 12)
    (let ((c (list 10 20 30)))
      (set-cdr! (cddr c) c)
      (map + '(1 2 1 2) c)))
;; order: R7RS allows any dynamic order, but the result order must match input
(test '(1 2 3) (map (lambda (x) x) '(1 2 3)))
(test 'caught (guard (e (#t 'caught)) (map (lambda (x) (error "boom")) '(1))))
(test 'caught (guard (e (#t 'caught)) (map (lambda () 1) '(1))))   ; arity mismatch
(test 'caught (guard (e (#t 'caught)) (map 5 '(1))))
(test 'caught (guard (e (#t 'caught)) (map + '(1 2 . 3))))
(test 'caught (guard (e (#t 'caught)) (map + 42)))
;; escaping continuation from inside the callback
(test 3 (call/cc (lambda (k)
                   (map (lambda (x) (if (= x 3) (k x) x)) '(1 2 3 4))
                   'no-escape)))
;; large-list boundary: 200 lists (guard's escape continuation limits
;; apply to 255 args; use 200 to stay safely under)
(test '(200) (apply map + (make-list 200 '(1))))
;; ... but 257+ crashes with an uncatchable ReleaseSafe panic (fixed [256]Value
;; buffers in mapFn/forEachFn with no bounds check; vector-map heap-allocates).
;; Cannot even be a disabled chibi test target — the process aborts (exit 134).
;; FAIL: #1176 (map/for-each with >256 lists panic instead of erroring)
;; (test '(257) (apply map + (make-list 257 '(1))))
;; (test-assert (begin (apply for-each (lambda args #f) (make-list 257 '(1))) #t))

;;; --- for-each (R7RS 6.10) ---
;; R7RS example
(test #(0 1 4 9 16)
    (let ((v (make-vector 5)))
      (for-each (lambda (i) (vector-set! v i (* i i))) '(0 1 2 3 4))
      v))
;; multi-list, terminates on shortest
(test 33
    (let ((sum 0))
      (for-each (lambda (a b) (set! sum (+ sum a b))) '(1 2) '(10 20 30))
      sum))
;; guaranteed left-to-right order
(test '(3 2 1)
    (let ((acc '()))
      (for-each (lambda (x) (set! acc (cons x acc))) '(1 2 3))
      acc))
(test 'caught (guard (e (#t 'caught)) (for-each (lambda (x) (error "boom")) '(1))))
(test 'caught (guard (e (#t 'caught)) (for-each 5 '(1))))
(test 'caught (guard (e (#t 'caught)) (for-each + '(1 . 2))))
(test 3 (call/cc (lambda (k)
                   (for-each (lambda (x) (if (= x 3) (k x))) '(1 2 3 4))
                   'no-escape)))

;;; --- boolean=? / symbol=? ---
(test #t (boolean=? #t #t))
(test #t (boolean=? #f #f #f))
(test #f (boolean=? #t #f))
(test #f (boolean=? #f #f #t))
(test 'caught (guard (e (#t 'caught)) (boolean=? #t 1)))
(test 'caught (guard (e (#t 'caught)) (boolean=? 'true #t)))
(test #t (symbol=? 'a 'a))
(test #t (symbol=? 'a 'a 'a))
(test #f (symbol=? 'a 'b))
(test #f (symbol=? 'a 'a 'b))
(test 'caught (guard (e (#t 'caught)) (symbol=? 'a "a")))
(test 'caught (guard (e (#t 'caught)) (symbol=? "a" 'a)))

;;; --- features (R7RS 6.14) ---
;; "Returns a list of the feature identifiers which cond-expand treats as true."
(test #t (and (memq 'r7rs (features)) #t))
(test #t (and (memq 'kaappi (features)) #t))
(test #t (list? (features)))
;; cond-expand (both expression- and library-level) treats exact-closed as
;; true, and library-level cond-expand additionally treats exact-complex as
;; true — but (features) lists neither, violating the 6.14 sentence above.
(test 'yes (cond-expand (exact-closed 'yes) (else 'no)))
(test #t (and (memq 'exact-closed (features)) #t))
(test 'yes (cond-expand (exact-complex 'yes) (else 'no)))
(test #t (and (memq 'exact-complex (features)) #t))

;;; --- string->symbol ---
(test 'mISSISSIppi (string->symbol "mISSISSIppi"))
(test #t (eq? 'bitBlt (string->symbol "bitBlt")))
(test #t (eq? (string->symbol "ab") (string->symbol "ab")))   ; interning
(test "ab" (symbol->string (string->symbol "ab")))
;; round trip with awkward spellings
(test "hello world" (symbol->string (string->symbol "hello world")))
(test "" (symbol->string (string->symbol "")))
(test "λx" (symbol->string (string->symbol "λx")))
(test 'caught (guard (e (#t 'caught)) (string->symbol 'not-a-string)))
(test 'caught (guard (e (#t 'caught)) (string->symbol 42)))

(test-end "primitives_list audit")
