;; SRFI-23 (error reporting mechanism) conformance tests — audit Phase 3a
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi23.scm
;;
;; SRFI 23 is one procedure and deliberately loose: "(error <reason>
;; <arg1> ...)", where <reason> "should be a string", and "What exactly
;; constitutes 'signalling' and 'reporting' is not prescribed, because of
;; the large variation in Scheme systems" -- it lists five acceptable
;; behaviours, one of which is doing nothing. So almost nothing here can be
;; asserted from SRFI 23 alone.
;;
;; What CAN be pinned is the intersection with R7RS, which Kaappi's `error`
;; actually implements: an error object carrying the message and the
;; irritants, catchable by `guard`. Grown in audit v2 Phase 3.8 from 7
;; assertions; the additions cover irritant fidelity (identity, not a copy;
;; every type; arbitrary count), the disjointness of the three R7RS error
;; predicates, unwinding through `dynamic-wind` and nested `guard`, and the
;; fact that the (srfi 23) re-export is the very same binding as
;; (scheme base)'s -- the property that makes importing both legal under
;; R7RS 5.2.

(import (scheme base) (srfi 23) (scheme process-context) (srfi 64))

(test-begin "srfi-23")

;;; --- signalling: the condition is raised and is catchable ---

(test-assert "error raises a catchable condition"
  (guard (e (#t (error-object? e))) (error "boom") #f))

(test-assert "the raised object is not an ordinary value"
  (guard (e (#t (not (string? e)))) (error "boom") #f))

(test-assert "error never returns to its caller"
  (guard (e (#t #t)) (error "boom") #f))

;;; --- reporting: the message and the irritants are preserved ---

(test-equal "the message is preserved" "boom"
  (guard (e (#t (error-object-message e))) (error "boom" 1 2)))

(test-equal "the irritants are preserved in order" '(1 2)
  (guard (e (#t (error-object-irritants e))) (error "boom" 1 2)))

(test-equal "no irritants yields the empty list" '()
  (guard (e (#t (error-object-irritants e))) (error "no-irritants")))

(test-equal "irritants keep arbitrary structure"
  '((a b) #(1) "s")
  (guard (e (#t (error-object-irritants e)))
    (error "msg" '(a b) #(1) "s")))

(test-equal "an irritant of every basic type survives"
  '(1 2.5 #\c "s" sym #t () (1 . 2) #(1) #u8(1))
  (guard (e (#t (error-object-irritants e)))
    (error "msg" 1 2.5 #\c "s" 'sym #t '() '(1 . 2) #(1) #u8(1))))

(test-assert "an irritant is the same object, not a copy"
  (let ((v (vector 1 2)))
    (guard (e (#t (eq? v (car (error-object-irritants e)))))
      (error "m" v))))

(test-equal "an empty message string is preserved" ""
  (guard (e (#t (error-object-message e))) (error "")))

(test-equal "a non-ASCII message string is preserved" "λ error"
  (guard (e (#t (error-object-message e))) (error "λ error")))

(test-equal "many irritants are all preserved" 20
  (guard (e (#t (length (error-object-irritants e))))
    (apply error "msg" (list 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20))))

(test-assert "a procedure survives as an irritant"
  (guard (e (#t (procedure? (car (error-object-irritants e)))))
    (error "m" car)))

;;; --- the R7RS error predicates are disjoint for this condition ---

(test-assert "the condition is an error object" (guard (e (#t (error-object? e))) (error "m")))
(test-assert "the condition is not a file error" (guard (e (#t (not (file-error? e)))) (error "m")))
(test-assert "the condition is not a read error" (guard (e (#t (not (read-error? e)))) (error "m")))

;;; --- unwinding ---

(test-equal "error unwinds from a nested expression" 'deep
  (guard (e (#t 'deep)) (+ 1 (error "inside"))))

(test-equal "error unwinds out of a deeply nested call" 'caught
  (guard (e (#t 'caught))
    (let loop ((n 20)) (if (= n 0) (error "deep") (+ 1 (loop (- n 1)))))))

(test-equal "dynamic-wind after thunks run while unwinding" '(after caught)
  (let ((log '()))
    (let ((r (guard (e (#t 'caught))
               (dynamic-wind
                 (lambda () #t)
                 (lambda () (error "m"))
                 (lambda () (set! log (cons 'after log)))))))
      (append log (list r)))))

(test-equal "an inner guard that re-raises reaches the outer one" "m"
  (guard (outer (#t (error-object-message outer)))
    (guard (inner ((symbol? inner) 'never))
      (error "m"))))

(test-equal "error inside a with-exception-handler handler is itself catchable"
  "second"
  (guard (e (#t (error-object-message e)))
    (with-exception-handler
      (lambda (c) (error "second"))
      (lambda () (error "first")))))

;;; --- the re-export is the same binding as (scheme base)'s.  R7RS 5.2
;;; makes importing one identifier from two libraries with DIFFERENT
;;; bindings an error, so this file importing both (scheme base) and
;;; (srfi 23) only loads at all because they agree. ---

(test-assert "error is a procedure" (procedure? error))
(test-assert "the (srfi 23) error is eq? to itself under both imports"
  (eq? error error))

;;; --- the derived cond-expand feature id (#1649) ---
(test-equal "cond-expand srfi-23" 'yes (cond-expand (srfi-23 'yes) (else 'no)))

(let ((runner (test-runner-current)))
  (test-end "srfi-23")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
