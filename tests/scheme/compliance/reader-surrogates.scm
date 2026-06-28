;;; #231: Reader must reject Unicode surrogate codepoints in character literals

(import (scheme base) (scheme read) (scheme process-context) (srfi 64))

(test-begin "reader-surrogates")

;; Surrogate codepoints (U+D800..U+DFFF) are not valid Unicode scalar values.
;; R7RS Section 6.6 requires characters to represent Unicode scalar values.
;; Reading #\xD800 etc. must raise a read error.

(test-group "surrogate codepoint rejection"
  (test-error "low surrogate #\\xD800 is rejected"
    (read (open-input-string "#\\xD800")))

  (test-error "high surrogate #\\xDFFF is rejected"
    (read (open-input-string "#\\xDFFF")))

  (test-error "mid surrogate #\\xDB00 is rejected"
    (read (open-input-string "#\\xDB00"))))

;; Boundary values just outside the surrogate range must still work
(test-group "surrogate boundary values"
  (test-eqv "U+D7FF is valid"
    #xD7FF
    (char->integer (read (open-input-string "#\\xD7FF"))))

  (test-eqv "U+E000 is valid"
    #xE000
    (char->integer (read (open-input-string "#\\xE000")))))

(define %test-fail-count (test-runner-fail-count (test-runner-current)))
(test-end "reader-surrogates")
(if (> %test-fail-count 0) (exit 1))
