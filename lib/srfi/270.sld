;;; SRFI 270 — Hexadecimal Floating-Point Constants
;;;
;;; Extends the reader's real-number grammar with a hex float body/suffix
;;; under `#x`: `#x9p9` (=4608, 9*2^9), `#x1.2p3` (=9), `#x-0.Ap-2`
;;; (=-0.15625), `#xFE.FF` (p optional, defaults to exponent 0). The `p`
;;; exponent is a power of *2*, not 16 -- this is what lets a hex float
;;; represent any IEEE-754 double bit-exactly, unlike decimal float syntax.
;;; This part of the spec is implemented directly in the reader
;;; (`readHexFloatSuffix` in src/reader_tokens.zig, sharing its digit-
;;; decoding with `string->number` via `bignum.parseHexFloat` in
;;; src/bignum.zig, since the spec requires `string->number` to also
;;; understand this syntax) -- there is no portable way to add new reader
;;; grammar, so this part is a genuine engine change, not a library.
;;;
;;; The one new procedure the spec defines, `write-hexadecimal-float`, IS
;;; portable: despite the spec's own text noting "a portable implementation
;;; is impossible" for the feature as a whole (true of the *reader* half),
;;; the writer doesn't need raw bit access -- `(exact x)` on a flonum
;;; already gives its exact rational value (a required R7RS property), so
;;; decomposing that rational via ordinary halving/doubling into an exact,
;;; terminating hex-digit expansion is sufficient for bit-exact
;;; round-tripping without touching the engine at all.

(define-library (srfi 270)
  (export write-hexadecimal-float)
  (import (scheme base) (scheme write) (scheme inexact))
  (begin

    ;; Per spec: nonzero normal numbers normalize to an integer part of
    ;; exactly 1 (i.e. binary-normalized into [1,2), which in any base
    ;; >= 2 has integer part 1); subnormals (|x| < 2^-1022, the smallest
    ;; normal double) keep the fixed minimum exponent, giving a mantissa
    ;; < 1 and hence integer part 0 -- matching real IEEE-754 double
    ;; semantics, where every subnormal shares that same exponent field.
    (define %min-normal-exponent -1022)

    ;; Halve/double an exact rational until it lies in [1, 2), returning
    ;; (values mantissa exponent) with mantissa * 2^exponent = original.
    ;; Terminates in a bounded number of steps for any finite double
    ;; (at most ~2100 iterations, for the most extreme exponents).
    (define (%normalize m e)
      (cond
        ((>= m 2) (%normalize (/ m 2) (+ e 1)))
        ((< m 1) (%normalize (* m 2) (- e 1)))
        (else (values m e))))

    ;; Converts an exact rational fractional part (0 <= frac < 1) to its
    ;; hex-digit expansion as a list of digit values 0-15. A flonum's
    ;; exact value is always a dyadic rational (denominator a power of
    ;; 2), so this always terminates -- at most 13 hex digits for a
    ;; double's 52-bit mantissa (rounded up to a hex-digit boundary).
    (define (%hex-digits frac)
      (if (zero? frac)
          '()
          (let* ((scaled (* frac 16))
                 (digit (exact (floor scaled))))
            (cons digit (%hex-digits (- scaled digit))))))

    (define (%digit->char d) (string-ref "0123456789abcdef" d))

    (define (%format-magnitude x) ; x: positive exact rational
      (let-values (((m e) (if (< x (expt 2 %min-normal-exponent))
                               (values (/ x (expt 2 %min-normal-exponent)) %min-normal-exponent)
                               (%normalize x 0))))
        (let* ((int-part (exact (floor m)))
               (frac (- m int-part))
               (digits (%hex-digits frac))
               (frac-str (if (null? digits)
                             ""
                             (list->string (cons #\. (map %digit->char digits))))))
          (string-append (number->string int-part) frac-str "p" (number->string e)))))

    ;; Formats one real (non-complex) inexact number per the spec's rules;
    ;; NaN/infinity print as ordinary Scheme syntax, exact reals are
    ;; coerced to inexact first (the spec doesn't address exact inputs;
    ;; this procedure is fundamentally about a float's representation).
    (define (%format-real x)
      (let ((x (inexact x)))
        (cond
          ((nan? x) (number->string x))
          ((not (finite? x)) (number->string x))
          ((zero? x) (string-append (if (negative? (/ 1.0 x)) "-0.0" "0.0") "p0"))
          ((negative? x) (string-append "-" (%format-magnitude (exact (- x)))))
          (else (%format-magnitude (exact x))))))

    (define (write-hexadecimal-float z . maybe-port)
      (let ((port (if (pair? maybe-port) (car maybe-port) (current-output-port))))
        (if (and (complex? z) (not (real? z)))
            (let ((im (imag-part z)))
              (display (%format-real (real-part z)) port)
              (when (or (not (negative? im)) (nan? im)) (display "+" port))
              (display (%format-real im) port)
              (display "i" port))
            (display (%format-real z) port))))))
