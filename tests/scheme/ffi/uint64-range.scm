;; Regression test for #794: uint64/size_t arguments in [2^63, 2^64) must
;; not be rejected.  The return direction already handled the full unsigned
;; range; the argument side was forcing values through a signed i64 path.
;;
;; Requires fixtures/libu64test.{dylib,so} — compile with:
;;   zig cc -dynamiclib fixtures/u64test.c -o fixtures/libu64test.dylib  (macOS)
;;   zig cc -shared -fPIC fixtures/u64test.c -o fixtures/libu64test.so   (Linux)

(import (scheme base) (scheme write))

(define pass 0)
(define fail 0)

(define (check name got expected)
  (if (equal? got expected)
      (set! pass (+ pass 1))
      (begin
        (set! fail (+ fail 1))
        (display "FAIL: ") (display name)
        (display " expected ") (write expected)
        (display " got ") (write got)
        (newline))))

(define lib
  (guard (exn (#t #f))
    (ffi-open "./fixtures/libu64test")))

(when (not lib)
  (display "SKIP: libu64test not found (compile fixtures/u64test.c first)")
  (newline))

(when lib
  (let ((echo-u64  (ffi-fn lib "echo_u64"  '(uint64) 'uint64))
        (echo-size (ffi-fn lib "echo_size" '(size_t) 'size_t))
        (check-u64 (ffi-fn lib "check_u64" '(uint64 uint64) 'uint64)))

    ;; Values below 2^63 (should have always worked)
    (check "echo-u64 0" (echo-u64 0) 0)
    (check "echo-u64 42" (echo-u64 42) 42)
    (check "echo-u64 2^62" (echo-u64 (expt 2 62)) (expt 2 62))

    ;; Values in [2^63, 2^64) — the bug range
    (check "echo-u64 2^63" (echo-u64 (expt 2 63)) (expt 2 63))
    (check "echo-u64 2^63+1"
           (echo-u64 (+ (expt 2 63) 1))
           (+ (expt 2 63) 1))
    (check "echo-u64 UINT64_MAX"
           (echo-u64 (- (expt 2 64) 1))
           (- (expt 2 64) 1))

    ;; size_t (same underlying fix)
    (check "echo-size 2^63" (echo-size (expt 2 63)) (expt 2 63))
    (check "echo-size UINT64_MAX"
           (echo-size (- (expt 2 64) 1))
           (- (expt 2 64) 1))

    ;; Round-trip: return value fed back as argument
    (let ((handle (echo-u64 (+ (expt 2 63) 1))))
      (check "round-trip check" (check-u64 handle handle) 1))

    ;; Negative values must still be rejected
    (let ((caught-neg #f))
      (guard (exn (#t (set! caught-neg #t)))
        (echo-u64 -1))
      (check "negative rejected" caught-neg #t))

    ;; Multi-limb bignums (>= 2^64) must still be rejected
    (let ((caught-overflow #f))
      (guard (exn (#t (set! caught-overflow #t)))
        (echo-u64 (expt 2 64)))
      (check "overflow rejected" caught-overflow #t))

    (ffi-close lib))

  (display pass) (display " passed, ") (display fail) (display " failed")
  (newline)
  (when (> fail 0) (error "FFI uint64 range tests failed" fail)))
