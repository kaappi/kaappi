;;; SRFI 14: Character-set Library
;;;
;;; A char set is an *inversion list*: a record wrapping a list of inclusive
;;; `(lo . hi)` code-point pairs, kept sorted, disjoint and non-adjacent.  That
;;; canonical form is what makes this a set rather than the multiset the
;;; previous member-list implementation was (kaappi#1895) — `equal?` on two
;;; range lists decides `char-set=` outright — and it is what makes
;;; `char-set:full` and `char-set-complement` representable at all: the whole
;;; Unicode space is two pairs, not 1.1 million list cells.
;;;
;;; Surrogates are excluded everywhere.  `integer->char` rejects D800–DFFF, so
;;; those code points have no character representative in this implementation;
;;; `char-set:full` is `((0 . #xD7FF) (#xE000 . #x10FFFF))` and complement is
;;; taken relative to it.  `ucs-range->char-set` treats them as the spec's
;;; "valid, assigned UCS character that has no corresponding representative"
;;; case: ignored by default, an error when `error?` is true.
;;;
;;; Every standard `char-set:*` constant is a literal built from generated
;;; Unicode general-category tables (see the block just above the constants —
;;; a library body is letrec*), produced by
;;; `tools/gen_srfi_charsets.py --target 14`, the same generator and the same
;;; arrangement `lib/srfi/115.sld` already uses.  Regenerate on a Unicode
;;; version bump.  Two things forced that over the obvious alternative of
;;; scanning the code-point space with `(scheme char)`'s own predicates:
;;;
;;;   * A scan costs ~0.14s per predicate — 0.7s for the five sets that need
;;;     one — which is far too much to pay at every `(import (srfi 14))`.
;;;   * Making the scan lazy and memoised is *unsafe in this engine*, not
;;;     merely inelegant.  Globals are shared between SRFI-18 threads by
;;;     pointer while heaps are per-thread, so a child thread that forces a
;;;     memo writes a child-heap value into a parent-heap record, and the
;;;     parent reads freed memory once the child is joined.  Reproduced with
;;;     no char sets involved at all: a `define-record-type` box, `set!` from
;;;     one thread, read from the main thread after `thread-join!`.  A field
;;;     holding a fixnum survives; one holding a fresh pair does not.  So no
;;;     char set is ever mutated after construction, and there is nothing
;;;     here for that bug to corrupt.
;;;
;;; Deriving from the categories is also what the spec actually asks for — it
;;; defines each set by general category, not by R7RS predicate — but it does
;;; mean two visible disagreements with `(scheme char)`, both intentional and
;;; both pinned by tests:
;;;
;;;   * `char-set:letter` is Lu/Ll/Lt/Lm/Lo, while `char-alphabetic?` answers
;;;     for the broader Unicode *Alphabetic* property.  `(char-alphabetic?
;;;     #\x2160)` is #t (Nl, a Roman numeral); that character is not a letter
;;;     by SRFI 14's definition.  Each predicate is right for its own spec.
;;;   * `char-set:digit` is all 680 of Nd, while `char-numeric?` covers only
;;;     the 370 in the BMP — its `isUnicodeNumeric` table
;;;     (`src/primitives_char.zig`) is a hand-maintained list of 36 "digit
;;;     zero" code points and omits every supplementary-plane digit.  Here
;;;     the char set is right and the predicate is not.
;;;
;;; One further deliberate deviation: the `!` linear-update variants are pure
;;; aliases of their functional counterparts.  The spec permits exactly this
;;; ("allowed, but not required, to side-effect"), and clients may not rely on
;;; the side effect in any case.
;;;
;;; Every name in the SRFI's export list is implemented; none is omitted.

(define-library (srfi 14)
  (import (scheme base) (scheme char))
  (export char-set? char-set= char-set<= char-set-hash
          char-set-cursor char-set-ref char-set-cursor-next end-of-char-set?
          char-set-fold char-set-unfold char-set-unfold!
          char-set-for-each char-set-map
          char-set-copy char-set
          list->char-set list->char-set!
          string->char-set string->char-set!
          char-set-filter char-set-filter!
          ucs-range->char-set ucs-range->char-set!
          ->char-set
          char-set-size char-set-count char-set->list char-set->string
          char-set-contains? char-set-every char-set-any
          char-set-adjoin char-set-adjoin!
          char-set-delete char-set-delete!
          char-set-complement char-set-complement!
          char-set-union char-set-union!
          char-set-intersection char-set-intersection!
          char-set-difference char-set-difference!
          char-set-xor char-set-xor!
          char-set-diff+intersection char-set-diff+intersection!
          char-set:lower-case char-set:upper-case char-set:title-case
          char-set:letter char-set:digit char-set:letter+digit
          char-set:graphic char-set:printing char-set:whitespace
          char-set:iso-control char-set:punctuation char-set:symbol
          char-set:hex-digit char-set:blank char-set:ascii
          char-set:empty char-set:full)
  (begin

    ;;; ------------------------------------------------------ the code space

    (define %cp-last #x10FFFF)
    (define %sur-lo #xD800)
    (define %sur-hi #xDFFF)

    ;; Every code point integer->char accepts, as two ranges.
    (define %full-ranges (list (cons 0 (- %sur-lo 1))
                               (cons (+ %sur-hi 1) %cp-last)))

    ;;; ------------------------------------------------ the char-set record

    ;; A char set is immutable once built: `ranges` is written exactly once,
    ;; by the constructor.  Nothing in this library ever mutates it.  See the
    ;; header for why that is load-bearing rather than merely tidy.
    (define-record-type <char-set>
      (%make-cs ranges)
      char-set?
      (ranges %ranges))

    (define (%check-cs who cs)
      (if (char-set? cs)
          (%ranges cs)
          (error (string-append who ": not a character set") cs)))

    (define (%check-cp who ch)
      (if (char? ch)
          (char->integer ch)
          (error (string-append who ": not a character") ch)))

    ;; The optional trailing base-cs argument of unfold/filter/->char-set
    ;; conversions: its ranges, or the empty set.
    (define (%opt-base who opt)
      (if (pair? opt) (%check-cs who (car opt)) '()))

    ;;; --------------------------------------------- range-list arithmetic
    ;;;
    ;;; Every operation below takes and returns canonical range lists:
    ;;; ascending by `car`, disjoint, and non-adjacent.

    ;; Coalesce a list already sorted by `car`.
    (define (%norm rs)
      (if (null? rs)
          '()
          (let loop ((cur (car rs)) (rest (cdr rs)) (acc '()))
            (if (null? rest)
                (reverse (cons cur acc))
                (let ((nxt (car rest)))
                  (if (<= (car nxt) (+ (cdr cur) 1))
                      (loop (cons (car cur)
                                  (if (> (cdr nxt) (cdr cur)) (cdr nxt) (cdr cur)))
                            (cdr rest)
                            acc)
                      (loop nxt (cdr rest) (cons cur acc))))))))

    ;; Iterative merge: the recursive spelling would nest once per element,
    ;; and a union over the letter/symbol tables is already ~900 ranges deep.
    (define (%merge a b)
      (let loop ((a a) (b b) (acc '()))
        (cond ((null? a) (append (reverse acc) b))
              ((null? b) (append (reverse acc) a))
              ((<= (caar a) (caar b)) (loop (cdr a) b (cons (car a) acc)))
              (else (loop a (cdr b) (cons (car b) acc))))))

    (define (%sort-ranges rs)
      (define (halve l)
        (let loop ((slow l) (fast l) (acc '()))
          (if (or (null? fast) (null? (cdr fast)))
              (cons (reverse acc) slow)
              (loop (cdr slow) (cddr fast) (cons (car slow) acc)))))
      (if (or (null? rs) (null? (cdr rs)))
          rs
          (let ((h (halve rs)))
            (%merge (%sort-ranges (car h)) (%sort-ranges (cdr h))))))

    (define (%union2 a b) (%norm (%merge a b)))

    (define (%intersect2 a b)
      (%norm
        (let loop ((a a) (b b) (acc '()))
          (if (or (null? a) (null? b))
              (reverse acc)
              (let* ((ahi (cdar a))
                     (bhi (cdar b))
                     (lo (if (> (caar a) (caar b)) (caar a) (caar b)))
                     (hi (if (< ahi bhi) ahi bhi))
                     (acc (if (<= lo hi) (cons (cons lo hi) acc) acc)))
                (if (< ahi bhi) (loop (cdr a) b acc) (loop a (cdr b) acc)))))))

    (define (%diff2 a b)
      (%norm
        (let loop ((a a) (b b) (acc '()))
          (cond
            ((null? a) (reverse acc))
            ((null? b) (append (reverse acc) a))
            (else
              (let ((alo (caar a)) (ahi (cdar a))
                    (blo (caar b)) (bhi (cdar b)))
                (cond
                  ((< bhi alo) (loop a (cdr b) acc))
                  ((< ahi blo) (loop (cdr a) b (cons (car a) acc)))
                  (else
                    (let ((acc (if (< alo blo)
                                   (cons (cons alo (- blo 1)) acc)
                                   acc)))
                      (if (> ahi bhi)
                          (loop (cons (cons (+ bhi 1) ahi) (cdr a)) (cdr b) acc)
                          (loop (cdr a) b acc)))))))))))

    (define (%xor2 a b) (%union2 (%diff2 a b) (%diff2 b a)))

    (define (%complement rs) (%diff2 %full-ranges rs))

    (define (%size rs)
      (let loop ((rs rs) (n 0))
        (if (null? rs) n (loop (cdr rs) (+ n 1 (- (cdar rs) (caar rs)))))))

    ;; Ranges are ascending, so a code point below the current range's `car`
    ;; cannot appear later either — ASCII lookups stop after a pair or two even
    ;; in a 700-range set.
    (define (%member? rs cp)
      (let loop ((rs rs))
        (cond ((null? rs) #f)
              ((< cp (caar rs)) #f)
              ((<= cp (cdar rs)) #t)
              (else (loop (cdr rs))))))

    (define (%cps->ranges cps)
      (%norm (%sort-ranges (map (lambda (n) (cons n n)) cps))))

    (define (%chars->cps who chars)
      (map (lambda (c) (%check-cp who c)) chars))

    ;;; ------------------------------------------------------- constructors

    (define (char-set . chars)
      (%make-cs (%cps->ranges (%chars->cps "char-set" chars))))

    (define (list->char-set chars . opt)
      (%make-cs (%union2 (%opt-base "list->char-set" opt)
                         (%cps->ranges (%chars->cps "list->char-set" chars)))))

    (define (string->char-set s . opt)
      (if (not (string? s))
          (error "string->char-set: not a string" s))
      (%make-cs (%union2 (%opt-base "string->char-set" opt)
                         (%cps->ranges (map char->integer (string->list s))))))

    (define (ucs-range->char-set lower upper . opt)
      (if (not (and (exact-integer? lower) (exact-integer? upper)
                    (>= lower 0) (<= lower upper)))
          (error "ucs-range->char-set: bad range" lower upper))
      (let* ((err? (and (pair? opt) (car opt)))
             (base (if (and (pair? opt) (pair? (cdr opt)))
                       (%check-cs "ucs-range->char-set" (cadr opt))
                       '()))
             (raw (if (= lower upper) '() (list (cons lower (- upper 1)))))
             (ok (%intersect2 raw %full-ranges)))
        (if (and err? (not (= (%size raw) (%size ok))))
            (error "ucs-range->char-set: range covers code points with no character representative"
                   lower upper))
        (%make-cs (%union2 base ok))))

    (define (->char-set x)
      (cond ((char-set? x) x)
            ((char? x) (char-set x))
            ((string? x) (string->char-set x))
            (else (error "->char-set: not a char set, string or character" x))))

    (define (char-set-copy cs)
      (%make-cs (%check-cs "char-set-copy" cs)))

    (define (char-set-unfold p f g seed . opt)
      (let loop ((seed seed) (cps '()))
        (if (p seed)
            (%make-cs (%union2 (%opt-base "char-set-unfold" opt)
                               (%cps->ranges cps)))
            (loop (g seed) (cons (%check-cp "char-set-unfold" (f seed)) cps)))))

    ;;; ---------------------------------------------------------- predicates

    (define (char-set-contains? cs ch)
      (%member? (%check-cs "char-set-contains?" cs)
                (%check-cp "char-set-contains?" ch)))

    (define (char-set= . sets)
      (or (null? sets)
          (let ((first (%check-cs "char-set=" (car sets))))
            (let loop ((rest (cdr sets)))
              (or (null? rest)
                  (and (equal? first (%check-cs "char-set=" (car rest)))
                       (loop (cdr rest))))))))

    (define (char-set<= . sets)
      (or (null? sets)
          (let loop ((prev (%check-cs "char-set<=" (car sets)))
                     (rest (cdr sets)))
            (or (null? rest)
                (let ((next (%check-cs "char-set<=" (car rest))))
                  (and (null? (%diff2 prev next))
                       (loop next (cdr rest))))))))

    (define (char-set-hash cs . opt)
      (let* ((given (if (pair? opt) (car opt) 0))
             (bound (if (and (exact-integer? given) (> given 0))
                        given
                        268435456)))
        (let loop ((rs (%check-cs "char-set-hash" cs)) (h 0))
          (if (null? rs)
              (modulo h bound)
              (loop (cdr rs)
                    (modulo (+ (* h 131) (* 31 (caar rs)) (cdar rs))
                            4294967296))))))

    ;;; ------------------------------------------------------------- cursors

    ;; A cursor is `()` at the end, otherwise `(code-point . ranges-tail)`,
    ;; where the tail's first range is the one holding the code point.  That
    ;; makes `end-of-char-set?` a `null?` test on the cursor alone, which is
    ;; all the spec gives it to work with.
    (define (%cursor rs)
      (if (null? rs) '() (cons (caar rs) rs)))

    (define (char-set-cursor cs)
      (%cursor (%check-cs "char-set-cursor" cs)))

    (define (end-of-char-set? cur) (null? cur))

    (define (char-set-ref cs cur)
      (if (null? cur)
          (error "char-set-ref: cursor is past the end of the char set"))
      (integer->char (car cur)))

    (define (char-set-cursor-next cs cur)
      (if (null? cur)
          (error "char-set-cursor-next: cursor is past the end of the char set"))
      (let ((cp (car cur)) (rs (cdr cur)))
        (if (< cp (cdar rs))
            (cons (+ cp 1) rs)
            (%cursor (cdr rs)))))

    ;;; ----------------------------------------------------------- iteration

    (define (char-set-fold kons knil cs)
      (let loop ((rs (%check-cs "char-set-fold" cs)) (acc knil))
        (if (null? rs)
            acc
            (let ((hi (cdar rs)))
              (let inner ((i (caar rs)) (acc acc))
                (if (> i hi)
                    (loop (cdr rs) acc)
                    (inner (+ i 1) (kons (integer->char i) acc))))))))

    (define (char-set-for-each proc cs)
      (char-set-fold (lambda (c acc) (proc c) acc) #f cs)
      (if #f #f))

    (define (char-set-map proc cs)
      (%make-cs
        (%cps->ranges
          (char-set-fold (lambda (c acc)
                           (cons (%check-cp "char-set-map" (proc c)) acc))
                         '() cs))))

    (define (char-set->list cs)
      (let loop ((rs (reverse (%check-cs "char-set->list" cs))) (acc '()))
        (if (null? rs)
            acc
            (let ((lo (caar rs)))
              (let inner ((i (cdar rs)) (acc acc))
                (if (< i lo)
                    (loop (cdr rs) acc)
                    (inner (- i 1) (cons (integer->char i) acc))))))))

    (define (char-set->string cs)
      (list->string (char-set->list cs)))

    (define (char-set-size cs) (%size (%check-cs "char-set-size" cs)))

    (define (char-set-count pred cs)
      (char-set-fold (lambda (c n) (if (pred c) (+ n 1) n)) 0 cs))

    (define (char-set-every pred cs)
      (let loop ((rs (%check-cs "char-set-every" cs)))
        (if (null? rs)
            #t
            (let ((hi (cdar rs)))
              (let inner ((i (caar rs)))
                (cond ((> i hi) (loop (cdr rs)))
                      ((pred (integer->char i)) (inner (+ i 1)))
                      (else #f)))))))

    (define (char-set-any pred cs)
      (let loop ((rs (%check-cs "char-set-any" cs)))
        (if (null? rs)
            #f
            (let ((hi (cdar rs)))
              (let inner ((i (caar rs)))
                (if (> i hi)
                    (loop (cdr rs))
                    (let ((v (pred (integer->char i))))
                      (if v v (inner (+ i 1))))))))))

    (define (char-set-filter pred cs . opt)
      (%make-cs
        (%union2 (%opt-base "char-set-filter" opt)
                 (%norm (reverse
                          (char-set-fold
                            (lambda (c acc)
                              (if (pred c)
                                  (let ((n (char->integer c))) (cons (cons n n) acc))
                                  acc))
                            '() cs))))))

    ;;; ---------------------------------------------------------- set algebra

    (define (char-set-adjoin cs . chars)
      (%make-cs (%union2 (%check-cs "char-set-adjoin" cs)
                         (%cps->ranges (%chars->cps "char-set-adjoin" chars)))))

    (define (char-set-delete cs . chars)
      (%make-cs (%diff2 (%check-cs "char-set-delete" cs)
                        (%cps->ranges (%chars->cps "char-set-delete" chars)))))

    (define (char-set-complement cs)
      (%make-cs (%complement (%check-cs "char-set-complement" cs))))

    (define (char-set-union . sets)
      (%make-cs
        (let loop ((sets sets) (acc '()))
          (if (null? sets)
              acc
              (loop (cdr sets)
                    (%union2 acc (%check-cs "char-set-union" (car sets))))))))

    (define (char-set-intersection . sets)
      (%make-cs
        (let loop ((sets sets) (acc %full-ranges))
          (if (null? sets)
              acc
              (loop (cdr sets)
                    (%intersect2 acc
                                 (%check-cs "char-set-intersection" (car sets))))))))

    (define (char-set-difference cs . sets)
      (%make-cs
        (let loop ((sets sets) (acc (%check-cs "char-set-difference" cs)))
          (if (null? sets)
              acc
              (loop (cdr sets)
                    (%diff2 acc (%check-cs "char-set-difference" (car sets))))))))

    (define (char-set-xor . sets)
      (%make-cs
        (let loop ((sets sets) (acc '()))
          (if (null? sets)
              acc
              (loop (cdr sets)
                    (%xor2 acc (%check-cs "char-set-xor" (car sets))))))))

    (define (char-set-diff+intersection cs . sets)
      (let ((a (%check-cs "char-set-diff+intersection" cs))
            (b (let loop ((sets sets) (acc '()))
                 (if (null? sets)
                     acc
                     (loop (cdr sets)
                           (%union2 acc
                                    (%check-cs "char-set-diff+intersection"
                                               (car sets))))))))
        (values (%make-cs (%diff2 a b)) (%make-cs (%intersect2 a b)))))

    ;;; ------------------------------------------ linear-update aliases
    ;;;
    ;;; "Linear-update procedures are allowed, but not required, to
    ;;; side-effect one of their parameters", and clients may not rely on the
    ;;; side effect.  These take the "not required" branch.

    (define char-set-unfold! char-set-unfold)
    (define list->char-set! list->char-set)
    (define string->char-set! string->char-set)
    (define ucs-range->char-set! ucs-range->char-set)
    (define char-set-filter! char-set-filter)
    (define char-set-adjoin! char-set-adjoin)
    (define char-set-delete! char-set-delete)
    (define char-set-complement! char-set-complement)
    (define char-set-union! char-set-union)
    (define char-set-intersection! char-set-intersection)
    (define char-set-difference! char-set-difference)
    (define char-set-xor! char-set-xor)
    (define char-set-diff+intersection! char-set-diff+intersection)

    ;;; Unicode tables -- generated by
    ;;;   tools/gen_srfi_charsets.py --target 14
    ;;; from UCD 15.1.0.  Do not edit by hand.
    ;;;
    ;;; SRFI 14 defines its standard sets by Unicode general category, so
    ;;; every one of them is a literal from this block -- see the header
    ;;; for why none of them is derived from a (scheme char) predicate.

;;; over (scheme char)'s predicates.  See the library header.

    ;; general categories Lu, Ll, Lt, Lm, Lo (660 ranges)
    (define %tbl-letter
      '((65 . 90) (97 . 122) (170 . 170) (181 . 181) (186 . 186) (192 . 214)
        (216 . 246) (248 . 705) (710 . 721) (736 . 740) (748 . 748)
        (750 . 750) (880 . 884) (886 . 887) (890 . 893) (895 . 895)
        (902 . 902) (904 . 906) (908 . 908) (910 . 929) (931 . 1013)
        (1015 . 1153) (1162 . 1327) (1329 . 1366) (1369 . 1369) (1376 . 1416)
        (1488 . 1514) (1519 . 1522) (1568 . 1610) (1646 . 1647) (1649 . 1747)
        (1749 . 1749) (1765 . 1766) (1774 . 1775) (1786 . 1788) (1791 . 1791)
        (1808 . 1808) (1810 . 1839) (1869 . 1957) (1969 . 1969) (1994 . 2026)
        (2036 . 2037) (2042 . 2042) (2048 . 2069) (2074 . 2074) (2084 . 2084)
        (2088 . 2088) (2112 . 2136) (2144 . 2154) (2160 . 2183) (2185 . 2190)
        (2208 . 2249) (2308 . 2361) (2365 . 2365) (2384 . 2384) (2392 . 2401)
        (2417 . 2432) (2437 . 2444) (2447 . 2448) (2451 . 2472) (2474 . 2480)
        (2482 . 2482) (2486 . 2489) (2493 . 2493) (2510 . 2510) (2524 . 2525)
        (2527 . 2529) (2544 . 2545) (2556 . 2556) (2565 . 2570) (2575 . 2576)
        (2579 . 2600) (2602 . 2608) (2610 . 2611) (2613 . 2614) (2616 . 2617)
        (2649 . 2652) (2654 . 2654) (2674 . 2676) (2693 . 2701) (2703 . 2705)
        (2707 . 2728) (2730 . 2736) (2738 . 2739) (2741 . 2745) (2749 . 2749)
        (2768 . 2768) (2784 . 2785) (2809 . 2809) (2821 . 2828) (2831 . 2832)
        (2835 . 2856) (2858 . 2864) (2866 . 2867) (2869 . 2873) (2877 . 2877)
        (2908 . 2909) (2911 . 2913) (2929 . 2929) (2947 . 2947) (2949 . 2954)
        (2958 . 2960) (2962 . 2965) (2969 . 2970) (2972 . 2972) (2974 . 2975)
        (2979 . 2980) (2984 . 2986) (2990 . 3001) (3024 . 3024) (3077 . 3084)
        (3086 . 3088) (3090 . 3112) (3114 . 3129) (3133 . 3133) (3160 . 3162)
        (3165 . 3165) (3168 . 3169) (3200 . 3200) (3205 . 3212) (3214 . 3216)
        (3218 . 3240) (3242 . 3251) (3253 . 3257) (3261 . 3261) (3293 . 3294)
        (3296 . 3297) (3313 . 3314) (3332 . 3340) (3342 . 3344) (3346 . 3386)
        (3389 . 3389) (3406 . 3406) (3412 . 3414) (3423 . 3425) (3450 . 3455)
        (3461 . 3478) (3482 . 3505) (3507 . 3515) (3517 . 3517) (3520 . 3526)
        (3585 . 3632) (3634 . 3635) (3648 . 3654) (3713 . 3714) (3716 . 3716)
        (3718 . 3722) (3724 . 3747) (3749 . 3749) (3751 . 3760) (3762 . 3763)
        (3773 . 3773) (3776 . 3780) (3782 . 3782) (3804 . 3807) (3840 . 3840)
        (3904 . 3911) (3913 . 3948) (3976 . 3980) (4096 . 4138) (4159 . 4159)
        (4176 . 4181) (4186 . 4189) (4193 . 4193) (4197 . 4198) (4206 . 4208)
        (4213 . 4225) (4238 . 4238) (4256 . 4293) (4295 . 4295) (4301 . 4301)
        (4304 . 4346) (4348 . 4680) (4682 . 4685) (4688 . 4694) (4696 . 4696)
        (4698 . 4701) (4704 . 4744) (4746 . 4749) (4752 . 4784) (4786 . 4789)
        (4792 . 4798) (4800 . 4800) (4802 . 4805) (4808 . 4822) (4824 . 4880)
        (4882 . 4885) (4888 . 4954) (4992 . 5007) (5024 . 5109) (5112 . 5117)
        (5121 . 5740) (5743 . 5759) (5761 . 5786) (5792 . 5866) (5873 . 5880)
        (5888 . 5905) (5919 . 5937) (5952 . 5969) (5984 . 5996) (5998 . 6000)
        (6016 . 6067) (6103 . 6103) (6108 . 6108) (6176 . 6264) (6272 . 6276)
        (6279 . 6312) (6314 . 6314) (6320 . 6389) (6400 . 6430) (6480 . 6509)
        (6512 . 6516) (6528 . 6571) (6576 . 6601) (6656 . 6678) (6688 . 6740)
        (6823 . 6823) (6917 . 6963) (6981 . 6988) (7043 . 7072) (7086 . 7087)
        (7098 . 7141) (7168 . 7203) (7245 . 7247) (7258 . 7293) (7296 . 7304)
        (7312 . 7354) (7357 . 7359) (7401 . 7404) (7406 . 7411) (7413 . 7414)
        (7418 . 7418) (7424 . 7615) (7680 . 7957) (7960 . 7965) (7968 . 8005)
        (8008 . 8013) (8016 . 8023) (8025 . 8025) (8027 . 8027) (8029 . 8029)
        (8031 . 8061) (8064 . 8116) (8118 . 8124) (8126 . 8126) (8130 . 8132)
        (8134 . 8140) (8144 . 8147) (8150 . 8155) (8160 . 8172) (8178 . 8180)
        (8182 . 8188) (8305 . 8305) (8319 . 8319) (8336 . 8348) (8450 . 8450)
        (8455 . 8455) (8458 . 8467) (8469 . 8469) (8473 . 8477) (8484 . 8484)
        (8486 . 8486) (8488 . 8488) (8490 . 8493) (8495 . 8505) (8508 . 8511)
        (8517 . 8521) (8526 . 8526) (8579 . 8580) (11264 . 11492)
        (11499 . 11502) (11506 . 11507) (11520 . 11557) (11559 . 11559)
        (11565 . 11565) (11568 . 11623) (11631 . 11631) (11648 . 11670)
        (11680 . 11686) (11688 . 11694) (11696 . 11702) (11704 . 11710)
        (11712 . 11718) (11720 . 11726) (11728 . 11734) (11736 . 11742)
        (11823 . 11823) (12293 . 12294) (12337 . 12341) (12347 . 12348)
        (12353 . 12438) (12445 . 12447) (12449 . 12538) (12540 . 12543)
        (12549 . 12591) (12593 . 12686) (12704 . 12735) (12784 . 12799)
        (13312 . 19903) (19968 . 42124) (42192 . 42237) (42240 . 42508)
        (42512 . 42527) (42538 . 42539) (42560 . 42606) (42623 . 42653)
        (42656 . 42725) (42775 . 42783) (42786 . 42888) (42891 . 42954)
        (42960 . 42961) (42963 . 42963) (42965 . 42969) (42994 . 43009)
        (43011 . 43013) (43015 . 43018) (43020 . 43042) (43072 . 43123)
        (43138 . 43187) (43250 . 43255) (43259 . 43259) (43261 . 43262)
        (43274 . 43301) (43312 . 43334) (43360 . 43388) (43396 . 43442)
        (43471 . 43471) (43488 . 43492) (43494 . 43503) (43514 . 43518)
        (43520 . 43560) (43584 . 43586) (43588 . 43595) (43616 . 43638)
        (43642 . 43642) (43646 . 43695) (43697 . 43697) (43701 . 43702)
        (43705 . 43709) (43712 . 43712) (43714 . 43714) (43739 . 43741)
        (43744 . 43754) (43762 . 43764) (43777 . 43782) (43785 . 43790)
        (43793 . 43798) (43808 . 43814) (43816 . 43822) (43824 . 43866)
        (43868 . 43881) (43888 . 44002) (44032 . 55203) (55216 . 55238)
        (55243 . 55291) (63744 . 64109) (64112 . 64217) (64256 . 64262)
        (64275 . 64279) (64285 . 64285) (64287 . 64296) (64298 . 64310)
        (64312 . 64316) (64318 . 64318) (64320 . 64321) (64323 . 64324)
        (64326 . 64433) (64467 . 64829) (64848 . 64911) (64914 . 64967)
        (65008 . 65019) (65136 . 65140) (65142 . 65276) (65313 . 65338)
        (65345 . 65370) (65382 . 65470) (65474 . 65479) (65482 . 65487)
        (65490 . 65495) (65498 . 65500) (65536 . 65547) (65549 . 65574)
        (65576 . 65594) (65596 . 65597) (65599 . 65613) (65616 . 65629)
        (65664 . 65786) (66176 . 66204) (66208 . 66256) (66304 . 66335)
        (66349 . 66368) (66370 . 66377) (66384 . 66421) (66432 . 66461)
        (66464 . 66499) (66504 . 66511) (66560 . 66717) (66736 . 66771)
        (66776 . 66811) (66816 . 66855) (66864 . 66915) (66928 . 66938)
        (66940 . 66954) (66956 . 66962) (66964 . 66965) (66967 . 66977)
        (66979 . 66993) (66995 . 67001) (67003 . 67004) (67072 . 67382)
        (67392 . 67413) (67424 . 67431) (67456 . 67461) (67463 . 67504)
        (67506 . 67514) (67584 . 67589) (67592 . 67592) (67594 . 67637)
        (67639 . 67640) (67644 . 67644) (67647 . 67669) (67680 . 67702)
        (67712 . 67742) (67808 . 67826) (67828 . 67829) (67840 . 67861)
        (67872 . 67897) (67968 . 68023) (68030 . 68031) (68096 . 68096)
        (68112 . 68115) (68117 . 68119) (68121 . 68149) (68192 . 68220)
        (68224 . 68252) (68288 . 68295) (68297 . 68324) (68352 . 68405)
        (68416 . 68437) (68448 . 68466) (68480 . 68497) (68608 . 68680)
        (68736 . 68786) (68800 . 68850) (68864 . 68899) (69248 . 69289)
        (69296 . 69297) (69376 . 69404) (69415 . 69415) (69424 . 69445)
        (69488 . 69505) (69552 . 69572) (69600 . 69622) (69635 . 69687)
        (69745 . 69746) (69749 . 69749) (69763 . 69807) (69840 . 69864)
        (69891 . 69926) (69956 . 69956) (69959 . 69959) (69968 . 70002)
        (70006 . 70006) (70019 . 70066) (70081 . 70084) (70106 . 70106)
        (70108 . 70108) (70144 . 70161) (70163 . 70187) (70207 . 70208)
        (70272 . 70278) (70280 . 70280) (70282 . 70285) (70287 . 70301)
        (70303 . 70312) (70320 . 70366) (70405 . 70412) (70415 . 70416)
        (70419 . 70440) (70442 . 70448) (70450 . 70451) (70453 . 70457)
        (70461 . 70461) (70480 . 70480) (70493 . 70497) (70656 . 70708)
        (70727 . 70730) (70751 . 70753) (70784 . 70831) (70852 . 70853)
        (70855 . 70855) (71040 . 71086) (71128 . 71131) (71168 . 71215)
        (71236 . 71236) (71296 . 71338) (71352 . 71352) (71424 . 71450)
        (71488 . 71494) (71680 . 71723) (71840 . 71903) (71935 . 71942)
        (71945 . 71945) (71948 . 71955) (71957 . 71958) (71960 . 71983)
        (71999 . 71999) (72001 . 72001) (72096 . 72103) (72106 . 72144)
        (72161 . 72161) (72163 . 72163) (72192 . 72192) (72203 . 72242)
        (72250 . 72250) (72272 . 72272) (72284 . 72329) (72349 . 72349)
        (72368 . 72440) (72704 . 72712) (72714 . 72750) (72768 . 72768)
        (72818 . 72847) (72960 . 72966) (72968 . 72969) (72971 . 73008)
        (73030 . 73030) (73056 . 73061) (73063 . 73064) (73066 . 73097)
        (73112 . 73112) (73440 . 73458) (73474 . 73474) (73476 . 73488)
        (73490 . 73523) (73648 . 73648) (73728 . 74649) (74880 . 75075)
        (77712 . 77808) (77824 . 78895) (78913 . 78918) (82944 . 83526)
        (92160 . 92728) (92736 . 92766) (92784 . 92862) (92880 . 92909)
        (92928 . 92975) (92992 . 92995) (93027 . 93047) (93053 . 93071)
        (93760 . 93823) (93952 . 94026) (94032 . 94032) (94099 . 94111)
        (94176 . 94177) (94179 . 94179) (94208 . 100343) (100352 . 101589)
        (101632 . 101640) (110576 . 110579) (110581 . 110587)
        (110589 . 110590) (110592 . 110882) (110898 . 110898)
        (110928 . 110930) (110933 . 110933) (110948 . 110951)
        (110960 . 111355) (113664 . 113770) (113776 . 113788)
        (113792 . 113800) (113808 . 113817) (119808 . 119892)
        (119894 . 119964) (119966 . 119967) (119970 . 119970)
        (119973 . 119974) (119977 . 119980) (119982 . 119993)
        (119995 . 119995) (119997 . 120003) (120005 . 120069)
        (120071 . 120074) (120077 . 120084) (120086 . 120092)
        (120094 . 120121) (120123 . 120126) (120128 . 120132)
        (120134 . 120134) (120138 . 120144) (120146 . 120485)
        (120488 . 120512) (120514 . 120538) (120540 . 120570)
        (120572 . 120596) (120598 . 120628) (120630 . 120654)
        (120656 . 120686) (120688 . 120712) (120714 . 120744)
        (120746 . 120770) (120772 . 120779) (122624 . 122654)
        (122661 . 122666) (122928 . 122989) (123136 . 123180)
        (123191 . 123197) (123214 . 123214) (123536 . 123565)
        (123584 . 123627) (124112 . 124139) (124896 . 124902)
        (124904 . 124907) (124909 . 124910) (124912 . 124926)
        (124928 . 125124) (125184 . 125251) (125259 . 125259)
        (126464 . 126467) (126469 . 126495) (126497 . 126498)
        (126500 . 126500) (126503 . 126503) (126505 . 126514)
        (126516 . 126519) (126521 . 126521) (126523 . 126523)
        (126530 . 126530) (126535 . 126535) (126537 . 126537)
        (126539 . 126539) (126541 . 126543) (126545 . 126546)
        (126548 . 126548) (126551 . 126551) (126553 . 126553)
        (126555 . 126555) (126557 . 126557) (126559 . 126559)
        (126561 . 126562) (126564 . 126564) (126567 . 126570)
        (126572 . 126578) (126580 . 126583) (126585 . 126588)
        (126590 . 126590) (126592 . 126601) (126603 . 126619)
        (126625 . 126627) (126629 . 126633) (126635 . 126651)
        (131072 . 173791) (173824 . 177977) (177984 . 178205)
        (178208 . 183969) (183984 . 191456) (191472 . 192093)
        (194560 . 195101) (196608 . 201546) (201552 . 205743)))

    ;; general category Ll (658 ranges)
    (define %tbl-lower-case
      '((97 . 122) (181 . 181) (223 . 246) (248 . 255) (257 . 257)
        (259 . 259) (261 . 261) (263 . 263) (265 . 265) (267 . 267)
        (269 . 269) (271 . 271) (273 . 273) (275 . 275) (277 . 277)
        (279 . 279) (281 . 281) (283 . 283) (285 . 285) (287 . 287)
        (289 . 289) (291 . 291) (293 . 293) (295 . 295) (297 . 297)
        (299 . 299) (301 . 301) (303 . 303) (305 . 305) (307 . 307)
        (309 . 309) (311 . 312) (314 . 314) (316 . 316) (318 . 318)
        (320 . 320) (322 . 322) (324 . 324) (326 . 326) (328 . 329)
        (331 . 331) (333 . 333) (335 . 335) (337 . 337) (339 . 339)
        (341 . 341) (343 . 343) (345 . 345) (347 . 347) (349 . 349)
        (351 . 351) (353 . 353) (355 . 355) (357 . 357) (359 . 359)
        (361 . 361) (363 . 363) (365 . 365) (367 . 367) (369 . 369)
        (371 . 371) (373 . 373) (375 . 375) (378 . 378) (380 . 380)
        (382 . 384) (387 . 387) (389 . 389) (392 . 392) (396 . 397)
        (402 . 402) (405 . 405) (409 . 411) (414 . 414) (417 . 417)
        (419 . 419) (421 . 421) (424 . 424) (426 . 427) (429 . 429)
        (432 . 432) (436 . 436) (438 . 438) (441 . 442) (445 . 447)
        (454 . 454) (457 . 457) (460 . 460) (462 . 462) (464 . 464)
        (466 . 466) (468 . 468) (470 . 470) (472 . 472) (474 . 474)
        (476 . 477) (479 . 479) (481 . 481) (483 . 483) (485 . 485)
        (487 . 487) (489 . 489) (491 . 491) (493 . 493) (495 . 496)
        (499 . 499) (501 . 501) (505 . 505) (507 . 507) (509 . 509)
        (511 . 511) (513 . 513) (515 . 515) (517 . 517) (519 . 519)
        (521 . 521) (523 . 523) (525 . 525) (527 . 527) (529 . 529)
        (531 . 531) (533 . 533) (535 . 535) (537 . 537) (539 . 539)
        (541 . 541) (543 . 543) (545 . 545) (547 . 547) (549 . 549)
        (551 . 551) (553 . 553) (555 . 555) (557 . 557) (559 . 559)
        (561 . 561) (563 . 569) (572 . 572) (575 . 576) (578 . 578)
        (583 . 583) (585 . 585) (587 . 587) (589 . 589) (591 . 659)
        (661 . 687) (881 . 881) (883 . 883) (887 . 887) (891 . 893)
        (912 . 912) (940 . 974) (976 . 977) (981 . 983) (985 . 985)
        (987 . 987) (989 . 989) (991 . 991) (993 . 993) (995 . 995)
        (997 . 997) (999 . 999) (1001 . 1001) (1003 . 1003) (1005 . 1005)
        (1007 . 1011) (1013 . 1013) (1016 . 1016) (1019 . 1020) (1072 . 1119)
        (1121 . 1121) (1123 . 1123) (1125 . 1125) (1127 . 1127) (1129 . 1129)
        (1131 . 1131) (1133 . 1133) (1135 . 1135) (1137 . 1137) (1139 . 1139)
        (1141 . 1141) (1143 . 1143) (1145 . 1145) (1147 . 1147) (1149 . 1149)
        (1151 . 1151) (1153 . 1153) (1163 . 1163) (1165 . 1165) (1167 . 1167)
        (1169 . 1169) (1171 . 1171) (1173 . 1173) (1175 . 1175) (1177 . 1177)
        (1179 . 1179) (1181 . 1181) (1183 . 1183) (1185 . 1185) (1187 . 1187)
        (1189 . 1189) (1191 . 1191) (1193 . 1193) (1195 . 1195) (1197 . 1197)
        (1199 . 1199) (1201 . 1201) (1203 . 1203) (1205 . 1205) (1207 . 1207)
        (1209 . 1209) (1211 . 1211) (1213 . 1213) (1215 . 1215) (1218 . 1218)
        (1220 . 1220) (1222 . 1222) (1224 . 1224) (1226 . 1226) (1228 . 1228)
        (1230 . 1231) (1233 . 1233) (1235 . 1235) (1237 . 1237) (1239 . 1239)
        (1241 . 1241) (1243 . 1243) (1245 . 1245) (1247 . 1247) (1249 . 1249)
        (1251 . 1251) (1253 . 1253) (1255 . 1255) (1257 . 1257) (1259 . 1259)
        (1261 . 1261) (1263 . 1263) (1265 . 1265) (1267 . 1267) (1269 . 1269)
        (1271 . 1271) (1273 . 1273) (1275 . 1275) (1277 . 1277) (1279 . 1279)
        (1281 . 1281) (1283 . 1283) (1285 . 1285) (1287 . 1287) (1289 . 1289)
        (1291 . 1291) (1293 . 1293) (1295 . 1295) (1297 . 1297) (1299 . 1299)
        (1301 . 1301) (1303 . 1303) (1305 . 1305) (1307 . 1307) (1309 . 1309)
        (1311 . 1311) (1313 . 1313) (1315 . 1315) (1317 . 1317) (1319 . 1319)
        (1321 . 1321) (1323 . 1323) (1325 . 1325) (1327 . 1327) (1376 . 1416)
        (4304 . 4346) (4349 . 4351) (5112 . 5117) (7296 . 7304) (7424 . 7467)
        (7531 . 7543) (7545 . 7578) (7681 . 7681) (7683 . 7683) (7685 . 7685)
        (7687 . 7687) (7689 . 7689) (7691 . 7691) (7693 . 7693) (7695 . 7695)
        (7697 . 7697) (7699 . 7699) (7701 . 7701) (7703 . 7703) (7705 . 7705)
        (7707 . 7707) (7709 . 7709) (7711 . 7711) (7713 . 7713) (7715 . 7715)
        (7717 . 7717) (7719 . 7719) (7721 . 7721) (7723 . 7723) (7725 . 7725)
        (7727 . 7727) (7729 . 7729) (7731 . 7731) (7733 . 7733) (7735 . 7735)
        (7737 . 7737) (7739 . 7739) (7741 . 7741) (7743 . 7743) (7745 . 7745)
        (7747 . 7747) (7749 . 7749) (7751 . 7751) (7753 . 7753) (7755 . 7755)
        (7757 . 7757) (7759 . 7759) (7761 . 7761) (7763 . 7763) (7765 . 7765)
        (7767 . 7767) (7769 . 7769) (7771 . 7771) (7773 . 7773) (7775 . 7775)
        (7777 . 7777) (7779 . 7779) (7781 . 7781) (7783 . 7783) (7785 . 7785)
        (7787 . 7787) (7789 . 7789) (7791 . 7791) (7793 . 7793) (7795 . 7795)
        (7797 . 7797) (7799 . 7799) (7801 . 7801) (7803 . 7803) (7805 . 7805)
        (7807 . 7807) (7809 . 7809) (7811 . 7811) (7813 . 7813) (7815 . 7815)
        (7817 . 7817) (7819 . 7819) (7821 . 7821) (7823 . 7823) (7825 . 7825)
        (7827 . 7827) (7829 . 7837) (7839 . 7839) (7841 . 7841) (7843 . 7843)
        (7845 . 7845) (7847 . 7847) (7849 . 7849) (7851 . 7851) (7853 . 7853)
        (7855 . 7855) (7857 . 7857) (7859 . 7859) (7861 . 7861) (7863 . 7863)
        (7865 . 7865) (7867 . 7867) (7869 . 7869) (7871 . 7871) (7873 . 7873)
        (7875 . 7875) (7877 . 7877) (7879 . 7879) (7881 . 7881) (7883 . 7883)
        (7885 . 7885) (7887 . 7887) (7889 . 7889) (7891 . 7891) (7893 . 7893)
        (7895 . 7895) (7897 . 7897) (7899 . 7899) (7901 . 7901) (7903 . 7903)
        (7905 . 7905) (7907 . 7907) (7909 . 7909) (7911 . 7911) (7913 . 7913)
        (7915 . 7915) (7917 . 7917) (7919 . 7919) (7921 . 7921) (7923 . 7923)
        (7925 . 7925) (7927 . 7927) (7929 . 7929) (7931 . 7931) (7933 . 7933)
        (7935 . 7943) (7952 . 7957) (7968 . 7975) (7984 . 7991) (8000 . 8005)
        (8016 . 8023) (8032 . 8039) (8048 . 8061) (8064 . 8071) (8080 . 8087)
        (8096 . 8103) (8112 . 8116) (8118 . 8119) (8126 . 8126) (8130 . 8132)
        (8134 . 8135) (8144 . 8147) (8150 . 8151) (8160 . 8167) (8178 . 8180)
        (8182 . 8183) (8458 . 8458) (8462 . 8463) (8467 . 8467) (8495 . 8495)
        (8500 . 8500) (8505 . 8505) (8508 . 8509) (8518 . 8521) (8526 . 8526)
        (8580 . 8580) (11312 . 11359) (11361 . 11361) (11365 . 11366)
        (11368 . 11368) (11370 . 11370) (11372 . 11372) (11377 . 11377)
        (11379 . 11380) (11382 . 11387) (11393 . 11393) (11395 . 11395)
        (11397 . 11397) (11399 . 11399) (11401 . 11401) (11403 . 11403)
        (11405 . 11405) (11407 . 11407) (11409 . 11409) (11411 . 11411)
        (11413 . 11413) (11415 . 11415) (11417 . 11417) (11419 . 11419)
        (11421 . 11421) (11423 . 11423) (11425 . 11425) (11427 . 11427)
        (11429 . 11429) (11431 . 11431) (11433 . 11433) (11435 . 11435)
        (11437 . 11437) (11439 . 11439) (11441 . 11441) (11443 . 11443)
        (11445 . 11445) (11447 . 11447) (11449 . 11449) (11451 . 11451)
        (11453 . 11453) (11455 . 11455) (11457 . 11457) (11459 . 11459)
        (11461 . 11461) (11463 . 11463) (11465 . 11465) (11467 . 11467)
        (11469 . 11469) (11471 . 11471) (11473 . 11473) (11475 . 11475)
        (11477 . 11477) (11479 . 11479) (11481 . 11481) (11483 . 11483)
        (11485 . 11485) (11487 . 11487) (11489 . 11489) (11491 . 11492)
        (11500 . 11500) (11502 . 11502) (11507 . 11507) (11520 . 11557)
        (11559 . 11559) (11565 . 11565) (42561 . 42561) (42563 . 42563)
        (42565 . 42565) (42567 . 42567) (42569 . 42569) (42571 . 42571)
        (42573 . 42573) (42575 . 42575) (42577 . 42577) (42579 . 42579)
        (42581 . 42581) (42583 . 42583) (42585 . 42585) (42587 . 42587)
        (42589 . 42589) (42591 . 42591) (42593 . 42593) (42595 . 42595)
        (42597 . 42597) (42599 . 42599) (42601 . 42601) (42603 . 42603)
        (42605 . 42605) (42625 . 42625) (42627 . 42627) (42629 . 42629)
        (42631 . 42631) (42633 . 42633) (42635 . 42635) (42637 . 42637)
        (42639 . 42639) (42641 . 42641) (42643 . 42643) (42645 . 42645)
        (42647 . 42647) (42649 . 42649) (42651 . 42651) (42787 . 42787)
        (42789 . 42789) (42791 . 42791) (42793 . 42793) (42795 . 42795)
        (42797 . 42797) (42799 . 42801) (42803 . 42803) (42805 . 42805)
        (42807 . 42807) (42809 . 42809) (42811 . 42811) (42813 . 42813)
        (42815 . 42815) (42817 . 42817) (42819 . 42819) (42821 . 42821)
        (42823 . 42823) (42825 . 42825) (42827 . 42827) (42829 . 42829)
        (42831 . 42831) (42833 . 42833) (42835 . 42835) (42837 . 42837)
        (42839 . 42839) (42841 . 42841) (42843 . 42843) (42845 . 42845)
        (42847 . 42847) (42849 . 42849) (42851 . 42851) (42853 . 42853)
        (42855 . 42855) (42857 . 42857) (42859 . 42859) (42861 . 42861)
        (42863 . 42863) (42865 . 42872) (42874 . 42874) (42876 . 42876)
        (42879 . 42879) (42881 . 42881) (42883 . 42883) (42885 . 42885)
        (42887 . 42887) (42892 . 42892) (42894 . 42894) (42897 . 42897)
        (42899 . 42901) (42903 . 42903) (42905 . 42905) (42907 . 42907)
        (42909 . 42909) (42911 . 42911) (42913 . 42913) (42915 . 42915)
        (42917 . 42917) (42919 . 42919) (42921 . 42921) (42927 . 42927)
        (42933 . 42933) (42935 . 42935) (42937 . 42937) (42939 . 42939)
        (42941 . 42941) (42943 . 42943) (42945 . 42945) (42947 . 42947)
        (42952 . 42952) (42954 . 42954) (42961 . 42961) (42963 . 42963)
        (42965 . 42965) (42967 . 42967) (42969 . 42969) (42998 . 42998)
        (43002 . 43002) (43824 . 43866) (43872 . 43880) (43888 . 43967)
        (64256 . 64262) (64275 . 64279) (65345 . 65370) (66600 . 66639)
        (66776 . 66811) (66967 . 66977) (66979 . 66993) (66995 . 67001)
        (67003 . 67004) (68800 . 68850) (71872 . 71903) (93792 . 93823)
        (119834 . 119859) (119886 . 119892) (119894 . 119911)
        (119938 . 119963) (119990 . 119993) (119995 . 119995)
        (119997 . 120003) (120005 . 120015) (120042 . 120067)
        (120094 . 120119) (120146 . 120171) (120198 . 120223)
        (120250 . 120275) (120302 . 120327) (120354 . 120379)
        (120406 . 120431) (120458 . 120485) (120514 . 120538)
        (120540 . 120545) (120572 . 120596) (120598 . 120603)
        (120630 . 120654) (120656 . 120661) (120688 . 120712)
        (120714 . 120719) (120746 . 120770) (120772 . 120777)
        (120779 . 120779) (122624 . 122633) (122635 . 122654)
        (122661 . 122666) (125218 . 125251)))

    ;; general category Lu (646 ranges)
    (define %tbl-upper-case
      '((65 . 90) (192 . 214) (216 . 222) (256 . 256) (258 . 258) (260 . 260)
        (262 . 262) (264 . 264) (266 . 266) (268 . 268) (270 . 270)
        (272 . 272) (274 . 274) (276 . 276) (278 . 278) (280 . 280)
        (282 . 282) (284 . 284) (286 . 286) (288 . 288) (290 . 290)
        (292 . 292) (294 . 294) (296 . 296) (298 . 298) (300 . 300)
        (302 . 302) (304 . 304) (306 . 306) (308 . 308) (310 . 310)
        (313 . 313) (315 . 315) (317 . 317) (319 . 319) (321 . 321)
        (323 . 323) (325 . 325) (327 . 327) (330 . 330) (332 . 332)
        (334 . 334) (336 . 336) (338 . 338) (340 . 340) (342 . 342)
        (344 . 344) (346 . 346) (348 . 348) (350 . 350) (352 . 352)
        (354 . 354) (356 . 356) (358 . 358) (360 . 360) (362 . 362)
        (364 . 364) (366 . 366) (368 . 368) (370 . 370) (372 . 372)
        (374 . 374) (376 . 377) (379 . 379) (381 . 381) (385 . 386)
        (388 . 388) (390 . 391) (393 . 395) (398 . 401) (403 . 404)
        (406 . 408) (412 . 413) (415 . 416) (418 . 418) (420 . 420)
        (422 . 423) (425 . 425) (428 . 428) (430 . 431) (433 . 435)
        (437 . 437) (439 . 440) (444 . 444) (452 . 452) (455 . 455)
        (458 . 458) (461 . 461) (463 . 463) (465 . 465) (467 . 467)
        (469 . 469) (471 . 471) (473 . 473) (475 . 475) (478 . 478)
        (480 . 480) (482 . 482) (484 . 484) (486 . 486) (488 . 488)
        (490 . 490) (492 . 492) (494 . 494) (497 . 497) (500 . 500)
        (502 . 504) (506 . 506) (508 . 508) (510 . 510) (512 . 512)
        (514 . 514) (516 . 516) (518 . 518) (520 . 520) (522 . 522)
        (524 . 524) (526 . 526) (528 . 528) (530 . 530) (532 . 532)
        (534 . 534) (536 . 536) (538 . 538) (540 . 540) (542 . 542)
        (544 . 544) (546 . 546) (548 . 548) (550 . 550) (552 . 552)
        (554 . 554) (556 . 556) (558 . 558) (560 . 560) (562 . 562)
        (570 . 571) (573 . 574) (577 . 577) (579 . 582) (584 . 584)
        (586 . 586) (588 . 588) (590 . 590) (880 . 880) (882 . 882)
        (886 . 886) (895 . 895) (902 . 902) (904 . 906) (908 . 908)
        (910 . 911) (913 . 929) (931 . 939) (975 . 975) (978 . 980)
        (984 . 984) (986 . 986) (988 . 988) (990 . 990) (992 . 992)
        (994 . 994) (996 . 996) (998 . 998) (1000 . 1000) (1002 . 1002)
        (1004 . 1004) (1006 . 1006) (1012 . 1012) (1015 . 1015) (1017 . 1018)
        (1021 . 1071) (1120 . 1120) (1122 . 1122) (1124 . 1124) (1126 . 1126)
        (1128 . 1128) (1130 . 1130) (1132 . 1132) (1134 . 1134) (1136 . 1136)
        (1138 . 1138) (1140 . 1140) (1142 . 1142) (1144 . 1144) (1146 . 1146)
        (1148 . 1148) (1150 . 1150) (1152 . 1152) (1162 . 1162) (1164 . 1164)
        (1166 . 1166) (1168 . 1168) (1170 . 1170) (1172 . 1172) (1174 . 1174)
        (1176 . 1176) (1178 . 1178) (1180 . 1180) (1182 . 1182) (1184 . 1184)
        (1186 . 1186) (1188 . 1188) (1190 . 1190) (1192 . 1192) (1194 . 1194)
        (1196 . 1196) (1198 . 1198) (1200 . 1200) (1202 . 1202) (1204 . 1204)
        (1206 . 1206) (1208 . 1208) (1210 . 1210) (1212 . 1212) (1214 . 1214)
        (1216 . 1217) (1219 . 1219) (1221 . 1221) (1223 . 1223) (1225 . 1225)
        (1227 . 1227) (1229 . 1229) (1232 . 1232) (1234 . 1234) (1236 . 1236)
        (1238 . 1238) (1240 . 1240) (1242 . 1242) (1244 . 1244) (1246 . 1246)
        (1248 . 1248) (1250 . 1250) (1252 . 1252) (1254 . 1254) (1256 . 1256)
        (1258 . 1258) (1260 . 1260) (1262 . 1262) (1264 . 1264) (1266 . 1266)
        (1268 . 1268) (1270 . 1270) (1272 . 1272) (1274 . 1274) (1276 . 1276)
        (1278 . 1278) (1280 . 1280) (1282 . 1282) (1284 . 1284) (1286 . 1286)
        (1288 . 1288) (1290 . 1290) (1292 . 1292) (1294 . 1294) (1296 . 1296)
        (1298 . 1298) (1300 . 1300) (1302 . 1302) (1304 . 1304) (1306 . 1306)
        (1308 . 1308) (1310 . 1310) (1312 . 1312) (1314 . 1314) (1316 . 1316)
        (1318 . 1318) (1320 . 1320) (1322 . 1322) (1324 . 1324) (1326 . 1326)
        (1329 . 1366) (4256 . 4293) (4295 . 4295) (4301 . 4301) (5024 . 5109)
        (7312 . 7354) (7357 . 7359) (7680 . 7680) (7682 . 7682) (7684 . 7684)
        (7686 . 7686) (7688 . 7688) (7690 . 7690) (7692 . 7692) (7694 . 7694)
        (7696 . 7696) (7698 . 7698) (7700 . 7700) (7702 . 7702) (7704 . 7704)
        (7706 . 7706) (7708 . 7708) (7710 . 7710) (7712 . 7712) (7714 . 7714)
        (7716 . 7716) (7718 . 7718) (7720 . 7720) (7722 . 7722) (7724 . 7724)
        (7726 . 7726) (7728 . 7728) (7730 . 7730) (7732 . 7732) (7734 . 7734)
        (7736 . 7736) (7738 . 7738) (7740 . 7740) (7742 . 7742) (7744 . 7744)
        (7746 . 7746) (7748 . 7748) (7750 . 7750) (7752 . 7752) (7754 . 7754)
        (7756 . 7756) (7758 . 7758) (7760 . 7760) (7762 . 7762) (7764 . 7764)
        (7766 . 7766) (7768 . 7768) (7770 . 7770) (7772 . 7772) (7774 . 7774)
        (7776 . 7776) (7778 . 7778) (7780 . 7780) (7782 . 7782) (7784 . 7784)
        (7786 . 7786) (7788 . 7788) (7790 . 7790) (7792 . 7792) (7794 . 7794)
        (7796 . 7796) (7798 . 7798) (7800 . 7800) (7802 . 7802) (7804 . 7804)
        (7806 . 7806) (7808 . 7808) (7810 . 7810) (7812 . 7812) (7814 . 7814)
        (7816 . 7816) (7818 . 7818) (7820 . 7820) (7822 . 7822) (7824 . 7824)
        (7826 . 7826) (7828 . 7828) (7838 . 7838) (7840 . 7840) (7842 . 7842)
        (7844 . 7844) (7846 . 7846) (7848 . 7848) (7850 . 7850) (7852 . 7852)
        (7854 . 7854) (7856 . 7856) (7858 . 7858) (7860 . 7860) (7862 . 7862)
        (7864 . 7864) (7866 . 7866) (7868 . 7868) (7870 . 7870) (7872 . 7872)
        (7874 . 7874) (7876 . 7876) (7878 . 7878) (7880 . 7880) (7882 . 7882)
        (7884 . 7884) (7886 . 7886) (7888 . 7888) (7890 . 7890) (7892 . 7892)
        (7894 . 7894) (7896 . 7896) (7898 . 7898) (7900 . 7900) (7902 . 7902)
        (7904 . 7904) (7906 . 7906) (7908 . 7908) (7910 . 7910) (7912 . 7912)
        (7914 . 7914) (7916 . 7916) (7918 . 7918) (7920 . 7920) (7922 . 7922)
        (7924 . 7924) (7926 . 7926) (7928 . 7928) (7930 . 7930) (7932 . 7932)
        (7934 . 7934) (7944 . 7951) (7960 . 7965) (7976 . 7983) (7992 . 7999)
        (8008 . 8013) (8025 . 8025) (8027 . 8027) (8029 . 8029) (8031 . 8031)
        (8040 . 8047) (8120 . 8123) (8136 . 8139) (8152 . 8155) (8168 . 8172)
        (8184 . 8187) (8450 . 8450) (8455 . 8455) (8459 . 8461) (8464 . 8466)
        (8469 . 8469) (8473 . 8477) (8484 . 8484) (8486 . 8486) (8488 . 8488)
        (8490 . 8493) (8496 . 8499) (8510 . 8511) (8517 . 8517) (8579 . 8579)
        (11264 . 11311) (11360 . 11360) (11362 . 11364) (11367 . 11367)
        (11369 . 11369) (11371 . 11371) (11373 . 11376) (11378 . 11378)
        (11381 . 11381) (11390 . 11392) (11394 . 11394) (11396 . 11396)
        (11398 . 11398) (11400 . 11400) (11402 . 11402) (11404 . 11404)
        (11406 . 11406) (11408 . 11408) (11410 . 11410) (11412 . 11412)
        (11414 . 11414) (11416 . 11416) (11418 . 11418) (11420 . 11420)
        (11422 . 11422) (11424 . 11424) (11426 . 11426) (11428 . 11428)
        (11430 . 11430) (11432 . 11432) (11434 . 11434) (11436 . 11436)
        (11438 . 11438) (11440 . 11440) (11442 . 11442) (11444 . 11444)
        (11446 . 11446) (11448 . 11448) (11450 . 11450) (11452 . 11452)
        (11454 . 11454) (11456 . 11456) (11458 . 11458) (11460 . 11460)
        (11462 . 11462) (11464 . 11464) (11466 . 11466) (11468 . 11468)
        (11470 . 11470) (11472 . 11472) (11474 . 11474) (11476 . 11476)
        (11478 . 11478) (11480 . 11480) (11482 . 11482) (11484 . 11484)
        (11486 . 11486) (11488 . 11488) (11490 . 11490) (11499 . 11499)
        (11501 . 11501) (11506 . 11506) (42560 . 42560) (42562 . 42562)
        (42564 . 42564) (42566 . 42566) (42568 . 42568) (42570 . 42570)
        (42572 . 42572) (42574 . 42574) (42576 . 42576) (42578 . 42578)
        (42580 . 42580) (42582 . 42582) (42584 . 42584) (42586 . 42586)
        (42588 . 42588) (42590 . 42590) (42592 . 42592) (42594 . 42594)
        (42596 . 42596) (42598 . 42598) (42600 . 42600) (42602 . 42602)
        (42604 . 42604) (42624 . 42624) (42626 . 42626) (42628 . 42628)
        (42630 . 42630) (42632 . 42632) (42634 . 42634) (42636 . 42636)
        (42638 . 42638) (42640 . 42640) (42642 . 42642) (42644 . 42644)
        (42646 . 42646) (42648 . 42648) (42650 . 42650) (42786 . 42786)
        (42788 . 42788) (42790 . 42790) (42792 . 42792) (42794 . 42794)
        (42796 . 42796) (42798 . 42798) (42802 . 42802) (42804 . 42804)
        (42806 . 42806) (42808 . 42808) (42810 . 42810) (42812 . 42812)
        (42814 . 42814) (42816 . 42816) (42818 . 42818) (42820 . 42820)
        (42822 . 42822) (42824 . 42824) (42826 . 42826) (42828 . 42828)
        (42830 . 42830) (42832 . 42832) (42834 . 42834) (42836 . 42836)
        (42838 . 42838) (42840 . 42840) (42842 . 42842) (42844 . 42844)
        (42846 . 42846) (42848 . 42848) (42850 . 42850) (42852 . 42852)
        (42854 . 42854) (42856 . 42856) (42858 . 42858) (42860 . 42860)
        (42862 . 42862) (42873 . 42873) (42875 . 42875) (42877 . 42878)
        (42880 . 42880) (42882 . 42882) (42884 . 42884) (42886 . 42886)
        (42891 . 42891) (42893 . 42893) (42896 . 42896) (42898 . 42898)
        (42902 . 42902) (42904 . 42904) (42906 . 42906) (42908 . 42908)
        (42910 . 42910) (42912 . 42912) (42914 . 42914) (42916 . 42916)
        (42918 . 42918) (42920 . 42920) (42922 . 42926) (42928 . 42932)
        (42934 . 42934) (42936 . 42936) (42938 . 42938) (42940 . 42940)
        (42942 . 42942) (42944 . 42944) (42946 . 42946) (42948 . 42951)
        (42953 . 42953) (42960 . 42960) (42966 . 42966) (42968 . 42968)
        (42997 . 42997) (65313 . 65338) (66560 . 66599) (66736 . 66771)
        (66928 . 66938) (66940 . 66954) (66956 . 66962) (66964 . 66965)
        (68736 . 68786) (71840 . 71871) (93760 . 93791) (119808 . 119833)
        (119860 . 119885) (119912 . 119937) (119964 . 119964)
        (119966 . 119967) (119970 . 119970) (119973 . 119974)
        (119977 . 119980) (119982 . 119989) (120016 . 120041)
        (120068 . 120069) (120071 . 120074) (120077 . 120084)
        (120086 . 120092) (120120 . 120121) (120123 . 120126)
        (120128 . 120132) (120134 . 120134) (120138 . 120144)
        (120172 . 120197) (120224 . 120249) (120276 . 120301)
        (120328 . 120353) (120380 . 120405) (120432 . 120457)
        (120488 . 120512) (120546 . 120570) (120604 . 120628)
        (120662 . 120686) (120720 . 120744) (120778 . 120778)
        (125184 . 125217)))

    ;; general category Lt (10 ranges)
    (define %tbl-title-case
      '((453 . 453) (456 . 456) (459 . 459) (498 . 498) (8072 . 8079)
        (8088 . 8095) (8104 . 8111) (8124 . 8124) (8140 . 8140) (8188 . 8188)))

    ;; general category Nd (64 ranges)
    (define %tbl-digit
      '((48 . 57) (1632 . 1641) (1776 . 1785) (1984 . 1993) (2406 . 2415)
        (2534 . 2543) (2662 . 2671) (2790 . 2799) (2918 . 2927) (3046 . 3055)
        (3174 . 3183) (3302 . 3311) (3430 . 3439) (3558 . 3567) (3664 . 3673)
        (3792 . 3801) (3872 . 3881) (4160 . 4169) (4240 . 4249) (6112 . 6121)
        (6160 . 6169) (6470 . 6479) (6608 . 6617) (6784 . 6793) (6800 . 6809)
        (6992 . 7001) (7088 . 7097) (7232 . 7241) (7248 . 7257)
        (42528 . 42537) (43216 . 43225) (43264 . 43273) (43472 . 43481)
        (43504 . 43513) (43600 . 43609) (44016 . 44025) (65296 . 65305)
        (66720 . 66729) (68912 . 68921) (69734 . 69743) (69872 . 69881)
        (69942 . 69951) (70096 . 70105) (70384 . 70393) (70736 . 70745)
        (70864 . 70873) (71248 . 71257) (71360 . 71369) (71472 . 71481)
        (71904 . 71913) (72016 . 72025) (72784 . 72793) (73040 . 73049)
        (73120 . 73129) (73552 . 73561) (92768 . 92777) (92864 . 92873)
        (93008 . 93017) (120782 . 120831) (123200 . 123209) (123632 . 123641)
        (124144 . 124153) (125264 . 125273) (130032 . 130041)))

    ;; general categories Zs, Zl, Zp plus U+0009..U+000D (9 ranges)
    (define %tbl-whitespace
      '((9 . 13) (32 . 32) (160 . 160) (5760 . 5760) (8192 . 8202)
        (8232 . 8233) (8239 . 8239) (8287 . 8287) (12288 . 12288)))

    ;; general category Zs plus U+0009 (8 ranges)
    (define %tbl-blank
      '((9 . 9) (32 . 32) (160 . 160) (5760 . 5760) (8192 . 8202)
        (8239 . 8239) (8287 . 8287) (12288 . 12288)))

    ;; general categories Pc, Pd, Ps, Pe, Pi, Pf, Po (191 ranges)
    (define %tbl-punctuation
      '((33 . 35) (37 . 42) (44 . 47) (58 . 59) (63 . 64) (91 . 93) (95 . 95)
        (123 . 123) (125 . 125) (161 . 161) (167 . 167) (171 . 171)
        (182 . 183) (187 . 187) (191 . 191) (894 . 894) (903 . 903)
        (1370 . 1375) (1417 . 1418) (1470 . 1470) (1472 . 1472) (1475 . 1475)
        (1478 . 1478) (1523 . 1524) (1545 . 1546) (1548 . 1549) (1563 . 1563)
        (1565 . 1567) (1642 . 1645) (1748 . 1748) (1792 . 1805) (2039 . 2041)
        (2096 . 2110) (2142 . 2142) (2404 . 2405) (2416 . 2416) (2557 . 2557)
        (2678 . 2678) (2800 . 2800) (3191 . 3191) (3204 . 3204) (3572 . 3572)
        (3663 . 3663) (3674 . 3675) (3844 . 3858) (3860 . 3860) (3898 . 3901)
        (3973 . 3973) (4048 . 4052) (4057 . 4058) (4170 . 4175) (4347 . 4347)
        (4960 . 4968) (5120 . 5120) (5742 . 5742) (5787 . 5788) (5867 . 5869)
        (5941 . 5942) (6100 . 6102) (6104 . 6106) (6144 . 6154) (6468 . 6469)
        (6686 . 6687) (6816 . 6822) (6824 . 6829) (7002 . 7008) (7037 . 7038)
        (7164 . 7167) (7227 . 7231) (7294 . 7295) (7360 . 7367) (7379 . 7379)
        (8208 . 8231) (8240 . 8259) (8261 . 8273) (8275 . 8286) (8317 . 8318)
        (8333 . 8334) (8968 . 8971) (9001 . 9002) (10088 . 10101)
        (10181 . 10182) (10214 . 10223) (10627 . 10648) (10712 . 10715)
        (10748 . 10749) (11513 . 11516) (11518 . 11519) (11632 . 11632)
        (11776 . 11822) (11824 . 11855) (11858 . 11869) (12289 . 12291)
        (12296 . 12305) (12308 . 12319) (12336 . 12336) (12349 . 12349)
        (12448 . 12448) (12539 . 12539) (42238 . 42239) (42509 . 42511)
        (42611 . 42611) (42622 . 42622) (42738 . 42743) (43124 . 43127)
        (43214 . 43215) (43256 . 43258) (43260 . 43260) (43310 . 43311)
        (43359 . 43359) (43457 . 43469) (43486 . 43487) (43612 . 43615)
        (43742 . 43743) (43760 . 43761) (44011 . 44011) (64830 . 64831)
        (65040 . 65049) (65072 . 65106) (65108 . 65121) (65123 . 65123)
        (65128 . 65128) (65130 . 65131) (65281 . 65283) (65285 . 65290)
        (65292 . 65295) (65306 . 65307) (65311 . 65312) (65339 . 65341)
        (65343 . 65343) (65371 . 65371) (65373 . 65373) (65375 . 65381)
        (65792 . 65794) (66463 . 66463) (66512 . 66512) (66927 . 66927)
        (67671 . 67671) (67871 . 67871) (67903 . 67903) (68176 . 68184)
        (68223 . 68223) (68336 . 68342) (68409 . 68415) (68505 . 68508)
        (69293 . 69293) (69461 . 69465) (69510 . 69513) (69703 . 69709)
        (69819 . 69820) (69822 . 69825) (69952 . 69955) (70004 . 70005)
        (70085 . 70088) (70093 . 70093) (70107 . 70107) (70109 . 70111)
        (70200 . 70205) (70313 . 70313) (70731 . 70735) (70746 . 70747)
        (70749 . 70749) (70854 . 70854) (71105 . 71127) (71233 . 71235)
        (71264 . 71276) (71353 . 71353) (71484 . 71486) (71739 . 71739)
        (72004 . 72006) (72162 . 72162) (72255 . 72262) (72346 . 72348)
        (72350 . 72354) (72448 . 72457) (72769 . 72773) (72816 . 72817)
        (73463 . 73464) (73539 . 73551) (73727 . 73727) (74864 . 74868)
        (77809 . 77810) (92782 . 92783) (92917 . 92917) (92983 . 92987)
        (92996 . 92996) (93847 . 93850) (94178 . 94178) (113823 . 113823)
        (121479 . 121483) (125278 . 125279)))

    ;; general categories Sm, Sc, Sk, So (233 ranges)
    (define %tbl-symbol
      '((36 . 36) (43 . 43) (60 . 62) (94 . 94) (96 . 96) (124 . 124)
        (126 . 126) (162 . 166) (168 . 169) (172 . 172) (174 . 177)
        (180 . 180) (184 . 184) (215 . 215) (247 . 247) (706 . 709)
        (722 . 735) (741 . 747) (749 . 749) (751 . 767) (885 . 885)
        (900 . 901) (1014 . 1014) (1154 . 1154) (1421 . 1423) (1542 . 1544)
        (1547 . 1547) (1550 . 1551) (1758 . 1758) (1769 . 1769) (1789 . 1790)
        (2038 . 2038) (2046 . 2047) (2184 . 2184) (2546 . 2547) (2554 . 2555)
        (2801 . 2801) (2928 . 2928) (3059 . 3066) (3199 . 3199) (3407 . 3407)
        (3449 . 3449) (3647 . 3647) (3841 . 3843) (3859 . 3859) (3861 . 3863)
        (3866 . 3871) (3892 . 3892) (3894 . 3894) (3896 . 3896) (4030 . 4037)
        (4039 . 4044) (4046 . 4047) (4053 . 4056) (4254 . 4255) (5008 . 5017)
        (5741 . 5741) (6107 . 6107) (6464 . 6464) (6622 . 6655) (7009 . 7018)
        (7028 . 7036) (8125 . 8125) (8127 . 8129) (8141 . 8143) (8157 . 8159)
        (8173 . 8175) (8189 . 8190) (8260 . 8260) (8274 . 8274) (8314 . 8316)
        (8330 . 8332) (8352 . 8384) (8448 . 8449) (8451 . 8454) (8456 . 8457)
        (8468 . 8468) (8470 . 8472) (8478 . 8483) (8485 . 8485) (8487 . 8487)
        (8489 . 8489) (8494 . 8494) (8506 . 8507) (8512 . 8516) (8522 . 8525)
        (8527 . 8527) (8586 . 8587) (8592 . 8967) (8972 . 9000) (9003 . 9254)
        (9280 . 9290) (9372 . 9449) (9472 . 10087) (10132 . 10180)
        (10183 . 10213) (10224 . 10626) (10649 . 10711) (10716 . 10747)
        (10750 . 11123) (11126 . 11157) (11159 . 11263) (11493 . 11498)
        (11856 . 11857) (11904 . 11929) (11931 . 12019) (12032 . 12245)
        (12272 . 12287) (12292 . 12292) (12306 . 12307) (12320 . 12320)
        (12342 . 12343) (12350 . 12351) (12443 . 12444) (12688 . 12689)
        (12694 . 12703) (12736 . 12771) (12783 . 12783) (12800 . 12830)
        (12842 . 12871) (12880 . 12880) (12896 . 12927) (12938 . 12976)
        (12992 . 13311) (19904 . 19967) (42128 . 42182) (42752 . 42774)
        (42784 . 42785) (42889 . 42890) (43048 . 43051) (43062 . 43065)
        (43639 . 43641) (43867 . 43867) (43882 . 43883) (64297 . 64297)
        (64434 . 64450) (64832 . 64847) (64975 . 64975) (65020 . 65023)
        (65122 . 65122) (65124 . 65126) (65129 . 65129) (65284 . 65284)
        (65291 . 65291) (65308 . 65310) (65342 . 65342) (65344 . 65344)
        (65372 . 65372) (65374 . 65374) (65504 . 65510) (65512 . 65518)
        (65532 . 65533) (65847 . 65855) (65913 . 65929) (65932 . 65934)
        (65936 . 65948) (65952 . 65952) (66000 . 66044) (67703 . 67704)
        (68296 . 68296) (71487 . 71487) (73685 . 73713) (92988 . 92991)
        (92997 . 92997) (113820 . 113820) (118608 . 118723) (118784 . 119029)
        (119040 . 119078) (119081 . 119140) (119146 . 119148)
        (119171 . 119172) (119180 . 119209) (119214 . 119274)
        (119296 . 119361) (119365 . 119365) (119552 . 119638)
        (120513 . 120513) (120539 . 120539) (120571 . 120571)
        (120597 . 120597) (120629 . 120629) (120655 . 120655)
        (120687 . 120687) (120713 . 120713) (120745 . 120745)
        (120771 . 120771) (120832 . 121343) (121399 . 121402)
        (121453 . 121460) (121462 . 121475) (121477 . 121478)
        (123215 . 123215) (123647 . 123647) (126124 . 126124)
        (126128 . 126128) (126254 . 126254) (126704 . 126705)
        (126976 . 127019) (127024 . 127123) (127136 . 127150)
        (127153 . 127167) (127169 . 127183) (127185 . 127221)
        (127245 . 127405) (127462 . 127490) (127504 . 127547)
        (127552 . 127560) (127568 . 127569) (127584 . 127589)
        (127744 . 128727) (128732 . 128748) (128752 . 128764)
        (128768 . 128886) (128891 . 128985) (128992 . 129003)
        (129008 . 129008) (129024 . 129035) (129040 . 129095)
        (129104 . 129113) (129120 . 129159) (129168 . 129197)
        (129200 . 129201) (129280 . 129619) (129632 . 129645)
        (129648 . 129660) (129664 . 129672) (129680 . 129725)
        (129727 . 129733) (129742 . 129755) (129760 . 129768)
        (129776 . 129784) (129792 . 129938) (129940 . 129994)))

    ;;; -------------------------------------------------- standard char sets

    (define char-set:empty (%make-cs '()))
    (define char-set:full (%make-cs %full-ranges))
    (define char-set:ascii (%make-cs (list (cons 0 127))))

    ;; "the Unicode/Latin-1 characters in the ranges [U+0000,U+001F] and
    ;; [U+007F,U+009F]"
    (define char-set:iso-control
      (%make-cs (list (cons #x00 #x1F) (cons #x7F #x9F))))

    ;; "The only hex digits are 0123456789abcdefABCDEF."
    (define char-set:hex-digit
      (%make-cs (list (cons 48 57) (cons 65 70) (cons 97 102))))

    ;; Straight from the generated category tables above.
    (define char-set:letter      (%make-cs %tbl-letter))
    (define char-set:lower-case  (%make-cs %tbl-lower-case))
    (define char-set:upper-case  (%make-cs %tbl-upper-case))
    (define char-set:title-case  (%make-cs %tbl-title-case))
    (define char-set:digit       (%make-cs %tbl-digit))
    (define char-set:whitespace  (%make-cs %tbl-whitespace))
    (define char-set:blank       (%make-cs %tbl-blank))
    (define char-set:punctuation (%make-cs %tbl-punctuation))
    (define char-set:symbol      (%make-cs %tbl-symbol))

    ;; The three composite sets are unions of the tables above rather than
    ;; tables of their own, so the spec's own definitions of them stay visible
    ;; in the source.  Merging canonical range lists is linear: all three cost
    ;; together under 2 ms at library load.

    ;; "The union of char-set:letter and char-set:digit"
    (define char-set:letter+digit
      (%make-cs (%union2 %tbl-letter %tbl-digit)))

    ;; "the union of letter, digit, punctuation, and symbol"
    (define char-set:graphic
      (%make-cs (%union2 (%ranges char-set:letter+digit)
                         (%union2 %tbl-punctuation %tbl-symbol))))

    ;; "a graphic character or a space character"
    (define char-set:printing
      (%make-cs (%union2 (%ranges char-set:graphic) %tbl-whitespace)))))
