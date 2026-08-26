;;; Kaappi WASM platform-gate test (kaappi#1972).
;;;
;;; The WASM build compiles out every filesystem entry point, so a handful of
;;; procedures stay registered but cannot do their job. What they report when
;;; called is only checkable here: the gates are `comptime is_wasm` branches,
;;; so a native-suite assertion for them would silently never run.
;;;
;;; All five reported a *type error* until #1972, putting "non-WASM platform"
;;; — not a type — in the "expected type" slot and blaming a valid argument for
;;; the platform. For the three `(scheme file)` procedures that was more than
;;; cosmetic: R7RS says they signal a condition satisfying `file-error?`, which
;;; is what they do on every native target and what portable code guards on, so
;;; the type error fell straight through such a guard on the playground.
;;;
;;; Any FAIL line fails CI.

(import (scheme base) (scheme write) (scheme file))

(define failures 0)
(define (check label ok)
  (display (if ok "PASS " "FAIL "))
  (display label)
  (newline)
  (if (not ok) (set! failures (+ failures 1))))

(define (starts-with? s prefix)
  (and (>= (string-length s) (string-length prefix))
       (string=? (substring s 0 (string-length prefix)) prefix)))

(define (classify thunk)
  (guard (e (#t (list (cond ((file-error? e) 'file-error)
                            ((error-object? e) 'error)
                            (else 'other))
                      (if (error-object? e) (error-object-message e) #f)
                      (if (error-object? e) (error-object-irritants e) #f))))
    (list 'returned (thunk))))

;; --- the three (scheme file) procedures ------------------------------------
;; Same condition their native failure paths raise, so `(file-error? e)` is the
;; one clause a caller needs on every target. The reason rides along in the
;; message and the offending path stays the irritant.

(check "open-input-file signals a file error naming the platform"
       (equal? (classify (lambda () (open-input-file "gate.txt")))
               '(file-error
                 "cannot open input file: this WebAssembly build has no filesystem access"
                 ("gate.txt"))))

(check "open-output-file signals a file error naming the platform"
       (equal? (classify (lambda () (open-output-file "gate.txt")))
               '(file-error
                 "cannot open output file: this WebAssembly build has no filesystem access"
                 ("gate.txt"))))

(check "delete-file signals a file error naming the platform"
       (equal? (classify (lambda () (delete-file "gate.txt")))
               '(file-error
                 "cannot delete file: this WebAssembly build has no filesystem access"
                 ("gate.txt"))))

;; The binary constructors delegate to the textual ones, so they inherit it.
(check "open-binary-input-file inherits the gate"
       (equal? (car (classify (lambda () (open-binary-input-file "gate.txt"))))
               'file-error))
(check "open-binary-output-file inherits the gate"
       (equal? (car (classify (lambda () (open-binary-output-file "gate.txt"))))
               'file-error))

;; The point of the R7RS condition: a portable fallback clause runs here.
(check "a portable (file-error? e) guard catches it"
       (eq? 'fallback
            (guard (e ((file-error? e) 'fallback))
              (open-input-file "gate.txt"))))

;; --- fd->port ---------------------------------------------------------------
;; A Kaappi extension over (kaappi ffi), which has no WASM-viable subset — so,
;; unlike SRFI 18's thread-sleep!, fd->port carries `.wasm = false` like its
;; seven ffi-* siblings and is not registered at all on this target
;; (kaappi#2018). The name genuinely does not exist here, so a reference is an
;; undefined-variable fault, not a global that exists solely to refuse. (A
;; "Did you mean …?" tail may follow, so match the prefix rather than the
;; whole message.)

(check "fd->port is not registered on WASM (undefined, not a refusing global)"
       (let ((c (classify (lambda () (fd->port 5)))))
         (and (eq? (car c) 'error)
              (string? (cadr c))
              (starts-with? (cadr c) "undefined variable 'fd->port'"))))

;; --- controls ---------------------------------------------------------------
;; Without these the fix could have flattened every failure into a file error
;; instead of drawing the distinction.

(check "CONTROL: a non-string argument is still a type error"
       (equal? (classify (lambda () (open-input-file 42)))
               '(error "type error in 'open-input-file': expected string, got 42" ())))

;; file-exists? is the one filesystem procedure with a value to degrade to, so
;; it answers #f rather than raising anything at all — deliberately unlike the
;; three above, and unchanged by #1972.
(check "CONTROL: file-exists? degrades to #f instead of raising"
       (equal? (classify (lambda () (file-exists? "gate.txt")))
               '(returned #f)))

(if (> failures 0)
    (begin (display "PLATFORM GATE TESTS FAILED") (newline) (exit 1))
    (begin (display "all platform gate tests passed") (newline)))
