;; SRFI 231 (Intervals and Generalized Arrays) tests -- phase 2: the core
;; array object. Views/sharing, combinators, and multi-array assembly are
;; later phases of this multi-slice SRFI, tracked under issue #1694;
;; (srfi 231) itself is not yet an importable bare library.
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi231-arrays.scm

(import (scheme base) (scheme process-context) (srfi 64)
        (srfi 231 intervals) (srfi 231 storage-classes) (srfi 231 arrays))

(test-begin "srfi-231-arrays")

;;; --- a plain (non-specialized) immutable array via closure ---
(let ((ident (make-array (make-interval (vector 3 3))
                          (lambda (i j) (if (= i j) 1 0)))))
  (test-equal #t (array? ident))
  (test-equal #f (mutable-array? ident))
  (test-equal #f (specialized-array? ident))
  (test-equal 1 (array-ref ident 0 0))
  (test-equal 0 (array-ref ident 0 1))
  (test-equal 1 (array-ref ident 1 1))
  (test-equal 2 (array-dimension ident))
  (test-equal #f (array-empty? ident))
  (test-equal #t (guard (e (#t #t)) (array-setter ident) #f))
  (test-equal #t (guard (e (#t #t)) (array-body ident) #f)))

;;; --- make-array validates its arguments ---
(test-equal #t (guard (e (#t #t)) (make-array "not an interval" (lambda () 1)) #f))
(test-equal #t (guard (e (#t #t)) (make-array (make-interval (vector 1)) "not a procedure") #f))

;;; --- a plain MUTABLE array via closures (sparse-style, matching the
;;; spec's own illustrative example shape) -- mutable but not specialized ---
(let* ((store (make-vector 9 0))
       (sparse (make-array (make-interval (vector 3 3))
                            (lambda (i j) (vector-ref store (+ (* i 3) j)))
                            (lambda (v i j) (vector-set! store (+ (* i 3) j) v)))))
  (test-equal #t (mutable-array? sparse))
  (test-equal #f (specialized-array? sparse))
  (array-set! sparse 'hello 1 2)
  (test-equal 'hello (array-ref sparse 1 2))
  ;; array-freeze! mutates the array in place, removing its setter
  (test-equal sparse (array-freeze! sparse))
  (test-equal #f (mutable-array? sparse))
  (test-equal 'hello (array-ref sparse 1 2)))

;;; --- array-freeze! rejects a non-array ---
(test-equal #t (guard (e (#t #t)) (array-freeze! 42) #f))

;;; --- make-specialized-array: arbitrary (including negative) lower
;;; bounds, both array? and mutable-array? and specialized-array? true ---
(let ((sa (make-specialized-array (make-interval (vector -2 -2) (vector 2 2)) s8-storage-class)))
  (test-equal #t (array? sa))
  (test-equal #t (mutable-array? sa))
  (test-equal #t (specialized-array? sa))
  (array-set! sa 42 -2 -2)
  (array-set! sa -1 1 1)
  (test-equal 42 (array-ref sa -2 -2))
  (test-equal -1 (array-ref sa 1 1))
  (test-equal 0 (array-ref sa 0 0))  ;; untouched cell reads the storage class's default
  (test-equal #t (eq? (array-storage-class sa) s8-storage-class))
  (test-equal #t (array-packed? sa))
  (test-equal #f (array-safe? sa))  ;; specialized-array-default-safe? defaults to #f
  ;; even in unsafe mode, the underlying storage class's own setter still
  ;; enforces its element-type range (Kaappi's numeric vectors are always
  ;; internally checked; "unsafe" only skips the array-level domain check)
  (test-equal #t (guard (e (#t #t)) (array-set! sa 999 -2 -2) #f)))

;;; --- make-specialized-array's optional arguments: storage-class,
;;; initial-value, safe? ---
(let ((safe-sa (make-specialized-array (make-interval (vector 3 3)) generic-storage-class 'x #t)))
  (test-equal #t (array-safe? safe-sa))
  (test-equal 'x (array-ref safe-sa 0 0))  ;; initial-value fills every cell
  (test-equal #t (guard (e (#t #t)) (array-ref safe-sa 5 5) #f))  ;; out-of-domain rejected explicitly
  (test-equal #t (guard (e (#t #t)) (array-set! safe-sa 'y 5 5) #f)))

;;; --- make-specialized-array validates its interval argument ---
(test-equal #t (guard (e (#t #t)) (make-specialized-array "not an interval") #f))

;;; --- make-specialized-array-from-data: zero-copy wrap of existing data ---
(let* ((existing (vector 'a 'b 'c 'd))
       (wrapped (make-specialized-array-from-data existing generic-storage-class)))
  (test-equal 1 (array-dimension wrapped))
  (test-equal 'a (array-ref wrapped 0))
  (test-equal 'd (array-ref wrapped 3))
  (array-set! wrapped 'z 1)
  ;; writing through the array mutates the ORIGINAL vector -- true sharing,
  ;; not a copy
  (test-equal 'z (vector-ref existing 1))
  (test-equal #t (eq? (array-body wrapped) existing)))

;; mutable? = #f produces an immutable wrapped array
(test-equal #f (mutable-array? (make-specialized-array-from-data (vector 1 2 3) generic-storage-class #f)))

;; data incompatible with the given storage-class is rejected
(test-equal #t (guard (e (#t #t))
                  (make-specialized-array-from-data "a string" s8-storage-class) #f))

;;; --- specialized-array-default-safe?/mutable? are genuine SRFI 39
;;; parameters, honored by make-specialized-array when safe?/... omitted ---
(test-equal #f (specialized-array-default-safe?))
(test-equal #t (specialized-array-default-mutable?))
(parameterize ((specialized-array-default-safe? #t))
  (test-equal #t (array-safe? (make-specialized-array (make-interval (vector 2 2))))))
;; parameterize doesn't leak past its dynamic extent
(test-equal #f (specialized-array-default-safe?))

;;; --- array-body/indexer/storage-class/safe?/packed? all reject a
;;; non-specialized array ---
(let ((plain (make-array (make-interval (vector 2)) (lambda (i) i))))
  (test-equal #t (guard (e (#t #t)) (array-body plain) #f))
  (test-equal #t (guard (e (#t #t)) (array-indexer plain) #f))
  (test-equal #t (guard (e (#t #t)) (array-storage-class plain) #f))
  (test-equal #t (guard (e (#t #t)) (array-safe? plain) #f))
  (test-equal #t (guard (e (#t #t)) (array-packed? plain) #f)))

;;; --- zero-dimensional arrays: a single element, accessed with an empty
;;; multi-index (a thunk call) ---
(let ((z (make-array (make-interval (vector)) (lambda () 42))))
  (test-equal 0 (array-dimension z))
  (test-equal #f (array-empty? z))  ;; per spec, a 0-dim interval is never empty
  (test-equal 42 (array-ref z)))

(let ((zs (make-specialized-array (make-interval (vector)) s8-storage-class 7)))
  (test-equal 0 (array-dimension zs))
  (test-equal 7 (array-ref zs))
  (array-set! zs 9)
  (test-equal 9 (array-ref zs))
  (test-equal #t (array-packed? zs)))

;;; --- empty-domain arrays (some axis has lower = upper): array-empty? is
;;; #t, and no multi-index can ever be valid since that axis's range is
;;; unsatisfiable, so any access is rejected -- via the explicit domain
;;; check in safe mode, and via the storage layer's own bounds check on
;;; the resulting zero-length body in unsafe mode ---
(let ((e (make-interval (vector 3 3) (vector 3 5))))
  (test-equal #t (interval-empty? e))
  (let ((ea (make-specialized-array e s8-storage-class)))
    (test-equal #t (array-empty? ea))
    (test-equal 0 (interval-volume (array-domain ea)))
    (test-equal #t (guard (exn (#t #t)) (array-ref ea 3 3) #f))
    (test-equal #t (guard (exn (#t #t)) (array-set! ea 1 3 3) #f)))
  (let ((safe-ea (make-specialized-array e s8-storage-class 0 #t)))
    (test-equal #t (guard (exn (#t #t)) (array-ref safe-ea 3 3) #f))))

(let ((runner (test-runner-current)))
  (test-end "srfi-231-arrays")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
