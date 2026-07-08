;; Regression test for #1268: reader uses generated Unicode tables
;; Verifies that codepoints newly accepted by alphabetic_ranges work
;; as identifiers and survive write/read round-trips.
(import (scheme base) (scheme write) (scheme read) (scheme process-context))

(define pass 0)
(define fail 0)
(define (check name got expect)
  (if (equal? got expect)
      (set! pass (+ pass 1))
      (begin
        (set! fail (+ fail 1))
        (display "FAIL: ") (display name)
        (display " expected ") (write expect)
        (display " got ") (write got)
        (newline))))

;; U+02B0 modifier letter small h (Lm category, Alphabetic)
(define xʰy 42)
(check "modifier letter identifier" xʰy 42)

;; U+00AA feminine ordinal (Lo category, Alphabetic)
(define ª 7)
(check "feminine ordinal identifier" ª 7)

;; Existing coverage: Greek letters
(define λ 99)
(check "lambda identifier" λ 99)

;; write/read round-trip for modifier letter symbol
(let ((p (open-output-string)))
  (write 'xʰy p)
  (let ((written (get-output-string p)))
    (check "write modifier letter symbol" written "xʰy")
    (check "round-trip modifier letter"
           (read (open-input-string written)) 'xʰy)))

;; write should NOT bar-quote alphabetic Unicode symbols
(let ((p (open-output-string)))
  (write 'ª p)
  (let ((written (get-output-string p)))
    (check "no bars for feminine ordinal" written "ª")
    (check "round-trip feminine ordinal"
           (read (open-input-string written)) 'ª)))

(display pass) (display "/") (display (+ pass fail)) (display " passed") (newline)
(when (> fail 0) (exit 1))
