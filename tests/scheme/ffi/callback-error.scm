;; Regression test for #1185: errors raised inside FFI callbacks were
;; silently swallowed. The trampoline set vm.last_callback_error but nothing
;; read it, so the callback returned garbage to C and the FFI call
;; "succeeded". Now the trampoline stashes the exception and callFfi
;; re-raises it when the enclosing FFI call returns. Non-integer returns
;; from int-declared callbacks were coerced to 0 with the same silence and
;; now raise too.

(import (scheme base) (scheme write) (scheme process-context) (srfi 64))

(test-begin "ffi-callback-errors")

(define lib (ffi-open #f))
;; qsort's true signature: void qsort(void *, size_t, size_t, cmp).
;; size_t (not long) matters on Windows, where long is only 32 bits.
(define c-qsort (ffi-fn lib "qsort" '(pointer size_t size_t pointer) 'void))

;; --- (error ...) inside a callback is catchable at the FFI call site ---

(test-equal "error in callback reaches guard" 'caught
  (let* ((bv (bytevector 3 1 2))
         (cmp (ffi-callback (lambda (a b) (error "cb-boom")) '(pointer pointer) 'int))
         (r (guard (e (#t 'caught))
              (c-qsort (ffi-bytevector-ptr bv) 3 1 cmp)
              'no-error)))
    (ffi-callback-release cmp)
    r))

;; --- the condition object survives the round trip through C ---

(test-equal "error object and message preserved" '(#t "cb-boom")
  (let* ((bv (bytevector 3 1 2))
         (cmp (ffi-callback (lambda (a b) (error "cb-boom")) '(pointer pointer) 'int))
         (r (guard (e (#t (list (error-object? e)
                                (and (error-object? e) (error-object-message e)))))
              (c-qsort (ffi-bytevector-ptr bv) 3 1 cmp)
              'no-error)))
    (ffi-callback-release cmp)
    r))

;; --- raise of a non-condition payload is preserved ---

(test-equal "raised symbol preserved" 'my-payload
  (let* ((bv (bytevector 3 1 2))
         (cmp (ffi-callback (lambda (a b) (raise 'my-payload)) '(pointer pointer) 'int))
         (r (guard (e (#t e))
              (c-qsort (ffi-bytevector-ptr bv) 3 1 cmp)
              'no-error)))
    (ffi-callback-release cmp)
    r))

;; --- VM-level errors (not raise) inside the callback also surface ---

(test-equal "type error in callback reaches guard" 'caught
  (let* ((bv (bytevector 3 1 2))
         (cmp (ffi-callback (lambda (a b) (car 42)) '(pointer pointer) 'int))
         (r (guard (e (#t 'caught))
              (c-qsort (ffi-bytevector-ptr bv) 3 1 cmp)
              'no-error)))
    (ffi-callback-release cmp)
    r))

;; --- non-integer / out-of-range returns for an int signature raise ---

(test-equal "string return from int callback raises" 'caught
  (let* ((bv (bytevector 3 1 2))
         (cmp (ffi-callback (lambda (a b) "not-an-int") '(pointer pointer) 'int))
         (r (guard (e (#t 'caught))
              (c-qsort (ffi-bytevector-ptr bv) 3 1 cmp)
              'no-error)))
    (ffi-callback-release cmp)
    r))

(test-equal "out-of-range return from int callback raises" 'caught
  (let* ((bv (bytevector 3 1 2))
         (cmp (ffi-callback (lambda (a b) 4294967296) '(pointer pointer) 'int))
         (r (guard (e (#t 'caught))
              (c-qsort (ffi-bytevector-ptr bv) 3 1 cmp)
              'no-error)))
    (ffi-callback-release cmp)
    r))

;; --- the error state is consumed: later FFI calls are unaffected ---

(test-equal "clean call after caught callback error" #u8(1 2 3)
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

(ffi-close lib)

(let ((runner (test-runner-current)))
  (test-end "ffi-callback-errors")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
