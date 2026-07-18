;; SRFI-267 (Raw String Syntax) conformance tests.
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi267.scm

(import (scheme base) (srfi 267) (srfi 64))

(test-begin "srfi-267")

;;; --- reader lexical syntax: #"X"..."X" -----------------------------------

;; Empty delimiter; no escape processing (backslashes are literal).
(test-equal "C:\\Users\\me" #""C:\Users\me"")
;; \n inside a raw string is backslash + n — two characters, not a newline.
(test-equal 4 (string-length #""x\ny""))
(test-equal #\\ (string-ref #""x\ny"" 1))
;; A custom delimiter lets the content hold bare double quotes.
(test-equal "he said \"hi\"" #"end"he said "hi""end")
;; Content may embed the delimiter char while the full terminator "xx" is absent.
(test-equal "a\"x\"b" #"xx"a"x"b"xx")
;; A raw string is an ordinary string value.
(test-equal "<>![]" (string-append #""<>"" "!" #""[]""))
;; Newlines are preserved verbatim.
(test-equal "line1\nline2" #"|"line1
line2"|")
;; Empty content.
(test-equal "" #"""")

;;; --- can-delimit? --------------------------------------------------------

(test-assert (can-delimit? "hello" ""))          ; no quotes at all
(test-assert (not (can-delimit? "a\"\"b" "")))   ; contains ""
(test-assert (not (can-delimit? "ends\"" "")))   ; ends with "
(test-assert (not (can-delimit? "a\"x\"b" "x"))) ; contains "x"
(test-assert (can-delimit? "a\"x\"b" "xx"))      ; "xx" is absent
(test-assert (not (can-delimit? "x" "\"")))      ; delimiter itself has a "
(test-assert (can-delimit? "" ""))               ; empty string, empty delimiter

;;; --- generate-delimiter --------------------------------------------------
;;; Contract: (can-delimit? s (generate-delimiter s)) holds for every s.

(define (gen-ok? s) (can-delimit? s (generate-delimiter s)))
(test-assert (gen-ok? "plain"))
(test-assert (gen-ok? "has \"quotes\""))
(test-assert (gen-ok? "trailing quote\""))
(test-assert (gen-ok? ""))
(test-assert (gen-ok? "=\"==\"===\""))
(test-assert (gen-ok? "\"\"\"\""))
(test-assert (gen-ok? "a\"\"===b"))    ; adjacent quotes force the =-run path
(test-assert (gen-ok? "café\""))       ; UTF-8 content ending in a quote

;;; --- read-raw-string / read-raw-string-after-prefix ----------------------

(define (read-rs str) (read-raw-string (open-input-string str)))
(test-equal "abc" (read-rs "#\"\"abc\"\""))
(test-equal "he said \"hi\"" (read-rs "#\"end\"he said \"hi\"\"end\""))
;; read-raw-string-after-prefix starts reading past the #" prefix.
(test-equal "body"
            (read-raw-string-after-prefix (open-input-string "e\"body\"e\"")))
;; read-raw-string leaves the port positioned right after the terminator.
(let ((p (open-input-string "#\"\"first\"\" rest")))
  (test-equal "first" (read-raw-string p))
  (test-equal #\space (read-char p))
  (test-equal #\r (read-char p)))

;;; --- write-raw-string ----------------------------------------------------

(define (write-rs s d)
  (let ((out (open-output-string)))
    (write-raw-string s d out)
    (get-output-string out)))
(test-equal "#\"\"abc\"\"" (write-rs "abc" ""))
(test-equal "#\"z\"say \"hi\"\"z\"" (write-rs "say \"hi\"" "z"))
;; write-then-read is the identity when the delimiter is valid.
(test-equal "any \"content\" here"
            (read-rs (write-rs "any \"content\" here"
                               (generate-delimiter "any \"content\" here"))))

;;; --- error predicates ----------------------------------------------------

(test-equal 'write-err
  (guard (e ((raw-string-write-error? e) 'write-err) (else 'other))
    (write-raw-string "a\"x\"b" "x")))   ; x cannot delimit a"x"b
(test-equal 'read-err
  (guard (e ((raw-string-read-error? e) 'read-err) (else 'other))
    (read-rs "not a raw string")))       ; missing #" prefix
(test-equal 'read-err
  (guard (e ((raw-string-read-error? e) 'read-err) (else 'other))
    (read-rs "#\"\"unterminated")))      ; eof before terminator
;; The two error condition types are distinct.
(test-assert
  (guard (e ((raw-string-read-error? e) (not (raw-string-write-error? e)))
            (else #f))
    (read-rs "bad")))

;;; --- optional-port arity -------------------------------------------------
;;; The SRFI signatures take a fixed [port]; surplus arguments are an error.

(test-assert
  (guard (e (#t #t))
    (read-raw-string (open-input-string "#\"\"x\"\"") (current-input-port))
    #f))
(test-assert
  (guard (e (#t #t))
    (read-raw-string-after-prefix (open-input-string "\"x\"") (current-input-port))
    #f))
(test-assert
  (guard (e (#t #t))
    (write-raw-string "x" "" (open-output-string) (open-output-string))
    #f))
;; A single port argument is still accepted.
(test-equal "x" (read-raw-string (open-input-string "#\"\"x\"\"")))

(let ((runner (test-runner-current)))
  (test-end "srfi-267")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
