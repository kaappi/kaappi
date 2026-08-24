;; SRFI 28 (Basic Format Strings) audit / regression tests.
;;
;; Guards kaappi#2100: `format` walked the format string with a `string-ref`
;; index loop, which is O(n^2) because Kaappi indexes strings by codepoint.
;; The linear (string-port) rewrite must keep every directive byte-identical
;; and handle a large input quickly.

(import (scheme base) (scheme write) (srfi 28))

(define failures 0)

(define (check name got expected)
  (if (equal? got expected)
      (begin (display "ok: ") (display name) (newline))
      (begin
        (set! failures (+ failures 1))
        (display "FAIL: ") (display name) (newline)
        (display "  expected: ") (write expected) (newline)
        (display "  got:      ") (write got) (newline))))

;; --- Directive correctness ------------------------------------------------

;; No directives: literal pass-through.
(check "no-directive" (format "hello world") "hello world")
(check "empty" (format "") "")

;; ~a — display form.
(check "~a string" (format "~a" "hi") "hi")
(check "~a number" (format "~a" 42) "42")
(check "~a list" (format "~a" '(1 2 3)) "(1 2 3)")
(check "~a char" (format "~a" #\x) "x")

;; ~s — write form (strings quoted, chars in #\ notation).
(check "~s string" (format "~s" "hi") "\"hi\"")
(check "~s char" (format "~s" #\x) "#\\x")
(check "~s list" (format "~s" '("a" "b")) "(\"a\" \"b\")")

;; ~% — newline.
(check "~% newline" (format "a~%b") "a\nb")

;; ~~ — literal tilde.
(check "~~ tilde" (format "~~") "~")
(check "~~ in text" (format "a~~b") "a~b")

;; Unknown directive: tilde plus the char, verbatim, no argument consumed.
(check "unknown ~d" (format "~d" ) "~d")
(check "unknown ~q with arg after" (format "~q~a" "X") "~qX")

;; Trailing tilde with no following char: emitted literally.
(check "trailing tilde" (format "end~") "end~")
(check "lone tilde" (format "~") "~")

;; Mixed directives and multiple arguments (order + interleaving).
(check "mixed"
       (format "~a = ~s (~a%)~%" "ratio" "half" 50)
       "ratio = \"half\" (50%)\n")
(check "two args"
       (format "~a and ~a" 1 2)
       "1 and 2")
(check "text around directives"
       (format "[~a]<~s>" 'sym "str")
       "[sym]<\"str\">")

;; Extra objects beyond directives are simply ignored.
(check "extra objects ignored" (format "~a" 1 2 3) "1")

;; --- Large-input regression guard (kaappi#2100) ---------------------------
;;
;; Build a ~50,000-character format string and format it. The old O(n^2)
;; version took seconds on inputs this size; the linear version is well under
;; a second. We assert on the result rather than on timing.

(define big-n 50000)

;; A literal run of 'x' with no directives: output must equal input.
(define big-literal (make-string big-n #\x))
(check "large literal length"
       (string-length (format big-literal))
       big-n)
(check "large literal identity"
       (format big-literal)
       big-literal)

;; A long run containing many ~~ escapes: 25,000 tilde-pairs -> 25,000 tildes.
(define big-tildes
  (let ((p (open-output-string)))
    (let loop ((i 0))
      (if (< i 25000)
          (begin (write-string "~~" p) (loop (+ i 1)))
          (get-output-string p)))))
(check "large tilde-escape length"
       (string-length (format big-tildes))
       25000)

;; A run with interleaved ~a directives (bounded by the 255-argument apply
;; limit) embedded in a long literal body, so the directive path is exercised
;; over a large overall input.
(define big-directives
  (let ((p (open-output-string)))
    (write-string (make-string big-n #\-) p)
    (let loop ((i 0))
      (if (< i 200)
          (begin (write-string "~a" p) (loop (+ i 1)))
          (get-output-string p)))))
(define big-args
  (let loop ((i 0) (acc '()))
    (if (< i 200) (loop (+ i 1) (cons #\z acc)) acc)))
(check "large directives length"
       (string-length (apply format big-directives big-args))
       (+ big-n 200))

;; --- Summary --------------------------------------------------------------

(if (= failures 0)
    (begin (display "ALL PASSED") (newline))
    (begin (display failures) (display " FAILURE(S)") (newline)
           (error "srfi28-audit failed")))
