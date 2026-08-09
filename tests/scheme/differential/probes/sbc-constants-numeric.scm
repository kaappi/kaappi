;; Probe: every numeric constant tag survives a `.sbc` round trip.
;;
;; Audit v2, Phase 4E.  `writeConstant`/`readConstant`
;; (src/bytecode_file_write.zig, src/bytecode_file_read.zig) have one arm per
;; constant kind; a kind the corpus never happens to embed is untested.  The
;; oracle is the harness's own: a cold run compiles from source, a warm run
;; deserialises this file's constant pool, and the two must print the same
;; bytes.
;;
;; The stronger half of each line is the second column: it compares the
;; *constant* (which only the cache round-trips) against a value the bytecode
;; *computes* at run time, so a lossy round trip shows up as a mismatch even
;; if both runs would otherwise print the same literal back.
;;
;; Nothing here may `import`, may use `define-record-type`, `define-values`,
;; `include`, a top-level `begin` or a top-level `cond-expand`: any of those
;; makes the whole file uncacheable (see the header of sbc-population.scm),
;; which would silently make this probe vacuous.

(define (chk name a b)
  (display name)
  (display " ")
  (display (if (equal? a b) "ok" (list "MISMATCH" a b)))
  (newline))

;; --- fixnum, including both ends of the 48-bit payload --------------------
(write (list -140737488355328 -1 0 1 140737488355327))
(newline)
(chk "fixnum-arith" '140737488355327 (- (* 140737488355328 1) 1))

;; --- flonum, including the values a naive f64 codec loses -----------------
(write (list 1.5 0.0 -0.0 1e308 5e-324 0.1))
(newline)
(write (list (/ 1.0 0.0) (/ -1.0 0.0)))
(newline)
;; -0.0 must keep its sign bit: 1/-0.0 is -inf, 1/0.0 is +inf.
(chk "negative-zero" (list (/ 1.0 -0.0)) (list (/ 1.0 (- 0.0))))
(chk "flonum-value" '0.1 (/ 1.0 10.0))
(chk "denormal" (list (> 5e-324 0.0)) (list #t))
(chk "nan-is-nan" (list (nan? (/ 0.0 0.0))) (list #t))
(chk "inexact" (list (exact? 1.0) (exact? 0.5)) (list #f #f))

;; --- bignum (sign + limb vector) ------------------------------------------
(write (list 123456789012345678901234567890
             -98765432109876543210987654321098765432109876543210
             340282366920938463463374607431768211456))
(newline)
(chk "bignum-value" '123456789012345678900000000000 (* 12345678901234567890 10000000000))
(chk "bignum-exact" (list (exact? '123456789012345678901234567890)) (list #t))
(chk "bignum-sign" (list (negative? '-98765432109876543210987654321098765432109876543210)) (list #t))

;; --- rational (a nested numerator/denominator constant) -------------------
(write (list 1/3 -22/7 123456789012345678901234567890/98765432109876543210987654321))
(newline)
(chk "rational-value" '22/7 (/ 22 7))
(chk "rational-exact" (list (exact? 1/3)) (list #t))
(chk "rational-parts" (list (numerator '-22/7) (denominator '-22/7)) (list -22 7))

;; --- complex (two component Values: fixnum/bignum/rational/flonum) ---------
(write (list 1+2i -3.5-4.25i 0+1i))
(newline)
(chk "complex-value" '1+2i (make-rectangular 1 2))
(chk "complex-parts" (list (real-part '-3.5-4.25i) (imag-part '-3.5-4.25i)) (list -3.5 -4.25))
(chk "complex-exactness" (list (exact? '1+2i) (exact? '1.5+2.5i)) (list #t #f))
;; Exact components (bignum real, rational imag) round-trip digit-exactly
;; through the .sbc constant pool (kaappi#2166).
(write (list 9007199254740993+3/4i 10000000000000000000000000/3+123456789012345678901234567890i))
(newline)
(chk "complex-exact-bignum" '9007199254740993+3/4i
     (make-rectangular 9007199254740993 3/4))
(chk "complex-exact-big-rational"
     (list (real-part '10000000000000000000000000/3+123456789012345678901234567890i)
           (imag-part '10000000000000000000000000/3+123456789012345678901234567890i))
     (list (/ (expt 10 25) 3) 123456789012345678901234567890))
