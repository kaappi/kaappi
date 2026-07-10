;; Audit tests for src/primitives_ffi.zig — C FFI surface (ffi-open, ffi-fn,
;; ffi-close, ffi-callback, ffi-callback-release, ffi-callback?,
;; ffi-bytevector-ptr) plus the call-time marshaling they route into ffi.zig.
;; Audit campaign Phase 2.13 (#1137). Complements tests/scheme/ffi/ (basic,
;; ranges, bool coercion, use-after-close, callback happy paths) — this file
;; covers the error paths and lifecycle edges those files skip.
;; Run directly and read the printed counts — run-all.sh only sees exit codes.

(import (scheme base) (scheme write))
(import (scheme process-context) (srfi 64))

(test-begin "primitives_ffi audit")

;;; --- ffi-open ---
(define proc-lib (ffi-open #f))          ; default process handle
(test-equal #t (and proc-lib #t))
(test-equal 'caught (guard (e (#t 'caught)) (ffi-open "kaappi-no-such-library-xyz")))
(test-equal 'caught (guard (e (#t 'caught)) (ffi-open 42)))
(test-equal 'caught (guard (e (#t 'caught)) (ffi-open (make-string 300 #\a))))
;; error message carries dlopen detail
(test-equal #t (guard (e (#t (and (error-object? e)
                                  (> (string-length (error-object-message e)) 20))))
                 (ffi-open "kaappi-no-such-library-xyz")
                 #f))

;;; --- ffi-fn creation ---
(define c-getpid (ffi-fn proc-lib "getpid" '() 'int))
(test-equal #t (> (c-getpid) 0))
(test-equal #t (procedure? c-getpid))
;; symbol lookup failure is catchable with a useful message
(test-equal 'caught (guard (e (#t 'caught)) (ffi-fn proc-lib "kaappi_no_such_symbol_xyz" '() 'int)))
;; type list validation
(test-equal 'caught (guard (e (#t 'caught)) (ffi-fn proc-lib "abs" '(integer) 'int)))
(test-equal 'caught (guard (e (#t 'caught)) (ffi-fn proc-lib "abs" '("int") 'int)))
(test-equal 'caught (guard (e (#t 'caught)) (ffi-fn proc-lib "abs" '(int . int) 'int)))
(test-equal 'caught (guard (e (#t 'caught)) (ffi-fn proc-lib "abs" '(int) 'number)))
(test-equal 'caught (guard (e (#t 'caught))
                      (ffi-fn proc-lib "abs"
                              '(int int int int int int int int int
                                int int int int int int int int) 'int)))
(test-equal 'caught (guard (e (#t 'caught)) (ffi-fn 42 "abs" '(int) 'int)))
(test-equal 'caught (guard (e (#t 'caught)) (ffi-fn proc-lib 42 '(int) 'int)))

;;; --- call-time marshaling ---
(define c-strlen (ffi-fn proc-lib "strlen" '(string) 'size_t))
(test-equal 5 (c-strlen "hello"))
(test-equal 0 (c-strlen ""))
(test-equal 2 (c-strlen "λ"))                  ; C strlen counts bytes, not codepoints
(define c-getenv (ffi-fn proc-lib "getenv" '(string) 'string))
(test-equal #t (string? (c-getenv "PATH")))
(test-equal #f (c-getenv "KAAPPI_DEFINITELY_NOT_SET_XYZ_123"))  ; NULL → #f
(define c-tolower (ffi-fn proc-lib "tolower" '(int) 'int))
(test-equal 97 (c-tolower 65))
(test-equal 'caught (guard (e (#t 'caught)) (c-tolower 65.5)))  ; lossy flonum→int rejected
;; sqrt lives in libm, which is not in the process handle's link closure on
;; Linux Release builds (LLVM inlines sqrt, so the binary never references
;; libm) — open it explicitly like tests/scheme/ffi/basic.scm does.
(define math-lib (ffi-open "libm"))
(define c-sqrt (ffi-fn math-lib "sqrt" '(double) 'double))
(test-equal 2.0 (c-sqrt 4.0))
(test-equal 2.0 (c-sqrt 4))                    ; fixnum → double coercion
(test-equal 0.5 (c-sqrt 1/4))                  ; rational → double coercion
(define c-abs (ffi-fn proc-lib "abs" '(int) 'int))
(test-equal 3 (c-abs -3))
;; lossy narrowing is rejected, catchable
(test-equal 'caught (guard (e (#t 'caught)) (c-abs -3.0)))
(test-equal 'caught (guard (e (#t 'caught)) (c-abs "x")))
;; arity mismatch is rejected, catchable
(test-equal 'caught (guard (e (#t 'caught)) (c-sqrt 1.0 2.0)))
(test-equal 'caught (guard (e (#t 'caught)) (c-sqrt)))
;; NUL bytes inside a 'string arg are rejected (cannot round-trip through C)
(test-equal 'caught (guard (e (#t 'caught)) (c-strlen (string #\a #\null #\b))))
;; The char FFI type bridges Scheme characters: char params accept both
;; integers and character values, char returns produce Scheme characters.
(define c-tolower-char (ffi-fn proc-lib "tolower" '(char) 'char))
(test-equal #\a (c-tolower-char 65))            ; fixnum accepted, char returned
(test-equal #\a (c-tolower-char #\A))           ; char accepted, char returned

;;; --- ffi-close lifecycle ---
(test-equal 'ok (let ((lib (ffi-open #f)))
                  (ffi-close lib)
                  (ffi-close lib)              ; double close is a no-op
                  'ok))
(test-equal 'caught (guard (e (#t 'caught))
                      (let ((lib (ffi-open #f)))
                        (ffi-close lib)
                        (ffi-fn lib "getpid" '() 'int))))
(test-equal 'caught (guard (e (#t 'caught)) (ffi-close 42)))

;;; --- ffi-bytevector-ptr ---
(test-equal 0 (ffi-bytevector-ptr (bytevector)))
(test-equal #t (let ((p (ffi-bytevector-ptr (bytevector 1 2 3))))
                 (and (integer? p) (> p 0))))
(test-equal 'caught (guard (e (#t 'caught)) (ffi-bytevector-ptr "abc")))
;; pointer round trip: C writes into the bytevector via memset
(test-equal #u8(65 65 65)
    (let* ((bv (make-bytevector 3 0))
           (c-memset (ffi-fn proc-lib "memset" '(pointer int size_t) 'pointer)))
      (c-memset (ffi-bytevector-ptr bv) 65 3)
      bv))

;;; --- ffi-callback lifecycle ---
(test-equal '(#t #f #f)
    (let ((cb (ffi-callback (lambda (a b) 0) '(pointer pointer) 'int)))
      (let ((r (list (ffi-callback? cb) (ffi-callback? 42) (ffi-callback? "x"))))
        (ffi-callback-release cb)
        r)))
(test-equal 'ok (let ((cb (ffi-callback (lambda () 0) '() 'void)))
                  (ffi-callback-release cb)
                  (ffi-callback-release cb)    ; double release is a no-op
                  'ok))
(test-equal 'caught (guard (e (#t 'caught)) (ffi-callback 42 '() 'void)))
(test-equal 'caught (guard (e (#t 'caught)) (ffi-callback (lambda (x) x) '(double) 'double)))
(test-equal 'caught (guard (e (#t 'caught)) (ffi-callback-release 42)))
;; slot exhaustion at 32, catchable; slots reusable after release
(test-equal '(slots-exhausted 32)
    (let ((cbs '()))
      (let ((r (guard (e (#t 'slots-exhausted))
                 (do ((i 0 (+ i 1))) ((= i 40) 'no-limit)
                   (set! cbs (cons (ffi-callback (lambda () 0) '() 'void) cbs))))))
        (for-each ffi-callback-release cbs)
        (list r (length cbs)))))
(test-equal 'ok (let ((cb (ffi-callback (lambda () 0) '() 'void)))
                  (ffi-callback-release cb)
                  'ok))

;;; --- callbacks invoked from C (qsort) ---
(define c-qsort (ffi-fn proc-lib "qsort" '(pointer long long pointer) 'void))
(test-equal #u8(1 2 3)
    (let* ((bv (bytevector 3 1 2))
           (base (ffi-bytevector-ptr bv))
           (cmp (ffi-callback
                 (lambda (a b)
                   (- (bytevector-u8-ref bv (- a base))
                      (bytevector-u8-ref bv (- b base))))
                 '(pointer pointer) 'int)))
      (c-qsort base 3 1 cmp)
      (ffi-callback-release cmp)
      bv))
;; Errors raised inside a C-invoked callback are stashed by the trampoline
;; and re-raised when the enclosing FFI call returns (#1185).
(test-equal 'caught
    (let* ((bv (bytevector 3 1 2))
           (cmp (ffi-callback (lambda (a b) (error "cb-boom")) '(pointer pointer) 'int))
           (r (guard (e (#t 'caught))
                (c-qsort (ffi-bytevector-ptr bv) 3 1 cmp)
                'no-error)))
      (ffi-callback-release cmp)
      r))
;; the original condition object survives the round trip through C
(test-equal "cb-boom"
    (let* ((bv (bytevector 3 1 2))
           (cmp (ffi-callback (lambda (a b) (error "cb-boom")) '(pointer pointer) 'int))
           (r (guard (e ((error-object? e) (error-object-message e)))
                (c-qsort (ffi-bytevector-ptr bv) 3 1 cmp)
                'no-error)))
      (ffi-callback-release cmp)
      r))
;; a non-integer return where int is declared is an error, not a silent 0
(test-equal 'caught
    (let* ((bv (bytevector 3 1 2))
           (cmp (ffi-callback (lambda (a b) "not-an-int") '(pointer pointer) 'int))
           (r (guard (e (#t 'caught))
                (c-qsort (ffi-bytevector-ptr bv) 3 1 cmp)
                'no-error)))
      (ffi-callback-release cmp)
      r))

(let ((runner (test-runner-current)))
  (test-end "primitives_ffi audit")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
