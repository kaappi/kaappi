;; Regression test for #1187: FFI call-time errors carry descriptive messages
(import (scheme base) (scheme write) (scheme process-context) (srfi 64))

(test-begin "ffi-error-messages")

(define lib (ffi-open #f))
(define c-abs (ffi-fn lib "abs" '(int) 'int))
(define c-strlen (ffi-fn lib "strlen" '(string) 'size_t))

;; Wrong argument type: flonum for int
(test-assert "type error names function and expected type"
  (guard (e (#t (let ((msg (error-object-message e)))
                  (and (string-contains msg "abs")
                       (string-contains msg "int")))))
    (c-abs -3.0)
    #f))

;; Wrong argument type: string for int
(test-assert "type error names actual type"
  (guard (e (#t (let ((msg (error-object-message e)))
                  (and (string-contains msg "abs")
                       (string-contains msg "string")))))
    (c-abs "x")
    #f))

;; Arity mismatch: too many arguments (use abs from libc, always available)
(test-assert "arity mismatch names function and counts"
  (guard (e (#t (let ((msg (error-object-message e)))
                  (and (string-contains msg "abs")
                       (string-contains msg "expected")
                       (string-contains msg "got")))))
    (c-abs 1 2)
    #f))

;; NUL byte in string argument
(test-assert "NUL-in-string error names function"
  (guard (e (#t (let ((msg (error-object-message e)))
                  (and (string-contains msg "strlen")
                       (string-contains msg "NUL")))))
    (c-strlen (string #\a #\null #\b))
    #f))

;; Closed library
(test-assert "closed library error names function"
  (let ((lib2 (ffi-open #f)))
    (let ((c-abs2 (ffi-fn lib2 "abs" '(int) 'int)))
      (ffi-close lib2)
      (guard (e (#t (let ((msg (error-object-message e)))
                      (and (string-contains msg "abs")
                           (string-contains msg "closed")))))
        (c-abs2 42)
        #f))))

;; Integer out of range for int parameter
(test-assert "out-of-range integer error names function"
  (guard (e (#t (let ((msg (error-object-message e)))
                  (and (string-contains msg "abs")
                       (string-contains msg "range")))))
    (c-abs (expt 2 40))
    #f))

;; kaappi#2026: an out-of-range FFI argument is a wrong *magnitude*, not a
;; wrong *type*, so it must carry KP3007 (invalid argument) while a genuine
;; type mismatch stays KP3002. Message text alone cannot tell them apart
;; (both name the function); `error-object-code` is the control a caller
;; recovers on. The FFI marshalling path used to collapse both to KP3002.
(test-equal "out-of-range int argument is KP3007, not KP3002"
  'KP3007
  (guard (e (#t (error-object-code e)))
    (c-abs (expt 2 40))
    'no-error))

(test-equal "wrong-type argument stays KP3002"
  'KP3002
  (guard (e (#t (error-object-code e)))
    (c-abs "x")
    'no-error))

;; The narrow-integer range checks (int8/uint8/… ) reclassify too.
(let ((c-abs-i8 (ffi-fn lib "abs" '(int8) 'int)))
  (test-equal "narrow int8 out-of-range is KP3007"
    'KP3007
    (guard (e (#t (error-object-code e)))
      (c-abs-i8 200)
      'no-error))
  (test-equal "narrow int8 wrong-type stays KP3002"
    'KP3002
    (guard (e (#t (error-object-code e)))
      (c-abs-i8 "x")
      'no-error)))

;; kaappi#1880: one FFI failure, four dispatch sites. `callFfi` is reached from
;; four places -- callValue and callWithArgs in vm_calls.zig, and the tail-call
;; and tail-apply opcodes in vm_dispatch.zig -- and until #1880 only the first
;; two supplied a fallback message when callFfi returned without setting one.
;; The four forms below are chosen because each reaches a DIFFERENT one of
;; those sites: the tail-position pair is what a non-tail call never reaches,
;; so a check built from direct/apply/map alone leaves both hot sites untested.
(define (ffi-error-message thunk)
  (guard (e (#t (error-object-message e)))
    (thunk)
    "no error raised"))

(define (tail-call x) (c-abs x))                       ; vm_dispatch: tail call
(define (tail-apply x) (apply c-abs (list x)))         ; vm_dispatch: tail apply
(define (nontail-call x) (+ 0 (c-abs x)))              ; vm_calls: callValue
(define (nontail-apply x) (+ 0 (apply c-abs (list x)))) ; vm_calls: callWithArgs

(define site-messages
  (map (lambda (f) (ffi-error-message (lambda () (f -3.0))))
       (list tail-call tail-apply nontail-call nontail-apply)))

(test-assert "the same FFI error reports identically through all four dispatch sites"
  (let ((first (car site-messages)))
    (and (string-contains first "abs")
         (let loop ((rest (cdr site-messages)))
           (cond ((null? rest) #t)
                 ((string=? (car rest) first) (loop (cdr rest)))
                 (else #f))))))

(let ((runner (test-runner-current)))
  (test-end "ffi-error-messages")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
