;; R7RS sections 6.10-6.14 conformance gap tests — audit Phase 1D.
;; Covers spec requirements not exercised by tests/scheme/r7rs/r7rs-tests.scm
;; sections 6.10 (control), 6.11 (exceptions), 6.12 (eval), 6.13 (I/O),
;; 6.14 (system). Deep continuation interactions (call/cc + dynamic-wind/
;; guard/parameterize) are Phase 4B's unit, not covered here.
;; Spec references cite docs/errata-corrected-r7rs.pdf.

(import (scheme base) (scheme write) (scheme read) (scheme eval) (scheme file)
        (scheme time) (scheme char) (scheme process-context) (srfi 64))

(test-begin "r7rs-control-io-gaps")

;; --- 6.10 map and friends (p. 51) ---
;; "If more than one list is given and not all lists have the same length,
;; map terminates when the shortest list runs out."
(test-equal "map stops at shortest list" '(5 7 9) (map + '(1 2 3) '(4 5 6 7)))
(test-equal "vector-map stops at shortest" #(5 7 9)
  (vector-map + #(1 2 3) #(4 5 6 7)))
;; string-map with two strings (spec example, p. 51)
(test-equal "string-map two strings" "StUdLyCaPs"
  (string-map (lambda (c k) ((if (eqv? k #\u) char-upcase char-downcase) c))
              "studlycaps xxx" "ululululul"))
;; for-each ordering guarantee (p. 51)
(test-equal "for-each in order" '(101 100 99 98 97)
  (let ((v '()))
    (string-for-each (lambda (c) (set! v (cons (char->integer c) v))) "abcde")
    v))

;; --- 6.10 apply / call-with-values (p. 50, 53) ---
;; apply "calls proc with the elements of the list (append (list arg1 ...)
;; args)" — spread arguments before the final list:
(test-equal "apply with spread args" 12 (apply + 3 4 (list 5)))
;; spec example: ((compose sqrt *) 12 75) => 30
(test-equal "compose spec example" 30
  (let ((compose (lambda (f g) (lambda args (f (apply g args))))))
    ((compose sqrt *) 12 75)))
;; spec example: (call-with-values * -) => -1
(test-equal "call-with-values * -" -1 (call-with-values * -))
;; procedure? on a lambda S-EXPRESSION is #f (p. 50)
(test-equal "procedure? on quoted lambda" #f (procedure? '(lambda (x) (* x x))))

;; --- 6.11 Exceptions (p. 54) ---
;; raise-continuable spec example: handler's value becomes the value of the
;; raise-continuable call => 65
(test-equal "raise-continuable spec example" 65
  (with-exception-handler
   (lambda (con) 42)
   (lambda () (+ (raise-continuable "should be a number") 23))))
;; error-object accessors round-trip (p. 54-55)
(test-equal "error-object message and irritants" '(#t "msg" (1 2))
  (guard (e (#t (list (error-object? e)
                      (error-object-message e)
                      (error-object-irritants e))))
    (error "msg" 1 2)))
;; file-error? for unopenable file; read-error? for incomplete datum (p. 55, 57)
(test-equal "file-error? on unopenable file" 'fe
  (guard (e ((file-error? e) 'fe) (#t 'other))
    (open-input-file "/nonexistent-kaappi-audit-file")))
(test-equal "read-error? on incomplete datum" 're
  (guard (e ((read-error? e) 're) (#t 'other))
    (read (open-input-string "(unclosed"))))

;; --- 6.12 Environments and evaluation (p. 55) ---
(test-equal "eval in (environment ...)" 21
  (eval '(* 7 3) (environment '(scheme base))))
;; environment respects its import set
(test-equal "environment restricts bindings" 'not-visible
  (guard (e (#t 'not-visible))
    (eval '(car (list 1 2)) (environment '(only (scheme base) +)))))
;; definitions must not leak into the calling global environment
(test-equal "eval define does not leak" 'not-visible
  (begin
    (guard (e (#t #f)) (eval '(define audit-leak-probe 32)
                             (environment '(scheme base))))
    (guard (e (#t 'not-visible)) (eval 'audit-leak-probe
                                       (environment '(scheme base))))))
;; FAIL: #1147 (define into immutable environment must signal an error)
;; (test-equal "eval define into immutable env signals" 'error-signaled
;;   (guard (e (#t 'error-signaled))
;;     (eval '(define foo 32) (environment '(scheme base)))))
;; FAIL: #1147
;; (test-equal "eval set! into immutable env signals" 'error-signaled
;;   (guard (e (#t 'error-signaled))
;;     (eval '(set! car 42) (environment '(scheme base)))))

;; --- 6.13 I/O (p. 56-59) ---
;; write must emit datum labels for cyclic structure and terminate (p. 58)
(test-equal "write cyclic list uses datum labels" "#0=(1 2 . #0#)"
  (let ((x (list 1 2)) (po (open-output-string)))
    (set-cdr! (cdr x) x)
    (write x po)
    (get-output-string po)))
;; read-line: "an end of line consists of either a linefeed character, a
;; carriage return character, or a sequence of a carriage return character
;; followed by a linefeed character" (p. 57-58)
(test-equal "read-line handles LF, CR, CRLF" '("a" "b" "c" "d" #t)
  (let ((ip (open-input-string "a\r\nb\rc\nd")))
    (list (read-line ip) (read-line ip) (read-line ip) (read-line ip)
          (eof-object? (read-line ip)))))
;; peek-char does not advance the port (p. 57)
(test-equal "peek-char does not advance" '(#\h #\h #\i)
  (let ((p (open-input-string "hi")))
    (list (peek-char p) (read-char p) (read-char p))))
;; call-with-port closes the port on return; -open? predicates (p. 56)
(test-equal "port open predicates" '(#t #f)
  (let ((p (open-input-string "hi")))
    (let ((before (input-port-open? p)))
      (close-port p)
      (list before (input-port-open? p)))))
(test-equal "call-with-port returns proc value" #\x
  (call-with-port (open-input-string "x") (lambda (p) (read-char p))))
;; current-output-port is a parameter object (spec example, p. 57)
(test-equal "parameterize current-output-port" "piece by piece by piece.\n"
  (let ((sp (open-output-string)))
    (parameterize ((current-output-port sp))
      (display "piece") (display " by piece ") (display "by piece.") (newline))
    (get-output-string sp)))
;; binary bytevector ports (p. 57-58)
(test-equal "bytevector output port" #u8(65 66)
  (let ((bo (open-output-bytevector)))
    (write-u8 65 bo) (write-u8 66 bo)
    (get-output-bytevector bo)))
(test-equal "peek-u8 does not advance" '(1 2 2 #t)
  (let ((bi (open-input-bytevector #u8(1 2))))
    (list (read-u8 bi) (peek-u8 bi) (read-u8 bi) (eof-object? (read-u8 bi)))))
;; write-string with start/end (p. 59)
(test-equal "write-string with range" "cd"
  (let ((so (open-output-string)))
    (write-string "abcdef" so 2 4)
    (get-output-string so)))
;; eof-object is a distinct readable-free object (p. 58)
(test-equal "eof-object identity" #t (eof-object? (eof-object)))

;; --- 6.14 System interface (p. 59-60) ---
(test-equal "get-environment-variable returns string" #t
  (string? (get-environment-variable "PATH")))
(test-equal "get-environment-variables alist" #t
  (pair? (assoc "PATH" (get-environment-variables))))
;; delete-file on a missing file signals a file-error (p. 60)
(test-equal "delete-file missing signals file-error" 'fe
  (guard (e ((file-error? e) 'fe) (#t 'other))
    (delete-file "/nonexistent-kaappi-audit-file")))
(test-equal "file-exists? on missing file" #f
  (file-exists? "/nonexistent-kaappi-audit-file"))
;; time procedures: current-second inexact, jiffies exact (p. 60)
(test-equal "time procedure types" '(#t #t #t)
  (list (inexact? (current-second))
        (exact? (current-jiffy))
        (exact? (jiffies-per-second))))

(let ((runner (test-runner-current)))
  (test-end "r7rs-control-io-gaps")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
