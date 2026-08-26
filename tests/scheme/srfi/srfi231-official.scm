;;; srfi231-official.scm -- the OFFICIAL SRFI 231 test suite (test-arrays.scm
;;; by Bradley J Lucier), adapted to run on kaappi. GENERATED FILE -- do not
;;; hand-edit; regenerate with:
;;;
;;;     python3 tests/scheme/srfi/srfi231-official-transform.py
;;;
;;; Provenance: upstream https://github.com/scheme-requests-for-implementation/srfi-231 (test-arrays.scm as of commit 72ac619d49ddb8610a1d18d19f3fe7049317917f, MIT license
;;; retained below). The adaptation rewrites the Gambit harness (define-macro
;;; test/test-multiple-values, with-exception-catcher, DSSSL optionals,
;;; ##-prefixed identifiers, (declare ...) forms) into portable R7RS and
;;; ports the reference implementation's internal %% procedures the suite
;;; uses as oracles; nothing about the tested BEHAVIOR is changed. Tests of
;;; pure reference internals (%%move-array-elements, %%array-packed? caching)
;;; are dropped -- the public procedures they underlie are covered directly.
;;;
;;; Known kaappi divergences are accounted, not failed: a small table of test
;;; ids whose failure encodes a documented kaappi-vs-reference divergence
;;; (each with an issue reference). The suite exits nonzero only on
;;; UNEXPECTED failures -- or when a known divergence stops diverging, which
;;; means its table entry is stale and hiding real coverage (prune it).
;;; Error-EXPECTING tests count as passes when any error is raised; only the
;;; Gambit message text differs.
;;;
;;; Runtime is ~80s (dominated by the PGM convolution timing blocks); the
;;; run-all.sh per-file timeout override keeps it out of the 60s default.
;;; Fixtures live in srfi231-official-fixtures/ next to this file; PGM
;;; outputs are written under TMPDIR, never the source tree.

#|
SRFI 231: Intervals and Generalized Arrays

Copyright 2016, 2018, 2020, 2021, 2022 Bradley J Lucier.
All Rights Reserved.

Permission is hereby granted, free of charge,
to any person obtaining a copy of this software
and associated documentation files (the "Software"),
to deal in the Software without restriction,
including without limitation the rights to use, copy,
modify, merge, publish, distribute, sublicense,
and/or sell copies of the Software, and to permit
persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice
(including the next paragraph) shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF
ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT
LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO
EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE
FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN
AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
OTHER DEALINGS IN THE SOFTWARE.
|#

;;; A test program for SRFI 231:
;;; Intervals and Generalized Arrays

(import (srfi 231) (srfi 27) (srfi 143) (srfi 4)
        (srfi 160 u64) (srfi 160 s64)
        (scheme base) (scheme write) (scheme char) (scheme cxr)
        (scheme file) (scheme read) (scheme lazy)
        (scheme process-context))

;; (quoted Gambit ##namespace block removed: kaappi reader rejects '##' even in datum)


;; (declare removed)

;; (declare removed)
(define random-tests 100)
(set! random-tests random-tests)

(define total-tests 0)
(set! total-tests total-tests)

(define failed-tests 0)
(set! failed-tests failed-tests)

;;; The next macros are not hygienic, so don't call any variable
;;; "continuation" ...

;;; kaappi harness: syntax-rules replacement for the Gambit define-macro
;;; test harness. On error the result is the sentinel ERROR-MARKER and the
;;; message is stashed in LAST-ERROR for failure reporting.

(define error-marker (vector 'error 'marker))
(define last-error #f)

(define (catch-test thunk)
  (guard (e (#t (begin (set! last-error
                             (if (error-object? e)
                                 (error-object-message e)
                                 e))
                       error-marker)))
    (set! last-error #f)
    (thunk)))

(define (obj->string x)
  (let ((p (open-output-string)))
    (write x p)
    (let ((s (get-output-string p)))
      (close-port p)
      (if (> (string-length s) 300)
          (string-append (substring s 0 300) "...")
          s))))

;;; --- kaappi vendoring: known-divergence accounting ------------------
;;; Test ids whose failure encodes a DOCUMENTED kaappi-vs-reference
;;; divergence rather than a bug. Each entry: (id . "reason"). A divergence
;;; that stops diverging is reported at the end and fails the suite -- the
;;; entry is stale and must be pruned (it hides real coverage).
(define divergent-tests 0)
(define diverged-ids (make-vector 10000 #f))
(define known-divergences
  (list '(98 . "f16-storage-class is #f (documented deferral, kaappi#2353)")
        '(148 . "f16-storage-class is #f (documented deferral, kaappi#2353)")
        '(149 . "f16-storage-class is #f (documented deferral, kaappi#2353)")
        '(150 . "f16-storage-class is #f (documented deferral, kaappi#2353)")
        '(147 . "R7RS strings are mutable; the suite encodes Gambit's immutable-string expectation")
        '(351 . "unsafe specialized views are unchecked per the spec text; the reference happens to check (see kaappi#2362)")))
(define (known-divergence id) (assq id known-divergences))

(define (report-failure id line result expected)
  (let ((kd (known-divergence id)))
    (if kd
        (begin
          (set! divergent-tests (+ divergent-tests 1))
          (vector-set! diverged-ids id #t)
          (display "DIVERGENT-EXPECTED ") (display id)
          (display " ") (display (cdr kd)) (newline))
        (begin
          (set! failed-tests (+ failed-tests 1))
          (display "FAIL ")
          (display id) (display " (line ") (display line) (display ") result=")
          (display (obj->string result))
          (display " expected=")
          (display (obj->string expected))
          (if (and (eq? result error-marker) last-error)
              (begin (display " [error: ") (display (obj->string last-error)) (display "]")))
          (newline)))))

(define error-string-tests 0)

(define executed-tests (make-vector 10000 #f))

(define-syntax test
  (syntax-rules ()
    ((_ id line expr value)
     (let* ((result (catch-test (lambda () expr)))
            (val value))
       (set! total-tests (+ total-tests 1))
       (vector-set! executed-tests id #t)
       (cond ((and (string? val) (eq? result error-marker))
              ;; an error was required and raised; only the Gambit message
              ;; text differs -- count separately, not a failure
              (set! error-string-tests (+ error-string-tests 1)))
             ((not (equal? result val))
              (report-failure id line result val)))))))

(define-syntax test-err
  (syntax-rules ()
    ((_ id line expr)
     (let ((result (catch-test (lambda () expr))))
       (set! total-tests (+ total-tests 1))
       (vector-set! executed-tests id #t)
       (if (not (eq? result error-marker))
           (report-failure id line result 'expected-an-error))))))

(define-syntax test-mv
  (syntax-rules ()
    ((_ id line expr vals)
     (call-with-values (lambda () expr)
       (lambda args
         (set! total-tests (+ total-tests 1))
         (vector-set! executed-tests id #t)
         (if (not (equal? args vals))
             (report-failure id line args vals)))))))

;;; ported reference-internals used as oracles by the suite (pure Scheme)

(define (%%every pred lst)
  (let loop ((l lst))
    (or (null? l)
        (and (pred (car l)) (loop (cdr l))))))

(define (%%vector-every pred . vectors)
  (let ((n (vector-length (car vectors))))
    (let loop ((i 0))
      (or (= i n)
          (and (apply pred (map (lambda (v) (vector-ref v i)) vectors))
               (loop (+ i 1)))))))

(define (%%interval-lower-bounds interval)
  (interval-lower-bounds->vector interval))

(define (%%interval-upper-bounds interval)
  (interval-upper-bounds->vector interval))

(define (%%array-getter array) (array-getter array))
(define (%%array-domain array) (array-domain array))

(define (%%vector-permute vec permutation)
  (let* ((n (vector-length vec))
         (result (make-vector n)))
    (do ((i 0 (+ i 1)))
        ((= i n) result)
      (vector-set! result i (vector-ref vec (vector-ref permutation i))))))

(define (%%vector-permute->list vec permutation)
  (do ((i (- (vector-length vec) 1) (- i 1))
       (result '() (cons (vector-ref vec (vector-ref permutation i)) result)))
      ((< i 0) result)))

(define (%%permutation-invert permutation)
  (let* ((n (vector-length permutation))
         (result (make-vector n)))
    (do ((i 0 (+ i 1)))
        ((= i n) result)
      (vector-set! result (vector-ref permutation i) i))))

(define (%%interval->basic-indexer interval)
  (let* ((lowers (vector->list (interval-lower-bounds->vector interval)))
         (widths (vector->list (interval-widths interval)))
         (coefficients
          (let loop ((ws (reverse widths)) (c 1) (acc '()))
            (if (null? ws)
                acc
                (loop (cdr ws) (* c (car ws)) (cons c acc))))))
    (lambda args
      (apply + (map (lambda (a l c) (* c (- a l))) args lowers coefficients)))))

(define (%%compose-indexers old-indexer new-domain new-domain->old-domain)
  (lambda args
    (call-with-values (lambda () (apply new-domain->old-domain args))
      old-indexer)))

;;; Gambit fixnum-comparison aliases
(define (fx= a b) (= a b))
(define (fx< a b) (< a b))
(define (fx> a b) (> a b))

;;; pretty-printers
(define (pp x) (write x) (newline))
(define (pretty-print x) (write x) (newline))

(define (fl+ a b) (+ a b))
(define (fl- a b) (- a b))
(define (fl* a b) (* a b))
(define (fl/ a b) (/ a b))
(define (flsqrt x) (sqrt x))
(define (identity x) x)

;;; suite bug: random-f64vector is called but never defined anywhere
(define (random-f64vector n)
  (let ((v (make-f64vector n 0.0)))
    (do ((i 0 (+ i 1)))
        ((= i n) v)
      (f64vector-set! v i (* 1.0 (random 100))))))

;;; requires make-list function

;;; Pseudo-random infrastructure

;;; The idea is to have more reproducibility in the random tests.
;;; Our goal is that if this file is run with random-tests=N and then
;;; run with random-tests=M>N, then the parameters of the first N of M tests in each block
;;; will be the same as the parameters of the tests in the run with random-tests=N.

;;; Call next-test-random-source-state! immediately *after* each loop that is
;;; executed random-tests number of times.


(define test-random-source
  (make-random-source))

(define initial-test-random-source-state
  (random-source-state-ref test-random-source))

(define next-test-random-source-state!
  (let ((j 0))
    (lambda ()
      (set! j (fx+ j 1))
      (random-source-state-set!
       test-random-source
       initial-test-random-source-state)
      (random-source-pseudo-randomize!
       test-random-source
       0 j))))

(define test-random-integer
  (random-source-make-integers
   test-random-source))

(define test-random-real
  (random-source-make-reals test-random-source))

(define (random a . opts)
  (let* ((b (if (< 0 (length opts)) (list-ref opts 0) #f)))
  (if b
      (+ a (test-random-integer (- b a)))
      (test-random-integer a))))

(define (random-inclusive a . opts)
  (let* ((b (if (< 0 (length opts)) (list-ref opts 0) #f)))
  (if b
      (+ a (test-random-integer (- b a -1)))
      (test-random-integer (+ a 1)))))

(define (random-char)
  (let ((n (random-inclusive #x10FFFF)))
    (if (or (fx< n #xd800)
            (fx< #xdfff n))
        (integer->char n)
        (random-char))))

(define (random-sample n . opts)
  (let* ((l (if (< 0 (length opts)) (list-ref opts 0) 4)))
  (list->vector (map (lambda (i)
                       (random 1 l))
                     (iota n)))))

(define (random-permutation n)
  (let ((result (make-vector n)))
    ;; fill it
    (do ((i 0 (fx+ i 1)))
        ((fx= i n))
      (vector-set! result i i))
    ;; permute it
    (do ((i 0 (fx+ i 1)))
        ((fx= i n) result)
      (let* ((index (random i n))
             (temp (vector-ref result index)))
        (vector-set! result index (vector-ref result i))
        (vector-set! result i temp)))))

(define (vector-permute v permutation)
  (let* ((n (vector-length v))
         (result (make-vector n)))
    (do ((i 0 (+ i 1)))
        ((= i n) result)
      (vector-set! result i (vector-ref v (vector-ref permutation i))))))

(define (filter p l)
  (cond ((null? l) l)
        ((p (car l))
         (cons (car l) (filter p (cdr l))))
        (else
         (filter p (cdr l)))))

(define (in-order < l)
  (or (null? l)
      (null? (cdr l))
      (and (< (car l) (cadr l))
           (in-order < (cdr l)))))

(define (foldl op id l)
  (if (null? l)
      id
      (foldl op (op id (car l)) (cdr l))))

(define (foldr op id l)
  (if (null? l)
      id
      (op (car l) (foldr op id (cdr l)))))

(define (indices->string  . l)
  (apply string-append (number->string (car l))
         (map (lambda (n) (string-append "_" (number->string n))) (cdr l))))

;; (include "generic-arrays.scm")

(pp "Interval error tests")

(test-err 1 230 (make-interval 1 '#(3 4)))

(test-err 2 233 (make-interval '#(1 1)  3))

(test-err 3 236 (make-interval '#(1 1)  '#(3)))

(test 4 239 (interval-volume (make-interval '#()  '#())) 1)

(test-err 5 242 (make-interval '#(1.)  '#(1)))

(test-err 6 245 (make-interval '#(1 #f)  '#(1 2)))

(test-err 7 248 (make-interval '#(1)  '#(1.)))

(test-err 8 251 (make-interval '#(1 1)  '#(1 #f)))

(test 9 254 (interval-volume (make-interval '#(1)  '#(1))) 0)

(test 10 257 (interval-volume (make-interval '#(1 2 3)  '#(4 2 6))) 0)

(test-err 11 260 (make-interval 1))

(test 12 263 (interval-volume (make-interval '#())) 1)

(test-err 13 266 (make-interval '#(1.)))

(test-err 14 269 (make-interval '#(-1)))

(test-err 15 272 (make-interval '#(1) '#(0)))


(pp "interval result tests")

(test 16 278 (make-interval '#(11111)  '#(11112)) (make-interval '#(11111) '#(11112)))

(test 17 281 (make-interval '#(1 2 3)  '#(4 5 6)) (make-interval '#(1 2 3) '#(4 5 6)))

(pp "interval? result tests")

(test 18 286 (interval? #t) #f)

(test 19 289 (interval? (make-interval '#(1 2 3) '#(4 5 6))) #t)


(pp "interval-dimension error tests")

(test-err 20 295 (interval-dimension 1))

(pp "interval-dimension result tests")

(test 21 300 (interval-dimension (make-interval '#(1 2 3) '#(4 5 6))) 3)

(pp "interval-lower-bound error tests")

(test-err 22 305 (interval-lower-bound 1 0))

(test-err 23 308 (interval-lower-bound (make-interval '#(1 2 3) '#(4 5 6)) #f))

(test-err 24 311 (interval-lower-bound (make-interval '#(1 2 3) '#(4 5 6)) 1.))

(test-err 25 314 (interval-lower-bound (make-interval '#(1 2 3) '#(4 5 6)) -1))

(test-err 26 317 (interval-lower-bound (make-interval '#(1 2 3) '#(4 5 6)) 3))

(test-err 27 320 (interval-lower-bound (make-interval '#(1 2 3) '#(4 5 6)) 4))

(test-err 28 323 (interval-lower-bound (make-interval '#()) 0))

(pp "interval-upper-bound error tests")

(test-err 29 328 (interval-upper-bound 1 0))

(test-err 30 331 (interval-upper-bound (make-interval '#(1 2 3) '#(4 5 6)) #f))

(test-err 31 334 (interval-upper-bound (make-interval '#(1 2 3) '#(4 5 6)) 1.))

(test-err 32 337 (interval-upper-bound (make-interval '#(1 2 3) '#(4 5 6)) -1))

(test-err 33 340 (interval-upper-bound (make-interval '#(1 2 3) '#(4 5 6)) 3))

(test-err 34 343 (interval-upper-bound (make-interval '#(1 2 3) '#(4 5 6)) 4))

(test-err 35 346 (interval-upper-bound (make-interval '#()) 0))

(pp "interval-lower-bounds->list error tests")

(test-err 36 351 (interval-lower-bounds->list 1))

(test 37 354 (interval-lower-bounds->list (make-interval '#())) '())

(pp "interval-upper-bounds->list error tests")

(test-err 38 359 (interval-upper-bounds->list #f))

(test 39 362 (interval-upper-bounds->list (make-interval '#())) '())

(pp "interval-lower-bounds->vector error tests")

(test-err 40 367 (interval-lower-bounds->vector 1))

(test 41 370 (interval-lower-bounds->vector (make-interval '#())) '#())

(pp "interval-upper-bounds->vector error tests")

(test-err 42 375 (interval-upper-bounds->vector #f))

(test 43 378 (interval-upper-bounds->vector (make-interval '#())) '#())

(pp "interval-width, interval-widths error tests")

(test-err 44 383 (interval-width 1 0))

(test-err 45 386 (interval-width (make-interval '#(1 2 3) '#(4 5 6)) #f))

(test-err 46 389 (interval-width (make-interval '#(1 2 3) '#(4 5 6)) 1.))

(test-err 47 392 (interval-width (make-interval '#(1 2 3) '#(4 5 6)) -1))

(test-err 48 395 (interval-width (make-interval '#(1 2 3) '#(4 5 6)) 3))

(test-err 49 398 (interval-width (make-interval '#(1 2 3) '#(4 5 6)) 4))

(test-err 50 401 (interval-widths 1))

(test 51 404 (interval-widths (make-interval '#())) '#())

(test 52 407 (interval-widths (make-interval '#(1 0))) '#(1 0))

(pp "interval-lower-bound, interval-upper-bound, interval-lower-bounds->list, interval-upper-bounds->list,")
(pp "interval-lower-bounds->vector, interval-upper-bounds->vector, interval-width, interval-widths result tests")

(do ((i 0 (+ i 1)))
    ((= i random-tests))
  (let* ((lower (map (lambda (x) (random 10)) (vector->list (make-vector (random 1 11)))))
         (upper (map (lambda (x) (+ (random 11) x)) lower)))
    (let ((interval (make-interval (list->vector lower)
                                   (list->vector upper)))
          (offset (random (length lower))))
      (test 53 420 (interval-lower-bound interval offset) (list-ref lower offset))
      (test 54 422 (interval-upper-bound interval offset) (list-ref upper offset))
      (test 55 424 (interval-lower-bounds->list interval) lower)
      (test 56 426 (interval-upper-bounds->list interval) upper)
      (test 57 428 (interval-lower-bounds->vector interval) (list->vector lower))
      (test 58 430 (interval-upper-bounds->vector interval) (list->vector upper))
      (test 59 432 (interval-width interval offset) (- (list-ref upper offset)
               (list-ref lower offset)))
      )))

(do ((i 0 (+ i 1)))
    ((= i random-tests))
  (let* ((lower (map (lambda (x) (random 10)) (vector->list (make-vector (random 1 11)))))
         (upper (map (lambda (x) (+ (random 11) x)) lower)))
    (let ((interval (make-interval (list->vector lower)
                                   (list->vector upper))))
      (test 60 443 (interval-widths interval) (vector-map -
                        (interval-upper-bounds->vector interval)
                        (interval-lower-bounds->vector interval))))))


(next-test-random-source-state!)


(pp "interval-projections error tests")

(test-err 61 454 (interval-projections 1 1))

(test-err 62 457 (interval-projections (make-interval '#(0) '#(1)) #t))


(test-err 63 461 (interval-projections (make-interval '#(0 0) '#(1 1)) 1/2))

(test-err 64 464 (interval-projections (make-interval '#(0 0) '#(1 1)) 1.))

(test-mv 742 467 (interval-projections (make-interval '#(0 0) '#(1 1)) 0) (list (make-interval '#(1 1))
       (make-interval '#()) ))

(test-mv 743 472 (interval-projections (make-interval '#(0 0) '#(1 1)) 2) (list (make-interval '#())
       (make-interval '#(1 1))))

(pp "interval-projections result tests")

(do ((i 0 (+ i 1)))
    ((= i random-tests))
  (let* ((lower (map (lambda (x) (random 10)) (vector->list (make-vector (random 3 11)))))
         (upper (map (lambda (x) (+ (random 1 11) x)) lower))
         (left-dimension (random 1 (- (length lower) 1)))
         (right-dimension (- (length lower) left-dimension)))
    (test-mv 744 485 (interval-projections (make-interval (list->vector lower)
                                          (list->vector upper))
                           right-dimension) (list (make-interval (list->vector (take lower left-dimension))
                          (list->vector (take upper left-dimension)))
           (make-interval (list->vector (drop lower left-dimension))
                          (list->vector (drop upper left-dimension)))))))

(next-test-random-source-state!)

(pp "interval-volume error tests")

(test-err 65 498 (interval-volume #f))

(pp "interval-volume result tests")

(do ((i 0 (+ i 1)))
    ((= i random-tests))
  (let* ((lower (map (lambda (x) (random 6)) (vector->list (make-vector (random 6)))))
         (upper (map (lambda (x) (+ (random 6) x)) lower)))
    (test 66 507 (interval-volume (make-interval (list->vector lower)
                                          (list->vector upper))) (apply * (map - upper lower)))))

(next-test-random-source-state!)

(pp "interval= error tests")

(test-err 67 515 (interval= #f (make-interval '#(1 2 3) '#(4 5 6))))

(test-err 68 518 (interval= (make-interval '#(1 2 3) '#(4 5 6)) #f))

(pp "interval= result tests")

(do ((i 0 (+ i 1)))
    ((= i random-tests))
  (let* ((lower1 (map (lambda (x) (random 2)) (vector->list (make-vector (random 4)))))
         (upper1 (map (lambda (x) (+ (random 3) x)) lower1))
         (lower2 (map (lambda (x) (random 2)) lower1))
         (upper2 (map (lambda (x) (+ (random 3) x)) lower2)))
    (test 69 529 (interval= (make-interval (list->vector lower1)
                                    (list->vector upper1))
                     (make-interval (list->vector lower2)
                                    (list->vector upper2))) (and (equal? lower1 lower2)                              ;; the probability of this happening is about 1/16
               (equal? upper1 upper2)))))

(next-test-random-source-state!)

(pp "interval-subset? error tests")

(test-err 70 540 (interval-subset? #f (make-interval '#(1 2 3) '#(4 5 6))))

(test-err 71 543 (interval-subset? (make-interval '#(1 2 3) '#(4 5 6)) #f))

(test-err 72 546 (interval-subset? (make-interval '#(1) '#(2))
                        (make-interval '#(0 0) '#(1 2))))

(pp "interval-subset? result tests")

(do ((i 0 (+ i 1)))
    ((= i random-tests))
  (let* ((lower1 (map (lambda (x) (random 2)) (vector->list (make-vector (random 6)))))
         (upper1 (map (lambda (x) (+ (random 3) x)) lower1))
         (lower2 (map (lambda (x) (random 2)) lower1))
         (upper2 (map (lambda (x) (+ (random 3) x)) lower2)))
    (test 73 558 (interval-subset? (make-interval (list->vector lower1)
                                           (list->vector upper1))
                            (make-interval (list->vector lower2)
                                           (list->vector upper2))) (and (%%every (lambda (x) (>= (car x) (cdr x))) (map cons lower1 lower2))
               (%%every (lambda (x) (<= (car x) (cdr x))) (map cons upper1 upper2))))))

(pp "interval-empty? tests")

(test-err 74 567 (interval-empty? 'a))

(test 75 570 (interval-empty? (make-interval '#(1) '#(1))) #t)

(test 76 573 (interval-empty? (make-interval '#(1) '#(2))) #f)

(test 77 576 (interval-empty? (make-interval '#())) #f)

(next-test-random-source-state!)

(pp "interval-contains-multi-index?  error tests")

(test-err 78 583 (interval-contains-multi-index? 1 1))

(test-err 79 586 (interval-contains-multi-index? (make-interval '#(1 2 3) '#(4 5 6)) 1))

(test-err 80 589 (interval-contains-multi-index? (make-interval '#(1 2 3) '#(4 5 6)) 1 1/2 0.1))

(pp "interval-contains-multi-index?  result tests")

(let ((interval   (make-interval '#(1 2 3) '#(4 5 6)))
      (interval-2 (make-interval '#(10 11 12) '#(13 14 15))))
  (if (not (array-fold-left (lambda (result x)
                              (and result (apply interval-contains-multi-index? interval x)))
                            #t
                            (make-array interval list)))
      (error "these should all be true"))
  (if (not (array-fold-left (lambda (result x)
                              (and result (not (apply interval-contains-multi-index? interval x))))
                            #t
                            (make-array interval-2 list)))
      (error "these should all be false")))

(pp "interval-for-each error tests")

(test-err 81 609 (interval-for-each (lambda (x) x) 1))

(test-err 82 612 (interval-for-each 1 (make-interval '#(3) '#(4))))

(define (local-iota a b)
  (if (= a b)
      '()
      (cons a (local-iota (+ a 1) b))))

(define (all-elements lower upper)
  (if (null? (cdr lower))
      (map list (local-iota (car lower) (car upper)))
      (apply append (map (lambda (x)
                           (map (lambda (y)
                                  (cons x y))
                                (all-elements (cdr lower) (cdr upper))))
                         (local-iota (car lower) (car upper))))))

(pp "interval-for-each result tests")

(do ((i 0 (+ i 1)))
    ((= i random-tests))
  (let* ((lower (map (lambda (x) (random 10))
                     (vector->list (make-vector (random 1 7)))))
         (upper (map (lambda (x) (+ (random 1 4) x))
                     lower)))
    (let ((result '()))

      (define (f . args)
        (set! result (cons args result)))

      (test 83 642 (let ()
              (interval-for-each f
                                 (make-interval (list->vector lower)
                                                (list->vector upper)))
              result) (reverse (all-elements lower upper))))))

(next-test-random-source-state!)

(pp "interval-fold-left and interval-fold-right error tests")

(test-err 84 653 (interval-fold-left 1 2 3 4))

(test-err 85 656 (interval-fold-left 1 2 3 (make-interval '#(2 2))))

(test-err 86 659 (interval-fold-left 1 values 3 (make-interval '#(2 2))))

(test-err 87 662 (interval-fold-right 1 2 3 4))

(test-err 88 665 (interval-fold-right 1 2 3 (make-interval '#(2 2))))

(test-err 89 668 (interval-fold-right 1 values 3 (make-interval '#(2 2))))

;;; We'll mainly rely on tests for array-fold[lr] to test interval-fold[lr]

(test 90 673 (interval-fold-left identity + 0 (make-interval '#(5))) 10)

(test 91 676 (interval-fold-right identity + 0 (make-interval '#(5))) 10)

(pp "interval-dilate error tests")

(let ((interval (make-interval '#(0 0) '#(100 100))))
  (test-err 92 682 (interval-dilate interval 'a '#(-10 10)))
  (test-err 93 684 (interval-dilate 'a '#(10 10) '#(-10 -10)))
  (test-err 94 686 (interval-dilate interval '#(10 10) 'a))
  (test-err 95 688 (interval-dilate interval '#(10) '#(-10 -10)))
  (test-err 96 690 (interval-dilate interval '#(10 10) '#( -10)))
  (test-err 97 692 (interval-dilate interval '#(100 100) '#(-100 -100))))



;;; define random-interval, random-multi-index

(define (random-multi-index interval)
  (apply values
         (apply map
                random
                (map (lambda (bounds)
                       (bounds interval))
                     (list interval-lower-bounds->list
                           interval-upper-bounds->list)))))

(define use-bignum-intervals #f)


(define (random-interval . opts)
  (let* ((min (if (< 0 (length opts)) (list-ref opts 0) 0))
    (max (if (< 1 (length opts)) (list-ref opts 1) 6)))
  ;; a random interval with min <= dimension < max
  ;; positive and negative lower bounds
  (let* ((lower
          (map (lambda (x)
                 (if use-bignum-intervals
                     (random (- (expt 2 90)) (expt 2 90))
                     (random -10 10)))
               (iota (random min max))))
         (upper
          (map (lambda (x)
                 (+ (random 0 8) x))
               lower)))
    (make-interval (list->vector lower)
                   (list->vector upper)))))

(define (random-nonempty-interval . opts)
  (let* ((min (if (< 0 (length opts)) (list-ref opts 0) 0))
    (max (if (< 1 (length opts)) (list-ref opts 1) 6)))
  ;; a random interval with min <= dimension < max
  ;; positive and negative lower bounds
  (let* ((lower
          (map (lambda (x)
                 (if use-bignum-intervals
                     (random (- (expt 2 90)) (expt 2 90))
                     (random -10 10)))
               (vector->list (make-vector (random min max)))))
         (upper
          (map (lambda (x)
                 (+ (random 1 8) x))
               lower)))
    (make-interval (list->vector lower)
                   (list->vector upper)))))

(define (random-subinterval interval)
  (let* ((lowers (interval-lower-bounds->vector interval))
         (uppers (interval-upper-bounds->vector interval))
         (new-lowers (vector-map random-inclusive lowers uppers))
         (new-uppers (vector-map random-inclusive new-lowers uppers))
         (subinterval (make-interval new-lowers new-uppers)))
    subinterval))


(define (random-nonnegative-interval . opts)
  (let* ((min (if (< 0 (length opts)) (list-ref opts 0) 1))
    (max (if (< 1 (length opts)) (list-ref opts 1) 6)))
  ;; a random interval with min <= dimension < max
  ;; positive and negative lower bounds
  (let* ((lower
          (make-vector (random min max) 0))
         (upper
          (vector-map (lambda (x) (random 1 7)) lower)))
    (make-interval lower upper))))

(define (random-positive-vector n . opts)
  (let* ((max (if (< 0 (length opts)) (list-ref opts 0) 5)))
  (vector-map (lambda (x)
                (random 1 max))
              (make-vector n))))

(define (random-boolean)
  (zero? (random 2)))

(define (array-display A)

  (define (display-item x)
    (display x) (display "\t"))

  (newline)
  (case (array-dimension A)
    ((1) (array-for-each display-item A) (newline))
    ((2) (array-for-each (lambda (row)
                           (array-for-each display-item row)
                           (newline))
                         (array-curry A 1)))
    (else
     (error "array-display can't handle > 2 dimensions: " A))))

(pp "storage-class tests")

(define storage-class-names
  (list (list   u1-storage-class   'u1-storage-class 'u16vector make-u16vector)
        (list   u8-storage-class   'u8-storage-class  'u8vector  make-u8vector)
        (list  u16-storage-class  'u16-storage-class 'u16vector make-u16vector)
        (list  u32-storage-class  'u32-storage-class 'u32vector make-u32vector)
        (list  u64-storage-class  'u64-storage-class 'u64vector make-u64vector)
        (list   s8-storage-class   's8-storage-class  's8vector  make-s8vector)
        (list  s16-storage-class  's16-storage-class 's16vector make-s16vector)
        (list  s32-storage-class  's32-storage-class 's32vector make-s32vector)
        (list  s64-storage-class  's64-storage-class 's64vector make-s64vector)
        (list  f16-storage-class  'f16-storage-class 'u16vector make-u16vector)
        (list  f32-storage-class  'f32-storage-class 'f32vector make-f32vector)
        (list  f64-storage-class  'f64-storage-class 'f64vector make-f64vector)
        (list char-storage-class 'char-storage-class 'string    make-string)
        (list  c64-storage-class  'c64-storage-class 'f32vector make-f32vector)
        (list c128-storage-class 'c128-storage-class 'f64vector make-f64vector)
        (list generic-storage-class 'generic-storage-class 'vector make-vector)
        ))

(define uniform-storage-classes
  (list u8-storage-class u16-storage-class u32-storage-class u64-storage-class
        s8-storage-class s16-storage-class s32-storage-class s64-storage-class
        f16-storage-class f32-storage-class f64-storage-class
        char-storage-class
        c64-storage-class c128-storage-class))


(for-each (lambda (storage-class)
            (test 98 814 ((storage-class-data? storage-class)
                   ((storage-class-maker storage-class)
                    8 (storage-class-default storage-class))) #t))
          uniform-storage-classes)

(test 99 820 ((storage-class-data? u1-storage-class) (u16vector 0)) #t)

(for-each (lambda (class-name-data-maker)
            (let* ((class
                    (car class-name-data-maker))
                   (name
                    (cadr class-name-data-maker))
                   (data
                    (caddr class-name-data-maker))
                   (maker
                    (cadddr class-name-data-maker))
                   (message
                    (string-append "Expecting a "
                                   (symbol->string data)
                                   (if (memq class (list c64-storage-class c128-storage-class))
                                       " with an even number of elements passed to "
                                       " passed to ")
                                   "(storage-class-data->body "
                                   (symbol->string name)
                                   "): ")))
              (test 100 841 ((storage-class-data->body class) 'a) message)))
          storage-class-names)

(pp "array error tests")

(test-err 101 847 (make-array 1 values))

(test-err 102 850 (make-array (make-interval '#(3) '#(4)) 1))

(test-err 103 853 (make-array 1 values values))

(test-err 104 856 (make-array (make-interval '#(3) '#(4)) 1 values))

(test-err 105 859 (make-array (make-interval '#(3) '#(4)) list 1))

(define (myarray= array1 array2 . opts)
  (let* ((compare (if (< 0 (length opts)) (list-ref opts 0) equal?)))
  (and (interval= (array-domain array1)
                  (array-domain array2))
       (array-every compare array1 array2))))

(pp "array-domain and array-getter error tests")

(test-err 106 869 (array-domain #f))

(test-err 107 872 (array-getter #f))

(pp "array?, array-domain, and array-getter result tests")

(let* ((getter (lambda args 1.))
       (domain (make-interval '#(3) '#(4)))
       (array  (make-array domain getter)))
  (test 108 880 (array? #f) #f)
  (test 109 882 (array? array) #t)
  (test 110 884 (array-domain array) domain)
  ;; We now wrap the getter in checking code, so
  ;; this test no longer passes
  #;(test (array-getter array)
        getter))


(pp "array-setter error tests")

(test-err 111 894 (array-setter #f))

(pp "mutable-array? and array-setter result tests")

(let ((result (cons #f #f)))
  (let ((getter (lambda (i) (car result)))
        (setter   (lambda (v i) (set-car! result v)))
        (domain   (make-interval '#(3) '#(4))))
    (let ((array (make-array domain
                             getter
                             setter)))
      (test 112 906 (array? array) #t)
      (test 113 908 (mutable-array? array) #t)
      (test 114 910 (mutable-array? 1) #f)
      ;; We now wrap the getter and setter in checking code, so
      ;; the next two no longer pass
     #; (test (array-setter array)
            setter)
      #;(test (array-getter array)
            getter)
      (test 115 918 (array-domain array) domain))))

(pp "array-freeze! tests")

(test-err 116 923 (array-freeze! 'a))

(let ((A (make-specialized-array (make-interval '#()))))
  (test 117 927 (mutable-array? A) #t)
  (let ((B (array-freeze! A)))
    (test 118 930 (mutable-array? B) #f)
    (test 119 932 (eq? A B) #t))
  (test 120 934 (mutable-array? A) #f))

(define (myindexer= indexer1 indexer2 interval)
  (array-fold-left (lambda (x y) (and x y))
                   #t
                   (make-array interval
                               (lambda args
                                 (= (apply indexer1 args)
                                    (apply indexer2 args))))))


(define (my-indexer base lower-bounds increments)
  (lambda indices
    (apply + base (map * increments (map - indices lower-bounds)))))



(pp "new-indexer result tests")

(define (random-sign)
  (- 1 (* 2 (random 2))))

(do ((i 0 (+ i 1)))
    ((= i random-tests))
  (let* ((lower-bounds
          (map (lambda (x) (random 2))
               (vector->list (make-vector (random 1 7)))))
         (upper-bounds
          (map (lambda (x) (+ x (random 1 3)))
               lower-bounds))
         (new-domain
          (make-interval (list->vector lower-bounds)
                         (list->vector upper-bounds)))
         (new-domain-dimension
          (interval-dimension new-domain))
         (old-domain-dimension
          (random 1 7))
         (base
          (random 100))
         (coefficients
          (map (lambda (x) (* (random-sign)
                              (random 20)))
               (local-iota 0 old-domain-dimension)))
         (old-indexer
          (lambda args
            (apply + base (map * args coefficients))))
         (new-domain->old-domain-coefficients
          (map (lambda (x)
                 (map (lambda (x) (* (random-sign) (random 10)))
                      (local-iota 0 new-domain-dimension)))
               (local-iota 0 old-domain-dimension)))
         (new-domain->old-domain
          (lambda args
            (apply values (map (lambda (row)
                                 (apply + (map * row args)))
                               new-domain->old-domain-coefficients)))))
    (if (not (and (myindexer= (lambda args
                                (call-with-values
                                    (lambda () (apply new-domain->old-domain args))
                                  old-indexer))
                              (%%compose-indexers old-indexer new-domain  new-domain->old-domain)
                              new-domain)))
        (pp (list new-domain
                  old-domain-dimension
                  base
                  coefficients
                  new-domain->old-domain-coefficients)))))

(next-test-random-source-state!)

(pp "array body, indexer, storage-class, and safe? error tests")

(let ((a (make-array (make-interval '#(0 0) '#(1 1)) ;; not valid
                     values
                     values)))
  (test-err 121 1010 (array-body a))
  (test-err 122 1012 (array-indexer a))
  (test-err 123 1014 (array-storage-class a))
  (test-err 124 1016 (array-safe? a)))

(pp "make-specialized-array error tests")

(test-err 125 1021 (make-specialized-array  'a))

(test-err 126 1024 (make-specialized-array (make-interval '#(0) '#(10)) 'a))

(test-err 127 1027 (make-specialized-array (make-interval '#(0) '#(10)) 'a 'a))

(test-err 128 1030 (make-specialized-array (make-interval '#(0) '#(10)) u16-storage-class 'a))

(test-err 129 1033 (make-specialized-array (make-interval '#(0) '#(10)) generic-storage-class 'a 'a))

;;; let's test a few more

(test 130 1038 (array-every (lambda (x) (eqv? x 42)) (make-specialized-array (make-interval '#(10)) u8-storage-class 42)) #t)

(test 131 1041 (array-safe? (make-specialized-array (make-interval '#(10)) u8-storage-class 42)) (specialized-array-default-safe?))

(test 132 1044 (parameterize ((specialized-array-default-safe? #t)) (array-safe? (make-specialized-array (make-interval '#(10)) u8-storage-class 42))) #t)

(test 133 1047 (parameterize ((specialized-array-default-safe? #f)) (array-safe? (make-specialized-array (make-interval '#(10)) u8-storage-class 42))) #f)

(test 134 1050 (array-safe? (make-specialized-array (make-interval '#(10)) u8-storage-class 42  #t)) #t)

(test 135 1053 (array-safe? (make-specialized-array (make-interval '#(10)) u8-storage-class 42 #f)) #f)

(pp "make-specialized-array-from-data error tests")

(test-err 136 1058 (make-specialized-array-from-data 'a 'a 'a 'a))

(test-err 137 1061 (make-specialized-array-from-data 'a 'a 'a #t))

(test-err 138 1064 (make-specialized-array-from-data 'a 'a 'a))

(test-err 139 1067 (make-specialized-array-from-data 'a 'a #f #t))

(test-err 140 1070 (make-specialized-array-from-data 'a 'a #f))

(test-err 141 1073 (make-specialized-array-from-data 'a 'a))

(test-err 142 1076 (make-specialized-array-from-data 'a generic-storage-class #f #t))

(test-err 143 1079 (make-specialized-array-from-data 'a generic-storage-class #f))

(test-err 144 1082 (make-specialized-array-from-data 'a generic-storage-class))

(test-err 145 1085 (make-specialized-array-from-data 'a))

;;; The string is mutable in the interpreter, and immutable in the compiler, and this passes both ways.
;;; Passing immutable data to make-specialized-array-from-data with the mutable? argument #t
;;; is an error situation, but this is how the sample implementation currently deals with it.

(let* ((string "123")
       (array (make-specialized-array-from-data string char-storage-class #t)))
  (test 146 1094 (array? array) #t)
  (test 147 1095 (mutable-array? array) #f))

(let ((test-values
       (list ;;       storae-class   default other data
        (list generic-storage-class  #f 'a 1 #\c)
        (list    char-storage-class  '#\null '#\a '#\b)
        (list      u1-storage-class  0 1)
        (list      u8-storage-class  0 23)
        (list     u16-storage-class  0 500)
        (list     u32-storage-class  0 70000)
        (list     u64-storage-class  0 100000000000)
        (list      s8-storage-class  0 -1 1)
        (list     s16-storage-class  0 -300 300)
        (list     s32-storage-class  0 -70000 70000)
        (list     s64-storage-class  0 -1000000000 1000000000)
        (list     f16-storage-class  0. 1.)
        (list     f32-storage-class  0. 1.)
        (list     f64-storage-class  0. 1.)
        (list     c64-storage-class  0.+0.i 1.+1.i)
        (list    c128-storage-class  0.+0.i 1.+1.i))))
  (for-each (lambda (data)
              (let ((storage-class (car data))
                    (default       (cadr data))
                    (other-values  (cddr data)))
                (test 148 1120 (array-every (lambda (v)
                                     (equal? v default))
                                   (make-specialized-array (make-interval '#(4 4)) storage-class)) #t)
                (for-each (lambda (val)
                            (test 149 1125 (array-every (lambda (v)
                                                 (equal? v val))
                                               (make-specialized-array (make-interval '#(4 4))
                                                                       storage-class
                                                                       val)) #t))
                          other-values)))
            test-values))

(let ((test-values
       (list ;;       storae-class  good data           bad data
        (list generic-storage-class (make-vector 10)    (make-u16vector 10))
        (list    char-storage-class (make-string 10)    (make-u16vector 10))
        (list      u1-storage-class (make-u16vector 10) (make-u32vector 10))
        (list      u8-storage-class (make-u8vector 10)  (make-u16vector 10))
        (list     u16-storage-class (make-u16vector 10) (make-u32vector 10))
        (list     u32-storage-class (make-u32vector 10) (make-u16vector 10))
        (list     u64-storage-class (make-u64vector 10) (make-s16vector 10))
        (list      s8-storage-class (make-s8vector 10)  (make-u16vector 10))
        (list     s16-storage-class (make-s16vector 10) (make-u16vector 10))
        (list     s32-storage-class (make-s32vector 10) (make-u16vector 10))
        (list     s64-storage-class (make-s64vector 10) (make-u16vector 10))
        (list     f16-storage-class (make-u16vector 10) (make-s16vector 10))
        (list     f32-storage-class (make-f32vector 10) (make-u16vector 10))
        (list     f64-storage-class (make-f64vector 10) (make-u16vector 10))
        (list     c64-storage-class (make-f32vector 10) (make-u16vector 10) (make-f32vector 5))
        (list    c128-storage-class (make-f64vector 10) (make-u16vector 10) (make-f64vector 5)))))
  (for-each (lambda (data)
              (let ((storage-class (car data))
                    (good-data     (cadr data))
                    (rest          (cddr data)))
                (test 150 1156 (and (array? (make-specialized-array-from-data good-data storage-class))
                           (eq? ((storage-class-data? storage-class) good-data)
                                #t)) #t)
                (for-each (lambda (bad)
                            (test-err 151 1161 (make-specialized-array-from-data bad storage-class)))
                          rest)))
            test-values))

(pretty-print
 (array->list*
  (specialized-array-reshape           ;; Reshape to a zero-dimensional array
   (array-extract                      ;; Restrict to the first element
    (make-specialized-array-from-data  ;; The basic one-dimensional array
     (vector 'foo 'bar 'baz))
    (make-interval '#(1)))
   (make-interval '#()))))

(let* ((board (u16vector #b111100110111))
       (A (specialized-array-reshape
           (array-extract
            (make-specialized-array-from-data board u1-storage-class)
            (make-interval '#(9)))
           (make-interval '#(3 3))))
       (B (list->array (make-interval '#(3 3))
                       '(1 1 1
                         0 1 1
                         0 0 1)
                       u1-storage-class)))
  (define (pad n s)
    (string-append (make-string (- n (string-length s)) #\0) s))

  (test 152 1189 (array-every = A B) #t)
  (for-each display (list "(array-every = A B) => " (array-every = A B) #\newline))
  (for-each display (list "(array-body A) => " (array-body A) #\newline))
  (for-each display (list "(array-body B) => " (array-body B) #\newline))
  (for-each display (list "(pad 16 (number->string (u16vector-ref (vector-ref (array-body A) 1) 0) 2)) => " #\newline
                          (pad 16 (number->string (u16vector-ref (vector-ref (array-body A) 1) 0) 2)) #\newline))
  (for-each display (list "(pad 16 (number->string (u16vector-ref (vector-ref (array-body B) 1) 0) 2)) => " #\newline
                          (pad 16 (number->string (u16vector-ref (vector-ref (array-body B) 1) 0) 2)) #\newline)))

(pp "list*->array and vector*->array tests")

;;; Error tests

(for-each
 (lambda (operation message)

   (test 153 1206 (operation 1 2 3 4 5) (string-append message "The fifth argument is not a boolean: "))

   (test 154 1209 (operation 1 2 3 4 #t) (string-append message "The fourth argument is not a boolean: "))

   (test 155 1212 (operation 1 2 3 4) (string-append message "The fourth argument is not a boolean: "))

   (test 156 1215 (operation 1 2 3 #t #t) (string-append message "The third argument is not a storage class: "))

   (test 157 1218 (operation 1 2 3 #t) (string-append message "The third argument is not a storage class: "))

   (test 158 1221 (operation 1 2 3) (string-append message "The third argument is not a storage class: "))

   (test 159 1224 (operation 'a 1 generic-storage-class #t #f) (string-append message "The first argument is not a nonnegative fixnum: "))

   (test 160 1227 (operation -1 1 generic-storage-class #t #f) (string-append message "The first argument is not a nonnegative fixnum: "))

   (test 161 1230 (operation 'a 1 generic-storage-class #t) (string-append message "The first argument is not a nonnegative fixnum: "))

   (test 162 1233 (operation -1 1 generic-storage-class #t) (string-append message "The first argument is not a nonnegative fixnum: "))

   (test 163 1236 (operation 'a 1 generic-storage-class) (string-append message "The first argument is not a nonnegative fixnum: "))

   (test 164 1239 (operation -1 1 generic-storage-class) (string-append message "The first argument is not a nonnegative fixnum: "))

   (test 165 1242 (operation 'a 1) (string-append message "The first argument is not a nonnegative fixnum: "))

   (test 166 1245 (operation -1 1) (string-append message "The first argument is not a nonnegative fixnum: ")))
 (list list*->array
       vector*->array)
 (list "list*->array: "
       "vector*->array: "))

;;; Output tests

(test 167 1254 (array-every equal?
                   (list*->array 1 '((a b c) (1 2 3)))
                   (list->array (make-interval '#(2))
                                '((a b c) (1 2 3)))) #t)

(test 168 1260 (array-every equal?
                   (list*->array 2 '((a b c) (1 2 3)))
                   (list->array (make-interval '#(2 3))
                                '(a b c 1 2 3))) #t)

(test 169 1266 (array-every equal?
                   (list*->array 3 '(((a b c) (1 2 3))))
                   (list->array (make-interval '#(1 2 3))
                                '(a b c 1 2 3))) #t)

(test 170 1272 (array-every equal?
                   (list*->array 2 '(((a b c) (1 2 3))))
                   (list->array (make-interval '#(1 2))
                                '((a b c) (1 2 3)))) #t)

(test 171 1278 (list*->array 3 '(((a b c) (1 2)))) (string-append "list*->array: " "The second argument is not the right shape to be converted to an array of the given dimension: "))

(test 172 1281 (array-every equal?
                   (list*->array 2 '(((a b c) (1 2))))
                   (list->array (make-interval '#(1 2))
                                '((a b c) (1 2)))) #t)

(test 173 1287 (array-every equal?
                   (list*->array 0 '())
                   (make-array (make-interval '#()) (lambda () '()))) #t)

(test 174 1292 (array-every equal?
                   (list*->array 1 '())
                   (make-array (make-interval '#(0)) (lambda () (error)))) #t)

(test 175 1297 (array-every equal?
                   (list*->array 2 '())
                   (make-array (make-interval '#(0 0)) (lambda () (error)))) #t)

(test 176 1302 (array-every equal?
                   (list*->array 2 '(()()))
                   (make-array (make-interval '#(2 0)) (lambda () (error)))) #t)

(test 177 1307 (array-every equal?
                   (vector*->array 2 '#(#(a b c) #(1 2 3)))
                   (list->array (make-interval '#(2 3))
                                '(a b c 1 2 3))) #t)

(test 178 1313 (array-every equal?
                   (vector*->array 3 '#(#(#(a b c) #(1 2 3))))
                   (list->array (make-interval '#(1 2 3))
                                '(a b c 1 2 3))) #t)

(test 179 1319 (array-every equal?
                   (vector*->array 2 '#(#((a b c) (1 2 3))))
                   (list->array (make-interval '#(1 2))
                                '((a b c) (1 2 3)))) #t)

(test 180 1325 (vector*->array 3 '#(#(#(a b c) #(1 2)))) (string-append "vector*->array: " "The second argument is not the right shape to be converted to an array of the given dimension: "))

(test 181 1328 (array-every equal?
                   (vector*->array 2 '#(#((a b c) (1 2))))
                   (list->array(make-interval '#(1 2))
                               '((a b c) (1 2)))) #t)

(test 182 1334 (array-every equal?
                   (vector*->array 0 '#())
                   (make-array (make-interval '#()) (lambda () '#()))) #t)

(test 183 1339 (array-every equal?
                   (vector*->array 1 '#())
                   (make-array (make-interval '#(0)) (lambda () (error)))) #t)

(test 184 1344 (array-every equal?
                   (vector*->array 2 '#())
                   (make-array (make-interval '#(0 0)) (lambda () (error)))) #t)

(test 185 1349 (array-every equal?
                   (vector*->array 2 '#(#()#()))
                   (make-array (make-interval '#(2 0)) (lambda () (error)))) #t)

(test-err 186 1354 (vector*->array 2 '#(#((a b c) (1 2))) u8-storage-class))

(test-err 187 1357 (list*->array 2 '(((a b c) (1 2))) u8-storage-class))

(test-err 188 1360 (list*->array 0 'a u8-storage-class))

(test-err 189 1363 (vector*->array 0 'a u8-storage-class))

(for-each (lambda (operation data)
            (for-each (lambda (mutable?)
                        (for-each (lambda (safe?)
                                    (parameterize
                                        ((specialized-array-default-mutable? mutable?)
                                         (specialized-array-default-safe? safe?))
                                      (let ((A (operation 2 data)))
                                        (test 190 1373 (mutable-array? A) mutable?)
                                        (test 191 1374 (array-safe? A) safe?))))
                                  '(#t #f)))
                      '(#t #f)))
          (list list*->array
                vector*->array)
          (list '(((a b c) (1 2)))
                '#(#((a b c) (1 2)))))

(pp "array->list* and array->vector*")

;;; Minimal tests, sorry.

(test-err 192 1386 (array->list* 'a))

(test-err 193 1389 (array->vector* 'a))

(test 194 1392 (array->list* (make-array (make-interval '#(1 1)) indices->string)) '(("0_0")))

(test 195 1395 (array->list* (make-array (make-interval '#(1)) indices->string)) '("0"))

(test 196 1398 (array->list* (make-array (make-interval '#(2 3)) indices->string)) '(("0_0" "0_1" "0_2") ("1_0" "1_1" "1_2")))

(test 197 1401 (array->list* (make-array (make-interval '#(1 1) '#(2 3)) indices->string)) '(("1_1" "1_2")))

(test 198 1404 (array->vector* (make-array (make-interval '#(1 1)) indices->string)) '#(#("0_0")))

(test 199 1407 (array->vector* (make-array (make-interval '#(1)) indices->string)) '#("0"))

(test 200 1410 (array->vector* (make-array (make-interval '#(2 3)) indices->string)) '#(#("0_0" "0_1" "0_2") #("1_0" "1_1" "1_2")))

(test 201 1413 (array->list* (make-array (make-interval '#(2 3)) indices->string)) '(("0_0" "0_1" "0_2") ("1_0" "1_1" "1_2")))

(test 202 1416 (array->vector* (make-array (make-interval '#(1 1) '#(2 3)) indices->string)) '#(#("1_1" "1_2")))

(test 203 1419 (array->vector* (list->array (make-interval '#(2 3))
                                   '(0 1 0
                                     0 1 1)
                                   u1-storage-class)) '#(#(0 1 0) #(0 1 1)))

(test 204 1425 (array->list* (list->array (make-interval '#(2 3))
                                 '(0 1 0
                                   0 1 1)
                                  u1-storage-class)) '((0 1 0) (0 1 1)))

(test 205 1431 (array->vector* (make-array (make-interval '#()) (lambda () 2))) 2)

(test 206 1434 (array->vector* (make-array (make-interval '#(0)) error)) '#())

(test 207 1437 (array->vector* (make-array (make-interval '#(2 0)) error)) '#(#() #()))

(test 208 1440 (array->vector* (make-array (make-interval '#(0 0)) error)) '#())

(test 209 1443 (array->vector* (make-array (make-interval '#(0 2)) error)) '#())

(test 210 1446 (array->list* (make-array (make-interval '#()) (lambda () 2))) 2)

(test 211 1449 (array->list* (make-array (make-interval '#(0)) error)) '())

(test 212 1452 (array->list* (make-array (make-interval '#(2 0)) error)) '(() ()))

(test 213 1455 (array->list* (make-array (make-interval '#(0 0)) error)) '())

(test 214 1458 (array->list* (make-array (make-interval '#(0 2)) error)) '())

(define random-storage-class-and-initializer
  (let* ((storage-classes
          (vector
           ;; generic
           (list generic-storage-class
                 (lambda args (random-permutation (length args))))
           ;; signed integer
           (list s8-storage-class
                 (lambda args (random (- (expt 2 7)) (- (expt 2 7) 1))))
           (list s16-storage-class
                 (lambda args (random (- (expt 2 15)) (- (expt 2 15) 1))))
           (list s32-storage-class
                 (lambda args (random (- (expt 2 31)) (- (expt 2 31) 1))))
           (list s64-storage-class
                 (lambda args (random (- (expt 2 63)) (- (expt 2 63) 1))))
           ;; unsigned integer
           (list u1-storage-class
                 (lambda args (random (expt 2 1))))
           (list u8-storage-class
                 (lambda args (random (expt 2 8))))
           (list u16-storage-class
                 (lambda args (random (expt 2 16))))
           (list u32-storage-class
                 (lambda args (random (expt 2 32))))
           (list u64-storage-class
                 (lambda args (random (expt 2 64))))
           ;; float
           (list f16-storage-class
                 (lambda args (test-random-real)))
           (list f32-storage-class
                 (lambda args (test-random-real)))
           (list f64-storage-class
                 (lambda args (test-random-real)))
           ;; char
           (list char-storage-class
                 (lambda args (random-char)))
           ;; complex-float
           (list c64-storage-class
                 (lambda args (make-rectangular (test-random-real) (test-random-real))))
           (list c128-storage-class
                 (lambda args (make-rectangular (test-random-real) (test-random-real))))))
         (n
          (vector-length storage-classes)))
    (lambda ()
      (vector-ref storage-classes (random n)))))

(pp "array-empty? tests")

(test-err 215 1509 (array-empty? 'a))

(test 216 1512 (array-empty? (make-array (make-interval '#(1) '#(1)) list)) #t)

(test 217 1515 (array-empty? (make-array (make-interval '#(1) '#(2)) list)) #f)

(test 218 1518 (array-empty? (make-array (make-interval '#()) list)) #f)


(pp "array-packed? tests")

;; We'll use specialized arrays with u1-storage-class---we never
;; use the array contents, just the indexers, and it saves storage.

(test-err 219 1527 (array-packed? 1))

(test-err 220 1530 (array-packed? (make-array (make-interval '#(1 2)) list)))

(test-err 221 1533 (array-packed? (make-array (make-interval '#(1 2)) list list)))

;; all these are true, we'll have to see how to screw it up later.

(do ((i 0 (+ i 1)))
    ((= i random-tests))
  (let ((array
         (make-specialized-array (random-interval)
                                 u1-storage-class)))
    (test 222 1543 (array-packed? array) #t)))

(next-test-random-source-state!)

;; the elements of curried arrays are in order

(do ((i 0 (+ i 1)))
    ((= i random-tests))
  (let* ((base
          (make-specialized-array (random-interval 2 5)
                                  u1-storage-class))
         (curried
          (array-curry base (random 1 (array-dimension base)))))
    (test 223 1557 (array-every array-packed? curried) #t)))

(next-test-random-source-state!)

;; Extracted arrays are in order if they are empty or have
;; dimension 0.
;; Elements of extracted arrays of newly created specialized
;; arrays are not in order unless
;; (1) the differences in the upper and lower bounds of the
;;     first dimensions all equal 1 *and*
;; (2) the next dimension doesn't matter *and*
;; (3) the upper and lower bounds of the latter dimensions
;;     of the original and extracted arrays are the same
;; Whew!

(define (extracted-array-packed? base extracted)
  (let ((base-domain (array-domain base))
        (extracted-domain (array-domain extracted))
        (dim (array-dimension base)))
    (or (interval-empty? extracted-domain)
        (eqv? dim 0)
        (let loop-1 ((i 0))
          (or (= i (- dim 1))
              (or (and (= 1 (- (interval-upper-bound extracted-domain i)
                               (interval-lower-bound extracted-domain i)))
                       (loop-1 (+ i 1)))
                  (let loop-2 ((i (+ i 1)))
                    (or (= i dim)
                        (and (= (interval-upper-bound extracted-domain i)
                                (interval-upper-bound base-domain i))
                             (= (interval-lower-bound extracted-domain i)
                                (interval-lower-bound base-domain i))
                             (loop-2 (+ i 1)))))))))))

(do ((i 0 (+ i 1)))
    ((= i random-tests))
  (let* ((base
          (make-specialized-array (random-interval 0 6)
                                  u1-storage-class))
         (extracted
          (array-extract base (random-subinterval (array-domain base)))))
    (test 224 1599 (array-packed? extracted) (extracted-array-packed? base extracted))))

(next-test-random-source-state!)

;; Should we do reversed now?

(do ((i 0 (+ i 1)))
    ((= i random-tests))
  (let* ((base
          (make-specialized-array (random-interval)
                                  u1-storage-class))
         (domain
          (array-domain base))
         (reversed-dimensions
          (vector-map (lambda args (random-boolean))
                      (make-vector (array-dimension base))))
         (reversed
          (array-reverse base reversed-dimensions)))
    (test 225 1618 (array-packed? reversed) (or (array-empty? reversed)
              (%%vector-every
               (lambda (lower upper reversed)
                 (or (= (+ 1 lower) upper)  ;; side-length 1
                     (not reversed)))       ;; dimension not reversed
               (interval-lower-bounds->vector domain)
               (interval-upper-bounds->vector domain)
               reversed-dimensions)))))

(next-test-random-source-state!)

;; permutations

;; A permuted array has elements in order iff all the dimensions with
;; sidelength > 1 are in the same order, or if it's empty.

(define (permuted-array-packed? array permutation)
  (let* ((domain
          (array-domain array))
         (axes-and-limits
          (vector-map list
                      (list->vector (iota (vector-length permutation)))
                      (interval-lower-bounds->vector domain)
                      (interval-upper-bounds->vector domain)))
         (permuted-axes-and-limits
          (vector->list (vector-permute axes-and-limits permutation))))
    (or (interval-empty? domain)
        (in-order (lambda (x y)
                    (< (car x) (car y)))
                  (filter (lambda (l)
                            (let ((i (car l))
                                  (l (cadr l))
                                  (u (caddr l)))
                              (< 1 (- u l))))
                          permuted-axes-and-limits)))))

(do ((i 0 (+ i 1)))
    ((= i random-tests))
  (let* ((base
          (make-specialized-array (random-interval)
                                  u1-storage-class))
         (domain
          (array-domain base))
         (permutation
          (random-permutation (array-dimension base)))
         (permuted
          (array-permute base permutation)))
    (test 226 1666 (array-packed? permuted) (permuted-array-packed? base permutation))))

(next-test-random-source-state!)

;; a sampled array has elements in order iff after a string of
;; dimensions with side-length 1 at the beginning, all the rest
;; of the dimensions have sidelengths the same as the original

(define (sampled-array-packed? base scales)
  (let* ((domain
          (array-domain base))
         (sampled-base
          (array-sample base scales))
         (scaled-domain
          (array-domain sampled-base))
         (base-sidelengths
          (vector->list
           (vector-map -
                       (interval-upper-bounds->vector domain)
                       (interval-lower-bounds->vector domain))))
         (scaled-sidelengths
          (vector->list
           (vector-map -
                       (interval-upper-bounds->vector scaled-domain)
                       (interval-lower-bounds->vector scaled-domain)))))
    (let loop-1 ((base-lengths   base-sidelengths)
                 (scaled-lengths scaled-sidelengths))
      (or (null? base-lengths)
          (if (= (car scaled-lengths) 1)
              (loop-1 (cdr base-lengths)
                      (cdr scaled-lengths))
              (let loop-2 ((base-lengths   base-lengths)
                           (scaled-lengths scaled-lengths))
                (or (null? base-lengths)
                    (and (= (car base-lengths) (car scaled-lengths))
                         (loop-2 (cdr base-lengths)
                                 (cdr scaled-lengths))))))))))

(do ((i 0 (+ i 1)))
    ((= i random-tests))
  (let* ((base
          (make-specialized-array (random-nonnegative-interval 1 6)
                                   u1-storage-class))
         (scales
          (random-positive-vector (array-dimension base) 4))
         (sampled
          (array-sample base scales)))
    (test 227 1714 (array-packed? sampled) (sampled-array-packed? base scales))))

(next-test-random-source-state!)

;;; REMOVED for kaappi run: array-packed? caching tests and the
;;; %%move-array-elements section (reference internals; the public
;;; array-copy/array-assign! behavior they underlie is covered by
;;; the array-copy, array-assign! and array-reshape tests below).
(pp "array-copy and array-copy! error tests")

(for-each (lambda (call/cc-safe?)
            (let* ((array-copy (if call/cc-safe?
                                   array-copy
                                   array-copy!))
                   (message    (if call/cc-safe?
                                   "array-copy: "
                                   "array-copy!: ")))

              (define (wrap error-reason)
                (string-append message error-reason))

              (test 246 2029 (array-copy (make-array (make-interval '#(4)) list) u8-storage-class #t 'a) (wrap "The fourth argument is not a boolean: "))

              (test 247 2032 (array-copy (make-array (make-interval '#(4)) list) u8-storage-class 'a #t) (wrap "The third argument is not a boolean: "))

              (test 248 2035 (array-copy (make-array (make-interval '#(4)) list) 'u8-storage-class #t #t) (wrap "The second argument is not a storage-class: "))

              (test 249 2038 (array-copy 'a) (wrap "The first argument is not an array: "))

              (test 250 2041 (array-copy #f generic-storage-class) (wrap "The first argument is not an array: "))

              (test 251 2044 (array-copy (make-array (make-interval '#(1) '#(2))
                                            list)
                                #f) (wrap "The second argument is not a storage-class: "))

              (test 252 2049 (array-copy (make-array (make-interval '#(1) '#(2))
                                            list)
                                generic-storage-class
                                'a) (wrap "The third argument is not a boolean: "))


              (test 253 2056 (array-copy (make-array (make-interval '#(1) '#(2))
                                            list)
                                generic-storage-class
                                #f
                                'a) (wrap "The fourth argument is not a boolean: "))

              ;; Check that explicit setting of mutable? and safe? work


              (test 254 2066 (mutable-array? (array-copy (list->array (make-interval '#(2 2))
                                                             '(1 2 3 4)
                                                             generic-storage-class
                                                             #f))) #f)

              (test 255 2072 (mutable-array? (array-copy (list->array (make-interval '#(2 2))
                                                             '(1 2 3 4)
                                                             generic-storage-class
                                                             #f)
                                                generic-storage-class
                                                #t)) #t)


              (test 256 2081 (array-safe? (array-copy (list->array (make-interval '#(2 2))
                                                          '(1 2 3 4)
                                                          generic-storage-class
                                                          #f
                                                          #f))) #f)

              (test 257 2088 (array-safe? (array-copy (list->array (make-interval '#(2 2))
                                                          '(1 2 3 4)
                                                          generic-storage-class
                                                          #f
                                                          #f)
                                             generic-storage-class
                                             #t
                                             #t)) #t)

              ;; Check that defaults of mutable? and safe? work

              (parameterize
                  ((specialized-array-default-mutable? #t))
                (test 258 2102 (mutable-array? (array-copy (list->array (make-interval '#(2 2))
                                                               '(1 2 3 4)
                                                               generic-storage-class
                                                               #t))) #t)

                (test 259 2108 (mutable-array? (array-copy (list->array (make-interval '#(2 2))
                                                               '(1 2 3 4)
                                                               generic-storage-class
                                                               #t)
                                                  generic-storage-class
                                                  #f)) #f)
                (test 260 2115 (mutable-array? (array-copy (make-array (make-interval '#(2 2)) list))) #t)

                (test 261 2118 (mutable-array? (array-copy (make-array (make-interval '#(2 2)) list)
                                                  generic-storage-class
                                                  #f)) #f))

              (parameterize
                  ((specialized-array-default-mutable? #f))
                (test 262 2125 (array-safe? (array-copy (list->array (make-interval '#(2 2))
                                                            '(1 2 3 4)
                                                            generic-storage-class
                                                            #t
                                                            #t))) #t)

                (test 263 2132 (array-safe? (array-copy (list->array (make-interval '#(2 2))
                                                            '(1 2 3 4)
                                                            generic-storage-class
                                                            #t
                                                            #t)
                                               generic-storage-class
                                               #f
                                               #f)) #f)

                (test 264 2142 (mutable-array? (array-copy (make-array (make-interval '#(2 2)) list))) #f)

                (test 265 2145 (mutable-array? (array-copy (make-array (make-interval '#(2 2)) list)
                                                  generic-storage-class
                                                  #t)) #t))

              (parameterize
                  ((specialized-array-default-safe? #t))
                (test 266 2152 (mutable-array? (array-copy (list->array (make-interval '#(2 2))
                                                               '(1 2 3 4)
                                                               generic-storage-class
                                                               #f))) #f)

                (test 267 2158 (mutable-array? (array-copy (list->array (make-interval '#(2 2))
                                                               '(1 2 3 4)
                                                               generic-storage-class
                                                               #f)
                                                  generic-storage-class
                                                  #t)) #t)
                (test 268 2165 (array-safe? (array-copy (make-array (make-interval '#(2 2)) list))) #t)

                (test 269 2168 (array-safe? (array-copy (make-array (make-interval '#(2 2)) list)
                                               generic-storage-class
                                               #f
                                               #f)) #f))

              (parameterize
                  ((specialized-array-default-safe? #f))
                (test 270 2176 (array-safe? (array-copy (list->array (make-interval '#(2 2))
                                                            '(1 2 3 4)
                                                            generic-storage-class
                                                            #f
                                                            #f))) #f)

                (test 271 2183 (array-safe? (array-copy (list->array (make-interval '#(2 2))
                                                            '(1 2 3 4)
                                                            generic-storage-class
                                                            #f
                                                            #f)
                                               generic-storage-class
                                               #t
                                               #t)) #t)

                (test 272 2193 (array-safe? (array-copy (make-array (make-interval '#(2 2)) list))) #f)

                (test 273 2196 (array-safe? (array-copy (make-array (make-interval '#(2 2)) list)
                                               generic-storage-class
                                               #t
                                               #t)) #t))



              ;; We gotta make sure than the error checks work in all dimensions ...

              (test 274 2206 (array-copy (make-array (make-interval '#()) list)
                                u16-storage-class) (wrap "Not all elements of the source can be stored in destination: "))

              (test 275 2210 (array-copy (make-array (make-interval '#(1) '#(2))
                                            list)
                                u16-storage-class) (wrap "Not all elements of the source can be stored in destination: "))

              (test 276 2215 (array-copy (make-array (make-interval '#(1 1) '#(2 2))
                                            list)
                                u16-storage-class) (wrap "Not all elements of the source can be stored in destination: "))

              (test 277 2220 (array-copy (make-array (make-interval '#(1 1 1) '#(2 2 2))
                                            list)
                                u16-storage-class) (wrap "Not all elements of the source can be stored in destination: "))

              (test 278 2225 (array-copy (make-array (make-interval '#(1 1 1 1) '#(2 2 2 2))
                                            list)
                                u16-storage-class) (wrap "Not all elements of the source can be stored in destination: "))

              (test 279 2230 (array-copy (make-array (make-interval '#(1 1 1 1 1) '#(2 2 2 2 2))
                                            list)
                                u16-storage-class) (wrap "Not all elements of the source can be stored in destination: "))
              ))
          '(#t #f))

(test-err 280 2237 (specialized-array-default-safe? 'a))

(test-err 281 2240 (specialized-array-default-mutable? 'a))

(let ((mutable-default (specialized-array-default-mutable?)))
  (specialized-array-default-mutable? #f)
  (do ((i 1 (+ i 1)))
      ((= i 6))
    (let ((A (array-copy (make-array (make-interval (make-vector i 2)) (lambda args 10)))))
      (test-err 282 2248 (apply array-set! A 0 (make-list i 0)))
      (test-err 283 2250 (array-assign! A A))))
  (specialized-array-default-mutable? mutable-default))


(pp "array-copy result tests")

(specialized-array-default-safe? #t)

(pp "Safe tests")

(do ((i 0 (+ i 1)))
    ((= i random-tests))
  (let* ((domain
          (random-interval))
         (lower-bounds
          (interval-lower-bounds->list domain))
         (upper-bounds
          (interval-upper-bounds->list domain))
         (array1
          (let ((alist '()))
            (make-array
             domain
             (lambda indices
               (cond ((assoc indices alist)
                      => cdr)
                     (else
                      indices)))
             (lambda (value . indices)
               (cond ((assoc indices alist)
                      =>(lambda (entry)
                          (set-cdr! entry value)))
                     (else
                      (set! alist (cons (cons indices value)
                                        alist))))))))
         (array2
          (array-copy array1 generic-storage-class))
         (array2!
          (array-copy! array1 generic-storage-class))
         (setter1
          (array-setter array1))
         (setter2
          (array-setter array2))
         (setter2!
          (array-setter array2!)))
    (if (not (array-empty? array1))
        (do ((j 0 (+ j 1)))
            ((= j 25))
          (let ((v (random 1000))
                (indices (map random lower-bounds upper-bounds)))
            (apply setter1 v indices)
            (apply setter2 v indices)
            (apply setter2! v indices))))
    (test 284 2303 (myarray= array1 array2) #t)
    (test 285 2304 (myarray= array1 array2!) #t)
    (test 286 2305 (myarray= (array-copy array1 generic-storage-class) array2) #t)
    (test 287 2306 (myarray= (array-copy array1 generic-storage-class) array2!) #t)))

(next-test-random-source-state!)

(specialized-array-default-safe? #f)

(pp "Unsafe tests")

(do ((i 0 (+ i 1)))
    ((= i random-tests))
  (let* ((domain
          (random-interval))
         (lower-bounds
          (interval-lower-bounds->list domain))
         (upper-bounds
          (interval-upper-bounds->list domain))
         (array1
          (let ((alist '()))
            (make-array
             domain
             (lambda indices
               (cond ((assoc indices alist)
                      => cdr)
                     (else
                      indices)))
             (lambda (value . indices)
               (cond ((assoc indices alist)
                      =>(lambda (entry)
                          (set-cdr! entry value)))
                     (else
                      (set! alist (cons (cons indices value)
                                        alist))))))))
         (array2
          (array-copy array1 generic-storage-class))
         (array2!
          (array-copy! array1 generic-storage-class))
         (setter1
          (array-setter array1))
         (setter2
          (array-setter array2))
         (setter2!
          (array-setter array2!)))
    (if (not (array-empty? array1))
        (do ((j 0 (+ j 1)))
            ((= j 25))
          (let ((v (random 1000))
                (indices (map random lower-bounds upper-bounds)))
            (apply setter1 v indices)
            (apply setter2 v indices)
            (apply setter2! v indices))))
    (test 288 2356 (myarray= array1 array2) #t)
    (test 289 2357 (myarray= array1 array2!) #t)
    (test 290 2358 (myarray= (array-copy array1 generic-storage-class) array2) #t)
    (test 291 2359 (myarray= (array-copy array1 generic-storage-class) array2!) #t)))

(next-test-random-source-state!)

(pp "array-map error tests")

(test-err 292 2365 (array-map 1 #f))

(test-err 293 2368 (array-map list 1 (make-array (make-interval '#(3) '#(4))
                                    list)))

(test-err 294 2372 (array-map list (make-array (make-interval '#(3) '#(4))
                                  list) 1))

(test-err 295 2376 (array-map list
                 (make-array (make-interval '#(3) '#(4))
                             list)
                 (make-array (make-interval '#(3 4) '#(4 5))
                             list)))

(do ((d 0 (+ d 1)))
    ((= d 6))
  (let* ((A (make-array (make-interval (make-vector d 3)) list))
         (B (array-map length A)))
    (test 296 2387 (apply (array-getter B) (make-list d 3)) (if (zero? d)  ;; zero copies of 3 is a valid multi-index
              0
              "array-getter: domain does not contain multi-index: "))
    (test 297 2391 (apply (array-getter B) (make-list 6 2)) (if (= d 5)
              ;; the actual getter is variadic, so it checks that the
              ;; number of arguments is accurate itself
              "array-getter: multi-index is not the correct dimension: "
              ;; for d < 5 we rely on the built-in check
              "Wrong number of arguments passed to procedure "))))

(pp "array-every and array-any error tests")

(test-err 298 2401 (array-every 1 2))

(test-err 299 2404 (array-every list 1))

(test-err 300 2407 (array-every list
                   (make-array (make-interval '#(3) '#(4))
                               list)
                   1))

(test-err 301 2413 (array-every list
                   (make-array (make-interval '#(3) '#(4))
                               list)
                   (make-array (make-interval '#(3 4) '#(4 5))
                               list)))

(test-err 302 2420 (array-any 1 2))

(test-err 303 2423 (array-any list 1))

(test-err 304 2426 (array-any list
                 (make-array (make-interval '#(3) '#(4))
                             list)
                 1))

(test-err 305 2432 (array-any list
                 (make-array (make-interval '#(3) '#(4))
                             list)
                 (make-array (make-interval '#(3 4) '#(4 5))
                             list)))

(pp "array-every and array-any")

(define (multi-index< ind1 ind2)
  (and (not (null? ind1))
       (not (null? ind2))
       (or (< (car ind1)
              (car ind2))
           (and (= (car ind1)
                   (car ind2))
                (multi-index< (cdr ind1)
                              (cdr ind2))))))

(define (indices-in-proper-order l)
  (or (null? l)
      (null? (cdr l))
      (and (multi-index< (car l)
                         (cadr l))
           (indices-in-proper-order (cdr l)))))

(do ((i 0 (+ i 1)))
    ((= i random-tests))
  (let* ((interval
          (random-nonnegative-interval 1 6))
         (n
          (interval-volume interval))
         (separator
          ;; I want to make sure that the last item is chosen at least
          ;; once for each random
          (random (max 0 (- n 10)) n))
         (indexer
          (%%interval->basic-indexer interval))
         (arguments-1
          '())
         (array-1
          (make-array interval
                      (lambda args
                        (set! arguments-1 (cons args
                                                arguments-1))
                        (let ((index (apply indexer args)))
                          (cond ((< index separator)
                                 #f)
                                ((= index separator)
                                 1)
                                (else
                                 (error "The array should never be called with these args"
                                        interval
                                        separator
                                        args
                                        index)))))))
         (arguments-2
          '())
         (array-2
          (make-array interval
                      (lambda args
                        (set! arguments-2 (cons args
                                                arguments-2))
                        (let ((index (apply indexer args)))
                          (cond ((< index separator)
                                 #t)
                                ((= index separator)
                                 #f)
                                (else
                                 (error "The array should never be called with these args"
                                        interval
                                        separator
                                        args
                                        index))))))))
    (test 306 2506 (array-any values array-1) 1)
    (test 307 2508 (array-every values array-2) #f)
    (if (not (indices-in-proper-order (reverse arguments-1)))
        (error "arrghh arguments-1" arguments-1))
    (if (not (indices-in-proper-order (reverse arguments-2)))
        (error "arrghh arguments-2" arguments-2))))

(next-test-random-source-state!)




(pp "array-fold-left, array-fold-right error tests")

(test-err 308 2522 (array-fold-left 1 1 1))

(test-err 309 2525 (array-fold-left list 1 1))

(test-err 310 2528 (array-fold-left list 1 (make-array (make-interval '#()) list) 1))

(test-err 311 2531 (array-fold-left list 1 (make-array (make-interval '#()) list) (make-array (make-interval '#(1)) list)))

(test 312 2534 (array-fold-left cons '() (make-array (make-interval '#()) (lambda () 42))) '(() . 42))

(test 313 2537 (array-fold-right cons 42 (make-array (make-interval '#(0)) error)) 42)

(test-err 314 2540 (array-fold-right 1 1 1))

(test-err 315 2543 (array-fold-right list 1 1))

(test-err 316 2546 (array-fold-right list 1 (make-array (make-interval '#()) list) 1))

(test-err 317 2549 (array-fold-right list 1 (make-array (make-interval '#()) list) (make-array (make-interval '#(1)) list)))

(test 318 2552 (array-fold-right cons '() (make-array (make-interval '#()) (lambda () 42))) '(42))

(test 319 2555 (array-fold-right cons 42 (make-array (make-interval '#(0)) error)) 42)

(pp "array-for-each error tests")

(test-err 320 2560 (array-for-each 1 #f))

(test-err 321 2563 (array-for-each list 1 (make-array (make-interval '#(3) '#(4))
                                         list)))

(test-err 322 2567 (array-for-each list (make-array (make-interval '#(3) '#(4))
                                       list) 1))

(test-err 323 2571 (array-for-each list
                      (make-array (make-interval '#(3) '#(4))
                                  list)
                      (make-array (make-interval '#(3 4) '#(4 5))
                                  list)))

(pp "array-map, array-fold-right, and array-for-each result tests")

(let ((list-of-60 (iota 60)))
  (for-each (lambda (divisor)   ;; 1 through 5
              ;; Break up list-of-60 into equivalence classes modulo divisor
              ;; Convert these to arrays.
              ;; Do a simple test on array-fold-left and array-fold-right with cons and '()
              (let* ((specialized-parts
                      (map (lambda (remainder)
                             (list*->array
                              1
                              (filter (lambda (j)
                                        (eqv? (modulo j divisor) remainder))
                                      list-of-60)))
                           (iota divisor)))
                     (generalized-parts
                      (map (lambda (a)
                             (make-array (array-domain a)
                                         (array-getter a)))
                           specialized-parts)))
                (test 324 2598 (apply array-fold-left
                             (lambda (id . lst)
                               (foldl cons id lst))
                             '()
                             specialized-parts) (foldl cons '() list-of-60))
                (test 325 2604 (apply array-fold-right
                             (lambda args
                               (foldr cons (list-ref args divisor) (take args divisor)))
                             '()
                             specialized-parts) (foldr cons '() list-of-60))
                (test 326 2610 (apply array-fold-left
                             (lambda (id . lst)
                               (foldl cons id lst))
                             '()
                             generalized-parts) (foldl cons '() list-of-60))
                (test 327 2616 (apply array-fold-right
                             (lambda args
                               (foldr cons (list-ref args divisor) (take args divisor)))
                             '()
                             generalized-parts) (foldr cons '() list-of-60))
                ))
            (iota 6 1)))




(specialized-array-default-safe? #t)

(let ((array-builders (vector (list u1-storage-class      (lambda indices (random 0 (expt 2 1))))
                              (list u8-storage-class      (lambda indices (random 0 (expt 2 8))))
                              (list u16-storage-class     (lambda indices (random 0 (expt 2 16))))
                              (list u32-storage-class     (lambda indices (random 0 (expt 2 32))))
                              (list u64-storage-class     (lambda indices (random 0 (expt 2 64))))
                              (list s8-storage-class      (lambda indices (random (- (expt 2 7))  (expt 2 7))))
                              (list s16-storage-class     (lambda indices (random (- (expt 2 15)) (expt 2 15))))
                              (list s32-storage-class     (lambda indices (random (- (expt 2 31)) (expt 2 31))))
                              (list s64-storage-class     (lambda indices (random (- (expt 2 63)) (expt 2 63))))
                              (list f16-storage-class     (lambda indices (test-random-real)))
                              (list f32-storage-class     (lambda indices (test-random-real)))
                              (list f64-storage-class     (lambda indices (test-random-real)))
                              (list char-storage-class    (lambda indices (random-char)))
                              (list c64-storage-class     (lambda indices (make-rectangular (test-random-real) (test-random-real))))
                              (list c128-storage-class    (lambda indices (make-rectangular (test-random-real) (test-random-real))))
                              (list generic-storage-class (lambda indices indices)))))
  (do ((i 0 (+ i 1)))
      ((= i random-tests))
    (let* ((domain
            (random-interval))
           (lower-bounds
            (interval-lower-bounds->list domain))
           (upper-bounds
            (interval-upper-bounds->list domain))
           (array-length
            (lambda (a)
              (let ((upper-bounds (interval-upper-bounds->list (array-domain a)))
                    (lower-bounds (interval-lower-bounds->list (array-domain a))))
                (apply * (map - upper-bounds lower-bounds)))))
           (arrays
            (map (lambda (ignore)
                   (let ((array-builder (vector-ref array-builders (random (vector-length array-builders)))))
                     (array-copy (make-array domain
                                             (cadr array-builder))
                                 (car array-builder))))
                 (local-iota 0 (random 1 7))))
           (result-array-1
            (apply array-map
                   list
                   arrays))
           (result-array-2
            (array-copy
             (apply array-map
                    list
                    arrays)))
           (getters
            (map array-getter arrays))
           (result-array-3
            (make-array domain
                        (lambda indices
                          (map (lambda (g) (apply g indices)) getters)))))
      (test 328 2681 (myarray= result-array-1 result-array-2) #t)
      (test 329 2683 (myarray= result-array-2 result-array-3) #t)
      (test 330 2685 (vector->list (array-body result-array-2)) (array-fold-right (lambda (x y) (cons x y))
                              '()
                              result-array-2))
      (test 331 2689 (vector->list (array-body result-array-2)) (reverse (let ((result '()))
                       (array-for-each (lambda (f)
                                         (set! result (cons f result)))
                                       result-array-2)
                       result)))
      (test 332 2695 (map array-length arrays) (map (lambda (array)
                    ((storage-class-length (array-storage-class array)) (array-body array)))
                  arrays)))))

(next-test-random-source-state!)

(specialized-array-default-safe? #f)

(let ((array-builders (vector (list u1-storage-class      (lambda indices (random (expt 2 1))))
                              (list u8-storage-class      (lambda indices (random (expt 2 8))))
                              (list u16-storage-class     (lambda indices (random (expt 2 16))))
                              (list u32-storage-class     (lambda indices (random (expt 2 32))))
                              (list u64-storage-class     (lambda indices (random (expt 2 64))))
                              (list s8-storage-class      (lambda indices (random (- (expt 2 7))  (expt 2 7))))
                              (list s16-storage-class     (lambda indices (random (- (expt 2 15)) (expt 2 15))))
                              (list s32-storage-class     (lambda indices (random (- (expt 2 31)) (expt 2 31))))
                              (list s64-storage-class     (lambda indices (random (- (expt 2 63)) (expt 2 63))))
                              (list f16-storage-class     (lambda indices (test-random-real)))
                              (list f32-storage-class     (lambda indices (test-random-real)))
                              (list f64-storage-class     (lambda indices (test-random-real)))
                              (list char-storage-class    (lambda indices (random-char)))
                              (list c64-storage-class     (lambda indices (make-rectangular (test-random-real) (test-random-real))))
                              (list c128-storage-class    (lambda indices (make-rectangular (test-random-real) (test-random-real))))
                              (list generic-storage-class (lambda indices indices)))))
  (do ((i 0 (+ i 1)))
      ((= i random-tests))
    (let* ((domain
            (random-interval))
           (lower-bounds
            (interval-lower-bounds->list domain))
           (upper-bounds
            (interval-upper-bounds->list domain))
           (arrays
            (map (lambda (ignore)
                   (let ((array-builder (vector-ref array-builders (random (vector-length array-builders)))))
                     (array-copy (make-array domain
                                             (cadr array-builder))
                                 (car array-builder))))
                 (local-iota 0 (random 1 7))))
           (result-array-1
            (apply array-map
                   list
                   arrays))
           (result-array-2
            (array-copy
             (apply array-map
                    list
                    arrays)))
           (getters
            (map array-getter arrays))
           (result-array-3
            (make-array domain
                        (lambda indices
                          (map (lambda (g) (apply g indices)) getters)))))
      (test 333 2750 (myarray= result-array-1 result-array-2) #t)
      (test 334 2752 (myarray= result-array-2 result-array-3) #t)
      (test 335 2754 (vector->list (array-body result-array-2)) (array-fold-right cons
                              '()
                              result-array-2))
      (test 336 2758 (vector->list (array-body result-array-2)) (reverse (let ((result '()))
                       (array-for-each (lambda (f)
                                         (set! result (cons f result)))
                                       result-array-2)
                       result))))))

(next-test-random-source-state!)

(pp "array-reduce tests")

(test-err 337 2769 (array-reduce 'a 'a))

(test-err 338 2772 (array-reduce 'a (make-array (make-interval '#(1) '#(3)) list)))

(test-err 339 2775 (array-reduce + (make-array (make-interval '#(0)) error)))

(test 340 2778 (array-reduce (lambda (a b) error) (make-array (make-interval '#()) (lambda () 42))) 42)

;;; OK, how to test array-reduce?

;;; Well, we take an associative, non-commutative operation,
;;; multiplying two-x-two matrices, with data such that doing operations
;;; in the opposite order gives the wrong answer, doing it for the
;;; wrong interval (e.g., swapping axes) gives the wrong answer.

;;; This is not in the same style as the other tests, which use random
;;; data to a great extent, but I couldn't see how to choose random
;;; data that would satisfy the constraints.


(define matrix vector)

(define (two-x-two-multiply A B)
  (let ((a_11 (vector-ref A 0)) (a_12 (vector-ref A 1))
        (a_21 (vector-ref A 2)) (a_22 (vector-ref A 3))
        (b_11 (vector-ref B 0)) (b_12 (vector-ref B 1))
        (b_21 (vector-ref B 2)) (b_22 (vector-ref B 3)))
    (vector (+ (* a_11 b_11) (* a_12 b_21)) (+ (* a_11 b_12) (* a_12 b_22))
            (+ (* a_21 b_11) (* a_22 b_21)) (+ (* a_21 b_12) (* a_22 b_22)))))

(define A (make-array (make-interval '#(1) '#(11))
                      (lambda (i)
                        (if (even? i)
                            (matrix 1 i
                                    0 1)
                            (matrix 1 0
                                    i 1)))))


(define A_2 (make-array (make-interval '#(1 1) '#(3 7))
                        (lambda (i j)
                          (if (and (even? i) (even? j))
                              (matrix 1 i
                                      j 1)
                              (matrix 1 j
                                      i -1)))))

(define A_3 (make-array (make-interval '#(1 1 1) '#(3 5 4))
                        (lambda (i j k)
                          (if (and (even? i) (even? j))
                              (matrix 1 i
                                      j k)
                              (matrix k j
                                      i -1)))))


(define A_4 (make-array (make-interval '#(1 1 1 1) '#(3 2 4 3))
                        (lambda (i j k l)
                          (if (and (even? i) (even? j))
                              (matrix l i
                                      j k)
                              (matrix l k
                                      i j)))))

(define A_5 (make-array (make-interval '#(1 1 1 1 1) '#(3 2 4 3 3))
                        (lambda (i j k l m)
                          (if (even? m)
                              (matrix (+ m l) i
                                      j k)
                              (matrix (- l m) k
                                      i j)))))


(for-each (lambda (A)
            (test 341 2847 (array-reduce two-x-two-multiply A) (array-fold-right two-x-two-multiply (matrix 1 0 0 1) A))

            (test 342 2850 (array-reduce two-x-two-multiply A) (array-fold-left two-x-two-multiply (matrix 1 0 0 1) A))

            (test 343 2853 (equal? (array-reduce two-x-two-multiply A)
                          (array-reduce two-x-two-multiply (array-reverse A))) #f))
          (list A A_2 A_3 A_4 A_5))

(pp "Some array-curry tests.")

(test-err 344 2860 (array-curry 'a 1))

(test-err 345 2863 (array-curry (make-array (make-interval '#(0) '#(1)) list)  'a))

(test-err 346 2866 (array-curry (make-array (make-interval '#(0 0) '#(1 1)) list)  -1))

(test-err 347 2869 (array-curry (make-array (make-interval '#(0 0) '#(1 1)) list)  3))

;;; Used to fail.

(test 348 2874 (array? (array-curry (array-permute (make-specialized-array (make-interval '#(4 4 0 4))) (index-last 4 1)) 1)) #t)

(let* ((dim 6)
       (domain (make-interval (make-vector dim 3)))
       (immutable (make-array domain list))
       (mutable   (make-array domain list list)) ;; nonsensical
       (special   (make-specialized-array domain)))
  (do ((left-dim 0 (+ left-dim 1)))
      ((> left-dim dim))
    (let* ((right-dim (- dim left-dim))
           (immutable-curry (array-curry immutable right-dim))
           (mutable-curry   (array-curry  mutable right-dim))
           (special-curry   (array-curry special right-dim)))
      (for-each (lambda (array)
                  (if (positive? left-dim)
                      (begin
                        (test-err 349 2891 (apply array-ref array (make-list left-dim 100)))
                        (test-err 350 2893 (apply array-ref array (make-list left-dim 'a)))))
                  (if (positive? right-dim)
                      (begin
                        (test-err 351 2897 (apply array-ref
                                     (apply array-ref array (make-list left-dim 0))
                                     (make-list right-dim 100)))
                        (test-err 352 2901 (apply array-ref
                                     (apply array-ref array (make-list left-dim 0))
                                     (make-list right-dim 'a)))))
                  (if (not (= 2 left-dim))
                      (test 353 2906 (apply array-ref array '(0 0)) (if (< left-dim 5)
                                "Wrong number of arguments passed to procedure "
                                "array-getter: multi-index is not the correct dimension: ")))
                  (if (not (= 2 right-dim))
                      (test 354 2911 (apply array-ref
                                   (apply array-ref array (make-list left-dim 0))
                                   '(0 0)) (if (< right-dim 5)
                                "Wrong number of arguments passed to procedure "
                                "array-getter: multi-index is not the correct dimension: "))))
                (list immutable-curry mutable-curry special-curry)))))

(let ((array-builders (vector (list u1-storage-class      (lambda indices (random (expt 2 1))))
                              (list u8-storage-class      (lambda indices (random (expt 2 8))))
                              (list u16-storage-class     (lambda indices (random (expt 2 16))))
                              (list u32-storage-class     (lambda indices (random (expt 2 32))))
                              (list u64-storage-class     (lambda indices (random (expt 2 64))))
                              (list s8-storage-class      (lambda indices (random (- (expt 2 7))  (expt 2 7))))
                              (list s16-storage-class     (lambda indices (random (- (expt 2 15)) (expt 2 15))))
                              (list s32-storage-class     (lambda indices (random (- (expt 2 31)) (expt 2 31))))
                              (list s64-storage-class     (lambda indices (random (- (expt 2 63)) (expt 2 63))))
                              (list f16-storage-class     (lambda indices (test-random-real)))
                              (list f32-storage-class     (lambda indices (test-random-real)))
                              (list f64-storage-class     (lambda indices (test-random-real)))
                              (list char-storage-class    (lambda indices (random-char)))
                              (list c64-storage-class     (lambda indices (make-rectangular (test-random-real) (test-random-real))))
                              (list c128-storage-class    (lambda indices (make-rectangular (test-random-real) (test-random-real))))
                              (list generic-storage-class (lambda indices indices)))))
  (do ((i 0 (+ i 1)))
      ((= i random-tests))
    (let* ((domain
            (random-interval 0 7))
           (lower-bounds
            (interval-lower-bounds->list domain))
           (upper-bounds
            (interval-upper-bounds->list domain))
           (array-builder
            (vector-ref array-builders (random (vector-length array-builders))))
           (random-array-element
            (cadr array-builder))
           (storage-class
            (car array-builder))
           (Array
            (array-copy (make-array domain
                                    random-array-element)
                        storage-class))
           (copied-array
            (array-copy Array
                        storage-class))
           (inner-dimension
            (random-inclusive (interval-dimension domain)))
           (domains
            (call-with-values (lambda ()(interval-projections domain inner-dimension)) list))
           (outer-domain
            (car domains))
           (inner-domain
            (cadr domains))
           (immutable-curry
            (array-curry (make-array (array-domain Array)
                                     (array-getter Array))
                         inner-dimension))
           (mutable-curry
            (array-curry (make-array (array-domain Array)
                                     (array-getter Array)
                                     (array-setter Array))
                         inner-dimension))
           (specialized-curry
            (array-curry Array inner-dimension))
           (immutable-curry-from-definition
            (call-with-values
                (lambda () (interval-projections (array-domain Array) inner-dimension))
              (lambda (outer-interval inner-interval)
                (make-array outer-interval
                            (lambda outer-multi-index
                              (make-array inner-interval
                                          (lambda inner-multi-index
                                            (apply (array-getter Array) (append outer-multi-index inner-multi-index)))))))))
           (mutable-curry-from-definition
            (call-with-values
                (lambda () (interval-projections (array-domain Array) inner-dimension))
              (lambda (outer-interval inner-interval)
                (make-array outer-interval
                            (lambda outer-multi-index
                              (make-array inner-interval
                                          (lambda inner-multi-index
                                            (apply (array-getter Array) (append outer-multi-index inner-multi-index)))
                                          (lambda (v . inner-multi-index)
                                            (apply (array-setter Array) v (append outer-multi-index inner-multi-index)))))))))
           (specialized-curry-from-definition
            (call-with-values
                (lambda () (interval-projections (array-domain Array) inner-dimension))
              (lambda (outer-interval inner-interval)
                (make-array outer-interval
                            (lambda outer-multi-index
                              (specialized-array-share Array
                                                       inner-interval
                                                       (lambda inner-multi-index
                                                         (apply values (append outer-multi-index inner-multi-index))))))))))
      ;; mutate the curried array
      (if (and (not (interval-empty? outer-domain))
               (not (interval-empty? inner-domain)))
          (for-each (lambda (curried-array)
                      (let ((outer-getter
                             (array-getter curried-array)))
                        (do ((i 0 (+ i 1)))
                            ((= i 50))  ;; used to be tests, not 50, but 50 will do fine
                          (call-with-values
                              (lambda ()
                                (random-multi-index outer-domain))
                            (lambda outer-multi-index
                              (let ((inner-setter
                                     (array-setter (apply outer-getter outer-multi-index))))
                                (call-with-values
                                    (lambda ()
                                      (random-multi-index inner-domain))
                                  (lambda inner-multi-index
                                    (let ((new-element
                                           (random-array-element)))
                                      (apply inner-setter new-element inner-multi-index)
                                      ;; mutate the copied array without currying
                                      (apply (array-setter copied-array) new-element (append outer-multi-index inner-multi-index)))))))))))
                    (list mutable-curry
                          specialized-curry
                          mutable-curry-from-definition
                          specialized-curry-from-definition)))

      (test 355 3033 (myarray= Array copied-array) #t)
      (test 356 3034 (array-every array? immutable-curry) #t)
      (test 357 3035 (array-every (lambda (a) (not (mutable-array? a))) immutable-curry) #t)
      (test 358 3036 (array-every (lambda (a) (not (specialized-array? a))) mutable-curry) #t)
      (test 359 3037 (array-every specialized-array? specialized-curry) #t)
      (test 360 3038 (array-every (lambda (xy) (apply myarray= xy))
                         (array-map list immutable-curry immutable-curry-from-definition)) #t)
      (test 361 3041 (array-every (lambda (xy) (apply myarray= xy))
                         (array-map list mutable-curry mutable-curry-from-definition)) #t)
      (test 362 3044 (array-every (lambda (xy) (apply myarray= xy))
                         (array-map list specialized-curry specialized-curry-from-definition)) #t))))


(next-test-random-source-state!)

(pp "array-decurry and array-decurry! tests")

(for-each (lambda (call/cc-safe?)
            (let ((array-decurry
                   (if call/cc-safe?
                       array-decurry
                       array-decurry!))
                  (message
                   (if call/cc-safe?
                       "array-decurry: "
                       "array-decurry!: ")))

              (define (wrap error-reason)
                (string-append message error-reason))

              (test 363 3066 (array-decurry 'a) (wrap "The first argument is not an array: "))

              (test 364 3069 (array-decurry (make-array (make-interval '#(0)) list)) (wrap "The first argument is an empty array: "))

              (test 365 3072 (array-decurry (make-array (make-interval '#()) list) 'a) (wrap "The second argument is not a storage class: "))

              (test 366 3075 (array-decurry (make-array (make-interval '#()) list) generic-storage-class 'a) (wrap "The third argument is not a boolean: "))

              (test 367 3078 (array-decurry (make-array (make-interval '#()) list) generic-storage-class #f 'a) (wrap "The fourth argument is not a boolean: "))

              (test 368 3081 (array-decurry (make-array (make-interval '#()) list)) (wrap "Not all elements of the first argument (an array) are arrays: "))

              (test 369 3084 (array-decurry (list*->array 1 (list (make-array (make-interval '#()) list)
                                                         (make-array (make-interval '#(1)) list)))) (wrap "Not all elements of the first argument (an array) have the domain: "))

              (test 370 3088 (array-decurry (list*->array 1 (list (make-array (make-interval '#(1)) list)
                                                         (make-array (make-interval '#(1)) list)))
                                   u1-storage-class) (wrap "Not all elements of the source can be stored in destination: "))
              ))
          '(#t #f))

(define (my-array-decurry  A)
  (let* ((A
          (array-copy A))      ;; evaluate all elements of A once
         (A_dim
          (array-dimension A))
         (A_
          (array-getter A))
         (A_D
          (array-domain A))
         (element-domain
          (array-domain (apply A_ (interval-lower-bounds->list A_D))))
         (result-domain
          (interval-cartesian-product A_D (array-domain (apply A_ (interval-lower-bounds->list A_D)))))
         (result
          (make-specialized-array result-domain u1-storage-class))
         (curried-result
          (array-curry result (interval-dimension element-domain))))
    (array-for-each array-assign! result A)
    result))

(do ((i 0 (+ i 1)))
    ((= i random-tests))
  (let* ((outer-domain
          (random-nonempty-interval 0 5))
         (inner-domain
          (random-interval 0 5))
         (A
          (array-copy (make-array (interval-cartesian-product outer-domain inner-domain)
                                  (lambda args
                                    (random 2)))
                      u1-storage-class))
         (A-curried
          (array-curry A (interval-dimension inner-domain)))
         (A-curried
          (array-map (lambda (A) (make-array (array-domain A) (array-getter A))) A-curried))
         (A-decurried!
          (array-decurry! A-curried u1-storage-class))
         (A-decurried
          (array-decurry A-curried u1-storage-class)))
    (test 371 3134 (myarray= A A-decurried) #t)
    (test 372 3136 (myarray= A A-decurried!) #t)))

(next-test-random-source-state!)

(pp "specialized-array-share error tests")

(test-err 373 3143 (specialized-array-share 1 1 1))

(test-err 374 3146 (specialized-array-share (make-specialized-array (make-interval '#(1) '#(2)))
                               1 1))

(test-err 375 3150 (specialized-array-share (make-specialized-array (make-interval '#(1) '#(2)))
                               (make-interval '#(0) '#(1))
                               1))

(test-err 376 3155 (specialized-array-share (make-specialized-array (make-interval '#(0 0)))
                               (make-interval '#(1))
                               (lambda (i) (values i i))))


(test 377 3161 (myarray= (list->array (make-interval '#(0) '#(10))
                             (reverse (local-iota 0 10)))
                (specialized-array-share (list->array (make-interval '#(0) '#(10))
                                                      (local-iota 0 10))
                                         (make-interval '#(0) '#(10))
                                         (lambda (i)
                                           (- 9 i)))) #t)

(pp "specialized-array-share result tests")

(do ((i 0 (+ i 1)))
    ((= i random-tests))
  (let* ((n (random 1 11))
         (permutation (random-permutation n))
         (input-vec (list->vector (f64vector->list (random-f64vector n)))))
    (test 378 3177 (vector-permute input-vec permutation) (%%vector-permute input-vec permutation))
    (test 379 3179 (list->vector (%%vector-permute->list input-vec permutation)) (vector-permute input-vec permutation))))


(next-test-random-source-state!)


(specialized-array-default-safe? #t)

(do ((i 0 (+ i 1)))
    ((= i random-tests))
  (let* ((interval (random-interval))
         (axes (local-iota 0 (interval-dimension interval)))
         (lower-bounds (interval-lower-bounds->vector interval))
         (upper-bounds (interval-upper-bounds->vector interval))
         (a (array-copy (make-array interval list)))
         (new-axis-order (vector-permute (list->vector axes) (random-permutation (length axes))))
         (reverse-order? (list->vector (map (lambda (x) (zero? (random 2))) axes))))
    (let ((b (make-array (make-interval (vector-permute lower-bounds new-axis-order)
                                        (vector-permute upper-bounds new-axis-order))
                         (lambda multi-index
                           (apply (array-getter a)
                                  (let* ((n (vector-length new-axis-order))
                                         (multi-index-vector (list->vector multi-index))
                                         (result (make-vector n)))
                                    (do ((i 0 (+ i 1)))
                                        ((= i n) (vector->list result))
                                      (vector-set! result (vector-ref new-axis-order i)
                                                   (if (vector-ref reverse-order? (vector-ref new-axis-order i))
                                                       (+ (vector-ref lower-bounds (vector-ref new-axis-order i))
                                                          (- (vector-ref upper-bounds (vector-ref new-axis-order i))
                                                             (vector-ref multi-index-vector i)
                                                             1))
                                                       (vector-ref multi-index-vector i)))))))))
          (c (specialized-array-share a
                                      (make-interval (vector-permute lower-bounds new-axis-order)
                                                     (vector-permute upper-bounds new-axis-order))
                                      (lambda multi-index
                                        (apply values
                                               (let* ((n (vector-length new-axis-order))
                                                      (multi-index-vector (list->vector multi-index))
                                                      (result (make-vector n)))
                                                 (do ((i 0 (+ i 1)))
                                                     ((= i n) (vector->list result))
                                                   (vector-set! result (vector-ref new-axis-order i)
                                                                (if (vector-ref reverse-order? (vector-ref new-axis-order i))
                                                                    (+ (vector-ref lower-bounds (vector-ref new-axis-order i))
                                                                       (- (vector-ref upper-bounds (vector-ref new-axis-order i))
                                                                          (vector-ref multi-index-vector i)
                                                                          1))
                                                                    (vector-ref multi-index-vector i))))))))))
      (test 380 3230 (myarray= b c) #t))))

(next-test-random-source-state!)

(specialized-array-default-safe? #f)

(do ((i 0 (+ i 1)))
    ((= i random-tests))
  (let* ((interval (random-interval))
         (axes (local-iota 0 (interval-dimension interval)))
         (lower-bounds (interval-lower-bounds->vector interval))
         (upper-bounds (interval-upper-bounds->vector interval))
         (a (array-copy (make-array interval list)))
         (new-axis-order (vector-permute (list->vector axes) (random-permutation (length axes))))
         (reverse-order? (list->vector (map (lambda (x) (zero? (random 2))) axes))))
    (let ((b (make-array (make-interval (vector-permute lower-bounds new-axis-order)
                                        (vector-permute upper-bounds new-axis-order))
                         (lambda multi-index
                           (apply (array-getter a)
                                  (let* ((n (vector-length new-axis-order))
                                         (multi-index-vector (list->vector multi-index))
                                         (result (make-vector n)))
                                    (do ((i 0 (+ i 1)))
                                        ((= i n) (vector->list result))
                                      (vector-set! result (vector-ref new-axis-order i)
                                                   (if (vector-ref reverse-order? (vector-ref new-axis-order i))
                                                       (+ (vector-ref lower-bounds (vector-ref new-axis-order i))
                                                          (- (vector-ref upper-bounds (vector-ref new-axis-order i))
                                                             (vector-ref multi-index-vector i)
                                                             1))
                                                       (vector-ref multi-index-vector i)))))))))
          (c (specialized-array-share a
                                      (make-interval (vector-permute lower-bounds new-axis-order)
                                                     (vector-permute upper-bounds new-axis-order))
                                      (lambda multi-index
                                        (apply values
                                               (let* ((n (vector-length new-axis-order))
                                                      (multi-index-vector (list->vector multi-index))
                                                      (result (make-vector n)))
                                                 (do ((i 0 (+ i 1)))
                                                     ((= i n) (vector->list result))
                                                   (vector-set! result (vector-ref new-axis-order i)
                                                                (if (vector-ref reverse-order? (vector-ref new-axis-order i))
                                                                    (+ (vector-ref lower-bounds (vector-ref new-axis-order i))
                                                                       (- (vector-ref upper-bounds (vector-ref new-axis-order i))
                                                                          (vector-ref multi-index-vector i)
                                                                          1))
                                                                    (vector-ref multi-index-vector i))))))))))
      (if (not (myarray= b c))
          (pp (list "piffle"
                    a b c))))))

(next-test-random-source-state!)


(pp "interval and array translation tests")

(test 381 3288 (translation? '()) #f)

(test 382 3290 (translation? '#()) #t)

(test 383 3292 (translation? '#(a)) #f)

(test 384 3294 (translation? '#(1.0)) #f)

(test 385 3296 (translation? '#(1 2)) #t)

(let ((int (make-interval '#(0 0) '#(10 10)))
      (translation '#(10 -2)))
  (test-err 386 3300 (interval-translate 'a 10))
  (test-err 387 3302 (interval-translate int 10))
  (test-err 388 3304 (interval-translate int '#(a b)))
  (test-err 389 3306 (interval-translate int '#(1. 2.)))
  (test-err 390 3308 (interval-translate int '#(1))))

(do ((i 0 (+ i 1)))
    ((= i random-tests))
  (let* ((int (random-interval))
         (lower-bounds (interval-lower-bounds->vector int))
         (upper-bounds (interval-upper-bounds->vector int))
         (translation (list->vector (map (lambda (x)
                                           (random -10 10))
                                         (local-iota 0 (vector-length lower-bounds))))))
    (test 391 3319 (interval= (interval-translate int translation)
                     (make-interval (vector-map + lower-bounds translation)
                                    (vector-map + upper-bounds translation))) #t)))

(next-test-random-source-state!)

(let* ((domain (make-interval '#(4 4)))
       (specialized (array-copy (make-array domain list)))
       (mutable (make-array domain list list)) ;; setter is nonsensical
       (immutable (make-array domain list)))
  (for-each (lambda (array)
              (let ((translated (array-translate array '#(4 4))))
                (test-err 392 3332 (array-ref translated 0 0))
                (if (mutable-array? translated)
                    (test-err 393 3335 (array-set! translated 1 0 0)))))
            (list specialized mutable immutable)))

(let* ((specialized-array (array-copy (make-array (make-interval '#(0 0) '#(10 12))
                                                  list)))
       (mutable-array (let ((temp (array-copy specialized-array)))
                        (make-array (array-domain temp)
                                    (array-getter temp)
                                    (array-setter temp))))
       (immutable-array (make-array (array-domain mutable-array)
                                    (array-getter mutable-array)))
       (translation '#(10 -2)))

  (define (my-array-translate Array translation)
    (let* ((array-copy (array-copy Array))
           (getter (array-getter array-copy))
           (setter (array-setter array-copy)))
      (make-array (interval-translate (array-domain Array)
                                      translation)
                  (lambda args
                    (apply getter
                           (map - args (vector->list translation))))
                  (lambda (v . args)
                    (apply setter
                           v
                           (map - args (vector->list translation)))))))

  (test-err 394 3363 (array-translate 'a 1))
  (test-err 395 3365 (array-translate immutable-array '#(1.)))
  (test-err 396 3367 (array-translate immutable-array '#(0 2 3)))
  (let ((specialized-result (array-translate specialized-array translation)))
    (test 397 3370 (specialized-array? specialized-result) #t))
  (let ((mutable-result (array-translate mutable-array translation)))
    (test 398 3373 (and (mutable-array? mutable-array)
               (not (specialized-array? mutable-array))
               (mutable-array? mutable-result)
               (not (specialized-array? mutable-result))) #t))
  (let ((immutable-result (array-translate immutable-array translation)))
    (test 399 3379 (and (array? immutable-array)
               (not (mutable-array? immutable-array))
               (array? immutable-result)
               (not (mutable-array? immutable-result))) #t))

  (do ((i 0 (+ i 1)))
      ((= i random-tests))
    (let* ((domain (random-interval))
           (Array (let ((temp (make-array domain list)))
                    (case (test-random-integer 3)
                      ((0) temp)
                      ((1) (array-copy temp))
                      ((2) (let ((temp (array-copy temp)))
                             (make-array (array-domain temp)
                                         (array-getter temp)
                                         (array-setter temp)))))))
           (translation (list->vector (map (lambda (x) (random -10 10)) (vector->list (%%interval-lower-bounds domain))))))
      ;;(pp (list domain translation (interval-volume domain)))
      (let ((translated-array       (array-translate Array translation))
            (my-translated-array (my-array-translate Array translation)))
        (if (and (mutable-array? Array)
                 (not (interval-empty? (array-domain Array))))
            (let ((translated-domain (interval-translate domain translation)))
              (do ((j 0 (+ j 1)))
                  ((= j 50))
                (call-with-values
                    (lambda ()
                      (random-multi-index translated-domain))
                  (lambda multi-index
                    (let ((value (test-random-integer 10000)))
                      (apply (array-setter translated-array) value multi-index)
                      (apply (array-setter my-translated-array) value multi-index)))))))
        (test 400 3412 (myarray= (array-translate Array translation)
                        (my-array-translate Array translation)) #t)))))

(next-test-random-source-state!)

(let* ((specialized (make-specialized-array (make-interval '#(0 0 0 0 0) '#(1 1 1 1 1))))
       (mutable (make-array (array-domain specialized)
                            (array-getter specialized)
                            (array-setter specialized)))
       (A (array-translate  mutable '#(0 0 0 0 0))))

  (test-err 401 3424 ((array-getter A) 0 0))

  (test-err 402 3427 ((array-setter A) 'a 0 0)))


(pp "interval and array permutation tests")

(test-err 403 3433 (index-first 'a 'b))

(test-err 404 3436 (index-first 1. 'b))

(test-err 405 3439 (index-first -1 2))

(test-err 406 3442 (index-first 1 'a))

(test-err 407 3445 (index-first 2 1.0))

(test-err 408 3448 (index-first 2 2))

(test-err 409 3451 (index-first 2 -1))

(test-err 410 3454 (index-last 'a 'b))

(test-err 411 3457 (index-last 1. 'b))

(test-err 412 3460 (index-last -1 2))

(test-err 413 3463 (index-last 1 'a))

(test-err 414 3466 (index-last 2 1.0))

(test-err 415 3469 (index-last 2 2))

(test-err 416 3472 (index-last 2 -1))

(test-err 417 3475 (index-rotate 'a 'b))

(test-err 418 3478 (index-rotate 1. 'b))

(test-err 419 3481 (index-rotate -1 2))

(test-err 420 3484 (index-rotate 1 'a))

(test-err 421 3487 (index-rotate 2 1.0))

(test-err 422 3490 (index-rotate 2 3))

(test-err 423 3493 (index-rotate 2 -1))

(test-err 424 3496 (index-swap 'a 'b 'c))

(test-err 425 3499 (index-swap -1 'b 'c))

(test-err 426 3502 (index-swap 1 'b 'c))

(test-err 427 3505 (index-swap 1 -1 'c))

(test-err 428 3508 (index-swap 1 1 'c))

(test-err 429 3511 (index-swap 2 0 'c))

(test-err 430 3514 (index-swap 2 0 -1))

(test-err 431 3517 (index-swap 2 0 2))

;;; Testing index-*

(define (my-index-first n k)
  (let ((identity (iota n)))
    (list->vector
     (cons k (append (take identity k)
                     (drop identity (+ k 1)))))))

(define (my-index-last n k)
  (let ((identity (iota n)))
    (list->vector
     (append (take identity k)
             (drop identity (+ k 1))
             (list k)))))

(define (my-index-rotate n k)
  (let ((identity (iota n)))
    (list->vector
     (append (drop identity k)
             (take identity k)))))

(define (my-index-swap n i j)
  (let ((result (list->vector (iota n))))
    (vector-set! result i j)
    (vector-set! result j i)
    result))

(do ((n 0 (+ n 1)))
    ((= n 6))
  (do ((i 0 (+ i 1)))
      ((= i n)
       (test 432 3551 (index-rotate n i) (my-index-rotate n i)))
    (test 433 3553 (index-first n i) (my-index-first n i))
    (test 434 3555 (index-last n i) (my-index-last n i))
    (test 435 3557 (index-rotate n i) (my-index-rotate n i))
    (do ((j 0 (+ j 1)))
        ((= j n))
      (test 436 3561 (index-swap n i j) (my-index-swap n i j)))))

(pp "interval-permute and array-permute tests")

(let ((int (make-interval '#(0 0) '#(10 10)))
      (permutation '#(1 0)))
  (test-err 437 3568 (interval-permute 'a 10))
  (test-err 438 3570 (interval-permute int 10))
  (test-err 439 3572 (interval-permute int '#(a b)))
  (test-err 440 3574 (interval-permute int '#(1. 2.)))
  (test-err 441 3576 (interval-permute int '#(10 -2)))
  (test-err 442 3578 (interval-permute int '#(0)))
  (do ((i 0 (+ i 1)))
      ((= i random-tests))
    (let* ((int (random-interval))
           (lower-bounds (interval-lower-bounds->vector int))
           (upper-bounds (interval-upper-bounds->vector int))
           (permutation (random-permutation (vector-length lower-bounds))))
      (test 443 3586 (interval= (interval-permute int permutation)
                       (make-interval (vector-permute lower-bounds permutation)
                                      (vector-permute upper-bounds permutation))) #t))))

(next-test-random-source-state!)

(test 444 3593 (permutation? 'a) #f)
(test 445 3594 (permutation? '#()) #t)
(test 446 3595 (permutation? '#(1.0)) #f)
(test 447 3596 (permutation? '#(1 1)) #f)
(test 448 3597 (permutation? '#(1 2)) #f)
(test 449 3598 (permutation? '#(1 2 0)) #t)

(test 450 3600 (array-every equal?
                   (array-permute (make-array (make-interval '#()) (lambda () 42))
                                  '#())
                   (make-array (make-interval '#()) (lambda () 42))) #t)

(test 451 3606 (array-every equal?
                   (array-permute (make-array (make-interval '#(0 1)) error)
                                  '#(1 0))
                   (make-array (make-interval '#(1 0)) error)) #t)

(let* ((domain (make-interval '#(2 4)))
       (specialized (array-copy (make-array domain list)))
       (mutable (make-array domain list list))
       (immutable (make-array domain list)))
  (for-each (lambda (array)
              (let ((permuted (array-permute array '#(1 0))))
                (test-err 452 3618 (array-ref permuted 1 3))
                (if (mutable-array? array)
                    (test-err 453 3621 (array-set! permuted 1 1 3)))))
            (list specialized mutable immutable)))

(let* ((specialized-array (array-copy (make-array (make-interval '#(0 0) '#(10 12))
                                                                list)))
       (mutable-array (let ((temp (array-copy specialized-array)))
                        (make-array (array-domain temp)
                                    (array-getter temp)
                                    (array-setter temp))))
       (immutable-array (make-array (array-domain mutable-array)
                                    (array-getter mutable-array)))
       (permutation '#(1 0)))

  (test-err 454 3635 (array-permute 'a 1))
  (test-err 455 3637 (array-permute immutable-array '#(1.)))
  (test-err 456 3639 (array-permute immutable-array '#(2)))
  (test-err 457 3641 (array-permute immutable-array '#(0 1 2)))
  (let ((specialized-result (array-permute specialized-array permutation)))
    (test 458 3644 (specialized-array? specialized-result) #t))
  (let ((mutable-result (array-permute mutable-array permutation)))
    (test 459 3647 (and (mutable-array? mutable-array)
               (not (specialized-array? mutable-array))
               (mutable-array? mutable-result)
               (not (specialized-array? mutable-result))) #t))
  (let ((immutable-result (array-permute immutable-array permutation)))
    (test 460 3653 (and (array? immutable-array)
               (not (mutable-array? immutable-array))
               (array? immutable-result)
               (not (mutable-array? immutable-result))) #t))

  (specialized-array-default-safe? #t)

  (do ((i 0 (+ i 1)))
      ((= i random-tests))
    (let* ((domain (random-interval))
           (Array (let ((temp (make-array domain list)))
                    (case (test-random-integer 3)
                      ((0) temp)
                      ((1) (array-copy temp))
                      ((2) (let ((temp (array-copy temp)))
                             (make-array (array-domain temp)
                                         (array-getter temp)
                                         (array-setter temp)))))))
           (permutation (random-permutation (interval-dimension domain))))

      (define (my-array-permute Array permutation)
        (let* ((array-copy (array-copy Array))
               (getter (array-getter array-copy))
               (setter (array-setter array-copy))
               (permutation-inverse (%%permutation-invert permutation)))
          (make-array (interval-permute (array-domain Array)
                                        permutation)
                      (lambda args
                        (apply getter
                               (vector->list (vector-permute (list->vector args) permutation-inverse))))
                      (lambda (v . args)
                        (apply setter
                               v
                               (vector->list (vector-permute (list->vector args) permutation-inverse)))))))

      ;; (pp (list domain permutation (interval-volume domain)))
      (let ((permuted-array       (array-permute Array permutation))
            (my-permuted-array (my-array-permute Array permutation)))
        (if (and (mutable-array? Array)
                 (not (interval-empty? (array-domain Array))))
            (let ((permuted-domain (interval-permute domain permutation)))
              (do ((j 0 (+ j 1)))
                  ((= j 50))
                (call-with-values
                    (lambda ()
                      (random-multi-index permuted-domain))
                  (lambda multi-index
                    (let ((value (test-random-integer 10000)))
                      (apply (array-setter permuted-array) value multi-index)
                      (apply (array-setter my-permuted-array) value multi-index)))))))
        (test 461 3704 (myarray= permuted-array
                        my-permuted-array) #t))))

(next-test-random-source-state!)

  (specialized-array-default-safe? #f)

  (do ((i 0 (+ i 1)))
      ((= i random-tests))
    (let* ((domain (random-interval))
           (Array (let ((temp (make-array domain list)))
                    (case (test-random-integer 3)
                      ((0) temp)
                      ((1) (array-copy temp))
                      ((2) (let ((temp (array-copy temp)))
                             (make-array (array-domain temp)
                                         (array-getter temp)
                                         (array-setter temp)))))))
           (permutation (random-permutation (interval-dimension domain))))

      (define (my-array-permute Array permutation)
        (let* ((array-copy (array-copy Array))
               (getter (array-getter array-copy))
               (setter (array-setter array-copy))
               (permutation-inverse (%%permutation-invert permutation)))
          (make-array (interval-permute (array-domain Array)
                                        permutation)
                      (lambda args
                        (apply getter
                               (vector->list (vector-permute (list->vector args) permutation-inverse))))
                      (lambda (v . args)
                        (apply setter
                               v
                               (vector->list (vector-permute (list->vector args) permutation-inverse)))))))

      ;; (pp (list domain permutation (interval-volume domain)))
      (let ((permuted-array       (array-permute Array permutation))
            (my-permuted-array (my-array-permute Array permutation)))
        (if (and (not (array-empty? Array))
                 (mutable-array? Array))
            (let ((permuted-domain (interval-permute domain permutation)))
              (do ((j 0 (+ j 1)))
                  ((= j 50))
                (call-with-values
                    (lambda ()
                      (random-multi-index permuted-domain))
                  (lambda multi-index
                    (let ((value (test-random-integer 10000)))
                      (apply (array-setter permuted-array) value multi-index)
                      (apply (array-setter my-permuted-array) value multi-index)))))))
        (test 462 3755 (myarray= permuted-array
                        my-permuted-array) #t)))))

(next-test-random-source-state!)


(pp "interval-intersect tests")

(let ((a (make-interval '#(0 0) '#(10 10)))
      (b (make-interval '#(0) '#(10)))
      (c (make-interval '#(10 10) '#(20 20))))
  (test-err 463 3767 (interval-intersect 'a))
  (test-err 464 3769 (interval-intersect  a 'a))
  (test-err 465 3771 (interval-intersect a b)))


(define (my-interval-intersect . args)

  (define (fold-left operator           ;; called with (operator result-so-far (car list))
                     initial-value
                     list)
    (if (null? list)
        initial-value
        (fold-left operator
                   (operator initial-value (car list))
                   (cdr list))))


  (let ((new-uppers (let ((uppers (map interval-upper-bounds->vector args)))
                      (fold-left (lambda (arg result)
                                   (vector-map min arg result))
                                 (car uppers)
                                 uppers)))
        (new-lowers (let ((lowers (map interval-lower-bounds->vector args)))
                      (fold-left (lambda (arg result)
                                   (vector-map max arg result))
                                 (car lowers)
                                 lowers))))
    ;; (pp (list args new-lowers new-uppers (vector-every < new-lowers new-uppers)))
    (and (%%vector-every <= new-lowers new-uppers)
         (make-interval new-lowers new-uppers))))


(do ((i 0 (+ i 1)))
    ((= i random-tests))
  (let* ((dimension (random 1 6))
         (number-of-intervals (random 1 4))
         (intervals (map (lambda (x)
                           (random-interval dimension (+ dimension 1)))
                         (local-iota 0 number-of-intervals))))
    ;; (pp (list intervals (apply my-interval-intersect intervals)))
    (test 466 3810 (apply my-interval-intersect intervals) (apply interval-intersect intervals))))

(next-test-random-source-state!)

(pp "test interval-scale and array-sample")

(test-err 467 3817 (interval-scale 1 'a))

(test-err 468 3820 (interval-scale (make-interval '#(1) '#(2)) 'a))

(test-err 469 3823 (interval-scale (make-interval '#(0) '#(1))
                      'a))

(test-err 470 3827 (interval-scale (make-interval '#(0) '#(1))
                      '#(a)))

(test-err 471 3831 (interval-scale (make-interval '#(0) '#(1))
                      '#(0)))

(test-err 472 3835 (interval-scale (make-interval '#(0) '#(1))
                      '#(1.)))

(test-err 473 3839 (interval-scale (make-interval '#(0) '#(1))
                      '#(1 2)))

(define (myinterval-scale interval scales)
  (make-interval (interval-lower-bounds->vector interval)
                 (vector-map (lambda (u s)
                               (quotient (+ u s -1) s))
                             (interval-upper-bounds->vector interval)
                             scales)))

(do ((i 0 (fx+ i 1)))
    ((fx= i random-tests))
  (let* ((interval (random-nonnegative-interval))
         (scales   (random-positive-vector (interval-dimension interval))))
    (test 474 3854 (  interval-scale interval scales) (myinterval-scale interval scales))))

(next-test-random-source-state!)

(test-err 475 3859 (array-sample 'a 'a))

(test-err 476 3862 (array-sample (make-array (make-interval '#(1) '#(2)) list) 'a))

(test-err 477 3865 (array-sample (make-array (make-interval '#(0) '#(2)) list) 'a))

(test-err 478 3868 (array-sample (make-array (make-interval '#(0) '#(2)) list) '#(1.)))

(test-err 479 3871 (array-sample (make-array (make-interval '#(0) '#(2)) list) '#(0)))

(test-err 480 3874 (array-sample (make-array (make-interval '#(0) '#(2)) list) '#(2 1)))

(let* ((domain (make-interval '#(8)))
       (specialized (array-copy (make-array domain list)))
       (mutable (make-array domain list list))
       (immutable (make-array domain list)))
  (for-each (lambda (array)
              (let ((sampled (array-sample array '#(3))))
                (test-err 481 3883 (array-ref sampled 3))
                (if (mutable-array? sampled)
                    (test-err 482 3886 (array-set! sampled 1 3)))))
            (list specialized mutable immutable)))

(define (myarray-sample array scales)
  (let ((scales-list (vector->list scales)))
    (cond ((specialized-array? array)
           (specialized-array-share array
                                    (interval-scale (array-domain array) scales)
                                    (lambda multi-index
                                      (apply values (map * multi-index scales-list)))))
          ((mutable-array? array)
           (let ((getter (array-getter array))
                 (setter (array-setter array)))
             (make-array (interval-scale (array-domain array) scales)
                         (lambda multi-index
                           (apply getter (map * multi-index scales-list)))
                         (lambda (v . multi-index)
                           (apply setter v (map * multi-index scales-list))))))
          (else
           (let ((getter (array-getter array)))
             (make-array (interval-scale (array-domain array) scales)
                         (lambda multi-index
                           (apply getter (map * multi-index scales-list)))))))))



(do ((i 0 (+ i 1)))
    ((= i random-tests))
  (let* ((domain (random-nonnegative-interval 1 6))
         (Array (let ((temp (make-array domain list)))
                  (case (test-random-integer 3)
                    ((0) temp)
                    ((1) (array-copy temp))
                    ((2) (let ((temp (array-copy temp)))
                           (make-array (array-domain temp)
                                       (array-getter temp)
                                       (array-setter temp)))))))
         (scales (random-positive-vector (interval-dimension domain)))
         (sampled-array (array-sample Array scales))
         (my-sampled-array (myarray-sample Array scales)))

      (if (mutable-array? Array)
          (let ((scaled-domain (interval-scale domain scales)))
            (do ((j 0 (+ j 1)))
                ((= j 50))
              (call-with-values
                  (lambda ()
                    (random-multi-index scaled-domain))
                (lambda multi-index
                  (let ((value (test-random-integer 10000)))
                    (apply (array-setter sampled-array) value multi-index)
                    (apply (array-setter my-sampled-array) value multi-index)))))))
      (test 483 3939 (myarray= sampled-array
                      my-sampled-array) #t)))

(next-test-random-source-state!)

(pp "test array-extract and array-tile")

(test-err 484 3947 (array-extract (make-array (make-interval '#(0 0) '#(1 1)) list)
                     'a))

(test-err 485 3951 (array-extract 'a (make-interval '#(0 0) '#(1 1))))

(test-err 486 3954 (array-extract (make-array (make-interval '#(0 0) '#(1 1)) list)
                     (make-interval '#(0) '#(1))))

(test-err 487 3958 (array-extract (make-array (make-interval '#(0 0) '#(1 1)) list)
                     (make-interval '#(0 0) '#(1 3))))

(let* ((A (list->array (make-interval '#(10)) (iota 10)  generic-storage-class #f)) ;; not mutable
       (B (array-extract A (make-interval '#(0)))))   ;; used to tickle a bug
  (test 488 3964 (mutable-array? A) #f)
  (test 489 3966 (mutable-array? B) #f))

(let* ((specialized
        (make-specialized-array (make-interval '#(4 4))
                                generic-storage-class
                                #t     ;; mutable?
                                #t))
       (mutable
        (make-array (array-domain specialized)
                    (array-getter specialized)
                    (array-setter specialized)))
       (immutable
        (make-array (array-domain specialized)
                    (array-getter specialized))))
  (for-each (lambda (array)
              (let ((subarray
                     (array-extract array (make-interval '#(2 2)))))
                (test-err 490 3984 (array-ref subarray 2 2))
                (if (mutable-array? array)
                    (test-err 491 3987 (array-set! subarray 'a 2 2)))))
            (list specialized mutable immutable)))

(do ((i 0 (fx+ i 1)))
    ((fx= i random-tests))
  (let* ((domain (random-interval))
         (subdomain (random-subinterval domain))
         (spec-A (array-copy (make-array domain list)))
         (spec-A-extract (array-extract spec-A subdomain))
         (mut-A (let ((A-prime (array-copy spec-A)))
                  (make-array domain
                              (array-getter A-prime)
                              (array-setter A-prime))))
         (mut-A-extract (array-extract mut-A subdomain))
         (immutable-A (let ((A-prime (array-copy spec-A)))
                        (make-array domain
                                    (array-getter A-prime))))
         (immutable-A-extract (array-extract immutable-A subdomain))
         (spec-B (array-copy (make-array domain list)))
         (spec-B-extract (array-extract spec-B subdomain))
         (mut-B (let ((B-prime (array-copy spec-B)))
                  (make-array domain
                              (array-getter B-prime)
                              (array-setter B-prime))))
         (mut-B-extract (array-extract mut-B subdomain)))
    ;; test that the extracts are the same kind of arrays as the original
    (test 492 4014 (specialized-array? spec-A) #t)
    (test 493 4016 (specialized-array? spec-A-extract) #t)
    (test 494 4018 (and (mutable-array? mut-A)
               (not (specialized-array? mut-A))) #t)
    (test 495 4021 (and (mutable-array? mut-A-extract)
               (not (specialized-array? mut-A-extract))) #t)
    (test 496 4024 (and (array? immutable-A)
               (not (mutable-array? immutable-A))) #t)
    (test 497 4027 (and (array? immutable-A-extract)
               (not (mutable-array? immutable-A-extract))) #t)
    (test 498 4030 (array-domain spec-A-extract) subdomain)
    (test 499 4032 (array-domain mut-A-extract) subdomain)
    (test 500 4034 (array-domain immutable-A-extract) subdomain)
    ;; test that applying the original setter to arguments in
    ;; the subdomain gives the same answer as applying the
    ;; setter of the extracted array to the same arguments.
    (for-each (lambda (A B A-extract B-extract)
                (let ((A-setter (array-setter A))
                      (B-extract-setter (array-setter B-extract)))
                  (do ((i 0 (fx+ i 1)))
                      ((fx= i 100)
                       (test 501 4044 (myarray= spec-A spec-B) #t)
                       (test 502 4046 (myarray= spec-A-extract spec-B-extract) #t))
                    (if (not (interval-empty? subdomain))
                        (call-with-values
                            (lambda ()
                              (random-multi-index subdomain))
                          (lambda multi-index
                            (let ((val (test-random-real)))
                              (apply A-setter val multi-index)
                              (apply B-extract-setter val multi-index))))))))
              (list spec-A mut-A)
              (list spec-B mut-B)
              (list spec-A-extract mut-A-extract)
              (list spec-B-extract mut-B-extract))))

(next-test-random-source-state!)


(test-err 503 4064 (array-tile 'a '#(10)))
(test-err 504 4066 (array-tile (make-array (make-interval '#(0 0) '#(10 10)) list) 'a))
(test-err 505 4068 (array-tile (make-array (make-interval '#(0 0) '#(10 10)) list) '#(a a)))
(test-err 506 4070 (array-tile (make-array (make-interval '#(0 0) '#(10 10)) list) '#(-1 1)))
(test-err 507 4072 (array-tile (make-array (make-interval '#(0 0) '#(10 10)) list) '#(10)))
(test-err 508 4074 (array-tile (make-array (make-interval '#(4)) list) '#(#(0 3 0 -1 2))))
(test-err 509 4076 (array-tile (make-array (make-interval '#(4)) list) '#(#(0 3 0 0 2))))
(test-err 510 4078 (array-tile (make-array (make-interval '#(0)) list) '#(2)))

(do ((d 1 (fx+ d 1)))
     ((fx= d 6))
  (let* ((A (make-array (make-interval (make-vector d 100)) list))
         (B (array-tile A (make-vector d 10)))
         (index (make-list d 12)))
    (test-err 511 4086 (apply array-ref B (make-list d 12)))
    (test-err 512 4088 (apply array-ref B (make-list d 'a)))
    (if (< 4 d)
        (test-err 513 4091 (array-ref B 0 0 0 0)))))

(define (ceiling-quotient x d)
  ;; assumes x and d are positive
  (quotient (+ x d -1) d))

(define (my-array-tile array sidelengths)
  ;; an alternate definition more-or-less from the srfi document
  (let* ((domain
          (array-domain array))
         (lowers
          (%%interval-lower-bounds domain))
         (uppers
          (%%interval-upper-bounds domain))
         (result-lowers
          (vector-map (lambda (x)
                        0)
                      lowers))
         (result-uppers
          (vector-map (lambda (l u s)
                        (ceiling-quotient (- u l) s))
                      lowers uppers sidelengths)))
    (make-array (make-interval result-lowers result-uppers)
                (lambda i
                  (let* ((vec-i
                          (list->vector i))
                         (result-lowers
                          (vector-map (lambda (l i s)
                                        (+ l (* i s)))
                                      lowers vec-i sidelengths))
                         (result-uppers
                          (vector-map (lambda (l u i s)
                                        (min u (+ l (* (+ i 1) s))))
                                      lowers uppers vec-i sidelengths)))
                    (array-extract array
                                   (make-interval result-lowers result-uppers)))))))

;;; The array-block random tests also test array-tile.

(do ((i 0 (fx+ i 1)))
    ((fx= i random-tests))
  (let* ((domain
          (random-nonempty-interval))   ;; We use positive integers for the array-tile arguments here, so we need the domain to be nonempty.
         (array
          (let ((res (make-array domain list)))
            (case (test-random-integer 3)
              ;; immutable
              ((0) res)
              ;; specialized
              ((1) (array-copy res))
              (else
               ;; mutable, but not specialized
               (let ((res (array-copy res)))
                 (make-array domain (array-getter res) (array-setter res)))))))
         (lowers
          (%%interval-lower-bounds domain))
         (uppers
          (%%interval-upper-bounds domain))
         (sidelengths
          (vector-map (lambda (l u)
                        (let ((dim (- u l)))
                          (random 1 (ceiling-quotient (* dim 7) 5))))
                      lowers uppers))
         (result
          (array-tile array sidelengths))
         (test-result
          (my-array-tile array sidelengths)))

    ;; extract-array is tested independently, so we just make a few tests.

    ;; test all the subdomain tiles are the same
    (test 514 4163 (array-every (lambda (r t)
                         (equal? (array-domain r) (array-domain t)))
                       result test-result) #t)
    ;; test that the subarrays are the same type
    (test 515 4168 (array-every (lambda (r t)
                         (and
                          (eq? (mutable-array? r) (mutable-array? t))
                          (eq? (mutable-array? r) (mutable-array? array))
                          (eq? (specialized-array? r) (specialized-array? t))
                          (eq? (specialized-array? r) (specialized-array? array))))
                       result test-result) #t)
    ;; test that the first tile has the right values
    (test 516 4177 (myarray= (apply (array-getter result) (make-list (vector-length lowers) 0))
                    (apply (array-getter test-result) (make-list (vector-length lowers) 0))) #t)))

(next-test-random-source-state!)

(pp "array-reverse tests")

(test-err 517 4185 (array-reverse 'a))

(test-err 518 4188 (array-reverse 'a 'a))

(test-err 519 4191 (array-reverse (make-array (make-interval '#(0 0) '#(2 2)) list)
                     'a))

(test-err 520 4195 (array-reverse (make-array (make-interval '#(0 0) '#(2 2)) list)
                     '#(1 0)))

(test-err 521 4199 (array-reverse (make-array (make-interval '#(0 0) '#(2 2)) list)
                     '#(#t)))


(define (myarray-reverse array flip?)
  (let* ((flips (vector->list flip?))
         (domain (array-domain array))
         (lowers (interval-lower-bounds->list domain))
         (uppers (interval-upper-bounds->list domain))
         (transform
          (lambda (multi-index)
            (map (lambda (i_k l_k u_k f_k?)
                   (if f_k?
                       (- (+ u_k l_k -1) i_k)
                       i_k))
                 multi-index lowers uppers flips))))
    (cond ((specialized-array? array)
           (specialized-array-share array
                                    domain
                                    (lambda multi-index
                                      (apply values (transform multi-index)))))
          ((mutable-array? array)
           (let ((getter (array-getter array))
                 (setter (array-setter array)))
             (make-array domain
                         (lambda multi-index
                           (apply getter (transform multi-index)))
                         (lambda (v . multi-index)
                           (apply setter v (transform multi-index))))))
          (else
           (let ((getter (array-getter array)))
             (make-array domain
                         (lambda multi-index
                           (apply getter (transform multi-index)))))))))


(do ((i 0 (+ i 1)))
    ((= i random-tests))
  (let* ((domain (random-interval))
         (Array (let ((temp (make-array domain list)))
                  (case (test-random-integer 3)
                    ((0) temp)
                    ((1) (array-copy temp))
                    ((2) (let ((temp (array-copy temp)))
                           (make-array (array-domain temp)
                                       (array-getter temp)
                                       (array-setter temp)))))))
         (flips (vector-map (lambda (x) (random-boolean)) (make-vector (interval-dimension domain))))
         (reversed-array (array-reverse Array flips))
         (my-reversed-array (myarray-reverse Array flips)))

    (if (and (mutable-array? Array)
             (not (array-empty? Array)))
        (do ((j 0 (+ j 1)))
            ((= j 50))
          (call-with-values
              (lambda ()
                (random-multi-index domain))
            (lambda multi-index
              (let ((value (test-random-integer 10000)))
                (apply (array-setter reversed-array) value multi-index)
                (apply (array-setter my-reversed-array) value multi-index))))))
    (test 522 4262 (myarray= reversed-array
                    my-reversed-array) #t)))

(next-test-random-source-state!)

;; next test that the optional flip? argument is computed correctly.

(for-each (lambda (n)
            (let* ((upper-bounds (make-vector n 2))
                   (lower-bounds (make-vector n 0))
                   (domain (make-interval lower-bounds upper-bounds))
                   (A (array-copy (make-array domain list)))
                   (immutable-A
                    (let ((A (array-copy A))) ;; copy A
                      (make-array domain
                                  (array-getter A))))
                   (mutable-A
                    (let ((A (array-copy A))) ;; copy A
                      (make-array domain
                                  (array-getter A)
                                  (array-setter A))))
                   (flip? (make-vector n #t)))
              (let ((r1 (array-reverse A))
                    (r2 (array-reverse A flip?)))
                (if (not (and (specialized-array? r1)
                              (specialized-array? r2)
                              (myarray= r1 r2)))
                    (begin
                      (error "blah reverse specialized")
                      (pp 'crap))))
              (let ((r1 (array-reverse mutable-A))
                    (r2 (array-reverse mutable-A flip?)))
                (if (not (and (mutable-array? r1)
                              (mutable-array? r2)
                              (myarray= r1 r2)))
                    (begin
                      (error "blah reverse mutable")
                      (pp 'crap))))
              (let ((r1 (array-reverse immutable-A))
                    (r2 (array-reverse immutable-A flip?)))
                (if (not (and (array? r1)
                              (array? r2)
                              (myarray= r1 r2)))
                    (begin
                      (error "blah reverse immutable")
                      (pp 'crap))))))
          (iota 5 1))

(pp "array-assign! tests")

(test-err 523 4313 (array-assign! 'a 'a))

(test-err 524 4316 (array-assign! (make-array (make-interval '#(0 0) '#(1 1)) values) 'a))

(test-err 525 4319 (array-assign! (array-copy (make-array (make-interval '#(0 0) '#(1 1)) values)) 'a))

(test-err 526 4322 (array-assign! (array-copy (make-array (make-interval '#(0 0) '#(1 1)) values))
                     (make-array (make-interval '#(0 0) '#(2 1)) values)))

(test-err 527 4326 (array-assign! (make-array (make-interval '#(1 2)) list list) ;; not valid
                     (make-array (make-interval '#(0 0) '#(2 1)) values)))

(test-err 528 4330 (array-assign! (array-permute (array-copy (make-array (make-interval '#(2 3))
                                                           list))
                                    '#(1 0))
                     (make-array (make-interval '#(2 3)) list)))

(let ((destination (make-specialized-array (make-interval '#(3 2))))  ;; elements in order
      (source (array-permute (make-array (make-interval '#(3 2)) list) ;; not the same interval, but same volume
                             '#(1 0))))
  (test-err 529 4339 (array-assign! destination source)))



(do ((d 1 (fx+ d 1)))
    ((= d 6))
  (let* ((unsafe-specialized-destination
          (make-specialized-array (make-interval (make-vector d 10))
                                  u1-storage-class))
         (safe-specialized-destination
          (make-specialized-array (make-interval (make-vector d 10))
                                  u1-storage-class
                                  0
                                  #t))
         (mutable-destination
          (make-array (array-domain safe-specialized-destination)
                      (array-getter safe-specialized-destination)
                      (array-setter safe-specialized-destination)))
         (source
          (make-array (array-domain safe-specialized-destination)
                      (lambda args 100)))) ;; not 0 or 1
    (test-err 530 4361 (array-assign! unsafe-specialized-destination source))
    (test-err 531 4363 (array-assign! safe-specialized-destination source))
    (test-err 532 4365 (array-assign! mutable-destination source))))

(do ((i 0 (fx+ i 1)))
    ((fx= i random-tests))
  (let* ((interval
          (random-interval))
         (subinterval
          (random-subinterval interval))
         (storage-class-and-initializer
          (random-storage-class-and-initializer))
         (storage-class
          (car storage-class-and-initializer))
         (initializer
          (cadr storage-class-and-initializer))
         (specialized-array
          (array-copy
           (make-array interval initializer)
           storage-class))
         (mutable-array
          (let ((specialized-array
                 (array-copy
                  (make-array interval initializer)
                  storage-class)))
            (make-array interval
                        (array-getter specialized-array)
                        (array-setter specialized-array))))
         (specialized-subarray
          (array-extract specialized-array subinterval))
         (mutable-subarray
          (array-extract mutable-array subinterval))
         (new-subarray
          (array-copy
           (make-array subinterval initializer)
           storage-class)))
    ;; (pp specialized-array)
    (array-assign! specialized-subarray new-subarray)
    (array-assign! mutable-subarray new-subarray)
    (test 533 4403 (myarray= specialized-array
                    (make-array interval
                                (lambda multi-index
                                  (if (apply interval-contains-multi-index? subinterval multi-index)
                                      (apply (array-getter new-subarray) multi-index)
                                      (apply (array-getter specialized-array) multi-index))))) #t)
    (test 534 4410 (myarray= mutable-array
                    (make-array interval
                                (lambda multi-index
                                  (if (apply interval-contains-multi-index? subinterval multi-index)
                                      (apply (array-getter new-subarray) multi-index)
                                      (apply (array-getter mutable-array) multi-index))))) #t)))

(next-test-random-source-state!)

(pp "Miscellaneous error tests")

(test-err 535 4422 (make-array (make-interval '#(0 0) '#(10 10))
                  list
                  'a))

(test-err 536 4427 (array-dimension 'a))

(test 537 4430 (array-safe?
       (array-copy (make-array (make-interval '#(0 0) '#(10 10)) list)
                   generic-storage-class
                   #t
                   #t)) #t)


(test 538 4438 (array-safe?
       (array-copy (make-array (make-interval '#(0 0) '#(10 10)) list)
                   generic-storage-class
                   #t
                   #f)) #f)

(let ((array-builders (vector (list u1-storage-class      (lambda indices (random (expt 2 1))) '(a -1))
                              (list u8-storage-class      (lambda indices (random (expt 2 8))) '(a -1))
                              (list u16-storage-class     (lambda indices (random (expt 2 16))) '(a -1))
                              (list u32-storage-class     (lambda indices (random (expt 2 32))) '(a -1))
                              (list u64-storage-class     (lambda indices (random (expt 2 64))) '(a -1))
                              (list s8-storage-class      (lambda indices (random (- (expt 2 7))  (expt 2 7))) `(a ,(expt 2 8)))
                              (list s16-storage-class     (lambda indices (random (- (expt 2 15)) (expt 2 15))) `(a ,(expt 2 16)))
                              (list s32-storage-class     (lambda indices (random (- (expt 2 31)) (expt 2 31))) `(a ,(expt 2 32)))
                              (list s64-storage-class     (lambda indices (random (- (expt 2 63)) (expt 2 63))) `(a ,(expt 2 64)))
                              (list f16-storage-class     (lambda indices (test-random-real)) `(a 1))
                              (list f32-storage-class     (lambda indices (test-random-real)) `(a 1))
                              (list f64-storage-class     (lambda indices (test-random-real)) `(a 1))
                              (list char-storage-class    (lambda indices (random-char)) `(a 1))
                              (list c64-storage-class     (lambda indices (make-rectangular (test-random-real) (test-random-real))) `(a 1))
                              (list c128-storage-class    (lambda indices (make-rectangular (test-random-real) (test-random-real))) `(a 1))
                              )))
  (do ((i 0 (+ i 1)))
      ((= i random-tests))
    (let* ((domain (random-nonempty-interval))  ;; we're testing invalid arguments, so no zero-dimensional arrays
           (builders (vector-ref array-builders (test-random-integer (vector-length array-builders))))
           (storage-class (car builders))
           (random-entry (cadr builders))
           (invalid-entry (list-ref (caddr builders) (random 2)))
           (Array (array-copy (make-array domain random-entry)
                              storage-class
                              #t   ; mutable
                              #t)) ; safe
           (getter (array-getter Array))
           (setter (array-setter Array))
           (dimension (interval-dimension domain))
           (valid-args (call-with-values
                           (lambda ()
                             (random-multi-index domain))
                         list)))
      (test-err 539 4479 (apply setter invalid-entry valid-args))
      (if (positive? dimension)
          (begin
            (set-car! valid-args 'a)
            (test-err 540 4484 (apply getter valid-args))
            (test-err 541 4486 (apply setter 10 valid-args))
            (set-car! valid-args 10000) ;; outside the range of any random-interval
            (test-err 542 4489 (apply getter valid-args))
            (test-err 543 4491 (apply setter 10 valid-args))))
      (if (< 4 dimension)
          (begin
            (set! valid-args (cons 1 valid-args))
            (test-err 544 4496 (apply getter valid-args))
            (test-err 545 4498 (apply setter 10 valid-args)))))))

(next-test-random-source-state!)

(pp "array->list, array->vector and list->array, vector->array")

(test-err 546 4505 (array->list 'a))

(test-err 547 4508 (array->vector 'a))

(let* ((multi-indices
        '())
       (a
        (make-array (make-interval '#(3 5))
                    (lambda (i j)
                      (set! multi-indices (cons (list i j) multi-indices))
                      (+ j (* i 5)))))
       (result
        (array->list a))
       (correct-multi-indices
        (let ((result '()))
          (interval-for-each (lambda (i j)
                               (set! result (cons (list i j) result)))
                             (array-domain a))
          result)))
  (test 548 4526 result (iota 15))
  (test 549 4527 multi-indices correct-multi-indices))

(for-each (lambda (function arg name name2)
            (test 550 4530 (function 'b arg) (string-append name "The first argument is not an interval: "))
            (test 551 4532 (function (make-interval '#(0) '#(1)) 'b) (string-append name "The second argument is not a " name2 ": "))
            (test 552 4534 (function (make-interval '#(0) '#(1)) arg 'a) (string-append name "The third argument is not a storage-class: "))
            (test 553 4536 (function (make-interval '#(0) '#(1)) arg generic-storage-class 'a) (string-append name "The fourth argument is not a boolean: "))
            (test 554 4538 (function (make-interval '#(0) '#(1)) arg generic-storage-class #t 'a) (string-append name "The fifth argument is not a boolean: "))
            (test 555 4540 (function (make-interval '#(0) '#(10)) arg) (string-append name "The volume of the first argument does not equal the length of the second: "))
            (test 556 4542 (function (make-interval '#(0) '#(1)) arg u1-storage-class) (string-append name "Not all elements of the source can be manipulated by the storage class: "))
            (test 557 4544 (function (make-interval '#(10)) arg) (string-append name "The volume of the first argument does not equal the length of the second: ")))
          (list list->array vector->array)
          '((10) #(10))
          '("list->array: " "vector->array: ")
          '("list" "vector"))


(let ((array-builders (vector (list u1-storage-class      (lambda indices (random 0 (expt 2 1))))
                              (list u8-storage-class      (lambda indices (random 0 (expt 2 8))))
                              (list u16-storage-class     (lambda indices (random 0 (expt 2 16))))
                              (list u32-storage-class     (lambda indices (random 0 (expt 2 32))))
                              (list u64-storage-class     (lambda indices (random 0 (expt 2 64))))
                              (list s8-storage-class      (lambda indices (random (- (expt 2 7))  (expt 2 7))))
                              (list s16-storage-class     (lambda indices (random (- (expt 2 15)) (expt 2 15))))
                              (list s32-storage-class     (lambda indices (random (- (expt 2 31)) (expt 2 31))))
                              (list s64-storage-class     (lambda indices (random (- (expt 2 63)) (expt 2 63))))
                              (list f16-storage-class     (lambda indices (test-random-real)))
                              (list f32-storage-class     (lambda indices (test-random-real)))
                              (list f64-storage-class     (lambda indices (test-random-real)))
                              (list char-storage-class    (lambda indices (random-char)))
                              (list c64-storage-class     (lambda indices (make-rectangular (test-random-real) (test-random-real))))
                              (list c128-storage-class    (lambda indices (make-rectangular (test-random-real) (test-random-real))))
                              (list generic-storage-class (lambda indices indices)))))
  (do ((i 0 (+ i 1)))
      ((= i random-tests))
    (let* ((domain (random-interval))
           (builders (vector-ref array-builders (test-random-integer (vector-length array-builders))))
           (storage-class (car builders))
           (random-entry (cadr builders))
           (Array (array-copy (make-array domain random-entry)
                              storage-class
                              #f
                              #t)) ; safe
           (l (array->list Array))
           (mutable? (zero? (test-random-integer 2)))
           (new-list-array (list->array domain l storage-class mutable?))
           (new-vector-array (vector->array domain (list->vector l) storage-class mutable?)))
      (test 558 4582 (myarray= Array new-list-array) #t)
      (test 559 4584 (myarray= Array new-vector-array) #t))))

(next-test-random-source-state!)

(pp "interval-cartesian-product and array-outer-product")

(define (my-interval-cartesian-product . args)
  (make-interval (list->vector (apply append (map interval-lower-bounds->list args)))
                 (list->vector (apply append (map interval-upper-bounds->list args)))))

(test-err 560 4595 (interval-cartesian-product 'a))

(test-err 561 4598 (interval-cartesian-product (make-interval '#(0) '#(1)) 'a))

(do ((i 0 (+ i 1)))
    ((= i random-tests))
  (let* ((intervals
          (map (lambda (ignore)
                 (random-interval 1 4))
               (make-list (random 4)))))
    (test 562 4607 (apply interval-cartesian-product intervals) (apply my-interval-cartesian-product intervals))))

(next-test-random-source-state!)

(let ((test-array (make-array  (make-interval '#(0) '#(1)) list)))

  (test-err 563 4614 (array-outer-product 'a test-array test-array))

  (test-err 564 4617 (array-outer-product append 'a test-array))

  (test-err 565 4620 (array-outer-product append test-array 'a)))

(let* ((A (make-array (make-interval '#(0 10)) list))
       (B (make-array (make-interval '#(10 0)) list))
       (A*B (array-outer-product cons A B)))
  (test-err 566 4626 ((array-getter A*B) 0 0 0 0)))

(let* ((domain (make-interval '#(4)))
       (specialized (array-copy (make-array domain list)))
       (immutable (make-array domain list))
       (arrays (list specialized immutable)))
  (for-each (lambda (A)
              (for-each (lambda (B)
                          (let ((array (array-outer-product append A B)))
                            (test-err 567 4636 (array-ref array 10 3))
                            (test-err 568 4638 (array-ref array 1 1 1 1))))
                        arrays))
            arrays))

(do ((i 0 (+ i 1)))
    ((= i random-tests))
  (let* ((arrays
          (map (lambda (ignore)
                 (make-array (random-interval 0 6) list))
               (make-list 2))))
    (myarray= (apply array-outer-product append arrays)
                    (make-array (apply my-interval-cartesian-product (map array-domain arrays))
                                list))
    (test 569 4652 (myarray= (apply array-outer-product append arrays)
                    (make-array (apply my-interval-cartesian-product (map array-domain arrays))
                                list)) #t)))

(next-test-random-source-state!)


(pp "array-ref and array-set! tests")

(specialized-array-default-safe? #t)

(define A-ref
  (array-copy
   (make-array (make-interval '#(10 10))
               (lambda (i j) (if (= i j) 1 0)))))

(do ((i 1 (+ i 1)))
    ((= i 6))
  (test-err 570 4671 (apply array-ref 1 (make-list i 0))))

(test-err 571 4674 (array-ref A-ref 1))

(test-err 572 4677 (array-ref A-ref 1 1001))

(test 573 4680 (array-ref A-ref 4 4) 1)

(test 574 4683 (array-ref A-ref 4 5) 0)

(let ((A (array-copy (make-array (make-interval '#(1 1 1 1 1 1)) list)))
      (B (array-copy (make-array (make-interval '#(-1 -1 -1 -1 -1 -1)
                                                '#( 1  1  1  1  1  1))
                                 list))))
  ;; We copied A and B so they would have the default error checking.
  (test-err 575 4691 (array-ref A 0))
  (test-err 576 4693 (array-ref B 0))
  (test-err 577 4695 (array-ref A 0 0 0 0 0 0 0))
  (test-err 578 4697 (array-ref B 0 0 0 0 0 0 0))
  (test-err 579 4699 (array-set! A 0 0))
  (test-err 580 4701 (array-set! B 0 0))
  (test-err 581 4703 (array-set! A 0 0 0 0 0 0 0 0))
  (test-err 582 4705 (array-set! B 0 0 0 0 0 0 0 0)))


(do ((d 0 (+ d 1)))
    ((= d 6))
  (let ((A (make-specialized-array (make-interval (make-vector d 1)) generic-storage-class 42)))
    (test 583 4712 (apply array-ref A (make-list d 0)) 42)
    (test 584 4714 (apply array-ref 2 (make-list d 0)) (if (zero? d)
              "array-ref: The argument is not an array: "
              "array-ref: The first argument is not an array: "))))

(test-err 585 4719 (array-ref (make-specialized-array (make-interval '#(0 0)) generic-storage-class 42) 0 0))

(test-err 586 4722 (array-set! (make-specialized-array (make-interval '#(0 0)) generic-storage-class 42) 42 0 0))

(define B-set!
  (array-copy
   (make-array (make-interval '#(10 10))
               (lambda (i j) (if (= i j) 1 0)))
   u1-storage-class))

(test-err 587 4731 (array-set! 1 1 1))

(test-err 588 4734 (array-set! B-set!))

(test-err 589 4737 (array-set! B-set! 2))

(test-err 590 4740 (array-set! B-set! 2 1))

(test-err 591 4743 (array-set! B-set! 2 1 1))

(array-set! B-set! 1 1 2)
(array-set! B-set! 0 2 2)
(array-display B-set!)

(do ((d 0 (+ d 1)))
    ((= d 6))
  (let ((A (make-specialized-array (make-interval (make-vector d 1)) generic-storage-class 10)))
    (apply array-set! A 42 (make-list d 0))
    (test 592 4754 (apply array-ref A (make-list d 0)) 42)
    (test-err 593 4756 (apply array-set! 2 42 (make-list d 0)))))

(specialized-array-default-safe? #f)

(define A-ref
  (array-copy
   (make-array (make-interval '#(10 10))
               (lambda (i j) (if (= i j) 1 0)))))

(do ((i 1 (+ i 1)))
    ((= i 6))
  (test-err 594 4768 (apply array-ref 1 (make-list i 0))))

(test-err 595 4771 (array-ref A-ref 1))

#|
   For unsafe arrays, this error will not be caught, and could crash the program.
|#
#;
(test (array-ref A-ref 1 1001)
      "array-getter: domain does not contain multi-index: ")

(test 596 4781 (array-ref A-ref 4 4) 1)

(test 597 4784 (array-ref A-ref 4 5) 0)

(do ((d 0 (+ d 1)))
    ((= d 6))
  (let ((A (make-specialized-array (make-interval (make-vector d 1)) generic-storage-class 42)))
    (test 598 4790 (apply array-ref A (make-list d 0)) 42)
    (test 599 4792 (apply array-ref 2 (make-list d 0)) (if (zero? d)
              "array-ref: The argument is not an array: "
              "array-ref: The first argument is not an array: "))))

(test-err 600 4797 (array-ref (make-specialized-array (make-interval '#(0 0)) generic-storage-class 42) 0 0))

(test-err 601 4800 (array-set! (make-specialized-array (make-interval '#(0 0)) generic-storage-class 42) 42 0 0))

(define B-set!
  (array-copy
   (make-array (make-interval '#(10 10))
               (lambda (i j) (if (= i j) 1 0)))
   u1-storage-class))

(test-err 602 4809 (array-set! 1 1 1))

(test-err 603 4812 (array-set! B-set!))

(test-err 604 4815 (array-set! B-set! 2))

(test-err 605 4818 (array-set! B-set! 2 1))

#|
   For unsafe arrays, this error will not be caught, and could crash the program.
|#
#;
(test (array-set! B-set! 2 1 1)
      "array-setter: value cannot be stored in body: ")

(array-set! B-set! 1 1 2)
(array-set! B-set! 0 2 2)
(array-display B-set!)

(do ((d 0 (+ d 1)))
    ((= d 6))
  (let ((A (make-specialized-array (make-interval (make-vector d 1)) generic-storage-class 10)))
    (apply array-set! A 42 (make-list d 0))
    (test 606 4836 (apply array-ref A (make-list d 0)) 42)
    (test-err 607 4838 (apply array-set! 2 42 (make-list d 0)))))




(pp "specialized-array-reshape tests")

(test-err 608 4846 (specialized-array-reshape 'a 1))

(test-err 609 4849 (specialized-array-reshape A-ref 'a))

(test-err 610 4852 (specialized-array-reshape A-ref (make-interval '#(5))))

(test-err 611 4855 (specialized-array-reshape A-ref (make-interval '#(100)) 'a))

(let ((array (array-copy (make-array (make-interval '#(2 1 3 1)) list))))
  (test 612 4859 (array->list array) (array->list (specialized-array-reshape array (make-interval '#(6))))))

(let ((array (array-copy (make-array (make-interval '#(2 1 3 1)) list))))
  (test 613 4863 (array->list array) (array->list (specialized-array-reshape array (make-interval '#(3 2))))))

(let ((array (array-reverse (array-copy (make-array (make-interval '#(2 1 3 1)) list)))))
  (test 614 4867 (array->list array) (array->list (specialized-array-reshape array (make-interval '#(6))))))

(let ((array (array-reverse (array-copy (make-array (make-interval '#(2 1 3 1)) list)))))
  (test 615 4871 (array->list (specialized-array-reshape array (make-interval '#(3 2)))) (array->list array)))

(let ((array (array-reverse (array-copy (make-array (make-interval '#(2 1 3 1)) list)) '#(#f #f #f #t))))
  (test 616 4875 (array->list (specialized-array-reshape array (make-interval '#(3 2)))) (array->list array)))

(let ((array (array-reverse (array-copy (make-array (make-interval '#(2 1 3 1)) list)) '#(#f #f #f #t))))
  (test 617 4879 (array->list (specialized-array-reshape array (make-interval '#(3 1 2)))) (array->list array)))

(let ((array (array-reverse (array-copy (make-array (make-interval '#(2 1 3 1)) list)) '#(#f #f #f #t))))
  (test 618 4883 (array->list (specialized-array-reshape array (make-interval '#(1 1 1 3 2)))) (array->list array)))

(let ((array (array-reverse (array-copy (make-array (make-interval '#(2 1 3 1)) list)) '#(#f #f #f #t))))
  (test 619 4887 (array->list (specialized-array-reshape array (make-interval '#(3 2 1 1 1)))) (array->list array)))

(let ((array (array-reverse (array-copy (make-array (make-interval '#(2 1 3 1)) list)) '#(#f #f #f #t))))
  (test 620 4891 (array->list (specialized-array-reshape array (make-interval '#(3 1 1 2)))) (array->list array)))

(let ((array (array-reverse (array-copy (make-array (make-interval '#(2 1 3 1)) list)) '#(#f #f #f #t))))
  (test 621 4895 (array->list (specialized-array-reshape array (make-interval '#(3 1 2 1)))) (array->list array)))

(let ((array (array-sample (array-reverse (array-copy (make-array (make-interval '#(2 1 4 1)) list)) '#(#f #f #f #t)) '#(1 1 2 1))))
  (test 622 4899 (array->list (specialized-array-reshape array (make-interval '#(4)))) (array->list array)))

(let ((array (array-sample (array-reverse (array-copy (make-array (make-interval '#(2 1 4 1)) list)) '#(#t #f #t #t)) '#(1 1 2 1))))
  (test 623 4903 (array->list (specialized-array-reshape array (make-interval '#(4)))) (array->list array)))

(test-err 624 4906 (specialized-array-reshape (array-reverse (array-copy (make-array (make-interval '#(2 1 3 1)) list)) '#(#t #f #f #f)) (make-interval '#(6))))

(test-err 625 4909 (specialized-array-reshape (array-reverse (array-copy (make-array (make-interval '#(2 1 3 1)) list)) '#(#t #f #f #f)) (make-interval '#(3 2))))

(test-err 626 4912 (specialized-array-reshape (array-reverse (array-copy (make-array (make-interval '#(2 1 3 1)) list)) '#(#f #f #t #f)) (make-interval '#(6))))

(test-err 627 4915 (specialized-array-reshape (array-reverse (array-copy (make-array (make-interval '#(2 1 3 1)) list)) '#(#f #f #t #t)) (make-interval '#(3 2))))

(test-err 628 4918 (specialized-array-reshape (array-sample (array-reverse (array-copy (make-array (make-interval '#(2 1 3 1)) list)) '#(#f #f #f #t)) '#(1 1 2 1)) (make-interval '#(4))))

(test-err 629 4921 (specialized-array-reshape (array-sample (array-reverse (array-copy (make-array (make-interval '#(2 1 4 1)) list)) '#(#f #f #t #t)) '#(1 1 2 1)) (make-interval '#(4))))

(test 630 4924 (array? (specialized-array-reshape (make-specialized-array (make-interval '#(1 2 0 4)))
                                         (make-interval '#(2 0 4)))) #t)

(pp "Test code from the SRFI document")

(test 631 4930 (interval= (interval-dilate (make-interval '#(100 100)) '#(1 1) '#(1 1))
                 (make-interval '#(1 1) '#(101 101))) #t)

(test 632 4934 (interval= (interval-dilate (make-interval '#(100 100)) '#(-1 -1) '#(1 1))
                 (make-interval '#(-1 -1) '#(101 101))) #t)

(test 633 4938 (interval= (interval-dilate (make-interval '#(100 100))  '#(0 0) '#(-50 -50))
                 (make-interval '#(50 50))) #t)

(test-err 634 4942 (interval-dilate (make-interval '#(100 100)) '#(0 0) '#(-500 -50)))

(define a (make-array (make-interval '#(1 1) '#(11 11))
                      (lambda (i j)
                        (if (= i j)
                            1
                            0))))

(test 635 4951 ((array-getter a) 3 3) 1)

(test 636 4954 ((array-getter a) 2 3) 0)

;; ((array-getter a) 11 0) is an error, but it isn't signalled

(define a (make-array (make-interval '#(0 0) '#(10 10))
                      list))

(test 637 4962 ((array-getter a) 3 4) '(3 4))

(define curried-a (array-curry a 1))

(test 638 4967 ((array-getter ((array-getter curried-a) 3)) 4) '(3 4))

(define sparse-array
  (let ((domain (make-interval '#(1000000 1000000)))
        (sparse-rows (make-vector 1000000 '())))
    (make-array domain
                (lambda (i j)
                  (cond ((assv j (vector-ref sparse-rows i))
                         => cdr)
                        (else
                         0.0)))
                (lambda (v i j)
                  (cond ((assv j (vector-ref sparse-rows i))
                         => (lambda (pair)
                              (set-cdr! pair v)))
                        (else
                         (vector-set! sparse-rows i (cons (cons j v) (vector-ref sparse-rows i)))))))))

(test 639 4986 ((array-getter sparse-array) 12345 6789) 0.)

(test 640 4989 ((array-getter sparse-array) 0 0) 0.)

((array-setter sparse-array) 1.0 0 0)

(test 641 4994 ((array-getter sparse-array) 12345 6789) 0.)

(test 642 4997 ((array-getter sparse-array) 0 0) 1.)

(let ()
  (define a
    (array-copy
     (make-array (make-interval '#(5 10))
                 list)))
  (define b
    (specialized-array-share
     a
     (make-interval '#(5 5))
     (lambda (i j)
       (values i (+ i j)))))
  ;; Print the \"rows\" of b
  (array-for-each (lambda (row)
                    (pretty-print (array->list row)))
                  (array-curry b 1))

  ;; which prints
  ;; ((0 0) (0 1) (0 2) (0 3) (0 4))
  ;; ((1 1) (1 2) (1 3) (1 4) (1 5))
  ;; ((2 2) (2 3) (2 4) (2 5) (2 6))
  ;; ((3 3) (3 4) (3 5) (3 6) (3 7))
  ;; ((4 4) (4 5) (4 6) (4 7) (4 8))
  )

(define (palindrome? s)
  (let* ((n
          (string-length s))
         (a
          ;; an array accessing the characters of s
          (make-array (make-interval (vector n))
                      (lambda (i)
                        (string-ref s i))))
         (ra
          ;; the characters accessed in reverse order
          (array-reverse a))
         (half-domain
          (make-interval (vector (quotient n 2)))))
    ;; If n is 0 or 1 the following extracted arrays
    ;; are empty.
    (array-every
     char=?
     ;; the first half of s
     (array-extract a half-domain)
     ;; the reversed second half of s
     (array-extract ra half-domain))))

(for-each (lambda (s)
            (for-each display
                      (list "(palindrome? \""
                            s
                            "\") => "
                            (palindrome? s)
                            #\newline)))
          '("" "a" "aa" "ab" "aba" "abc" "abba" "abca" "abbc"))

(let ((a (make-array (make-interval '#(10)) (lambda (i) i))))
  (test 643 5056 (array-fold-left cons '() a) '((((((((((() . 0) . 1) . 2) . 3) . 4) . 5) . 6) . 7) . 8) . 9))
  (test 644 5058 (array-fold-right cons '() a) '(0 1 2 3 4 5 6 7 8 9))
  (test 645 5060 (array-fold-left - 0 a) -45)
  (test 646 5062 (array-fold-right - 0 a) -5))


(define make-pgm   cons)
(define pgm-greys  car)
(define pgm-pixels cdr)

(define (read-pgm file)
  ;; kaappi adaptation: binary-port PGM reader (P5 binary and P2 ascii).
  (define bytes
    (let ((p (open-binary-input-file file)))
      (let loop ((acc '()))
        (let ((b (read-u8 p)))
          (if (eof-object? b)
              (begin (close-port p) (list->vector (reverse acc)))
              (loop (cons b acc)))))))
  (define n (vector-length bytes))
  (define (vref i) (vector-ref bytes i))
  (define (ws? c) (or (= c 32) (= c 9) (= c 10) (= c 13)))
  (define (skip-ws i)
    (let loop ((i i))
      (if (>= i n)
          i
          (let ((c (vref i)))
            (cond ((ws? c) (loop (+ i 1)))
                  ((= c 35)
                   (let sk ((i i))
                     (if (or (>= i n) (= (vref i) 10))
                         (loop (if (< i n) (+ i 1) i))
                         (sk (+ i 1)))))
                  (else i))))))
  (define (read-token i)
    (let loop ((j i) (acc '()))
      (if (or (>= j n) (ws? (vref j)))
          (cons (list->string (map integer->char (reverse acc))) j)
          (loop (+ j 1) (cons (vref j) acc)))))
  (define (token-number i)
    (let ((tok (read-token i)))
      (cons (string->number (car tok)) (cdr tok))))
  (let* ((h (skip-ws 0))
         (hdr (car (read-token h)))
         (c1 (token-number (skip-ws (cdr (read-token h)))))
         (columns (car c1))
         (r1 (token-number (skip-ws (cdr c1))))
         (rows (car r1))
         (g1 (token-number (skip-ws (cdr r1))))
         (greys (car g1))
         (data-start (+ (cdr g1) 1))
         (header (string->symbol hdr)))
    (make-pgm greys
              (array-copy
               (make-array (make-interval (vector rows columns))
                           (cond ((or (eq? header 'p5)
                                      (eq? header 'P5))
                                  (if (< greys 256)
                                      (let ((k 0))
                                        (lambda (i j)
                                          (set! k (+ k 1))
                                          (vref (- (+ data-start k) 1))))
                                      (let ((k 0))
                                        (lambda (i j)
                                          (set! k (+ k 2))
                                          (+ (* (vref (- (+ data-start k) 1)) 256)
                                             (vref (- (+ data-start k) 2)))))))
                                 ((or (eq? header 'p2)
                                      (eq? header 'P2))
                                  (let* ((nums
                                          (let loop ((i (skip-ws data-start)) (acc '()))
                                            (if (>= i n)
                                                (reverse acc)
                                                (let ((t (token-number i)))
                                                  (loop (skip-ws (cdr t)) (cons (car t) acc))))))
                                         (vec (list->vector nums))
                                         (k 0))
                                    (lambda (i j)
                                      (set! k (+ k 1))
                                      (vector-ref vec (- k 1)))))
                                 (else
                                  (error "read-pgm: not a pgm file"))))))))

(define (write-pgm pgm-data file . opts)
  (let ((force-ascii (and (pair? opts) (car opts))))
    (let* ((greys (pgm-greys pgm-data))
           (pgm-array (pgm-pixels pgm-data))
           (domain (array-domain pgm-array))
           (rows (- (interval-upper-bound domain 0)
                    (interval-lower-bound domain 0)))
           (columns (- (interval-upper-bound domain 1)
                       (interval-lower-bound domain 1))))
      (let ((port (open-binary-output-file file)))
        (define (wstr s)
          (for-each (lambda (c) (write-u8 (char->integer c) port))
                    (string->list s)))
        (wstr (if force-ascii "P2" "P5"))
        (write-u8 10 port)
        (wstr (number->string columns)) (write-u8 32 port)
        (wstr (number->string rows)) (write-u8 10 port)
        (wstr (number->string greys)) (write-u8 10 port)
        (array-for-each (if force-ascii
                            (let ((next-pixel-in-line 1))
                              (lambda (p)
                                (wstr (number->string p))
                                (if (fxzero? (fxand next-pixel-in-line 15))
                                    (begin
                                      (write-u8 10 port)
                                      (set! next-pixel-in-line 1))
                                    (begin
                                      (write-u8 32 port)
                                      (set! next-pixel-in-line (fx+ 1 next-pixel-in-line))))))
                            (if (fx< greys 256)
                                (lambda (p) (write-u8 p port))
                                (lambda (p)
                                  (write-u8 (fxand p 255) port)
                                  (write-u8 (fxarithmetic-shift-right p 8) port))))
                        pgm-array)
        (close-port port)))))

;;; --- kaappi vendoring: fixture and output paths ---------------------
;;; Inputs resolve relative to THIS file (command-line carries the script
;;; path), with a repo-root spelling as fallback; convolution-timing
;;; outputs go under TMPDIR, never the source tree or the runner cwd.
(define (official-fixture-path name)
  (let ((dir (let ((cl (command-line)))
               (if (null? cl) ""
                   (let ((p (car cl)))
                     (let loop ((i (- (string-length p) 1)))
                       (if (or (< i 0) (char=? (string-ref p i) #\/))
                           (substring p 0 (+ i 1))
                           (loop (- i 1)))))))))
    (let ((cands (list (string-append dir "srfi231-official-fixtures/" name)
                       (string-append "tests/scheme/srfi/srfi231-official-fixtures/" name)
                       name)))
      (let loop ((cs cands))
        (cond ((null? cs) (error "srfi231-official: fixture not found" name))
              ((file-exists? (car cs)) (car cs))
              (else (loop (cdr cs))))))))
(define (official-output-path name)
  (let ((tmp (get-environment-variable "TMPDIR")))
    (string-append (if (and tmp (> (string-length tmp) 0)) tmp "/tmp")
                   "/srfi231-official-" name)))
(define test-pgm (read-pgm (official-fixture-path "girl.pgm")))

(define (array-convolve source filter)
  (let* ((source-domain
          (array-domain source))
         (S_
          (array-getter source))
         (filter-domain
          (array-domain filter))
         (F_
          (array-getter filter))
         (result-domain
          (interval-dilate
           source-domain
           ;; left bound of an interval is an equality,
           ;; right bound is an inequality, hence the
           ;; the difference in the following two expressions
           (vector-map -
                       (interval-lower-bounds->vector filter-domain))
           (vector-map (lambda (x)
                         (- 1 x))
                       (interval-upper-bounds->vector filter-domain)))))
    (make-array result-domain
                #|
                This was my first attempt at convolve, but the problem is that
                it creates two specialized arrays per pixel, which is a lot of
                overhead (computing an indexer and a setter, for example) for
                not very much computation.
                (lambda (i j)
                  (array-dot-product
                   (array-extract
                    (array-translate source (vector (- i) (- j)))
                    filter-domain)
                   filter))
where

(define (array-dot-product a b)
  (array-fold-left (lambda (x y)
                 (+ x y))
               0
               (array-map
                (lambda (x y)
                  (* x y))
                a b)))

                The times are
(time (let ((greys (pgm-greys test-pgm))) (write-pgm (make-pgm greys (array-map (lambda (p) (round-and-clip p greys)) (array-convolve (pgm-pixels test-pgm) sharpen-filter))) (official-output-path "sharper-test.pgm"))))
    0.514201 secs real time
    0.514190 secs cpu time (0.514190 user, 0.000000 system)
    64 collections accounting for 0.144107 secs real time (0.144103 user, 0.000000 system)
    663257736 bytes allocated
    676 minor faults
    no major faults
(time (let* ((greys (pgm-greys test-pgm)) (edge-array (array-copy (array-map abs (array-convolve (pgm-pixels test-pgm) edge-filter)))) (max-pixel (array-fold max 0 edge-array)) (normalizer (/ greys max-pixel))) (write-pgm (make-pgm greys (array-map (lambda (p) (- greys (round-and-clip (* p normalizer) greys))) edge-array)) (official-output-path "edge-test.pgm"))))
    0.571130 secs real time
    0.571136 secs cpu time (0.571136 user, 0.000000 system)
    57 collections accounting for 0.154109 secs real time (0.154093 user, 0.000000 system)
    695631496 bytes allocated
    959 minor faults
    no major faults


In the following, where we just package up a little array for each result pixel
that computes the componentwise products when we need them, the times are

(time (let ((greys (pgm-greys test-pgm))) (write-pgm (make-pgm greys (array-map (lambda (p) (round-and-clip p greys)) (array-convolve (pgm-pixels test-pgm) sharpen-filter))) (official-output-path "sharper-test.pgm"))))
    0.095921 secs real time
    0.095922 secs cpu time (0.091824 user, 0.004098 system)
    6 collections accounting for 0.014276 secs real time (0.014275 user, 0.000000 system)
    62189720 bytes allocated
    678 minor faults
    no major faults
(time (let* ((greys (pgm-greys test-pgm)) (edge-array (array-copy (array-map abs (array-convolve (pgm-pixels test-pgm) edge-filter)))) (max-pixel (array-fold max 0 edge-array)) (normalizer (inexact (/ greys max-pixel)))) (write-pgm (make-pgm greys (array-map (lambda (p) (- greys (round-and-clip (* p normalizer) greys))) edge-array)) (official-output-path "edge-test.pgm"))))
    0.165065 secs real time
    0.165066 secs cpu time (0.165061 user, 0.000005 system)
    13 collections accounting for 0.033885 secs real time (0.033878 user, 0.000000 system)
    154477720 bytes allocated
    966 minor faults
    no major faults
            |#
                (lambda (i j)
                  (array-fold-left
                   (lambda (p q)
                     (+ p q))
                   0
                   (make-array
                    filter-domain
                    (lambda (k l)
                      (* (S_ (+ i k)
                             (+ j l))
                         (F_ k l)))))))))

(define sharpen-filter
  (list->array
   (make-interval '#(-1 -1) '#(2 2))
   '(0 -1  0
    -1  5 -1
     0 -1  0)))

(define edge-filter
  (list->array
   (make-interval '#(-1 -1) '#(2 2))
   '(0 -1  0
    -1  4 -1
     0 -1  0)))

(define (round-and-clip pixel max-grey)
  (max 0 (min (exact (round pixel)) max-grey)))

(begin (let ((greys (pgm-greys test-pgm)))
   (write-pgm
    (make-pgm
     greys
     (array-map (lambda (p)
                  (round-and-clip p greys))
                (array-convolve
                 (pgm-pixels test-pgm)
                 sharpen-filter)))
    (official-output-path "sharper-test.pgm"))))

(begin (let* ((greys (pgm-greys test-pgm))
        (edge-array
         (array-copy
          (array-map
           abs
           (array-convolve
            (pgm-pixels test-pgm)
            edge-filter))))
        (max-pixel
         (array-fold-left max 0 edge-array))
        (normalizer
         (inexact (/ greys max-pixel))))
   (write-pgm
    (make-pgm
     greys
     (array-map (lambda (p)
                  (- greys
                     (round-and-clip (* p normalizer) greys)))
                edge-array))
    (official-output-path "edge-test.pgm"))))


(define m (array-copy (make-array (make-interval '#(0 0) '#(40 30)) (lambda (i j) (exact->inexact (+ i j))))))

(define (array-sum a)
  (array-fold-left + 0 a))
(define (array-max a)
  (array-fold-left max -inf.0 a))

(define (max-norm a)
  (array-max (array-map abs a)))
(define (one-norm a)
  (array-sum (array-map abs a)))

(define (operator-max-norm a)
  (max-norm (array-map one-norm (array-curry (array-permute a '#(1 0)) 1))))
(define (operator-one-norm a)
  ;; The "permutation" to apply here is the identity, so we omit it.
  (max-norm (array-map one-norm (array-curry a 1))))

(test 647 5345 (operator-max-norm m) 1940.)

(test 648 5347 (operator-one-norm m) 1605.)

(define (all-second-differences image direction)
  (let ((image-domain (array-domain image)))
    (let loop ((i 1)
               (result '()))
      (let ((negative-scaled-direction
             (vector-map (lambda (j) (* -1 j i)) direction))
            (twice-negative-scaled-direction
             (vector-map (lambda (j) (* -2 j i)) direction)))
        (cond ((interval-intersect image-domain
                                    (interval-translate image-domain negative-scaled-direction)
                                    (interval-translate image-domain twice-negative-scaled-direction))
               => (lambda (subdomain)
                    (loop (+ i 1)
                          (cons (array-copy
                                 (array-map (lambda (f_i f_i+d f_i+2d)
                                              (+ f_i+2d
                                                 (* -2. f_i+d)
                                                 f_i))
                                            (array-extract image
                                                           subdomain)
                                            (array-extract (array-translate image
                                                                            negative-scaled-direction)
                                                           subdomain)
                                            (array-extract (array-translate image
                                                                            twice-negative-scaled-direction)
                                                           subdomain)))
                                result))))
              (else
               (reverse result)))))))

(define image (array-copy (make-array (make-interval '#(8 8))
                                      (lambda (i j)
                                        (exact->inexact (+ (* i i) (* j j)))))))

(define (expose difference-images)
  (pretty-print (map (lambda (difference-image)
                       (list (array-domain difference-image)
                             (array->list* difference-image)))
                     difference-images)))
(begin
  (display "\nOriginal image:\n")
  (pretty-print (list (array-domain image)
                      (array->list* image)))
  (display "\nSecond-difference images in the direction $k\\times (1,0)$, $k=1,2,...$, wherever they're defined:\n")
  (expose (all-second-differences image '#(1 0)))
  (display "\nSecond-difference images in the direction $k\\times (1,1)$, $k=1,2,...$, wherever they're defined:\n")
  (expose (all-second-differences image '#(1 1)))
  (display "\nSecond-difference images in the direction $k\\times (1,-1)$, $k=1,2,...$, wherever they're defined:\n")
  (expose (all-second-differences image '#(1 -1))))

(define (make-separable-transform one-d-transform)
  (lambda (a)
    (let ((n (array-dimension a)))
      (do ((d 0 (fx+ d 1)))
          ((fx= d n))
        (array-for-each
         one-d-transform
         (array-curry (array-permute a (index-last n d)) 1))))))

(define (recursively-apply-transform-and-downsample transform)
  (lambda (a)
    (let ((sample-vector (make-vector (array-dimension a) 2)))
      (define (helper a)
        (if (fx< 1 (interval-upper-bound (array-domain a) 0))
            (begin
              (transform a)
              (helper (array-sample a sample-vector)))))
      (helper a))))

(define (recursively-downsample-and-apply-transform transform)
  (lambda (a)
    (let ((sample-vector (make-vector (array-dimension a) 2)))
      (define (helper a)
        (if (fx< 1 (interval-upper-bound (array-domain a) 0))
            (begin
              (helper (array-sample a sample-vector))
              (transform a))))
      (helper a))))

(define (one-d-Haar-loop a)
  (let ((a_ (array-getter a))
        (a! (array-setter a))
        (n (interval-upper-bound (array-domain a) 0)))
    (do ((i 0 (fx+ i 2)))
        ((fx= i n))
      (let* ((a_i               (a_ i))
             (a_i+1             (a_ (fx+ i 1)))
             (scaled-sum        (fl/ (fl+ a_i a_i+1) (flsqrt 2.0)))
             (scaled-difference (fl/ (fl- a_i a_i+1) (flsqrt 2.0))))
        (a! scaled-sum i)
        (a! scaled-difference (fx+ i 1))))))

(define one-d-Haar-transform
  (recursively-apply-transform-and-downsample one-d-Haar-loop))

(define one-d-Haar-inverse-transform
  (recursively-downsample-and-apply-transform one-d-Haar-loop))

(define hyperbolic-Haar-transform
  (make-separable-transform one-d-Haar-transform))

(define hyperbolic-Haar-inverse-transform
  (make-separable-transform one-d-Haar-inverse-transform))

(define Haar-transform
  (recursively-apply-transform-and-downsample
   (make-separable-transform one-d-Haar-loop)))

(define Haar-inverse-transform
  (recursively-downsample-and-apply-transform
   (make-separable-transform one-d-Haar-loop)))

(let ((image
       (array-copy
        (make-array (make-interval '#(4 4))
                    (lambda (i j)
                      (case i
                        ((0) 1.)
                        ((1) -1.)
                        (else 0.)))))))
  (display "\nInitial image: \n")
  (pretty-print (list (array-domain image)
                      (array->list* image)))
  (hyperbolic-Haar-transform image)
  (display "\nArray of hyperbolic Haar wavelet coefficients: \n")
  (pretty-print (list (array-domain image)
                      (array->list* image)))
  (hyperbolic-Haar-inverse-transform image)
  (display "\nReconstructed image: \n")
  (pretty-print (list (array-domain image)
                      (array->list* image))))


(let ((image
       (array-copy
        (make-array (make-interval '#(4 4))
                    (lambda (i j)
                      (case i
                        ((0) 1.)
                        ((1) -1.)
                        (else 0.)))))))
  (display "\nInitial image: \n")
  (pretty-print (list (array-domain image)
                      (array->list* image)))
  (Haar-transform image)
  (display "\nArray of Haar wavelet coefficients: \n")
  (pretty-print (list (array-domain image)
                      (array->list* image)))
  (Haar-inverse-transform image)
  (display "\nReconstructed image: \n")
  (pretty-print (list (array-domain image)
                      (array->list* image))))

(define (LU-decomposition A)
  ;; Assumes the domain of A is [0,n)\\times [0,n)
  ;; and that Gaussian elimination can be applied
  ;; without pivoting.
  (let ((n
         (interval-upper-bound (array-domain A) 0))
        (A_
         (array-getter A)))
    (do ((i 0 (fx+ i 1)))
        ((= i (fx- n 1)) A)
      (let* ((pivot
              (A_ i i))
             (column/row-domain
              ;; both will be one-dimensional
              (make-interval (vector (+ i 1))
                             (vector n)))
             (column
              ;; the column below the (i,i) entry
              (specialized-array-share A
                                       column/row-domain
                                       (lambda (k)
                                         (values k i))))
             (row
              ;; the row to the right of the (i,i) entry
              (specialized-array-share A
                                       column/row-domain
                                       (lambda (k)
                                         (values i k))))

             ;; the subarray to the right and
             ;;below the (i,i) entry
             (subarray
              (array-extract
               A (make-interval
                  (vector (fx+ i 1) (fx+ i 1))
                  (vector n         n)))))
        ;; compute multipliers
        (array-assign!
         column
         (array-map (lambda (x)
                      (/ x pivot))
                    column))
        ;; subtract the outer product of i'th
        ;; row and column from the subarray
        (array-assign!
         subarray
         (array-map -
                    subarray
                    (array-outer-product * column row)))))))


(define A
  ;; A Hilbert matrix
  (array-copy
   (make-array (make-interval '#(4 4))
               (lambda (i j)
                 (/ (+ 1 i j))))))

(display "\nHilbert matrix:\n\n")
(array-display A)

(LU-decomposition A)

(display "\nLU decomposition of Hilbert matrix:\n\n")

(array-display A)

;;; Functions to extract the lower- and upper-triangular
;;; matrices of the LU decomposition of A.

(define (L a)
  (let ((a_ (array-getter a))
        (d  (array-domain a)))
    (make-array
     d
     (lambda (i j)
       (cond ((= i j) 1)        ;; diagonal
             ((> i j) (a_ i j)) ;; below diagonal
             (else 0))))))      ;; above diagonal

(define (U a)
  (let ((a_ (array-getter a))
        (d  (array-domain a)))
    (make-array
     d
     (lambda (i j)
       (cond ((<= i j) (a_ i j)) ;; diagonal and above
             (else 0))))))       ;; below diagonal

(display "\nLower triangular matrix of decomposition of Hilbert matrix:\n\n")
(array-display (L A))

(display "\nUpper triangular matrix of decomposition of Hilbert matrix:\n\n")
(array-display (U A))

;;; We'll define a brief, not-very-efficient matrix multiply routine.

(define (matrix-multiply a b)
  (array-inner-product a + * b))

;;; We'll check that the product of the result of LU
;;; decomposition of A is again A.

(define product (matrix-multiply (L A) (U A)))

(display "\nProduct of lower and upper triangular matrices ")
(display "of LU decomposition of Hilbert matrix:\n\n")
(array-display product)

(array-display
 (matrix-multiply (list->array (make-interval '#(2 2))
                               '(1 0
                                 0 1))
                  (make-array (make-interval '#(2 4))
                              (lambda (i j)
                                (+ i j)))))

(test 649 5619 (myarray= (matrix-multiply (list->array (make-interval '#(2 2))
                                              '(1 0
                                                   0 1))
                                  (make-array (make-interval '#(2 4))
                                              (lambda (i j)
                                                (+ i j))))
                 (make-array (make-interval '#(2 4))
                             (lambda (i j)
                               (+ i j)))) #t)

;; Examples from
;; http://microapl.com/apl_help/ch_020_020_880.htm

(define TABLE1
  (list->array
   (make-interval '#(3 2))
   '(1 2
     5 4
     3 0)))

(define TABLE2
  (list->array
   (make-interval '#(2 4))
   '(6 2 3 4
     7 0 1 8)))

(pp (array->list* (array-inner-product TABLE1 + * TABLE2)))

(array-display (array-inner-product TABLE1 + * TABLE2))

;;; Displays
;;; 20 2 5 20
;;; 58 10 19 52
;;; 18 6 9 12

(define X (list*->array 1 '(1 3 5 7)))

(define Y (list*->array 1 '(2 3 6 7)))

(pp (array->list* (array-inner-product X + (lambda (x y) (if (= x y) 1 0)) Y)))

;;; Displays
;;; 2

(define A (array-copy (make-array (make-interval '#(3 4)) list)))

(array-display A)

(array-display (array-permute A '#(1 0)))

(array-display (specialized-array-reshape A (make-interval '#(4 3))))

(define B (array-sample A '#(2 1)))

(array-display B)

(test-err 650 5676 (array-display (specialized-array-reshape B (make-interval '#(8)))))

(array-display (specialized-array-reshape B (make-interval '#(8)) #t))

(define interval-flat (make-interval '#(100 100 4)))

(define interval-2x2  (make-interval '#(100 100 2 2)))

(define A (array-copy (make-array interval-flat (lambda args (test-random-integer 5)))))

(define B (array-copy (make-array interval-flat (lambda args (test-random-integer 5)))))

(define C (array-copy (make-array interval-flat (lambda args 0))))

(define (two-x-two-matrix-multiply-into! A B C)
  (let ((C! (array-setter C))
        (A_ (array-getter A))
        (B_ (array-getter B)))
    (C! (+ (* (A_ 0 0) (B_ 0 0))
           (* (A_ 0 1) (B_ 1 0)))
        0 0)
    (C! (+ (* (A_ 0 0) (B_ 0 1))
           (* (A_ 0 1) (B_ 1 1)))
        0 1)
    (C! (+ (* (A_ 1 0) (B_ 0 0))
           (* (A_ 1 1) (B_ 1 0)))
        1 0)
    (C! (+ (* (A_ 1 0) (B_ 0 1))
           (* (A_ 1 1) (B_ 1 1)))
        1 1)))

(begin (array-for-each two-x-two-matrix-multiply-into!
                 (array-curry (specialized-array-reshape A interval-2x2) 2)
                 (array-curry (specialized-array-reshape B interval-2x2) 2)
                 (array-curry (specialized-array-reshape C interval-2x2) 2)))

(begin (array-for-each (lambda (A B C)
                   (array-assign! C (matrix-multiply A B)))
                 (array-curry (specialized-array-reshape A interval-2x2) 2)
                 (array-curry (specialized-array-reshape B interval-2x2) 2)
                 (array-curry (specialized-array-reshape C interval-2x2) 2)))

(array-display ((array-getter
                 (array-curry
                  (specialized-array-reshape A interval-2x2)
                  2))
                0 0))
(array-display ((array-getter
                 (array-curry
                  (specialized-array-reshape B interval-2x2)
                  2))
                0 0))
(array-display ((array-getter
                 (array-curry
                  (specialized-array-reshape C interval-2x2)
                  2))
                0 0))

(define two-x-two (make-interval '#(2 2)))

(begin (array-for-each (lambda (A B C)
                   (two-x-two-matrix-multiply-into!
                    (specialized-array-reshape A two-x-two)
                    (specialized-array-reshape B two-x-two)
                    (specialized-array-reshape C two-x-two)))
                 (array-curry A 1)
                 (array-curry B 1)
                 (array-curry C 1)))

(begin (array-for-each (lambda (A B C)
                   (array-assign!
                    (specialized-array-reshape C two-x-two)
                    (matrix-multiply
                     (specialized-array-reshape A two-x-two)
                     (specialized-array-reshape B two-x-two))))
                 (array-curry A 1)
                 (array-curry B 1)
                 (array-curry C 1)))


(pp "cursory array-inner-product tests")

(test-err 651 5763 (array-inner-product 'a 'a 'a 'a))

(test-err 652 5766 (array-inner-product (make-array (make-interval '#(10)) list) 'a 'a 'a))

(test-err 653 5769 (array-inner-product (make-array (make-interval '#(10)) list) list 'a 'a))

(test-err 654 5772 (array-inner-product (make-array (make-interval '#(10)) list) list list 'a))

(test-err 655 5775 (array-inner-product (make-array (make-interval '#(10 1)) list) list list (make-array (make-interval '#(10)) list)))

(test-err 656 5778 (array-inner-product (make-array (make-interval '#(10 1)) list) list list (make-array (make-interval '#(10 1)) list)))


(test-err 657 5782 (array-inner-product (make-array (make-interval '#(1 10)) list)
                           list list
                           (make-array (make-interval '#(2 10)) list)))


(test-err 658 5788 (array-inner-product (make-array (make-interval '#()) list)
                           list list
                           (make-array (make-interval '#(10 0)) list)))

(test-err 659 5793 (array-inner-product (make-array (make-interval '#(10 0)) list)
                           list list
                           (make-array (make-interval '#()) list)))

(let* ((A (make-array (make-interval '#(0 4)) list))
       (B (make-array (make-interval '#(4 0)) list))
       (C (array-inner-product A list list B))) ;; should be no error, you can take outer product of empty arrays
  (test-err 660 5801 (array-ref C 0 0)))


(let* ((A (make-array (make-interval '#(4 0)) list))
       (B (make-array (make-interval '#(0 4)) list)))
  (test-err 661 5807 (array-inner-product A list list B)))


(pp "array-append and array-append! tests")

(for-each
 (lambda (call/cc-safe?)
   (let ((array-append
          (if call/cc-safe?
              array-append
              array-append!))
         (message
          (if call/cc-safe?
              "array-append:"    ;; no trailing space
              "array-append!:")))

     (define (wrap error-reason)
       (string-append message error-reason))

     (test 662 5827 (array-append 1 'a) (wrap " Expecting as the second argument a nonnull list of arrays with the same dimension: "))

     (test 663 5830 (array-append 1 '()) (wrap " Expecting as the second argument a nonnull list of arrays with the same dimension: "))

     (test 664 5833 (array-append 1 '(a)) (wrap " Expecting as the second argument a nonnull list of arrays with the same dimension: "))

     (test 665 5836 (array-append 1 (list (make-array (make-interval '#(1)) list) (make-array (make-interval '#(2 2)) list))) (wrap " Expecting as the second argument a nonnull list of arrays with the same dimension: "))

     (test 666 5839 (array-append 1 (list (make-array (make-interval '#(2 2)) list) 'a)) (wrap " Expecting as the second argument a nonnull list of arrays with the same dimension: "))

     (test 667 5842 (array-append 3 (list (make-array (make-interval '#(1 1)) list) (make-array (make-interval '#(2 2)) list))) (wrap " Expecting an exact integer between 0 (inclusive) and the dimension of the arrays (exclusive) as the first argument:"))

     (test 668 5845 (array-append -1 (list (make-array (make-interval '#(1 1)) list) (make-array (make-interval '#(2 2)) list))) (wrap " Expecting an exact integer between 0 (inclusive) and the dimension of the arrays (exclusive) as the first argument:"))

     (test 669 5848 (array-append 2 (list (make-array (make-interval '#(1 1)) list) (make-array (make-interval '#(2 2)) list))) (wrap " Expecting an exact integer between 0 (inclusive) and the dimension of the arrays (exclusive) as the first argument:"))

     (test 670 5851 (array-append 0
                         (list (make-array (make-interval '#(1 1)) list) (make-array (make-interval '#(2 2)) list))
                         'a) (wrap " Expecting a storage class as the third argument: "))

     (test 671 5856 (array-append 0
                         (list (make-array (make-interval '#(1 1)) list) (make-array (make-interval '#(2 2)) list))
                         u1-storage-class
                         'a) (wrap " Expecting a boolean as the fourth argument: "))

     (test 672 5862 (array-append 0
                         (list (make-array (make-interval '#(1 1)) list) (make-array (make-interval '#(2 2)) list))
                         u1-storage-class
                         #t
                         'a) (wrap " Expecting a boolean as the fifth argument: "))

     (test 673 5869 (array-append 0
                         (list (make-array (make-interval '#(2 4)) list)
                               (make-array (make-interval '#(3 5)) list))) (wrap " Expecting as the second argument a nonnull list of arrays with the same upper and lower bounds (except for index 0): "))

     (test 674 5874 (array-append 0
                         (list (make-array (make-interval '#(1 1)) list) (make-array (make-interval '#(2 1)) list))
                         u1-storage-class) (wrap " Not all elements of the source can be stored in destination: "))
     ))
 '(#t #f))



(define (my-array-append k . arrays)              ;; call with at least one array
  (call-with-values
      (lambda ()
        ;; compute lower and upper bounds of where
        ;; we'll copy each array argument, plus
        ;; the size of the kth axis of the result array
        (let loop ((result '(0))
                   (arrays arrays))
          (if (null? arrays)
              (values (reverse result) (car result))
              (let ((interval (array-domain (car arrays))))
                (loop (cons (+ (car result)
                               (- (interval-upper-bound interval k)
                                  (interval-lower-bound interval k)))
                            result)
                      (cdr arrays))))))
    (lambda (axis-subdividers kth-size)
      (let* ((array
              (car arrays))
             (lowers                         ;; the domains of the arrays differ only in the kth axis
              (interval-lower-bounds->vector (array-domain array)))
             (uppers
              (interval-upper-bounds->vector (array-domain array)))
             (result                         ;; the result array
              (make-specialized-array
               (let ()
                 (vector-set! lowers k 0)
                 (vector-set! uppers k kth-size)
                 (make-interval lowers uppers))))
             (translation
              ;; a vector we'll use to align each argument
              ;; array into the proper subarray of the result
              (make-vector (array-dimension array) 0)))
        (let loop ((arrays arrays)
                   (subdividers axis-subdividers))
          (if (null? arrays)
              ;; we've assigned every array to the appropriate subarray of result
              result
              (let ((array (car arrays)))
                (vector-set! lowers k (car subdividers))
                (vector-set! uppers k (cadr subdividers))
                (vector-set! translation k (- (car subdividers)
                                              (interval-lower-bound (array-domain array) k)))
                (array-assign!
                 (array-extract result (make-interval lowers uppers))
                 (array-translate array translation))
                (loop (cdr arrays)
                      (cdr subdividers)))))))))





;;; We steal some tests from Alex Shinn's test suite.

(define (append-map f l)
  (foldr append
         '()
         (map f l)))

(define (flatten ls)
  (if (pair? (car ls))
      (append-map flatten ls)
      ls))

(define (tensor nested-ls . o)
  (let lp ((ls nested-ls) (lens '()))
    (cond
     ((pair? ls) (lp (car ls) (cons (length ls) lens)))
     (else
      (apply list->array
             (make-interval (list->vector (reverse lens)))
             (flatten nested-ls)
             o)))))

(define (identity-array k . o)
  (array-copy (make-array (make-interval (vector k k))
                          (lambda args
                            (if (apply = args)
                                1
                                0)))
              (if (null? o) generic-storage-class (car o))))

(for-each
 (lambda (array-append)

   (define (->generalized-array array)
     (make-array (array-domain array)
                 (array-getter array)))

   (test 675 5973 (array-storage-class
          (array-append 0
                        (list (array-copy (make-array (make-interval '#(10)) (lambda (i) (random-integer 10))) u8-storage-class)
                              (array-copy (make-array (make-interval '#(10)) (lambda (i) (random-integer 10))) u16-storage-class)))) generic-storage-class)

   (test 676 5979 (myarray= (array-append
                    0
                    (list (->generalized-array (list->array (make-interval '#(2 2))
                                                            '(1 2
                                                                3 4)))
                          (->generalized-array (list->array (make-interval '#(2 2))
                                                            '(5 6
                                                                7 8)))))
                   (list->array (make-interval '#(4 2))
                                '(1 2
                                    3 4
                                    5 6
                                    7 8))) #t)

   (test 677 5994 (myarray= (array-append
                    1
                    (list (->generalized-array (list->array (make-interval '#(2 2))
                                                            '(1 2
                                                                3 4)))
                          (list->array (make-interval '#(2 2))
                                       '(5 6
                                           7 8))))
                   (list->array (make-interval '#(2 4))
                                '(1 2 5 6
                                    3 4 7 8))) #t)

   (test 678 6007 (myarray= (array-append
                    0
                    (list (->generalized-array (list->array (make-interval '#(2 2))
                                                            '(1 2
                                                                3 4)))
                          (list->array (make-interval '#(2 2))
                                       '(5 6
                                           7 8))))
                   (my-array-append
                    0
                    (list->array (make-interval '#(2 2))
                                 '(1 2
                                     3 4))
                    (list->array (make-interval '#(2 2))
                                 '(5 6
                                     7 8)))) #t)

   (test 679 6025 (myarray= (array-append
                    1
                    (list (->generalized-array (list->array (make-interval '#(2 2))
                                                            '(1 2
                                                                3 4)))
                          (list->array (make-interval '#(2 2))
                                       '(5 6
                                           7 8))))
                   (my-array-append
                    1
                    (list->array (make-interval '#(2 2))
                                 '(1 2
                                     3 4))
                    (list->array (make-interval '#(2 2))
                                 '(5 6
                                     7 8)))) #t)

   (test 680 6043 (myarray= (tensor '((4 7)
                             (2 6)
                             (1 0)
                             (0 1)))
                   (array-append 0 (list (tensor '((4 7)
                                                   (2 6)))
                                         (identity-array 2)))) #t)

   (test 681 6052 (myarray= (tensor '((4 7)
                             (2 6)
                             (1 0)
                             (0 1)))
                   (array-append 0
                                 (list (list->array (make-interval '#(2 0) '#(4 2))
                                                    '(4 7 2 6))
                                       (identity-array 2)))) #t)

   (test 682 6062 (myarray= (tensor '((4 7 1 0)
                             (2 6 0 1)))
                   (array-append 1 (list (tensor '((4 7)
                                                   (2 6)))
                                         (identity-array 2)))) #t)

   (test 683 6069 (myarray= (tensor '((4 7 2 1 0)
                             (6 3 5 0 1)))
                   (array-append 1 (list (tensor '((4 7 2)
                                                   (6 3 5)))
                                         (identity-array 2)))) #t)

   (test 684 6076 (myarray= (tensor '((4 7 1 0 0 1 3)
                             (2 6 0 1 5 8 9)))
                   (array-append
                    1
                    (list (list->array (make-interval '#(2 2))
                                       '(4 7 2 6))
                          (identity-array 2)
                          (list->array (make-interval '#(2 3))
                                       '(0 1 3 5 8 9))))) #t)

   )
 (list array-append array-append!))


(do ((i 0 (+ i 1)))
    ((= i random-tests))
  (let* ((domain
          (random-interval 1 6))  ;; you can't append zero-dimensional arrays
         (dimension
          (interval-dimension domain))
         (A
          (array-copy (make-array domain (lambda args (random 10)))))
         (domain-widths
          (interval-widths domain))
         (cutting-axis
          (random dimension))
         (tiling-argument
          (vector-map (lambda (k)
                        (let ((kth-width (interval-width domain k)))
                          (if (fx= k cutting-axis)
                              (if (zero? kth-width)
                                  (make-vector (random 1 4) 0)
                                  (let loop ((result '())
                                             (sum 0))
                                    (if (fx< sum kth-width)
                                        (let ((slice-width (random (+ 1 kth-width))))
                                          (loop (cons slice-width result)
                                                (+ slice-width sum)))
                                        (vector-permute (list->vector (cons (- (car result) (- sum kth-width))
                                                                            (cdr result)))
                                                        (random-permutation (length result))))))
                              (if (zero? kth-width)
                                  '#(0)
                                  kth-width))))
                      (list->vector (iota dimension))))
         (arrays
          (array->list (array-tile A tiling-argument)))
         (A-reconstructed
          (array-append cutting-axis arrays))
         (A-reconstructed!
          (array-append! cutting-axis arrays)))
    (test 685 6128 (myarray= (array-translate A (vector-map -
                                                   (interval-lower-bounds->vector (array-domain A-reconstructed))
                                                   (interval-lower-bounds->vector (array-domain A))))
                    A-reconstructed) #t)
    (test 686 6133 (myarray= (array-translate A (vector-map -
                                                   (interval-lower-bounds->vector (array-domain A-reconstructed))
                                                   (interval-lower-bounds->vector (array-domain A))))
                    A-reconstructed!) #t)))

(let* ((a (make-array (make-interval '#(4 6)) list))
       (k 2)
       (m (interval-upper-bound (array-domain a) 0))
       (n (interval-upper-bound (array-domain a) 1)))
  (pretty-print
   (array->list* a))
  (newline)
  (pretty-print
   (array->list*
    (array-append
     0
     (list (array-extract a (make-interval (vector k 0) (vector (+ k 1) n)))
           (array-extract a (make-interval (vector k n)))
           (array-extract a (make-interval (vector (+ k 1) 0) (vector m n))))))))


(next-test-random-source-state!)

(pp "array-stack and array-stack! tests")

(for-each
 (lambda (call/cc-safe?)
   (let ((array-stack
          (if call/cc-safe?
              array-stack
              array-stack!))
         (message
          (if call/cc-safe?
              "array-stack:"     ;; no trailing space
              "array-stack!:")))

     (define (wrap error-reason)
       (string-append message error-reason))

     (test 687 6173 (array-stack 1 'a) (wrap " Expecting a nonnull list of arrays with the same domains as the second argument: "))

     (test 688 6176 (array-stack 1 '()) (wrap " Expecting a nonnull list of arrays with the same domains as the second argument: "))

     (test 689 6179 (array-stack 1 '(a)) (wrap " Expecting a nonnull list of arrays with the same domains as the second argument: "))

     (test 690 6182 (array-stack 1 (list (make-array (make-interval '#(1)) list) (make-array (make-interval '#(2 2)) list))) (wrap " Expecting a nonnull list of arrays with the same domains as the second argument: "))

     (test 691 6185 (array-stack 1 (list (make-array (make-interval '#(2 2)) list) 'a)) (wrap " Expecting a nonnull list of arrays with the same domains as the second argument: "))

     (test 692 6188 (array-stack 'a (list (make-array (make-interval '#(2 2)) list) (make-array (make-interval '#(2 2)) list))) (wrap " Expecting an exact integer between 0 (inclusive) and the dimension of the arrays (inclusive) as the first argument:"))

     (test 693 6191 (array-stack -1 (list (make-array (make-interval '#(2 2)) list) (make-array (make-interval '#(2 2)) list))) (wrap " Expecting an exact integer between 0 (inclusive) and the dimension of the arrays (inclusive) as the first argument:"))

     (test 694 6194 (array-stack 3 (list (make-array (make-interval '#(2 2)) list) (make-array (make-interval '#(2 2)) list))) (wrap " Expecting an exact integer between 0 (inclusive) and the dimension of the arrays (inclusive) as the first argument:"))

     (test 695 6197 (array-stack 0
                        (list (make-array (make-interval '#(2 2)) list) (make-array (make-interval '#(2 2)) list))
                        'a) (wrap " Expecting a storage class as the third argument: "))

     (test 696 6202 (array-stack 0
                        (list (make-array (make-interval '#(2 2)) list) (make-array (make-interval '#(2 2)) list))
                        u1-storage-class
                        'a) (wrap " Expecting a boolean as the fourth argument: "))

     (test 697 6208 (array-stack 0
                        (list (make-array (make-interval '#(2 2)) list) (make-array (make-interval '#(2 2)) list))
                        u1-storage-class
                        #t
                        'a) (wrap " Expecting a boolean as the fifth argument: "))


     (test 698 6216 (array-stack 0
                        (list (make-array (make-interval '#(2 2)) list) (make-array (make-interval '#(2 2)) list))
                        u1-storage-class) (wrap " Not all elements of the source can be stored in destination: "))

     (test 699 6221 (array-storage-class
            (array-stack 1 (list (make-array (make-interval '#(10)) list)))) generic-storage-class)

     (test 700 6225 (array-storage-class
            (array-stack 1
                         (list (array-copy (make-array (make-interval '#(10)) (lambda (i) (random-integer 10))) u8-storage-class)
                               (array-copy (make-array (make-interval '#(10)) (lambda (i) (random-integer 10))) u16-storage-class)))) generic-storage-class)

     (test 701 6231 (myarray= (tensor '(((4 7) (2 6))
                               ((1 0) (0 1))))
                     (array-stack 0 (list (tensor '((4 7)
                                                    (2 6)))
                                          (identity-array 2)))) #t)

     (test 702 6238 (myarray= (tensor '(((4 7) (1 0))
                               ((2 6) (0 1))))
                     (array-stack 1 (list (tensor '((4 7)
                                                    (2 6)))
                                          (identity-array 2)))) #t)

     (test 703 6245 (myarray= (tensor '(((4 1) (7 0))
                               ((2 0) (6 1))))
                     (array-stack 2 (list (tensor '((4 7)
                                                    (2 6)))
                                          (identity-array 2)))) #t)

     (let* ((A
             (make-array
              (make-interval '#(4 10))
              list))
            (column_
             (array-getter                  ;; the getter of ...
              (array-curry                  ;; a 1-D array of the columns of A
               (array-permute A '#(1 0))
               1)))
            (B
             (array-stack                  ;; stack into a new 2-D array ...
              1                            ;; along axis 1 (i.e., columns) ...
              (map column_ '(1 2 5 8)))))  ;; the columns of A you want
       (array-display B))

     (let* ((A
             (make-array
              (make-interval '#(4 10))
              list))
            (B
             (array-stack 1 (map (array-getter (array-curry (array-permute A '#(1 0)) 1)) '(1 2 5 8)))))
       (array-display B))
     ))
 '(#t #f))


;;; zero-dimensional and empty arrays

(let ()

  (define arrays (map (lambda (ignore) (array-copy (make-array (make-interval '#()) (lambda () (random-integer 10))))) (iota 4)))

  (define b  (array-stack 0 arrays))
  (define c  (array-stack! 0 arrays))

  (test 704 6287 (map array-ref arrays) (array->list b))
  (test 705 6289 (map array-ref arrays) (array->list c)))

(let* ((arrays (map (lambda (ignore) (array-copy (make-array (make-interval '#(0)) error))) (iota 4)))
       (b (array-stack 0 arrays))
       (c (array-stack 1 arrays))
       (b! (array-stack! 0 arrays))
       (c! (array-stack! 1 arrays)))

  (test 706 6298 (interval-upper-bounds->vector (array-domain b)) '#(4 0))
  (test 707 6300 (interval-upper-bounds->vector (array-domain c)) '#(0 4))

  (test 708 6303 (interval-upper-bounds->vector (array-domain b!)) '#(4 0))
  (test 709 6305 (interval-upper-bounds->vector (array-domain c!)) '#(0 4)))


;;; FIXME: Need to test the values of other optional arguments to array-append

(define (myarray-stack k . arrays)
  (let* ((array
          (car arrays))
         (domain
          (array-domain array))
         (lowers
          (interval-lower-bounds->list domain))
         (uppers
          (interval-upper-bounds->list domain))
         (new-domain
          (make-interval
           (list->vector (append (take lowers k) (cons 0 (drop lowers k))))
           (list->vector (append (take uppers k) (cons (length arrays) (drop uppers k))))))
         (getters
          (list->vector (map %%array-getter arrays))))
    (make-array new-domain
                (lambda args
                  (apply
                   (vector-ref getters (list-ref args k))
                   (append (take args k)
                           (drop args (+ k 1))))))))

(do ((d 0 (fx+ d 1)))
    ((= d 6))
  (let* ((uppers-list
          (iota d))
         (domain
          (make-interval (list->vector uppers-list))))
    (do ((i 0 (fx+ i 1)))
        ;; distribute "tests" results over five dimensions
        ((= i (quotient random-tests 5)))
      (let* ((arrays
              (map (lambda (ignore)
                     (array-copy
                      (make-array domain
                                  (lambda args
                                    (random 256)))
                      u8-storage-class))
                   (iota (random 1 5))))
             (k
              (random (+ d 1))))
        (test 710 6352 (myarray= (array-stack k arrays)
                        (apply myarray-stack k arrays)) #t)
        (test 711 6355 (myarray= (array-stack! k arrays)
                        (apply myarray-stack k arrays)) #t)))))

(next-test-random-source-state!)

(pp "array-block and array-block! tests")

(for-each
 (lambda (call/cc-safe?)
   (let ((array-block
          (if call/cc-safe?
              array-block
              array-block!))
         (message
          (if call/cc-safe?
              "array-block: "
              "array-block!: ")))

     (define (wrap error-reason)
       (string-append message error-reason))

     (test 712 6377 (array-block 'a) (wrap "The first argument is not an array: "))

     (test 713 6380 (array-block (make-array (make-interval '#(2 2)) list) 'a) (wrap "The second argument is not a storage class: "))

     (test 714 6383 (array-block (make-array (make-interval '#(2 2)) list)
                        u8-storage-class
                        'a) (wrap "The third argument is not a boolean: "))

     (test 715 6388 (array-block (make-array (make-interval '#(2 2)) list)
                        u8-storage-class
                        #f
                        'a) (wrap "The fourth argument is not a boolean: "))

     (test 716 6394 (array-block (make-array (make-interval '#(2 2)) list)) (wrap "Not all elements of the first argument (an array) are arrays: "))

     (test 717 6397 (array-block (vector*->array 1 (vector (vector*->array 1 '#(1 1))
                                                  (vector*->array 2 '#(#(1 2) #(3 4)))))) (wrap "Not all elements of the first argument (an array) have the same dimension as the first argument itself: "))

     (test 718 6401 (array-block (list*->array
                         2
                         (list (list (list*->array 2 '((0 1)
                                                       (2 3)))
                                     (list*->array 2 '((4)
                                                       (5)))
                                     (list*->array 2 '((6 7)     ;; these should each have ...
                                                       (9 10)))) ;; three elements
                               (list (list*->array 2 '((12 13)))
                                     (list*->array 2 '((14)))
                                     (list*->array 2 '((15 16 17))))))) (wrap "Cannot stack array elements of the first argument into result array: "))


     (test 719 6415 (array? (array-block (list*->array
                                 1
                                 (list (make-array (make-interval '#(0)) list)
                                       (make-array (make-interval '#(0)) list))))) #t)


     (let* ((A (list*->array
                2
                (list (list (list*->array 2 '((0 1)
                                              (2 3)))
                            (list*->array 2 '((4)
                                              (5)))
                            (list*->array 2 '((6 7 8)
                                              (9 10 11))))
                      (list (list*->array 2 '((12 13)))
                            (list*->array 2 '((14)))
                            (list*->array 2 '((15 16 17)))))))
            (A-appended
             (array-block A))
            (A-tiled
             (array-tile A-appended '#(#(2 1) #(2 1 3)))))

       (for-each (lambda (mutable?)
                   (for-each (lambda (safe?)
                               (let ((new-A (array-block A generic-storage-class mutable? safe?)))
                                 (test 720 6441 (array-safe? new-A) safe?)
                                 (test 721 6443 (mutable-array? new-A) mutable?)))
                             '(#t #f)))
                 '(#t #f))
       (for-each (lambda (mutable?)
                   (for-each (lambda (safe?)
                               (parameterize ((specialized-array-default-mutable? mutable?)
                                              (specialized-array-default-safe?    safe?))
                                 (let ((new-A (array-block A generic-storage-class)))
                                   (test 722 6452 (array-safe? new-A) safe?)
                                   (test 723 6454 (mutable-array? new-A) mutable?))))
                             '(#t #f)))
                 '(#t #f))

       (test 724 6459 (array-every equal?            ;; we convert them to list*'s to ignore domains.
                          (array-map array->list* A)
                          (array-map array->list* A-tiled)) #t))

     (let* ((A (list*->array
                2
                (list (list (list*->array 2 '((0 1)
                                              (2 3)))
                            (list*->array 2 '((4)
                                              (5)))
                            (list*->array 2 '((6 7 8)
                                              (9 10 11))))
                      (list (list*->array 2 '((12 13)))
                            (list*->array 2 '((14)))
                            (list*->array 2 '((15 16 17))))))))
       (test 725 6475 (array-block A u1-storage-class) (wrap "Not all elements of the source can be stored in destination: ")))
     ))
 '(#t #f))



(do ((i 0 (+ i 1)))
    ((= i random-tests))
  (let* ((dims
          (random 1 6))
         (A-uppers
          (list->vector (map (lambda (ignore) (random 3 6)) (iota dims))))
         (A
          (array-copy
           (make-array (make-interval A-uppers)
                       (lambda args
                         (random 2)))
           u1-storage-class))
         (A_
          (array-getter A))
         (number-of-cuts
          (array->vector
           (make-array (make-interval (vector dims))
                       (lambda args (random 3)))))
         (cuts
          (vector-map (lambda (cuts upper)
                        (let ((bitmap (make-vector (+ upper 1) #f)))
                          (vector-set! bitmap 0 #t)
                          (vector-set! bitmap upper #t)
                          (let loop ((i 0))
                            (if (fx= i cuts)
                                (let ((result (make-vector (fx+ cuts 2))))
                                  (let inner ((l 0)
                                              (j 0))
                                    (cond ((fx> j cuts)
                                           (vector-set! result j upper)
                                           result)
                                          ((vector-ref bitmap l)
                                           (vector-set! result j l)
                                           (inner (fx+ l 1)
                                                  (fx+ j 1)))
                                          (else
                                           (inner (fx+ l 1)
                                                  j)))))
                                (let ((proposed-cut (random upper)))
                                  (if (vector-ref bitmap proposed-cut)
                                      (loop i)
                                      (begin
                                        (vector-set! bitmap proposed-cut #t)
                                        (loop (fx+ i 1)))))))))
                      number-of-cuts
                      A-uppers))
         (side-lengths
          (vector-map
           (lambda (cuts)
             (let ((result
                    (make-vector (- (vector-length cuts) 1))))
               (do ((i 0 (fx+ i 1)))
                   ((fx= i (vector-length result)) result)
                 (vector-set! result i (- (vector-ref cuts (+ i 1))
                                          (vector-ref cuts i))))))
           cuts))
         (A-blocks
          (make-array (make-interval (vector-map (lambda (v)
                                                              (- (vector-length v) 1))
                                                            cuts))
                                 (lambda args
                                   (let ((vector-args (list->vector args)))
                                     (make-array (make-interval (vector-map (lambda (cuts i)
                                                                              (vector-ref cuts i))
                                                                            cuts
                                                                            vector-args)
                                                                (vector-map (lambda (cuts i)
                                                                              (vector-ref cuts (+ i 1)))
                                                                            cuts
                                                                            vector-args))
                                                 A_)))))
         (A-tiled
          (array-tile A side-lengths))
         (reconstructed-A
          (array-block A-blocks u1-storage-class))
         (reconstructed-A!
          (array-block! A-blocks u1-storage-class)))
    (test 726 6559 (array-every myarray= A-tiled A-blocks) #t)
    (test 727 6561 (array-every = A reconstructed-A) #t)
    (test 728 6563 (array-every = A reconstructed-A!) #t)
    (test 729 6565 (array-every = A
                       (array-block
                        (array-tile A
                                    (list->vector
                                     (map (lambda (ignore) (random 1 5))
                                          (iota dims)))))) #t)
    (test 730 6572 (array-every = A
                       (array-block!
                        (array-tile A
                                    (list->vector
                                     (map (lambda (ignore) (random 1 5))
                                          (iota dims)))))) #t)))

(next-test-random-source-state!)

;;; Let's do something similar now with possibly empty arrays and subarrays.

(do ((i 0 (+ i 1)))
    ((= i random-tests))
  (let* ((domain
          (random-interval))
         (domain-widths
          (interval-widths domain))
         (tiling-argument
          (vector-map (lambda (width)
                        (if (zero? width)                  ;; width of kth axis is 0
                            (make-vector (random 1 3) 0)
                            (if (even? (random 2))
                                (let loop ((result '())    ;; accumulate a list of nonnegative integers that (eventually) sum to no less than width
                                           (sum 0))
                                  (if (<= width sum)
                                      (vector-permute (list->vector (cons (- (car result)    ;; adjust last entry so the sum is width
                                                                             (- sum width))
                                                                          (cdr result)))
                                                      (random-permutation (length result)))  ;; randomly permute vector of cuts
                                      (let ((new-width (random (+ width 1))))
                                        (loop (cons new-width result)
                                              (+ new-width sum)))))
                                (random 1 (+ width 3)))))               ;; a positive scalar
                      domain-widths))
         (A
          (array-copy (make-array domain (lambda args (random 10)))))
         (A-tiled
          (array-tile A tiling-argument))
         (A-tiled
          (array-map (lambda (A) (make-array (array-domain A) (array-getter A))) A-tiled))
         (A-blocked!
          (array-block! A-tiled))
         (A-blocked
          (array-block A-tiled)))
    (test 731 6617 (myarray= (array-translate A (vector-map - (interval-lower-bounds->vector (array-domain A)))) ;; array-block returns an array based at the origin
                    A-blocked!) #t)
    (test 732 6620 (myarray= (array-translate A (vector-map - (interval-lower-bounds->vector (array-domain A)))) ;; array-block returns an array based at the origin
                    A-blocked) #t)))

(next-test-random-source-state!)

(define (array-pad-periodically a N)
  ;; Pad a periodically with N rows and columns top and bottom, left and right.
  ;; Returns a generalized array.
  (let* ((domain     (array-domain a))
         (m          (interval-upper-bound domain 0))
         (n          (interval-upper-bound domain 1))
         (a_         (array-getter a)))
    (make-array (interval-dilate domain (vector (- N) (- N)) (vector N N))
                (lambda (i j)
                  (a_ (modulo i m) (modulo j n))))))

(define (neighbor-count a)
  (let* ((big-a      (array-copy (array-pad-periodically a 1)
                                 (array-storage-class a)))
         (domain     (array-domain a))
         (translates (map (lambda (translation)
                            (array-extract (array-translate big-a translation) domain))
                          '(#(1 0) #(0 1) #(-1 0) #(0 -1)
                            #(1 1) #(1 -1) #(-1 1) #(-1 -1)))))
    ;; Returns a generalized array that contains the number
    ;; of 1s in the 8 cells surrounding each cell in the original array.
    (apply array-map + translates)))

(define (game-rules a neighbor-count)
  ;; a is a single cell, neighbor-count is the count of 1s in
  ;; its 8 neighboring cells.
  (if (= a 1)
      (if (or (= neighbor-count 2)
              (= neighbor-count 3))
          1 0)
      ;; (= a 0)
      (if (= neighbor-count 3)
          1 0)))

(define (advance a)
  (array-copy
   (array-map game-rules a (neighbor-count a))
   (array-storage-class a)))

(define glider
  (list*->array
   2
   '((0 0 0 0 0 0 0 0 0 0)
     (0 0 1 0 0 0 0 0 0 0)
     (0 0 0 1 0 0 0 0 0 0)
     (0 1 1 1 0 0 0 0 0 0)
     (0 0 0 0 0 0 0 0 0 0)
     (0 0 0 0 0 0 0 0 0 0)
     (0 0 0 0 0 0 0 0 0 0)
     (0 0 0 0 0 0 0 0 0 0)
     (0 0 0 0 0 0 0 0 0 0)
     (0 0 0 0 0 0 0 0 0 0))
   u1-storage-class))

(define (generations a N)
  (do ((i 0 (fx+ i 1))
       (a a  (advance a)))
      ((fx= i N))
    (newline)
    (pretty-print (array->list* a))))

(generations glider 5)


;;; Unit tests

(pp "unit-tests")

(let ((A (make-specialized-array (make-interval '#(5 5 5 5 5) '#(8 8 8 8 8))))
      (B (make-specialized-array (make-interval '#(5 5 5 5 5)))))
  (test-err 733 6696 (array-ref A 0 0))
  (test-err 734 6698 (array-set! A 2 0 0))
  (test-err 735 6700 (array-ref B 0 0))
  (test-err 736 6702 (array-set! B 2 0 0)))

(pp "Test interactions of continuations and array-{copy|append|stack|decurry|block}")

(pp 'array-copy)

(let* ((cont #f)
       (call-cont #t)
       (domain (make-interval '#(2 2)))
       (A_ (lambda (i j)
             (call-with-current-continuation
              (lambda (c)
                (if (= i j 0)
                    (set! cont c))
                1))))
       (A (make-array domain A_))
       (array-list '()))
  (let ((temp (array-copy A)))
    (set! array-list (cons temp array-list)))
  (if call-cont
      (begin
        (set! call-cont #f)
        (cont 4)))
  (for-each (lambda (result truth)
              (test 737 6727 (array->list* result) truth))
            array-list
            '(((4 1) (1 1))
              ((1 1) (1 1)))))

(pp 'array-append)

(let* ((cont #f)
       (call-cont #t)
       (domain (make-interval '#(2 2)))
       (B (list*->array 2 '((1 2) (3 4))))
       (A_ (lambda (i j)
             (call-with-current-continuation
              (lambda (c)
                (if (= i j 0)
                    (set! cont c))
                1))))
       (A (make-array domain A_))
       (array-list '()))
  (let ((temp (array-append 1 (list A B))))
    (set! array-list (cons temp array-list)))
  (if call-cont
      (begin
        (set! call-cont #f)
        (cont 4)))
  (for-each (lambda (result truth)
              (test 738 6754 (array->list* result) truth))
            array-list
            '(((4 1 1 2) (1 1 3 4))
              ((1 1 1 2) (1 1 3 4)))))

(pp 'array-stack)

(let* ((cont #f)
       (call-cont #t)
       (domain (make-interval '#(2 2)))
       (B (list*->array 2 '((1 2) (3 4))))
       (A_ (lambda (i j)
             (call-with-current-continuation
              (lambda (c)
                (if (= i j 0)
                    (set! cont c))
                1))))
       (A (make-array domain A_))
       (array-list '()))
  (let ((temp (array-stack 1 (list A B))))
    (set! array-list (cons temp array-list)))
  (if call-cont
      (begin
        (set! call-cont #f)
        (cont 4)))
  (for-each (lambda (result truth)
              (test 739 6781 (array->list* result) truth))
            array-list
            '((((4 1) (1 2)) ((1 1) (3 4)))
              (((1 1) (1 2)) ((1 1) (3 4))))))

(pp 'array-block)

(let* ((cont #f)
       (call-cont #t)
       (domain (make-interval '#(2 2)))
       (B (list*->array 2 '((1 2) (3 4))))
       (A_ (lambda (i j)
             (call-with-current-continuation
              (lambda (c)
                (if (= i j 0)
                    (set! cont c))
                1))))
       (A (make-array domain A_))
       (C (list*->array 2 (list (list A B))))
       (array-list '()))
  (let ((temp (array-block C)))
    (set! array-list (cons temp array-list)))
  (if call-cont
      (begin
        (set! call-cont #f)
        (cont 4)))
  (for-each (lambda (result truth)
              (test 740 6809 (array->list* result) truth))
            array-list
            '(((4 1 1 2) (1 1 3 4))
              ((1 1 1 2) (1 1 3 4)))))

(pp 'array-decurry)

(let* ((cont #f)
       (call-cont #t)
       (domain (make-interval '#(2 2)))
       (B (list*->array 2 '((1 2) (3 4))))
       (A_ (lambda (i j)
             (call-with-current-continuation
              (lambda (c)
                (if (= i j 0)
                    (set! cont c))
                1))))
       (A (make-array domain A_))
       (C (list*->array 1 (list A B)))
       (array-list '()))
  (let ((temp (array-decurry C)))
    (set! array-list (cons temp array-list)))
  (if call-cont
      (begin
        (set! call-cont #f)
        (cont 4)))
  (for-each (lambda (result truth)
              (test 741 6837 (array->list* result) truth))
            array-list
            '((((4 1) (1 1)) ((1 2) (3 4)))
              (((1 1) (1 1)) ((1 2) (3 4))))))

(pp "Test that the corresponding ! procedures don't crash when dealing with continuations.")

(pp 'array-copy!)

(let* ((cont #f)
       (call-cont #t)
       (domain (make-interval '#(2 2)))
       (A_ (lambda (i j)
             (call-with-current-continuation
              (lambda (c)
                (if (= i j 0)
                    (set! cont c))
                1))))
       (A (make-array domain A_))
       (array-list '()))
  (let ((temp (array-copy! A)))
    (set! array-list (cons temp array-list)))
  (if call-cont
      (begin
        (set! call-cont #f)
        (cont 4))))

(pp 'array-append!)

(let* ((cont #f)
       (call-cont #t)
       (domain (make-interval '#(2 2)))
       (B (list*->array 2 '((1 2) (3 4))))
       (A_ (lambda (i j)
             (call-with-current-continuation
              (lambda (c)
                (if (= i j 0)
                    (set! cont c))
                1))))
       (A (make-array domain A_))
       (array-list '()))
  (let ((temp (array-append! 1 (list A B))))
    (set! array-list (cons temp array-list)))
  (if call-cont
      (begin
        (set! call-cont #f)
        (cont 4))))

(pp 'array-stack!)

(let* ((cont #f)
       (call-cont #t)
       (domain (make-interval '#(2 2)))
       (B (list*->array 2 '((1 2) (3 4))))
       (A_ (lambda (i j)
             (call-with-current-continuation
              (lambda (c)
                (if (= i j 0)
                    (set! cont c))
                1))))
       (A (make-array domain A_))
       (array-list '()))
  (let ((temp (array-stack! 1 (list A B))))
    (set! array-list (cons temp array-list)))
  (if call-cont
      (begin
        (set! call-cont #f)
        (cont 4))))

(pp 'array-block!)

(let* ((cont #f)
       (call-cont #t)
       (domain (make-interval '#(2 2)))
       (B (list*->array 2 '((1 2) (3 4))))
       (A_ (lambda (i j)
             (call-with-current-continuation
              (lambda (c)
                (if (= i j 0)
                    (set! cont c))
                1))))
       (A (make-array domain A_))
       (C (list*->array 2 (list (list A B))))
       (array-list '()))
  (let ((temp (array-block! C)))
    (set! array-list (cons temp array-list)))
  (if call-cont
      (begin
        (set! call-cont #f)
        (cont 4))))

(pp 'array-decurry!)

(let* ((cont #f)
       (call-cont #t)
       (domain (make-interval '#(2 2)))
       (B (list*->array 2 '((1 2) (3 4))))
       (A_ (lambda (i j)
             (call-with-current-continuation
              (lambda (c)
                (if (= i j 0)
                    (set! cont c))
                1))))
       (A (make-array domain A_))
       (C (list*->array 1 (list A B)))
       (array-list '()))
  (let ((temp (array-decurry! C)))
    (set! array-list (cons temp array-list)))
  (if call-cont
      (begin
        (set! call-cont #f)
        (cont 4))))

(pp 'array-assign!)

(let* ((cont #f)
       (call-cont #t)
       (domain (make-interval '#(2 2)))
       (B (list*->array 2 '((1 2) (3 4))))
       (A_ (lambda (i j)
             (call-with-current-continuation
              (lambda (c)
                (if (= i j 0)
                    (set! cont c))
                1))))
       (A (make-array domain A_)))
  (array-assign! B A)
  (if call-cont
      (begin
        (set! call-cont #f)
        (cont 4))))


;;; --- kaappi vendoring: final verdict ---------------------------------
;;; Exit nonzero on any UNEXPECTED failure, and on any known divergence
;;; that no longer diverges (stale entry -- prune it above).
(define resolved-divergences 0)
(for-each (lambda (entry)
            (let ((id (car entry)))
              (when (and (vector-ref executed-tests id)
                         (not (vector-ref diverged-ids id)))
                (set! resolved-divergences (+ resolved-divergences 1))
                (display "DIVERGENCE-RESOLVED ") (display id)
                (display " -- prune it from known-divergences (")
                (display (cdr entry)) (display ")") (newline))))
          known-divergences)
(display "srfi231-official: ")
(display (- total-tests failed-tests divergent-tests)) (display " passed, ")
(display error-string-tests) (display " error-message-only, ")
(display divergent-tests) (display " known divergences, ")
(display failed-tests) (display " unexpected failures, ")
(display resolved-divergences) (display " resolved divergences, out of ")
(display total-tests) (display " evaluations")
(newline)
(exit (if (and (= failed-tests 0) (= resolved-divergences 0)) 0 1))
