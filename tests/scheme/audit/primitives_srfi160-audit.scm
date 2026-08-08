;; Audit tests for src/primitives_srfi160.zig — SRFI 160 homogeneous numeric
;; vectors, plus the portable surface it carries in lib/srfi/160/.
;; Audit campaign v2, Phase 2.4 (docs/audit-strategy.md, #1890).
;;
;; The file under audit is 280 lines and 6 `%`-prefixed generic primitives,
;; but those six are the ENTIRE native surface under 12 element kinds and
;; ~732 exported names across 13 .sld files. Elements are raw bytes in host
;; byte order; c64/c128 are two consecutive floats decoded into a Complex
;; only at the ref/set boundary. So the sweeps below are generated from a
;; kind table rather than hand-written per kind — a wrapper that fixes the
;; wrong kind symbol, or a range check that is off by one in exactly one of
;; twelve places, is the bug this design invites.
;;
;; Run directly and read the printed counts — run-all.sh only sees exit codes.

(import (scheme base) (scheme write) (scheme read) (scheme inexact) (scheme complex)
        (srfi 160 s8) (srfi 160 u8) (srfi 160 u16) (srfi 160 s16)
        (srfi 160 u32) (srfi 160 s32) (srfi 160 u64) (srfi 160 s64)
        (srfi 160 f32) (srfi 160 f64) (srfi 160 c64) (srfi 160 c128)
        (srfi 160 primitives) (srfi 128))
(import (scheme process-context) (srfi 64))

(test-begin "primitives_srfi160 audit")

;;; ------------------------------------------------------------------
;;; Helpers
;;; ------------------------------------------------------------------

;; Evaluate THUNK; return its value, or the symbol ERR if it raised.
;; Every reachable surface must reject bad input *catchably* — an
;; uncatchable failure shows up as the whole file dying, not as ERR.
(define (try thunk)
  (call-with-current-continuation
   (lambda (k) (with-exception-handler (lambda (e) (k 'ERR)) thunk))))

(define (nm . parts)
  (let loop ((p parts) (acc ""))
    (cond ((null? p) acc)
          (else (loop (cdr p)
                      (string-append
                       acc
                       (let ((x (car p)))
                         (cond ((string? x) x)
                               ((symbol? x) (symbol->string x))
                               ((number? x) (number->string x))
                               (else "?")))))))))

(define (write-to-string v)
  (let ((port (open-output-string)))
    (write v port)
    (get-output-string port)))

;; base.sld's own %uvec-length is internal and unexported; this mirrors it
;; over the two public entry points so the sweeps can stay kind-agnostic.
(define (%uvec-len v)
  (if (bytevector? v) (bytevector-length v) (%numeric-vector-length v)))

;;; The kind table. Every sweep below is driven from this — there is
;;; deliberately no per-kind copy of any assertion block.
;;;   name  make          ref            set!           pred  lo  hi
(define int-kinds
  (list
   (list 's8   make-s8vector   s8vector-ref   s8vector-set!   s8?   -128 127)
   (list 'u8   make-u8vector   u8vector-ref   u8vector-set!   u8?   0 255)
   (list 'u16  make-u16vector  u16vector-ref  u16vector-set!  u16?  0 65535)
   (list 's16  make-s16vector  s16vector-ref  s16vector-set!  s16?  -32768 32767)
   (list 'u32  make-u32vector  u32vector-ref  u32vector-set!  u32?  0 4294967295)
   (list 's32  make-s32vector  s32vector-ref  s32vector-set!  s32?
         -2147483648 2147483647)
   (list 'u64  make-u64vector  u64vector-ref  u64vector-set!  u64?
         0 18446744073709551615)
   (list 's64  make-s64vector  s64vector-ref  s64vector-set!  s64?
         -9223372036854775808 9223372036854775807)))

(define (k-name r) (list-ref r 0))
(define (k-make r) (list-ref r 1))
(define (k-ref  r) (list-ref r 2))
(define (k-set  r) (list-ref r 3))
(define (k-pred r) (list-ref r 4))
(define (k-lo   r) (list-ref r 5))
(define (k-hi   r) (list-ref r 6))

;; Store X into a fresh 1-element vector of this kind and read it back.
(define (rt row x)
  (let ((v ((k-make row) 1 0)))
    (try (lambda () ((k-set row) v 0 x) ((k-ref row) v 0)))))

;;; ------------------------------------------------------------------
;;; 1. Per-kind range enforcement: the exact boundary values
;;;
;;; 8 integer kinds x 4 boundaries. Phase 2.1 spot-checked this and found
;;; it correct; this makes it systematic. min and max must round-trip
;;; exactly (including u64's 2^64-1 and s64's -2^63, both of which leave
;;; fixnum range and go through the bignum encode/decode path); min-1 and
;;; max+1 must be rejected catchably.
;;; ------------------------------------------------------------------

(for-each
 (lambda (row)
   (let ((n (k-name row)) (lo (k-lo row)) (hi (k-hi row)))
     (test-equal (nm n " min round-trips")      lo   (rt row lo))
     (test-equal (nm n " max round-trips")      hi   (rt row hi))
     (test-equal (nm n " min-1 rejected")       'ERR (rt row (- lo 1)))
     (test-equal (nm n " max+1 rejected")       'ERR (rt row (+ hi 1)))
     ;; one step inside each end, so the above is a cliff and not a blanket
     (test-equal (nm n " min+1 round-trips")    (+ lo 1) (rt row (+ lo 1)))
     (test-equal (nm n " max-1 round-trips")    (- hi 1) (rt row (- hi 1)))))
 int-kinds)

;;; ------------------------------------------------------------------
;;; 2. Per-kind exactness and type rejection
;;;
;;; An exact-integer slot must reject: integral flonums (1.0 is not exact),
;;; non-integral flonums, rationals, complexes, non-numbers, and bignums
;;; outside range in both directions.
;;; ------------------------------------------------------------------

(for-each
 (lambda (row)
   (let ((n (k-name row)))
     (test-equal (nm n " rejects integral flonum 1.0") 'ERR (rt row 1.0))
     (test-equal (nm n " rejects flonum 1.5")          'ERR (rt row 1.5))
     (test-equal (nm n " rejects rational 1/2")        'ERR (rt row 1/2))
     (test-equal (nm n " rejects complex")             'ERR
                 (rt row (make-rectangular 1 1)))
     (test-equal (nm n " rejects symbol")              'ERR (rt row 'x))
     (test-equal (nm n " rejects string")              'ERR (rt row "1"))
     (test-equal (nm n " rejects boolean")             'ERR (rt row #t))
     (test-equal (nm n " rejects +bignum out of range") 'ERR
                 (rt row (expt 2 100)))
     (test-equal (nm n " rejects -bignum out of range") 'ERR
                 (rt row (- (expt 2 100))))
     ;; negative into unsigned / the signed kinds' own negative side
     (test-equal (nm n " -1 handled per signedness")
                 (if (negative? (k-lo row)) -1 'ERR)
                 (rt row -1))))
 int-kinds)

;;; ------------------------------------------------------------------
;;; 3. The two range checks agree
;;;
;;; The range table lives TWICE: as `%uvec-elt-valid?` in portable Scheme
;;; (lib/srfi/160/base.sld, which backs the `s8?`/`u16?`/... predicates)
;;; and as `expectSignedInRange`/`expectUnsignedInRange`/`expectReal` in
;;; Zig (src/primitives_srfi160.zig, which backs set!). Dual
;;; implementations of one rule drift; this pins them together.
;;; ------------------------------------------------------------------

(define all-kinds
  (append
   int-kinds
   (list
    (list 'f32  make-f32vector  f32vector-ref  f32vector-set!  f32?  #f #f)
    (list 'f64  make-f64vector  f64vector-ref  f64vector-set!  f64?  #f #f)
    (list 'c64  make-c64vector  c64vector-ref  c64vector-set!  c64?  #f #f)
    (list 'c128 make-c128vector c128vector-ref c128vector-set! c128? #f #f))))

(define agreement-corpus
  (list 0 1 -1 127 128 255 256 -128 -129 65535 65536 1.0 1.5 -0.0 1/2
        (expt 2 100) (- (expt 2 100)) (make-rectangular 1 2)
        (make-rectangular 1.5 2.5) 'sym "s" #t '()))

(for-each
 (lambda (row)
   (let* ((n (k-name row))
          (float? (memq n '(f32 f64 c64 c128)))
          (v ((k-make row) 1 (if float? 0.0 0))))
     (for-each
      (lambda (x)
        (test-equal (nm n " predicate agrees with set! on " (write-to-string x))
                    (if ((k-pred row) x) #t #f)
                    (if (eq? 'ERR (try (lambda () ((k-set row) v 0 x) 'ok)))
                        #f #t)))
      agreement-corpus)))
 all-kinds)

;;; ------------------------------------------------------------------
;;; 4. Float kinds: special values and f32 precision
;;; ------------------------------------------------------------------

(define (frow n) (assq n (map (lambda (r) (cons (k-name r) r)) all-kinds)))
(define f32row (cdr (frow 'f32)))
(define f64row (cdr (frow 'f64)))
(define c64row (cdr (frow 'c64)))
(define c128row (cdr (frow 'c128)))

(test-equal 0.0 (rt f64row 0.0))
(test-equal 1.5 (rt f64row 1.5))
(test-assert "f64 preserves -0.0" (eqv? -0.0 (rt f64row -0.0)))
(test-assert "f64 preserves +inf.0" (= (/ 1.0 0.0) (rt f64row (/ 1.0 0.0))))
(test-assert "f64 preserves -inf.0" (= (- (/ 1.0 0.0)) (rt f64row (- (/ 1.0 0.0)))))
(test-assert "f64 preserves NaN" (nan? (rt f64row (/ 0.0 0.0))))
(test-equal 1.0 (rt f64row 1))
(test-equal 0.5 (rt f64row 1/2))
(test-equal 'ERR (rt f64row (make-rectangular 1 1)))
(test-equal 'ERR (rt f64row 'x))

(test-assert "f32 preserves -0.0" (eqv? -0.0 (rt f32row -0.0)))
(test-assert "f32 preserves +inf.0" (= (/ 1.0 0.0) (rt f32row (/ 1.0 0.0))))
(test-assert "f32 preserves NaN" (nan? (rt f32row (/ 0.0 0.0))))
(test-equal 1.5 (rt f32row 1.5))
;; f32 really is 32-bit: 0.1 must come back as the f32-rounded value, not 0.1.
;; This is the bug the old bytevector-wrapping SRFI 4 port had.
(test-assert "f32 truncates to single precision" (not (= 0.1 (rt f32row 0.1))))
(test-equal 0.10000000149011612 (rt f32row 0.1))
(test-assert "f32 overflows to +inf.0" (= (/ 1.0 0.0) (rt f32row 1e300)))
(test-assert "f32 underflows to 0.0" (= 0.0 (rt f32row 1e-300)))
(test-equal 'ERR (rt f32row (make-rectangular 1 1)))

;;; ------------------------------------------------------------------
;;; 5. SEAM: c64/c128 two-slot packing
;;;
;;; One element is two consecutive floats (real, imag) packed contiguously
;;; in the raw byte buffer, decoded into a Complex only at ref/set. That
;;; makes three things worth pinning: both components must survive
;;; independently, both must take the element kind's precision, and a
;;; rejected set! must not leave a half-written slot.
;;; ------------------------------------------------------------------

(test-assert "c128 round-trips a real numerically" (= 1.5 (rt c128row 1.5)))
(test-assert "c128 round-trips a genuine complex"
             (= (make-rectangular 1.5 -2.5) (rt c128row (make-rectangular 1.5 -2.5))))
(test-assert "c128 keeps components independent"
             (let ((z (rt c128row (make-rectangular 3.25 -7.75))))
               (and (= 3.25 (real-part z)) (= -7.75 (imag-part z)))))
(test-assert "c128 preserves +inf.0/-inf.0 components"
             (let ((z (rt c128row (make-rectangular (/ 1.0 0.0) (- (/ 1.0 0.0))))))
               (and (= (/ 1.0 0.0) (real-part z)) (= (- (/ 1.0 0.0)) (imag-part z)))))
(test-assert "c128 preserves a NaN real component with a finite imag"
             (let ((z (rt c128row (make-rectangular (/ 0.0 0.0) 1.0))))
               (and (nan? (real-part z)) (= 1.0 (imag-part z)))))
(test-assert "c128 accepts an exact integer" (= 1.0 (rt c128row 1)))
(test-assert "c128 accepts a rational" (= 0.5 (rt c128row 1/2)))
(test-assert "c128 accepts an exact complex"
             (= (make-rectangular 1 2) (rt c128row (make-rectangular 1 2))))

;;; A c64/c128 element decodes to a real when its imaginary part is exactly
;;; +0.0, matching make-rectangular's normalisation and the standalone
;;; complex printer's collapse (kaappi#1951). A -0.0 imaginary part keeps
;;; its sign and stays a Complex, since the printer preserves -0.0 as
;;; "1.5-0.0i". These assertions pin the decode boundary.
(test-assert "a zero-imaginary (+0.0) c128 element decodes to a real"
             (real? (c128vector-ref (c128vector 1.5) 0)))
(test-assert "a zero-imaginary (+0.0) c64 element decodes to a real"
             (real? (c64vector-ref (c64vector 1.5) 0)))
(test-assert "a +0.0-imag c128 element is complex? (reals are complex)"
             (complex? (c128vector-ref (c128vector 1.5) 0)))
(test-assert "its imaginary part is zero"
             (= 0 (imag-part (c128vector-ref (c128vector 1.5) 0))))
;; Control 1: make-rectangular NORMALISES a zero imaginary part to a real,
;; so decodeElement now agrees with the ordinary constructor.
(test-assert "make-rectangular normalises a zero imaginary part"
             (real? (make-rectangular 1.5 0.0)))
;; Control 2: a genuinely complex element round-trips through write/read.
(test-assert "a genuine complex writes and reads back as a complex"
             (let ((e (c128vector-ref (c128vector (make-rectangular 1.5 2.5)) 0)))
               (eq? (real? e)
                    (real? (read (open-input-string (write-to-string e)))))))
;; Control 3: the vector printer is honest about the zero imaginary part.
(test-equal "#<c128vector 1.5+0.0i>" (write-to-string (c128vector 1.5)))
(test-equal "#<c64vector 1.5+0.0i>" (write-to-string (c64vector 1.5)))

;;; #1951 (a zero-imaginary c64/c128 element writes as a real): a +0.0
;;; imaginary part now decodes to a plain real, so `write` emits "1.5" and
;;; it reads back as the SAME type — real? agrees on both sides. The same
;;; holds for c64 and for the DEFAULT FILL, so every freshly-made c64/c128
;;; vector round-trips. A -0.0 imaginary part stays a Complex and writes
;;; as "1.5-0.0i", which also round-trips.
(test-assert "a zero-imaginary c128 element round-trips through write/read"
             (let ((e (c128vector-ref (c128vector 1.5) 0)))
               (eq? (real? e)
                    (real? (read (open-input-string (write-to-string e)))))))
(test-assert "a zero-imaginary c64 element round-trips through write/read"
             (let ((e (c64vector-ref (c64vector 1.5) 0)))
               (eq? (real? e)
                    (real? (read (open-input-string (write-to-string e)))))))
(test-assert "a default-filled c128 element round-trips through write/read"
             (let ((e (c128vector-ref (make-c128vector 1) 0)))
               (eq? (real? e)
                    (real? (read (open-input-string (write-to-string e)))))))
(test-assert "a -0.0-imag c128 element stays complex and round-trips"
             (let* ((v (make-c128vector 1 0.0))
                    (e (begin (c128vector-set! v 0 1.5-0.0i)
                              (c128vector-ref v 0))))
               (and (not (real? e))
                    (eq? (real? e)
                         (real? (read (open-input-string (write-to-string e))))))))
(test-assert "a -0.0-imag c64 element stays complex and round-trips"
             (let* ((v (make-c64vector 1 0.0))
                    (e (begin (c64vector-set! v 0 1.5-0.0i)
                              (c64vector-ref v 0))))
               (and (not (real? e))
                    (eq? (real? e)
                         (real? (read (open-input-string (write-to-string e))))))))

(test-assert "c64 round-trips a genuine complex"
             (= (make-rectangular 1.5 -2.5) (rt c64row (make-rectangular 1.5 -2.5))))
;; BOTH components must be f32-rounded, not just the real one. A packing
;; bug that wrote the imaginary part at f64 width would pass a real-only test.
(test-assert "c64 truncates the real component to single precision"
             (= 0.10000000149011612 (real-part (rt c64row (make-rectangular 0.1 0.2)))))
(test-assert "c64 truncates the imaginary component to single precision"
             (= 0.20000000298023224 (imag-part (rt c64row (make-rectangular 0.1 0.2)))))
(test-assert "c64 preserves infinite components"
             (let ((z (rt c64row (make-rectangular (/ 1.0 0.0) (- (/ 1.0 0.0))))))
               (and (= (/ 1.0 0.0) (real-part z)) (= (- (/ 1.0 0.0)) (imag-part z)))))
(test-assert "c64 preserves a NaN real component with a finite imag"
             (let ((z (rt c64row (make-rectangular (/ 0.0 0.0) 1.0))))
               (and (nan? (real-part z)) (= 1.0 (imag-part z)))))

;; A rejected set! must leave the slot exactly as it was. encodeElement
;; validates before writing any byte, so this must hold for every kind —
;; a "validate the real part, write it, then validate the imag" shape
;; would corrupt half an element on failure.
(for-each
 (lambda (row)
   (let* ((n (k-name row))
          (float? (memq n '(f32 f64 c64 c128)))
          (good (if float? 1.5 1))
          (v ((k-make row) 2 (if float? 0.0 0))))
     ((k-set row) v 0 good)
     (test-equal (nm n " rejected set! leaves the slot untouched")
                 'ERR (try (lambda () ((k-set row) v 0 'not-a-number))))
     (test-assert (nm n " slot survives a rejected set!")
                  (= good ((k-ref row) v 0)))))
 all-kinds)

;; Default fill for the two complex kinds is 0.0 (a real), which must
;; still land as a well-formed two-slot zero.
(test-assert "c64 default fill is a well-formed zero"
             (= 0 (c64vector-ref (make-c64vector 2) 1)))
(test-assert "c128 default fill is a well-formed zero"
             (= 0 (c128vector-ref (make-c128vector 2) 1)))

;;; ------------------------------------------------------------------
;;; 6. SEAM: u8 is a plain bytevector
;;;
;;; u8 is the one kind with no NumericVector behind it — `%uvec-ref`/
;;; `%uvec-set!`/`%uvec-length`/`%uvec-make` dispatch on `bytevector?` vs
;;; `%numeric-vector?`. So every u8 operation runs a different branch from
;;; its 11 siblings, and the identity must hold in both directions.
;;; ------------------------------------------------------------------

(test-assert "a bytevector is a u8vector" (u8vector? (bytevector 1 2)))
(test-assert "a u8vector is a bytevector" (bytevector? (u8vector 1 2)))
(test-assert "a bytevector is not an s8vector" (not (s8vector? (bytevector 1 2))))
(test-assert "a u8vector is not a NumericVector"
             (not (%numeric-vector? (u8vector 1 2))))
(test-assert "an s8vector is a NumericVector" (%numeric-vector? (s8vector 1 2)))
;; Derived operations must stay on the bytevector side, not silently
;; promote to a NumericVector of kind u8 (which does not exist).
(test-assert "u8vector-copy returns a bytevector"
             (bytevector? (u8vector-copy (u8vector 1 2 3))))
(test-assert "u8vector-map returns a bytevector"
             (bytevector? (u8vector-map (lambda (x) x) (u8vector 1 2))))
(test-assert "u8vector-append returns a bytevector"
             (bytevector? (u8vector-append (u8vector 1) (u8vector 2))))
(test-assert "u8vector-filter returns a bytevector"
             (bytevector? (u8vector-filter even? (u8vector 1 2 3 4))))
(test-assert "list->u8vector returns a bytevector"
             (bytevector? (list->u8vector '(1 2 3))))
(test-assert "u8vector-unfold returns a bytevector"
             (bytevector? (u8vector-unfold (lambda (i) i) 3)))
(test-equal '(1 2 3) (u8vector->list (u8vector 1 2 3)))
(test-equal 3 (u8vector-length (u8vector 1 2 3)))
;; The generic engine reads u8 through bytevector-u8-ref, so the u8 range
;; must be enforced by the bytevector primitives, not by SRFI 160's table.
(test-equal 'ERR (rt (cadr int-kinds) 256))
(test-equal 255 (rt (cadr int-kinds) 255))

;;; ------------------------------------------------------------------
;;; 7. Per-kind wrapper correctness
;;;
;;; Each lib/srfi/160/<tag>.sld renames the kind-agnostic generics and
;;; wraps the kind-constructing ones in a one-line closure fixing that
;;; type's kind symbol. A wrapper that fixes the WRONG kind symbol is
;;; exactly the bug this design invites, and it would be invisible to any
;;; test that only checks values. So: check the KIND of every constructed
;;; result, for every kind, through every constructing entry point.
;;; ------------------------------------------------------------------

(define (kind-of v) (if (bytevector? v) 'u8 (%numeric-vector-kind v)))

(for-each
 (lambda (row)
   (let* ((n (k-name row))
          (float? (memq n '(f32 f64 c64 c128)))
          (one (if float? 1.0 1))
          (v ((k-make row) 3 one)))
     (test-equal (nm n " make yields its own kind") n (kind-of v))
     (test-equal (nm n " own predicate accepts it") #t ((k-pred row) one))
     (test-equal (nm n " length") 3 (%uvec-len v))))
 all-kinds)

;; Every other kind's predicate must reject this kind's vector: 12x12,
;; true only on the diagonal. This is what catches a copy-pasted .sld.
(define vec-preds
  (list (cons 's8 s8vector?) (cons 'u8 (lambda (x) (and (u8vector? x) #t)))
        (cons 'u16 u16vector?) (cons 's16 s16vector?)
        (cons 'u32 u32vector?) (cons 's32 s32vector?)
        (cons 'u64 u64vector?) (cons 's64 s64vector?)
        (cons 'f32 f32vector?) (cons 'f64 f64vector?)
        (cons 'c64 c64vector?) (cons 'c128 c128vector?)))

(for-each
 (lambda (row)
   (let* ((n (k-name row))
          (float? (memq n '(f32 f64 c64 c128)))
          (v ((k-make row) 2 (if float? 0.0 0))))
     (for-each
      (lambda (pr)
        (test-equal (nm (car pr) "vector? on a " n "vector")
                    (eq? (car pr) n)
                    (and ((cdr pr) v) #t)))
      vec-preds)))
 all-kinds)

;;; Every kind-constructing wrapper must produce THIS kind. These are the
;;; entry points that carry a hard-coded 'kind symbol in the .sld.
(define (constructors row)
  (let* ((n (k-name row))
         (float? (memq n '(f32 f64 c64 c128)))
         (a (if float? 1.0 1))
         (b (if float? 2.0 2))
         (v ((k-make row) 2 a)))
    (case n
      ((s8) (list (cons "copy" (s8vector-copy v)) (cons "map" (s8vector-map (lambda (x) x) v))
                  (cons "append" (s8vector-append v v)) (cons "filter" (s8vector-filter (lambda (x) #t) v))
                  (cons "take" (s8vector-take v 1)) (cons "unfold" (s8vector-unfold (lambda (i) 0) 2))
                  (cons "reverse-copy" (s8vector-reverse-copy v))
                  (cons "vector->" (vector->s8vector (vector 1)))
                  (cons "list->" (list->s8vector (list 1)))
                  (cons "cumulate" (s8vector-cumulate + 0 v))))
      ((u8) (list (cons "copy" (u8vector-copy v)) (cons "map" (u8vector-map (lambda (x) x) v))
                  (cons "append" (u8vector-append v v)) (cons "filter" (u8vector-filter (lambda (x) #t) v))
                  (cons "take" (u8vector-take v 1)) (cons "unfold" (u8vector-unfold (lambda (i) 0) 2))
                  (cons "reverse-copy" (u8vector-reverse-copy v))
                  (cons "vector->" (vector->u8vector (vector 1)))
                  (cons "list->" (list->u8vector (list 1)))
                  (cons "cumulate" (u8vector-cumulate + 0 v))))
      ((u16) (list (cons "copy" (u16vector-copy v)) (cons "map" (u16vector-map (lambda (x) x) v))
                   (cons "append" (u16vector-append v v)) (cons "filter" (u16vector-filter (lambda (x) #t) v))
                   (cons "take" (u16vector-take v 1)) (cons "unfold" (u16vector-unfold (lambda (i) 0) 2))
                   (cons "reverse-copy" (u16vector-reverse-copy v))
                   (cons "vector->" (vector->u16vector (vector 1)))
                   (cons "list->" (list->u16vector (list 1)))
                   (cons "cumulate" (u16vector-cumulate + 0 v))))
      ((s16) (list (cons "copy" (s16vector-copy v)) (cons "map" (s16vector-map (lambda (x) x) v))
                   (cons "append" (s16vector-append v v)) (cons "filter" (s16vector-filter (lambda (x) #t) v))
                   (cons "take" (s16vector-take v 1)) (cons "unfold" (s16vector-unfold (lambda (i) 0) 2))
                   (cons "reverse-copy" (s16vector-reverse-copy v))
                   (cons "vector->" (vector->s16vector (vector 1)))
                   (cons "list->" (list->s16vector (list 1)))
                   (cons "cumulate" (s16vector-cumulate + 0 v))))
      ((u32) (list (cons "copy" (u32vector-copy v)) (cons "map" (u32vector-map (lambda (x) x) v))
                   (cons "append" (u32vector-append v v)) (cons "filter" (u32vector-filter (lambda (x) #t) v))
                   (cons "take" (u32vector-take v 1)) (cons "unfold" (u32vector-unfold (lambda (i) 0) 2))
                   (cons "reverse-copy" (u32vector-reverse-copy v))
                   (cons "vector->" (vector->u32vector (vector 1)))
                   (cons "list->" (list->u32vector (list 1)))
                   (cons "cumulate" (u32vector-cumulate + 0 v))))
      ((s32) (list (cons "copy" (s32vector-copy v)) (cons "map" (s32vector-map (lambda (x) x) v))
                   (cons "append" (s32vector-append v v)) (cons "filter" (s32vector-filter (lambda (x) #t) v))
                   (cons "take" (s32vector-take v 1)) (cons "unfold" (s32vector-unfold (lambda (i) 0) 2))
                   (cons "reverse-copy" (s32vector-reverse-copy v))
                   (cons "vector->" (vector->s32vector (vector 1)))
                   (cons "list->" (list->s32vector (list 1)))
                   (cons "cumulate" (s32vector-cumulate + 0 v))))
      ((u64) (list (cons "copy" (u64vector-copy v)) (cons "map" (u64vector-map (lambda (x) x) v))
                   (cons "append" (u64vector-append v v)) (cons "filter" (u64vector-filter (lambda (x) #t) v))
                   (cons "take" (u64vector-take v 1)) (cons "unfold" (u64vector-unfold (lambda (i) 0) 2))
                   (cons "reverse-copy" (u64vector-reverse-copy v))
                   (cons "vector->" (vector->u64vector (vector 1)))
                   (cons "list->" (list->u64vector (list 1)))
                   (cons "cumulate" (u64vector-cumulate + 0 v))))
      ((s64) (list (cons "copy" (s64vector-copy v)) (cons "map" (s64vector-map (lambda (x) x) v))
                   (cons "append" (s64vector-append v v)) (cons "filter" (s64vector-filter (lambda (x) #t) v))
                   (cons "take" (s64vector-take v 1)) (cons "unfold" (s64vector-unfold (lambda (i) 0) 2))
                   (cons "reverse-copy" (s64vector-reverse-copy v))
                   (cons "vector->" (vector->s64vector (vector 1)))
                   (cons "list->" (list->s64vector (list 1)))
                   (cons "cumulate" (s64vector-cumulate + 0 v))))
      ((f32) (list (cons "copy" (f32vector-copy v)) (cons "map" (f32vector-map (lambda (x) x) v))
                   (cons "append" (f32vector-append v v)) (cons "filter" (f32vector-filter (lambda (x) #t) v))
                   (cons "take" (f32vector-take v 1)) (cons "unfold" (f32vector-unfold (lambda (i) 0.0) 2))
                   (cons "reverse-copy" (f32vector-reverse-copy v))
                   (cons "vector->" (vector->f32vector (vector 1.0)))
                   (cons "list->" (list->f32vector (list 1.0)))
                   (cons "cumulate" (f32vector-cumulate + 0.0 v))))
      ((f64) (list (cons "copy" (f64vector-copy v)) (cons "map" (f64vector-map (lambda (x) x) v))
                   (cons "append" (f64vector-append v v)) (cons "filter" (f64vector-filter (lambda (x) #t) v))
                   (cons "take" (f64vector-take v 1)) (cons "unfold" (f64vector-unfold (lambda (i) 0.0) 2))
                   (cons "reverse-copy" (f64vector-reverse-copy v))
                   (cons "vector->" (vector->f64vector (vector 1.0)))
                   (cons "list->" (list->f64vector (list 1.0)))
                   (cons "cumulate" (f64vector-cumulate + 0.0 v))))
      ((c64) (list (cons "copy" (c64vector-copy v)) (cons "map" (c64vector-map (lambda (x) x) v))
                   (cons "append" (c64vector-append v v)) (cons "filter" (c64vector-filter (lambda (x) #t) v))
                   (cons "take" (c64vector-take v 1)) (cons "unfold" (c64vector-unfold (lambda (i) 0.0) 2))
                   (cons "reverse-copy" (c64vector-reverse-copy v))
                   (cons "vector->" (vector->c64vector (vector 1.0)))
                   (cons "list->" (list->c64vector (list 1.0)))
                   (cons "cumulate" (c64vector-cumulate + 0.0 v))))
      ((c128) (list (cons "copy" (c128vector-copy v)) (cons "map" (c128vector-map (lambda (x) x) v))
                    (cons "append" (c128vector-append v v)) (cons "filter" (c128vector-filter (lambda (x) #t) v))
                    (cons "take" (c128vector-take v 1)) (cons "unfold" (c128vector-unfold (lambda (i) 0.0) 2))
                    (cons "reverse-copy" (c128vector-reverse-copy v))
                    (cons "vector->" (vector->c128vector (vector 1.0)))
                    (cons "list->" (list->c128vector (list 1.0)))
                    (cons "cumulate" (c128vector-cumulate + 0.0 v))))
      (else '()))))

(for-each
 (lambda (row)
   (let ((n (k-name row)))
     (for-each
      (lambda (pr)
        (test-equal (nm n "vector-" (car pr) " fixes its own kind")
                    n (kind-of (cdr pr))))
      (constructors row))))
 all-kinds)

;;; ------------------------------------------------------------------
;;; 8. Byte order
;;;
;;; Elements are stored in host-native byte order (builtin.cpu.arch.endian()).
;;; printer.zig's numeric-vector arm decodes with native_endian too, and
;;; primitives_srfi160.zig encodes/decodes with it. Those are two separate
;;; hand-written decoders, and s390x is the only big-endian target in CI —
;;; where the byte-order-sensitive SRFI tests do not currently run (Phase
;;; 7C). If either decoder disagreed with the encoder, THESE assertions
;;; fail on that host and pass here, which is exactly what makes them worth
;;; having: each value below is chosen so its byte-reverse is a different
;;; in-range number (0x0102 = 258 reversed is 0x0201 = 513, etc.).
;;; ------------------------------------------------------------------

(define endian-probe
  (list (list 'u16  (u16vector 258)                "#<u16vector 258>")
        (list 's16  (s16vector 258)                "#<s16vector 258>")
        (list 'u32  (u32vector 16909060)           "#<u32vector 16909060>")
        (list 's32  (s32vector 16909060)           "#<s32vector 16909060>")
        (list 'u64  (u64vector 72623859790382856)  "#<u64vector 72623859790382856>")
        (list 's64  (s64vector 72623859790382856)  "#<s64vector 72623859790382856>")))

(for-each
 (lambda (p)
   (test-equal (nm (car p) " printer agrees with the encoder")
               (caddr p) (write-to-string (cadr p))))
 endian-probe)

;; The same check one level up: ref must agree with the printer, so a
;; byte-order bug cannot cancel out between the two decoders.
(test-equal 258 (u16vector-ref (u16vector 258) 0))
(test-equal 16909060 (u32vector-ref (u32vector 16909060) 0))
(test-equal 72623859790382856 (u64vector-ref (u64vector 72623859790382856) 0))
(test-equal 1.5 (f64vector-ref (f64vector 1.5) 0))
(test-equal "#<f64vector 1.5>" (write-to-string (f64vector 1.5)))
(test-equal "#<c64vector 1.5-2.5i>"
            (write-to-string (c64vector (make-rectangular 1.5 -2.5))))

;; Multi-element buffers: element N must not bleed into element N+1.
(test-equal '(258 513 1027) (u16vector->list (u16vector 258 513 1027)))
(test-equal '(-1 0 -32768 32767) (s16vector->list (s16vector -1 0 -32768 32767)))
(test-equal '(1.5 -2.5) (f64vector->list (f64vector 1.5 -2.5)))
(test-assert "c128 elements do not bleed into each other"
             (let ((v (c128vector (make-rectangular 1.5 2.5)
                                  (make-rectangular 3.5 4.5))))
               (and (= (make-rectangular 1.5 2.5) (c128vector-ref v 0))
                    (= (make-rectangular 3.5 4.5) (c128vector-ref v 1)))))

;;; ------------------------------------------------------------------
;;; 9. Index handling and error taxonomy (D2)
;;; ------------------------------------------------------------------

(for-each
 (lambda (row)
   (let* ((n (k-name row))
          (float? (memq n '(f32 f64 c64 c128)))
          (v ((k-make row) 2 (if float? 0.0 0))))
     (test-equal (nm n " ref rejects a negative index") 'ERR
                 (try (lambda () ((k-ref row) v -1))))
     (test-equal (nm n " ref rejects index = length") 'ERR
                 (try (lambda () ((k-ref row) v 2))))
     (test-equal (nm n " ref rejects a bignum index") 'ERR
                 (try (lambda () ((k-ref row) v (expt 2 60)))))
     (test-equal (nm n " ref rejects a flonum index") 'ERR
                 (try (lambda () ((k-ref row) v 1.0))))
     (test-equal (nm n " set! rejects an out-of-range index") 'ERR
                 (try (lambda () ((k-set row) v 2 (if float? 0.0 0)))))
     (test-equal (nm n " ref on an empty vector") 'ERR
                 (try (lambda () ((k-ref row) ((k-make row) 0 (if float? 0.0 0)) 0))))
     (test-equal (nm n " make rejects a negative length") 'ERR
                 (try (lambda () ((k-make row) -1 (if float? 0.0 0)))))))
 all-kinds)

;; An out-of-range INDEX is KP3006 (indexError, carrying index and length).
(test-assert "index failure is an error object"
             (guard (e (#t (error-object? e))) (s8vector-ref (s8vector 1 2) 9)))
;; An out-of-range VALUE of an acceptable type is reported as KP3002
;; typeError with a synthesized pseudo-type ("in-range signed integer")
;; rather than KP3007 argError. Pinning the current behaviour; see the
;; audit report — argError is what the D2 taxonomy describes for this case.
(test-assert "value-range failure is an error object"
             (guard (e (#t (error-object? e))) (s8vector-set! (s8vector 1 2) 0 999)))

;;; ------------------------------------------------------------------
;;; 10. The generic extended surface
;;;
;;; ~25 procedures written once in (srfi 160 base) and shared by all 12
;;; kinds, so one exemplar kind exercises the algorithm and section 7
;;; above covers the per-kind wrapping.
;;; ------------------------------------------------------------------

(define v5 (s8vector 1 2 3 4 5))

(test-equal '(1 2) (s8vector->list (s8vector-take v5 2)))
(test-equal '(4 5) (s8vector->list (s8vector-take-right v5 2)))
(test-equal '(3 4 5) (s8vector->list (s8vector-drop v5 2)))
(test-equal '(1 2 3) (s8vector->list (s8vector-drop-right v5 2)))
(test-equal '() (s8vector->list (s8vector-take v5 0)))
(test-equal 'ERR (try (lambda () (s8vector-take v5 -1))))
(test-equal 'ERR (try (lambda () (s8vector-take v5 99))))

(test-equal 15 (s8vector-fold (lambda (a x) (+ a x)) 0 v5))
(test-equal '(1 2 3 4 5) (s8vector-fold-right (lambda (a x) (cons x a)) '() v5))
(test-equal 2 (s8vector-count even? v5))
(test-equal 1 (s8vector-index even? v5))
(test-equal 3 (s8vector-index-right even? v5))
(test-equal 0 (s8vector-skip even? v5))
(test-equal #f (s8vector-index (lambda (x) (> x 99)) v5))
(test-equal 4 (s8vector-any (lambda (x) (and (> x 3) x)) v5))
(test-equal #f (s8vector-any (lambda (x) (> x 99)) v5))
(test-equal #t (s8vector-every (lambda (x) (> x 0)) v5))
(test-equal #f (s8vector-every even? v5))
(test-equal #t (s8vector-every even? (s8vector)))
(test-equal #f (s8vector-any even? (s8vector)))

(test-equal '(2 4) (s8vector->list (s8vector-filter even? v5)))
(test-equal '(1 3 5) (s8vector->list (s8vector-remove even? v5)))
(test-equal '(2 4 1 3 5)
            (s8vector->list
             (call-with-values (lambda () (s8vector-partition even? v5))
                               (lambda (v n) v))))
(test-equal 2 (call-with-values (lambda () (s8vector-partition even? v5))
                                (lambda (v n) n)))
(test-equal '(1 3 6 10 15) (s8vector->list (s8vector-cumulate + 0 v5)))

(test-equal '(1 2) (s8vector->list (s8vector-take-while (lambda (x) (< x 3)) v5)))
(test-equal '(3 4 5) (s8vector->list (s8vector-drop-while (lambda (x) (< x 3)) v5)))
(test-equal '(4 5) (s8vector->list (s8vector-take-while-right (lambda (x) (> x 3)) v5)))
(test-equal '(1 2 3) (s8vector->list (s8vector-drop-while-right (lambda (x) (> x 3)) v5)))

(test-equal '(1 2 3) (s8vector->list (s8vector-append (s8vector 1) (s8vector 2 3))))
(test-equal '(1 2) (s8vector->list (s8vector-concatenate (list (s8vector 1) (s8vector 2)))))
(test-equal '() (s8vector->list (s8vector-concatenate '())))
(test-equal '(1 2 5 6)
            (s8vector->list
             (s8vector-append-subvectors (s8vector 1 2 3) 0 2 (s8vector 4 5 6) 1 3)))

(test-equal '(0 2 4 6) (s8vector->list (s8vector-unfold (lambda (i) (* i 2)) 4)))
(test-equal '(0 2 4 6) (s8vector->list (s8vector-unfold-right (lambda (i) (* i 2)) 4)))
(test-equal '(5 4 3 2 1) (reverse-s8vector->list v5))
(test-equal '(3 2 1) (s8vector->list (reverse-list->s8vector '(1 2 3))))
(test-equal #(1 2 3 4 5) (s8vector->vector v5))
(test-equal '(1 2 3) (s8vector->list (vector->s8vector #(1 2 3))))
(test-equal '(2 3) (s8vector->list (s8vector-copy v5 1 3)))
(test-equal '(3 2) (s8vector->list (s8vector-reverse-copy v5 1 3)))
(test-equal 'ERR (try (lambda () (s8vector-copy v5 3 1))))

(test-equal '(5 4 3 2 1)
            (let ((w (s8vector-copy v5))) (s8vector-reverse! w) (s8vector->list w)))
(test-equal '(0 7 8 0 0)
            (let ((w (s8vector 0 0 0 0 0)))
              (s8vector-copy! w 1 (s8vector 7 8)) (s8vector->list w)))
;; Self-overlapping copies in both directions — the forward/backward
;; branch in %uvec-copy! exists precisely for this.
(test-equal '(3 4 5 4 5)
            (let ((w (s8vector 1 2 3 4 5))) (s8vector-copy! w 0 w 2 5) (s8vector->list w)))
(test-equal '(1 2 1 2 3)
            (let ((w (s8vector 1 2 3 4 5))) (s8vector-copy! w 2 w 0 3) (s8vector->list w)))
(test-equal '(9 9 3)
            (let ((w (s8vector 1 2 3))) (s8vector-fill! w 9 0 2) (s8vector->list w)))
(test-equal '(1 2 3)
            (let ((w (s8vector 1 2 3))) (s8vector-fill! w 9 2 1) (s8vector->list w)))
(test-equal '(2 1 3)
            (let ((w (s8vector 1 2 3))) (s8vector-swap! w 0 1) (s8vector->list w)))
(test-equal '(2 4 6)
            (let ((w (s8vector 1 2 3))) (s8vector-map! (lambda (x) (* 2 x)) w) (s8vector->list w)))
(test-equal '(1 2 3)
            (let ((acc '()))
              (s8vector-for-each (lambda (x) (set! acc (cons x acc))) (s8vector 1 2 3))
              (reverse acc)))

(test-equal #t (s8vector-empty? (s8vector)))
(test-equal #f (s8vector-empty? v5))
(test-equal #t (s8vector= (s8vector 1 2) (s8vector 1 2)))
(test-equal #f (s8vector= (s8vector 1 2) (s8vector 1 3)))
(test-equal #f (s8vector= (s8vector 1 2) (s8vector 1 2 3)))
(test-equal #t (s8vector= (s8vector 1) (s8vector 1) (s8vector 1)))
(test-equal #t (s8vector= (s8vector 1)))

(test-equal '(1 2 #t)
            (let ((g (make-s8vector-generator (s8vector 1 2))))
              (list (g) (g) (eof-object? (g)))))

;; %uvec-segment: the last segment may be shorter than n.
(test-equal '((1 2) (3 4)) (map s8vector->list (s8vector-segment (s8vector 1 2 3 4) 2)))
(test-equal '((1 2 3) (4)) (map s8vector->list (s8vector-segment (s8vector 1 2 3 4) 3)))
(test-equal '((1) (2)) (map s8vector->list (s8vector-segment (s8vector 1 2) 1)))
(test-equal '() (s8vector-segment (s8vector) 2))
;; SRFI 160: "It is an error if n is not an exact positive integer."
;; Regression, #1949: %uvec-segment used to advance with
;; (min len (+ start n)), so n = 0 looped forever on any non-empty vector
;; while consing a fresh zero-length copy each iteration — on all 12 kinds.
;; It now rejects a non-positive (or inexact, or non-integer) n at entry,
;; before the loop, so even the empty vector raises rather than answering.
(test-equal "segment n = -1 raises" 'ERR (try (lambda () (s8vector-segment (s8vector 1 2) -1))))
(test-equal "segment n = 0 raises catchably (NumericVector branch)"
            'ERR (try (lambda () (s8vector-segment (s8vector 1 2 3 4) 0))))
(test-equal "segment n = 0 raises catchably (bytevector branch)"
            'ERR (try (lambda () (u8vector-segment (u8vector 1 2 3 4) 0))))
(test-equal "segment n = 0 raises even on the empty vector"
            'ERR (try (lambda () (s8vector-segment (s8vector) 0))))
(test-equal "segment with an inexact n raises"
            'ERR (try (lambda () (s8vector-segment (s8vector 1 2) 2.0))))
;; The guard lives once in %uvec-segment, so s8/u8 above already prove both
;; dispatch branches — this sweep pins that every public wrapper reaches it,
;; so a future per-kind split cannot drop the guard for one kind unnoticed.
(for-each
 (lambda (row seg)
   (test-equal (nm (k-name row) "vector-segment rejects n = 0") 'ERR
               (try (lambda () (seg ((k-make row) 2) 0)))))
 all-kinds
 (list s8vector-segment u8vector-segment u16vector-segment s16vector-segment
       u32vector-segment s32vector-segment u64vector-segment s64vector-segment
       f32vector-segment f64vector-segment c64vector-segment c128vector-segment))

;;; ------------------------------------------------------------------
;;; 11. Comparators
;;;
;;; SRFI 160: "@vector-comparator — Variable containing a SRFI 128
;;; comparator whose components provide ordering and hashing of @vectors."
;;; ------------------------------------------------------------------

(test-assert "s8vector-comparator accepts its own kind"
             ((comparator-type-test-predicate s8vector-comparator) (s8vector 1)))
(test-assert "s8vector-comparator rejects another kind"
             (not ((comparator-type-test-predicate s8vector-comparator) (u16vector 1))))
(test-assert "u8vector-comparator accepts a bytevector"
             ((comparator-type-test-predicate u8vector-comparator) (bytevector 1)))
(test-assert "s8vector-comparator equality"
             ((comparator-equality-predicate s8vector-comparator)
              (s8vector 1 2) (s8vector 1 2)))
(test-assert "s8vector-comparator is ordered" (comparator-ordered? s8vector-comparator))
(test-assert "s8vector-comparator ordering"
             ((comparator-ordering-predicate s8vector-comparator)
              (s8vector 1 2) (s8vector 1 3)))
;; Complex numbers have no ordering, so these two correctly omit it.
(test-assert "c64vector-comparator is unordered"
             (not (comparator-ordered? c64vector-comparator)))
(test-assert "c128vector-comparator is unordered"
             (not (comparator-ordered? c128vector-comparator)))
;; Hashing, however, is mandated for every kind.
(test-assert "s8vector-comparator hashes"
             (exact-integer? ((comparator-hash-function s8vector-comparator)
                              (s8vector 1 2))))
(test-assert "f64vector-comparator hashes"
             (exact-integer? ((comparator-hash-function f64vector-comparator)
                              (f64vector 1.5))))
(test-assert "u8vector-comparator hashes"
             (exact-integer? ((comparator-hash-function u8vector-comparator)
                              (bytevector 1 2))))

;;; #1950 (c64/c128 comparator hash raises on every value): %uvec-hash
;;; (lib/srfi/160/base.sld:472) folds with `number-hash`, and number-hash
;;; (lib/srfi/128.sld:54) was `(abs x)`-based, which raised KP3002
;;; "expected number, got #<complex>" for a complex argument. It is now
;;; complex-aware (hashes the real and imaginary components), so the
;;; comparator can hash any c64/c128 vector — including one with genuinely
;;; complex elements. The s8/f64/u8 hash assertions above are controls.
(test-assert "c64vector-comparator hashes"
             (exact-integer? ((comparator-hash-function c64vector-comparator)
                              (c64vector 1.0))))
(test-assert "c128vector-comparator hashes"
             (exact-integer? ((comparator-hash-function c128vector-comparator)
                              (c128vector 1.0))))
(test-assert "c128vector-comparator hashes a genuinely complex element"
             (exact-integer? ((comparator-hash-function c128vector-comparator)
                              (c128vector (make-rectangular 1.5 2.5)))))
(test-assert "equal c128 vectors hash equally"
             (let ((h (comparator-hash-function c128vector-comparator)))
               (= (h (c128vector 1.0 2.0)) (h (c128vector 1.0 2.0)))))
(test-assert "default-hash handles a standalone complex"
             (exact-integer? (default-hash 1+2i)))
;; The comparator must be total over every vector SRFI 160 allows: c64/c128
;; elements may carry infinite or NaN components (pinned by the round-trip
;; tests above), so number-hash has to stay defined there too.
(test-assert "number-hash is total on non-finite reals"
             (and (exact-integer? (number-hash +inf.0))
                  (exact-integer? (number-hash -inf.0))
                  (exact-integer? (number-hash +nan.0))))
(test-assert "number-hash hashes a complex with non-finite components"
             (and (exact-integer? (number-hash 1+inf.0i))
                  (exact-integer? (number-hash +inf.0+1.0i))
                  (exact-integer? (number-hash 1+nan.0i))))
(test-assert "c128vector-comparator hashes a vector with infinite components"
             (let ((v (make-c128vector 1 0.0)))
               (c128vector-set! v 0 (make-rectangular +inf.0 1.0))
               (exact-integer? ((comparator-hash-function c128vector-comparator) v))))
(test-assert "equal non-finite components hash equally"
             (let ((h (comparator-hash-function c128vector-comparator)))
               (= (h (c128vector +inf.0)) (h (c128vector +inf.0)))))

;;; ------------------------------------------------------------------
;;; 12. write-@vector and the external representation
;;;
;;; SRFI 160's lexical-syntax section is titled "Optional lexical syntax",
;;; so omitting the `#s8(...)` read syntax is permitted. What is pinned
;;; here is the resulting INCONSISTENCY: u8 writes the spec's readable
;;; `#u8(...)` because it is a bytevector, while the other 11 kinds write
;;; an unreadable `#<...>` form. If the read syntax is ever added, these
;;; are the assertions to revisit.
;;; ------------------------------------------------------------------

(test-equal "#u8(1 2 3)" (write-to-string (u8vector 1 2 3)))
(test-equal "#<s8vector 1 2 3>" (write-to-string (s8vector 1 2 3)))
(test-equal "#<f32vector 1.5>" (write-to-string (f32vector 1.5)))
(test-assert "write-s8vector writes what write writes"
             (let ((p (open-output-string)))
               (write-s8vector (s8vector 1 2) p)
               (string=? "#<s8vector 1 2>" (get-output-string p))))
(test-assert "write-u8vector writes the spec's readable syntax"
             (let ((p (open-output-string)))
               (write-u8vector (u8vector 1 2) p)
               (string=? "#u8(1 2)" (get-output-string p))))

;;; ------------------------------------------------------------------
;;; 13. The six native primitives, called directly (D1)
;;;
;;; These are registered under .srfi_160_primitives, but like every other
;;; `%`-prefixed primitive they are reachable from a plain script with no
;;; import at all — so they must reject bad input catchably on their own,
;;; not merely behind the portable wrappers that normally call them.
;;; ------------------------------------------------------------------

(test-equal #f (%numeric-vector? 1))
(test-equal #f (%numeric-vector? (bytevector 1 2)))
(test-equal #t (%numeric-vector? (s8vector 1)))
(test-equal 's8 (%numeric-vector-kind (%make-numeric-vector 's8 2 0)))
(test-equal 'c128 (%numeric-vector-kind (%make-numeric-vector 'c128 1 0.0)))
(test-equal 2 (%numeric-vector-length (%make-numeric-vector 'u16 2 0)))
(test-equal 0 (%numeric-vector-length (%make-numeric-vector 'u16 0 0)))
(test-equal 'ERR (try (lambda () (%make-numeric-vector 'nosuchkind 1 0))))
(test-equal 'ERR (try (lambda () (%make-numeric-vector "s8" 1 0))))
(test-equal 'ERR (try (lambda () (%make-numeric-vector 's8 -1 0))))
(test-equal 'ERR (try (lambda () (%make-numeric-vector 's8 1 999))))
(test-equal 'ERR (try (lambda () (%make-numeric-vector 's8 1.0 0))))
;; u8 is deliberately NOT a NumericVector kind — it is a bytevector.
(test-equal 'ERR (try (lambda () (%make-numeric-vector 'u8 1 0))))
(test-equal 'ERR (try (lambda () (%numeric-vector-kind 1))))
(test-equal 'ERR (try (lambda () (%numeric-vector-kind (bytevector 1)))))
(test-equal 'ERR (try (lambda () (%numeric-vector-length 'x))))
(test-equal 'ERR (try (lambda () (%numeric-vector-ref (bytevector 1 2) 0))))
(test-equal 'ERR (try (lambda () (%numeric-vector-set! (bytevector 1 2) 0 1))))
(test-equal 'ERR (try (lambda () (%numeric-vector-ref "notavector" 0))))
;; A very large but fixnum-range length must be rejected catchably rather
;; than aborting on an allocation the GC cannot serve.
(test-equal 'ERR (try (lambda () (%make-numeric-vector 'c128 140737488355327 0.0))))

;;; ------------------------------------------------------------------
;;; 14. Zero-length vectors of every kind
;;; ------------------------------------------------------------------

(for-each
 (lambda (row)
   (let* ((n (k-name row))
          (float? (memq n '(f32 f64 c64 c128)))
          (v ((k-make row) 0 (if float? 0.0 0))))
     (test-equal (nm n " empty length") 0 (%uvec-len v))
     (test-equal (nm n " empty vector satisfies its own predicate") #t
                 (and ((cdr (assq n vec-preds)) v) #t))
     (test-equal (nm n " ref on empty is rejected") 'ERR
                 (try (lambda () ((k-ref row) v 0))))))
 all-kinds)

;;; ------------------------------------------------------------------
;;; 15. Callbacks
;;;
;;; Every kind-constructing generic writes its callback's result straight
;;; into a freshly allocated vector through %uvec-set!, so a callback is
;;; both an error-propagation path and a second, later-bound source of
;;; out-of-range values. Both must behave like a direct set!.
;;; ------------------------------------------------------------------

(define (raises-boom thunk)
  (eq? 'caught
       (call-with-current-continuation
        (lambda (k) (with-exception-handler (lambda (e) (k 'caught)) thunk)))))

(define (boom . args) (error "boom"))

(for-each
 (lambda (pr)
   (test-assert (nm "error propagates out of " (car pr)) (raises-boom (cdr pr))))
 (list (cons "s8vector-map"      (lambda () (s8vector-map boom v5)))
       (cons "s8vector-map!"     (lambda () (s8vector-map! boom (s8vector-copy v5))))
       (cons "s8vector-for-each" (lambda () (s8vector-for-each boom v5)))
       (cons "s8vector-fold"     (lambda () (s8vector-fold boom 0 v5)))
       (cons "s8vector-fold-right" (lambda () (s8vector-fold-right boom 0 v5)))
       (cons "s8vector-filter"   (lambda () (s8vector-filter boom v5)))
       (cons "s8vector-remove"   (lambda () (s8vector-remove boom v5)))
       (cons "s8vector-any"      (lambda () (s8vector-any boom v5)))
       (cons "s8vector-every"    (lambda () (s8vector-every boom v5)))
       (cons "s8vector-count"    (lambda () (s8vector-count boom v5)))
       (cons "s8vector-index"    (lambda () (s8vector-index boom v5)))
       (cons "s8vector-partition" (lambda () (s8vector-partition boom v5)))
       (cons "s8vector-unfold"   (lambda () (s8vector-unfold boom 3)))
       (cons "s8vector-cumulate" (lambda () (s8vector-cumulate boom 0 v5)))
       (cons "s8vector-take-while" (lambda () (s8vector-take-while boom v5)))
       (cons "s8vector-drop-while" (lambda () (s8vector-drop-while boom v5)))
       ;; the u8 branch dispatches through bytevector-u8-set!, so it is a
       ;; separate propagation path from the 11 NumericVector kinds
       (cons "u8vector-map"      (lambda () (u8vector-map boom (u8vector 1 2))))
       (cons "u8vector-unfold"   (lambda () (u8vector-unfold boom 2)))))

;; An escaping continuation captured inside a callback must unwind cleanly.
(test-equal 'escaped
            (call-with-current-continuation
             (lambda (k)
               (s8vector-for-each (lambda (x) (when (= x 2) (k 'escaped))) v5)
               'no-escape)))
(test-equal 'escaped
            (call-with-current-continuation
             (lambda (k)
               (s8vector-map (lambda (x) (if (= x 2) (k 'escaped) x)) v5)
               'no-escape)))

;; A callback returning an out-of-range value must be rejected exactly as a
;; direct set! would be — never silently truncated into the element width.
(for-each
 (lambda (row)
   (let* ((n (k-name row))
          (float? (memq n '(f32 f64 c64 c128))))
     (unless float?
       (test-assert (nm n " rejects an out-of-range value from an unfold callback")
                    (raises-boom
                     (lambda ()
                       (%uvec-len
                        (case n
                          ((s8) (s8vector-unfold (lambda (i) 99999) 2))
                          ((u8) (u8vector-unfold (lambda (i) 99999) 2))
                          ((u16) (u16vector-unfold (lambda (i) -1) 2))
                          ((s16) (s16vector-unfold (lambda (i) 99999) 2))
                          ((u32) (u32vector-unfold (lambda (i) -1) 2))
                          ((s32) (s32vector-unfold (lambda (i) (expt 2 40)) 2))
                          ((u64) (u64vector-unfold (lambda (i) -1) 2))
                          ((s64) (s64vector-unfold (lambda (i) (expt 2 70)) 2))
                          (else 0))))))
       (test-assert (nm n " rejects a non-integer from an unfold callback")
                    (raises-boom
                     (lambda ()
                       (%uvec-len
                        (case n
                          ((s8) (s8vector-unfold (lambda (i) 1.5) 2))
                          ((u8) (u8vector-unfold (lambda (i) 1.5) 2))
                          ((u16) (u16vector-unfold (lambda (i) 1.5) 2))
                          ((s16) (s16vector-unfold (lambda (i) 1.5) 2))
                          ((u32) (u32vector-unfold (lambda (i) 1.5) 2))
                          ((s32) (s32vector-unfold (lambda (i) 1.5) 2))
                          ((u64) (u64vector-unfold (lambda (i) 1.5) 2))
                          ((s64) (s64vector-unfold (lambda (i) 1.5) 2))
                          (else 0)))))))))
 int-kinds)

;;; ------------------------------------------------------------------
;;; 16. equal? vs Uvector=
;;;
;;; These are two different equivalences on the same objects and they
;;; disagree in three ways, all reachable from ordinary code. Neither is
;;; wrong — equal? on a NumericVector is bytewise, generalising R7RS's
;;; bytewise equal? on bytevectors (src/primitives.zig:908 compares kind
;;; AND bytes), while Uvector= folds numeric `=` over the elements — but
;;; the contrast is undocumented and easy to trip over.
;;; ------------------------------------------------------------------

(test-assert "equal? is #t for same kind and same bytes"
             (equal? (s8vector 1 2) (s8vector 1 2)))
;; equal? checks the kind; Uvector= does not.
(test-assert "equal? distinguishes kinds"
             (not (equal? (s8vector 1 2) (u16vector 1 2))))
(test-assert "Uvector= does not check the kind"
             (s8vector= (s8vector 1 2) (u16vector 1 2)))
;; equal? is bitwise, so 0.0 and -0.0 differ; numeric = says they are equal.
(test-assert "equal? separates 0.0 from -0.0"
             (not (equal? (f64vector 0.0) (f64vector -0.0))))
(test-assert "Uvector= equates 0.0 and -0.0"
             (f64vector= (f64vector 0.0) (f64vector -0.0)))
;; and conversely, bitwise equality makes NaN equal to itself while = does not.
(test-assert "equal? equates two identical NaN payloads"
             (equal? (f64vector (/ 0.0 0.0)) (f64vector (/ 0.0 0.0))))
(test-assert "Uvector= does not equate NaN with NaN"
             (not (f64vector= (f64vector (/ 0.0 0.0)) (f64vector (/ 0.0 0.0)))))

(let ((runner (test-runner-current)))
  (test-end "primitives_srfi160 audit")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
