;; SRFI-180 (JSON) conformance tests.
;; Run directly: zig-out/bin/kaappi --lib-path lib tests/scheme/srfi/srfi180.scm

(import (scheme base) (scheme write) (scheme process-context) (srfi 180) (srfi 64))

(test-begin "srfi-180")

;; Small helpers used throughout.
(define (read-str s) (json-read (open-input-string s)))
(define (write-str obj)
  (let ((out (open-output-string)))
    (json-write obj out)
    (get-output-string out)))
(define (json-err? thunk)
  (guard (e ((json-error? e) 'json-error) (else 'other-error))
    (thunk)
    'no-error))

;;; --- scalars: numbers ------------------------------------------------

(test-equal 0 (read-str "0"))
(test-equal 42 (read-str "42"))
(test-equal -42 (read-str "-42"))
(test-equal -0.0 (read-str "-0.0"))
(test-equal 3.14159 (read-str "3.14159"))
(test-equal 1e10 (read-str "1e10"))
(test-equal 1.5e-10 (read-str "1.5E-10"))
(test-equal 100.0 (read-str "1e2"))
(test-assert (exact? (read-str "100")))
(test-assert (not (exact? (read-str "1e2"))))
(test-assert (exact? (read-str "123456789012345678901234567890")))
(test-equal 123456789012345678901234567890 (read-str "123456789012345678901234567890"))
(test-assert (not (exact? (read-str "2.0"))))
(test-assert (exact? (read-str "2")))

;;; --- scalars: strings, booleans, null ---------------------------------

(test-equal "hello" (read-str "\"hello\""))
(test-equal "" (read-str "\"\""))
(test-equal #t (read-str "true"))
(test-equal #f (read-str "false"))
(test-equal 'null (read-str "null"))
(test-assert (json-null? (read-str "null")))
(test-assert (not (json-null? 'not-null)))
(test-assert (not (json-null? #f)))

;;; --- string escapes ----------------------------------------------------

(test-equal "a\"b" (read-str "\"a\\\"b\""))
(test-equal "a\\b" (read-str "\"a\\\\b\""))
(test-equal "a/b" (read-str "\"a\\/b\""))
(test-equal "a/b" (read-str "\"a/b\""))       ; unescaped '/' is also valid
(test-equal "\b" (read-str "\"\\b\""))
(test-equal "\t" (read-str "\"\\t\""))
(test-equal "\n" (read-str "\"\\n\""))
(test-equal "\r" (read-str "\"\\r\""))
(test-equal (string (integer->char #x0c)) (read-str "\"\\f\""))
(test-equal "A" (read-str "\"\\u0041\""))
(test-equal "Aé" (read-str "\"\\u0041\\u00e9\""))
;; astral character via UTF-16 surrogate pair (U+1F600 GRINNING FACE)
(test-equal (string (integer->char #x1F600)) (read-str "\"\\ud83d\\ude00\""))
(test-equal 1 (string-length (read-str "\"\\ud83d\\ude00\"")))

;; unescaped control characters are rejected (RFC 8259)
(test-equal 'json-error (json-err? (lambda () (read-str "\"a\tb\""))))
(test-equal 'json-error (json-err? (lambda () (read-str (string #\" #\a (integer->char 1) #\b #\")))))
;; but the escaped form is fine
(test-equal "a\tb" (read-str "\"a\\tb\""))
;; unknown escape / invalid \u / unpaired surrogate
(test-equal 'json-error (json-err? (lambda () (read-str "\"\\x\""))))
(test-equal 'json-error (json-err? (lambda () (read-str "\"\\u12\""))))
(test-equal 'json-error (json-err? (lambda () (read-str "\"\\ud800\""))))   ; unpaired high
(test-equal 'json-error (json-err? (lambda () (read-str "\"\\udc00\""))))  ; unpaired low

;;; --- arrays --------------------------------------------------------

(test-equal #() (read-str "[]"))
(test-equal #(1 2 3) (read-str "[1,2,3]"))
(test-equal #(1 2 3) (read-str "  [ 1 , 2 , 3 ]  "))
(test-equal #(#(1 2) #(3 4)) (read-str "[[1,2],[3,4]]"))
(test-equal #(1 "two" #t #f null) (read-str "[1,\"two\",true,false,null]"))

;;; --- objects ---------------------------------------------------------

(test-equal '() (read-str "{}"))
(test-equal '((a . 1)) (read-str "{\"a\":1}"))
(test-equal '((a . 1) (b . 2)) (read-str "{\"a\":1,\"b\":2}"))
(test-equal '((a . 1) (b . #(2 3))) (read-str "{\"a\":1,\"b\":[2,3]}"))
(test-equal '((outer . ((inner . 1)))) (read-str "{\"outer\":{\"inner\":1}}"))
;; keys map to symbols
(test-assert (symbol? (car (car (read-str "{\"a\":1}")))))

;; duplicate keys: spec is silent; both entries are preserved in order,
;; and assq/assoc naturally resolve to the first.
(test-equal '((a . 1) (a . 2)) (read-str "{\"a\":1,\"a\":2}"))
(test-equal 1 (cdr (assq 'a (read-str "{\"a\":1,\"a\":2}"))))

;;; --- whitespace ------------------------------------------------------

(test-equal #(1 2) (read-str "\t\n\r [1,\r\n 2]\t "))

;;; --- malformed JSON: json-error? / json-error-reason ------------------

(test-equal 'json-error (json-err? (lambda () (read-str "{bad json"))))
(test-equal 'json-error (json-err? (lambda () (read-str "\"abc"))))          ; unterminated string
(test-equal 'json-error (json-err? (lambda () (read-str "[1,2"))))            ; unterminated array
(test-equal 'json-error (json-err? (lambda () (read-str "{\"a\":1"))))        ; unterminated object
(test-equal 'json-error (json-err? (lambda () (read-str "tru"))))             ; bad literal
(test-equal 'json-error (json-err? (lambda () (read-str "[1,2,]"))))          ; trailing comma
(test-equal 'json-error (json-err? (lambda () (read-str "{\"a\":1,}"))))      ; trailing comma
(test-equal 'json-error (json-err? (lambda () (read-str "[01]"))))            ; leading zero
(test-equal 'json-error (json-err? (lambda () (read-str "[1.]"))))            ; no digit after '.'
(test-equal 'json-error (json-err? (lambda () (read-str "[1e]"))))            ; no digit in exponent
(test-equal 'json-error (json-err? (lambda () (read-str "{1:2}"))))           ; non-string key
(test-equal 'json-error (json-err? (lambda () (read-str "{\"a\" 1}"))))       ; missing ':'

;; json-error-reason is a human-readable string
(test-assert
  (guard (e ((json-error? e) (string? (json-error-reason e))) (else #f))
    (read-str "nope")))

;;; --- json-write: type validation --------------------------------------

(test-equal "42" (write-str 42))
(test-equal "true" (write-str #t))
(test-equal "false" (write-str #f))
(test-equal "null" (write-str 'null))
(test-equal "\"hi\"" (write-str "hi"))
(test-equal "[]" (write-str (vector)))
(test-equal "{}" (write-str '()))
(test-equal "[1,2,3]" (write-str (vector 1 2 3)))
(test-equal "{\"a\":1,\"b\":[2,3]}" (write-str (list (cons 'a 1) (cons 'b (vector 2 3)))))
(test-equal "{\"x\":1,\"y\":\"s\",\"z\":{\"w\":true}}"
  (write-str (list (cons 'x 1) (cons 'y "s") (cons 'z (list (cons 'w #t))))))

;; only integers or finite non-NaN inexact reals are valid JSON numbers
(test-equal 'json-error (json-err? (lambda () (json-write 1/2))))            ; exact non-integer rational
(test-equal 'json-error (json-err? (lambda () (json-write (make-rectangular 1 2))))) ; complex
(test-equal 'json-error (json-err? (lambda () (json-write +inf.0))))
(test-equal 'json-error (json-err? (lambda () (json-write -inf.0))))
(test-equal 'json-error (json-err? (lambda () (json-write +nan.0))))
;; non-alist list, and alist with a non-symbol key, are rejected
(test-equal 'json-error (json-err? (lambda () (json-write (list 1 2 3)))))
(test-equal 'json-error (json-err? (lambda () (json-write (list (cons "a" 1))))))
;; a bad value nested deep inside an otherwise-valid structure is still caught
;; up front, before anything is written.
(test-equal 'json-error (json-err? (lambda () (json-write (vector 1 (list (cons 'a 1/2)))))))

;;; --- json-write: string escaping ---------------------------------------

(test-equal "\"a\\\"b\"" (write-str "a\"b"))
(test-equal "\"a\\\\b\"" (write-str "a\\b"))
(test-equal "\"a\\tb\"" (write-str "a\tb"))
(test-equal "\"a\\nb\"" (write-str "a\nb"))
(test-equal "\"\\u0001\"" (write-str (string (integer->char 1))))
;; non-ASCII text is written as literal UTF-8, which is valid JSON.
(test-equal "\"café\"" (write-str "café"))

;;; --- round trip: write then read ----------------------------------------

(define (round-trip obj) (read-str (write-str obj)))

(test-equal 42 (round-trip 42))
(test-equal -7 (round-trip -7))
(test-equal 3.5 (round-trip 3.5))
(test-equal "hello world" (round-trip "hello world"))
(test-equal #t (round-trip #t))
(test-equal #f (round-trip #f))
(test-equal 'null (round-trip 'null))
(test-equal #(1 2 3) (round-trip (vector 1 2 3)))
(test-equal '((a . 1) (b . 2)) (round-trip (list (cons 'a 1) (cons 'b 2))))
(test-equal (vector 1 (list (cons 'a "x") (cons 'b (vector 2 3))) "tail")
            (round-trip (vector 1 (list (cons 'a "x") (cons 'b (vector 2 3))) "tail")))
(test-equal "special \"chars\"\n\t\\ and unicode: café 😀"
            (round-trip "special \"chars\"\n\t\\ and unicode: café 😀"))
;; exactness survives a round trip
(test-assert (exact? (round-trip 5)))
(test-assert (not (exact? (round-trip 5.0))))

;;; --- repeated top-level reads on one port (R7RS `read`-like) ------------

(let ((p (open-input-string "1 [2,3]   \"x\"  ")))
  (test-equal 1 (json-read p))
  (test-equal #(2 3) (json-read p))
  (test-equal "x" (json-read p))
  (test-assert (eof-object? (json-read p))))

;;; --- json-generator: raw event stream -----------------------------------

(define (drain-generator gen)
  (let loop ((acc '()))
    (let ((v (gen)))
      (if (eof-object? v)
          (reverse acc)
          (loop (cons v acc))))))

(test-equal '(array-start 1 "x" #t array-end)
            (drain-generator (json-generator (open-input-string "[1,\"x\",true]"))))
(test-equal '(object-start "a" 1 "b" 2 object-end)
            (drain-generator (json-generator (open-input-string "{\"a\":1,\"b\":2}"))))
(test-equal '(42) (drain-generator (json-generator (open-input-string "42"))))
;; nothing left to read: the generator's first call yields eof, no error.
(test-assert (eof-object? ((json-generator (open-input-string "   ")))))
;; object key/value pairs come through like a plist: nested structures
;; interleave correctly with their key.
(test-equal '(object-start "a" array-start 1 2 array-end object-end)
            (drain-generator (json-generator (open-input-string "{\"a\":[1,2]}"))))

;;; --- json-fold: a genuinely custom fold, not just json-read's own -------

;; Sum every number in the structure, at any nesting depth. array-start/
;; object-start reset to a fresh per-level accumulator (0); array-end/
;; object-end hand that level's sum back up as if it were itself a number,
;; and proc simply adds in any numeric obj -- scalar or finished subtree.
(define (sum-all-numbers str)
  (json-fold
    (lambda (obj seed) (+ seed (if (number? obj) obj 0)))
    (lambda (seed) 0)
    (lambda (seed) seed)
    (lambda (seed) 0)
    (lambda (seed) seed)
    0
    (open-input-string str)))

(test-equal 15 (sum-all-numbers "[1,2,[3,4],{\"a\":5}]"))
(test-equal 0 (sum-all-numbers "[\"no\",\"numbers\",true,null]"))
(test-equal 6 (sum-all-numbers "{\"a\":1,\"b\":{\"c\":2,\"d\":3}}"))

;; Reimplementing json-read's own mapping via json-fold (mirroring the
;; spec's own illustrative use of json-fold) reproduces json-read exactly.
(define (fold-based-read str)
  (car
    (json-fold cons
      (lambda (seed) '())
      (lambda (seed) (list->vector (reverse seed)))
      (lambda (seed) '())
      (lambda (seed)
        (let loop ((lst (reverse seed)) (acc '()))
          (if (null? lst)
              (reverse acc)
              (loop (cddr lst) (cons (cons (string->symbol (car lst)) (cadr lst)) acc)))))
      '()
      (open-input-string str))))

(test-equal (read-str "{\"a\":1,\"b\":[2,3]}") (fold-based-read "{\"a\":1,\"b\":[2,3]}"))
(test-equal (read-str "[1,[2,3],{\"x\":4}]") (fold-based-read "[1,[2,3],{\"x\":4}]"))
(test-equal (read-str "\"scalar\"") (fold-based-read "\"scalar\""))

;;; --- json-accumulator: direct token feeding -----------------------------

(let* ((out (open-output-string))
       (acc (json-accumulator out)))
  (acc 'array-start)
  (acc 1)
  (acc 'object-start)
  (acc "k")
  (acc 'null)
  (acc 'object-end)
  (acc 'array-end)
  (acc (eof-object))
  (test-equal "[1,{\"k\":null}]" (get-output-string out)))

;; protocol violations raise json-error?
(test-equal 'json-error
  (json-err? (lambda ()
    (let* ((out (open-output-string)) (acc (json-accumulator out)))
      (acc 'array-start)
      (acc 'object-end)))))                 ; mismatched end
(test-equal 'json-error
  (json-err? (lambda ()
    (let* ((out (open-output-string)) (acc (json-accumulator out)))
      (acc 'object-start)
      (acc 42)))))                          ; non-string key
(test-equal 'json-error
  (json-err? (lambda ()
    (let* ((out (open-output-string)) (acc (json-accumulator out)))
      (acc 'object-start)
      (acc 'array-start)))))                ; a structure can't be a key
(test-equal 'json-error
  (json-err? (lambda ()
    (let* ((out (open-output-string)) (acc (json-accumulator out)))
      (acc 'array-end)))))                  ; end with nothing open

;; json-accumulator also accepts a raw accumulator procedure (not just a
;; port), per spec ("a textual output port or an accumulator").
(let* ((chars '())
       (char-acc (lambda (x) (if (eof-object? x) (reverse chars) (set! chars (cons x chars)))))
       (acc (json-accumulator char-acc)))
  (acc 1)
  (acc (eof-object))
  (test-equal "1" (apply string-append chars)))

;;; --- json-lines-read ---------------------------------------------------

(test-equal '(1 2 #(3 4))
  (drain-generator (json-lines-read (open-input-string "1\n2\n[3,4]\n"))))
;; blank lines between records are tolerated
(test-equal '(1 2 #(3 4))
  (drain-generator (json-lines-read (open-input-string "1\n\n2\n\n\n[3,4]\n"))))
(test-equal '() (drain-generator (json-lines-read (open-input-string ""))))

;;; --- json-sequence-read (RFC 7464) --------------------------------------

(let* ((rs (integer->char #x1e))
       (text (string-append (string rs) "1" "\n"
                             (string rs) "[2,3]" "\n"
                             (string rs) "{\"a\":1}" "\n")))
  (test-equal '(1 #(2 3) ((a . 1)))
    (drain-generator (json-sequence-read (open-input-string text)))))

;;; --- limits: json-nesting-depth-limit / json-number-of-character-limit --

(test-equal +inf.0 (json-nesting-depth-limit))
(test-equal +inf.0 (json-number-of-character-limit))

(test-equal 'json-error
  (json-err? (lambda ()
    (parameterize ((json-nesting-depth-limit 1))
      (read-str "[[1]]")))))
(test-equal #(1 2)
  (parameterize ((json-nesting-depth-limit 1)) (read-str "[1,2]")))
(test-equal #(#(1))
  (parameterize ((json-nesting-depth-limit 2)) (read-str "[[1]]")))

(test-equal 'json-error
  (json-err? (lambda ()
    (parameterize ((json-number-of-character-limit 2))
      (read-str "[1,2,3]")))))
(test-equal #(1 2 3)
  (parameterize ((json-number-of-character-limit 50)) (read-str "[1,2,3]")))

(let ((runner (test-runner-current)))
  (test-end "srfi-180")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
