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

;; (srfi 192) is importable by name on WASM (kaappi#2019): all four of its
;; procedures already worked here via the vm.globals fallback, but the library
;; was wrongly excluded from `wasmAvailable`, so import-by-name and the derived
;; `cond-expand` feature id disagreed with the procedures. Importing it in this
;; file's own import set is itself the positive test -- if the exclusion came
;; back, this whole file would fail to load on WASM.
(import (scheme base) (scheme write) (scheme file) (srfi 192))

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

;; --- (srfi 192) on WASM (kaappi#2019) --------------------------------------
;; The import above already proves import-by-name works. Here we confirm the
;; two cond-expand probes agree with it, and that the string-port half of the
;; library actually works on this target. The fd-backed half is out of reach on
;; WASM (open-input-file and fd->port are gated), so coverage is string-port
;; only -- the honest scope, not a gap.

(check "srfi-192 cond-expand feature id is present on WASM"
       (eq? 'ok (cond-expand (srfi-192 'ok) (else 'MISSING))))

(check "(library (srfi 192)) cond-expand probe agrees on WASM"
       (eq? 'ok (cond-expand ((library (srfi 192)) 'ok) (else 'MISSING))))

(check "port-position works on a string input port"
       (let ((ip (open-input-string "abcd")))
         (and (= (port-position ip) 0)
              (begin (read-char ip) (= (port-position ip) 1)))))

(check "port-has-port-position? is #t for a string input port"
       (port-has-port-position? (open-input-string "abc")))

(check "set-port-position! repositions a string input port"
       (let ((ip (open-input-string "abcd")))
         (set-port-position! ip 3)
         (eqv? (read-char ip) #\d)))

(if (> failures 0)
    (begin (display "PLATFORM GATE TESTS FAILED") (newline) (exit 1))
    (begin (display "all platform gate tests passed") (newline)))
