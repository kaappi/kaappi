;;; SRFI 54 — Formatting
;;;
;;; Defines a single procedure, `cat', that converts any Scheme object to a
;;; string using a "free sequence" of optional directives: unlike Common
;;; Lisp's FORMAT or C's printf, `cat''s directives are ordinary Scheme
;;; values (not embedded in a control string) and are classified by *type*
;;; rather than by position, so callers can pass only the directives they
;;; need in any order, e.g. `(cat 42 10)` (pad to width 10) and
;;; `(cat 42 10 'hexadecimal)` (also render in hex) both work without a
;;; separate procedure or keyword per combination.
;;;
;;; Directive summary (full semantics in the spec's "Specification"
;;; section): <width> (exact integer: abs value is the field width;
;;; positive right-aligns/pads-left, negative left-aligns/pads-right),
;;; <char> (padding character, default #\space), <port> (#t = current
;;; output port, an actual port = write to it, #f/default = string only),
;;; <string> (a plain string argument is always appended verbatim to the
;;; result, in the position it would otherwise occupy relative to the
;;; other output); for numbers: <exactness> ('exact/'inexact), <radix>
;;; ('decimal/'octal/'binary/'hexadecimal), <sign> ('sign forces a '+' on
;;; positive numbers), <precision> (an inexact integer: digits after the
;;; decimal point), <separator> (a (char [group-size]) list for digit
;;; grouping, e.g. thousands separators -- the closest thing this SRFI has
;;; to a repetition/grouping count directive); for non-numbers: <writer>
;;; (a 2-arg object/port procedure), <pipe> (a list of string->string
;;; procedures chained together), <take> (a (left [right]) pair of exact
;;; integers selecting a prefix/suffix slice); and <converter> (a
;;; (predicate . procedure) pair: if the object satisfies predicate, only
;;; width/char/port/string apply, all number/writer/pipe/take directives
;;; are ignored).
;;;
;;; This is a faithful behavioral port of the spec's reference
;;; implementation and has been checked against essentially all of its
;;; worked examples (see tests/scheme/srfi/srfi54.scm). One part is
;;; deliberately NOT a line-for-line port: the reference dispatches its
;;; free-sequence argument classification through a small family of
;;; custom syntax-rules macros (`alet-cat*'/`wow-cat!'/`wow-cat-end',
;;; borrowed from SRFI 86) that repeatedly `set!' a shared list variable
;;; and rely on a pattern variable standing in for the identifier being
;;; tested. Below, `%cat-extract' implements the exact same algorithm --
;;; for each directive slot in turn, scan the remaining unclassified
;;; arguments left-to-right for the first one whose type matches that
;;; slot, remove and use it if found, otherwise keep that slot's default
;;; and leave the arguments untouched -- as a plain function threading an
;;; explicit "remaining arguments" list through `let*-values', which is
;;; easier to verify against the spec's worked examples line-by-line.
;;;
;;; Two things worth flagging for anyone re-verifying this against the
;;; spec's own text:
;;;
;;;   - The spec's own HTML has a typo in one example: "(cat \"string\"
;;;     `(,string-reverse ,string-upcase) => \"GNIRTS\"" is missing a
;;;     closing paren and is not valid Scheme as printed. The test suite
;;;     exercises the same pipe-chaining behavior with an equivalent,
;;;     well-formed call instead.
;;;   - A few worked examples involving large or scientific-notation
;;;     flonums (e.g. involving 1.2345e+15) assume a particular
;;;     `number->string' rendering (no leading zero suppression choices,
;;;     no "+" after "e", a specific large-magnitude threshold for
;;;     switching to scientific notation) that is implementation-defined
;;;     per R7RS and differs from Kaappi's own (equally valid)
;;;     `number->string' output. `cat''s directive-processing logic itself
;;;     does not depend on any particular flonum-printing convention -- it
;;;     just rounds/pads/groups whatever digit string `number->string'
;;;     hands it -- so the test suite adapts the *expected strings* for
;;;     these specific cases to Kaappi's actual (verified-by-hand)
;;;     `number->string' output rather than the spec transcript's, and
;;;     says so at each such case.
(define-library (srfi 54)
  (import (scheme base) (scheme char))
  (export cat)
  (begin

    ;;; -- generic helpers --

    (define (%str-index str ch)
      (let ((len (string-length str)))
        (let loop ((i 0))
          (cond ((= i len) #f)
                ((char=? (string-ref str i) ch) i)
                (else (loop (+ i 1)))))))

    (define (%every? pred lst)
      (or (null? lst) (and (pred (car lst)) (%every? pred (cdr lst)))))

    ;; Partitions `lst' into two lists (as multiple values): the elements
    ;; satisfying `string?' (in original order) and the rest (in original
    ;; order). `cat' uses this to pull out plain-string <string>
    ;; directives, which apply regardless of <object>'s type and are
    ;; appended to the final result, wherever they occur in the argument
    ;; list.
    (define (%partition-strings lst)
      (let loop ((lst lst) (strs '()) (others '()))
        (cond
          ((null? lst) (values (reverse strs) (reverse others)))
          ((string? (car lst)) (loop (cdr lst) (cons (car lst) strs) others))
          (else (loop (cdr lst) strs (cons (car lst) others))))))

    ;; Scans `lst' left-to-right for the first element satisfying `pred'.
    ;; Returns two values: that element (or `default' if none matches),
    ;; and `lst' with the matched element removed and relative order of
    ;; the rest preserved (or `lst' unchanged if nothing matched). This is
    ;; the core of `cat''s "free sequence" argument classification: each
    ;; directive slot is tried in a fixed order against whatever's left.
    (define (%cat-extract pred default lst)
      (let loop ((seen '()) (remaining lst))
        (cond
          ((null? remaining) (values default lst))
          ((pred (car remaining))
           (values (car remaining) (append (reverse seen) (cdr remaining))))
          (else (loop (cons (car remaining) seen) (cdr remaining))))))

    (define (%separator-directive? x)
      (and (list? x) (< 0 (length x) 3) (char? (car x))
           (or (null? (cdr x))
               (let ((n (cadr x))) (and (integer? n) (exact? n) (< 0 n))))))

    (define (%pipe-directive? x)
      (and (list? x) (not (null? x)) (%every? procedure? x)))

    (define (%take-directive? x)
      (and (list? x) (< 0 (length x) 3)
           (%every? (lambda (y) (and (integer? y) (exact? y))) x)))

    (define (%converter-directive? x)
      (and (pair? x) (procedure? (car x)) (procedure? (cdr x))))

    (define (%write-to-string object)
      (let ((p (open-output-string)))
        (write object p)
        (get-output-string p)))

    (define (%write-with writer object)
      (let ((p (open-output-string)))
        (writer object p)
        (get-output-string p)))

    ;; The default (no-directives) rendering of `object', per its type.
    (define (%default-string object)
      (cond
        ((number? object) (number->string object))
        ((string? object) object)
        ((char? object) (string object))
        ((boolean? object) (if object "#t" "#f"))
        ((symbol? object) (symbol->string object))
        (else (%write-to-string object))))

    ;;; -- decimal rounding/padding for the <precision> directive --

    ;; Rounds/pads `str' (a plain decimal numeral, no exponent marker) to
    ;; exactly `pre' digits after the decimal point. A dropped tail that is
    ;; > 5 (in its first digit) always rounds up; a tail that is exactly a
    ;; lone "5" with nothing nonzero after it rounds to even (up only if
    ;; the last kept digit is odd) -- see the SRFI 54 reference
    ;; implementation this is ported from.
    (define (%mold str pre)
      (let ((ind (%str-index str #\.)))
        (if (not ind)
            (string-append str "." (make-string pre #\0))
            (let ((d-len (- (string-length str) (+ ind 1))))
              (cond
                ((= d-len pre) str)
                ((< d-len pre) (string-append str (make-string (- pre d-len) #\0)))
                ((or (char<? #\5 (string-ref str (+ 1 ind pre)))
                     (and (char=? #\5 (string-ref str (+ 1 ind pre)))
                          (or (< (+ 1 pre) d-len)
                              (memv (string-ref str (+ ind (if (= 0 pre) -1 pre)))
                                    '(#\1 #\3 #\5 #\7 #\9)))))
                 (let* ((minus (char=? #\- (string-ref str 0)))
                        (digits (substring str (if minus 1 0) (+ 1 ind pre)))
                        (char-list
                         (reverse
                          (let lp ((index (- (string-length digits) 1)) (carry? #t))
                            (if (= -1 index)
                                (if carry? '(#\1) '())
                                (let ((chr (string-ref digits index)))
                                  (if (char=? #\. chr)
                                      (cons chr (lp (- index 1) carry?))
                                      (if carry?
                                          (if (char=? #\9 chr)
                                              (cons #\0 (lp (- index 1) carry?))
                                              (cons (integer->char (+ 1 (char->integer chr)))
                                                    (lp (- index 1) #f)))
                                          (cons chr (lp (- index 1) carry?))))))))))
                   (list->string (if minus (cons #\- char-list) char-list))))
                (else (substring str 0 (+ 1 ind pre))))))))

    ;; Like `%mold', but first strips off (and re-attaches unmolded) a
    ;; trailing scientific-notation exponent marker, if `number->string'
    ;; produced one.
    (define (%e-mold num pre)
      (let* ((str (number->string (exact->inexact num)))
             (e-index (%str-index str #\e)))
        (if e-index
            (string-append (%mold (substring str 0 e-index) pre)
                           (substring str e-index (string-length str)))
            (%mold str pre))))

    ;;; -- digit grouping for the <separator> directive --

    (define (%separate str sep group-size minus-aware?)
      (let* ((len (string-length str))
             (first-group
              (if minus-aware?
                  (let ((p (remainder (if (eq? minus-aware? 'minus) (- len 1) len)
                                      group-size)))
                    (if (= 0 p) group-size p))
                  group-size)))
        (apply string-append
               (let loop ((start 0)
                          (end (if (eq? minus-aware? 'minus) (+ first-group 1) first-group)))
                 (if (< end len)
                     (cons (substring str start end)
                           (cons sep (loop end (+ end group-size))))
                     (list (substring str start len)))))))

    ;;; -- <take> directive for non-number objects --

    (define (%apply-take str take)
      (let* ((left (car take))
             (right (if (null? (cdr take)) 0 (cadr take)))
             (len (string-length str)))
        (define (clamp n) (cond ((< n 0) 0) ((> n len) len) (else n)))
        (string-append
         (if (< left 0) (substring str (clamp (abs left)) len) (substring str 0 (clamp left)))
         (if (< right 0) (substring str 0 (clamp (+ len right))) (substring str (clamp (- len right)) len)))))

    ;;; -- radix tables for numbers --

    (define (%radix-base radix)
      (case radix ((decimal) 10) ((octal) 8) ((binary) 2) ((hexadecimal) 16) (else 10)))

    (define (%radix-sign radix)
      (case radix ((decimal) #f) ((octal) "#o") ((binary) "#b") ((hexadecimal) "#x") (else #f)))

    ;;; -- the three <object>-type-specific renderers --

    ;; <converter> matched: only width/char (and, at the call site,
    ;; port/string) apply.
    (define (%format-converted object converter width char)
      (let* ((s ((cdr converter) object))
             (pad (- (abs width) (string-length s))))
        (cond
          ((<= pad 0) s)
          ((< 0 width) (string-append (make-string pad char) s))
          (else (string-append s (make-string pad char))))))

    ;; <object> is a number (and no converter matched it).
    (define (%format-number object width char precision sign radix exactness separator)
      (when (and (not (eq? radix 'decimal)) precision)
        (error "cat: a non-decimal radix cannot be combined with a precision (decimal point) directive"
               radix precision))
      (when (and precision (< precision 0) (eq? exactness 'exact))
        (error "cat: an exact number cannot have a decimal point without an explicit exact sign"
               precision exactness))
      (let* ((exact-sign (and precision
                              (<= 0 precision)
                              (or (eq? exactness 'exact)
                                  (and (exact? object) (not (eq? exactness 'inexact))))
                              "#e"))
             (inexact-sign (and (not (eq? radix 'decimal))
                                (or (and (inexact? object) (not (eq? exactness 'exact)))
                                    (eq? exactness 'inexact))
                                "#i"))
             (radix-sign (%radix-sign radix))
             (plus-sign (and sign (> (real-part object) 0) "+"))
             (exactness-sign (or exact-sign inexact-sign))
             (str (if precision
                      (let ((prec (inexact->exact (abs precision)))
                            (imag (imag-part object)))
                        (if (= 0 imag)
                            (%e-mold object prec)
                            (string-append (%e-mold (real-part object) prec)
                                           (if (> imag 0) "+" "")
                                           (%e-mold imag prec)
                                           "i")))
                      (number->string
                       (cond
                         (inexact-sign (inexact->exact object))
                         (exactness (if (eq? exactness 'exact) (inexact->exact object) (exact->inexact object)))
                         (else object))
                       (%radix-base radix))))
             (str (if (and separator
                           (not (or (and (eq? radix 'decimal) (%str-index str #\e))
                                    (%str-index str #\i)
                                    (%str-index str #\/))))
                      (let ((sep (string (car separator)))
                            (group-size (if (null? (cdr separator)) 3 (cadr separator)))
                            (dot-index (%str-index str #\.)))
                        (if dot-index
                            (string-append
                             (%separate (substring str 0 dot-index) sep group-size
                                        (if (< object 0) 'minus #t))
                             "."
                             (%separate (substring str (+ 1 dot-index) (string-length str))
                                        sep group-size #f))
                            (%separate str sep group-size (if (< object 0) 'minus #t))))
                      str))
             (pad (- (abs width)
                     (+ (string-length str)
                        (if exactness-sign 2 0)
                        (if radix-sign 2 0)
                        (if plus-sign 1 0))))
             (pad (if (< 0 pad) pad 0)))
        (if (< 0 width)
            (if (char-numeric? char)
                (if (< (real-part object) 0)
                    (string-append (or exactness-sign "") (or radix-sign "") "-"
                                   (make-string pad char)
                                   (substring str 1 (string-length str)))
                    (string-append (or exactness-sign "") (or radix-sign "") (or plus-sign "")
                                   (make-string pad char) str))
                (string-append (make-string pad char)
                               (or exactness-sign "") (or radix-sign "") (or plus-sign "")
                               str))
            (string-append (or exactness-sign "") (or radix-sign "") (or plus-sign "")
                           str (make-string pad char)))))

    ;; <object> is neither number nor converter-matched: string, char,
    ;; boolean, symbol, or anything else (rendered via <writer> or
    ;; `write').
    (define (%format-other object width char writer pipe take)
      (let* ((s0 (cond
                   (writer (%write-with writer object))
                   ((string? object) object)
                   ((char? object) (string object))
                   ((boolean? object) (if object "#t" "#f"))
                   ((symbol? object) (symbol->string object))
                   (else (%write-to-string object))))
             (s1 (if pipe
                     (let loop ((s ((car pipe) s0)) (fns (cdr pipe)))
                       (if (null? fns) s (loop ((car fns) s) (cdr fns))))
                     s0))
             (s2 (if take (%apply-take s1 take) s1))
             (pad (- (abs width) (string-length s2))))
        (cond
          ((<= pad 0) s2)
          ((< 0 width) (string-append (make-string pad char) s2))
          (else (string-append s2 (make-string pad char))))))

    ;;; -- cat itself --

    (define (cat object . rest)
      (let*-values (((str-list args0) (%partition-strings rest)))
        (if (null? args0)
            ;; No non-string directives at all: render `object' by its
            ;; own type default and simply append every <string>
            ;; directive found in `rest'. (This mirrors the reference
            ;; implementation's fast path, which -- like this one --
            ;; never even looks at a <port> directive in this case; a
            ;; real port argument is never itself a string, so it can
            ;; only reach this branch if there were no other directives
            ;; either, in which case there is nothing to send it anyway.)
            (apply string-append (%default-string object) str-list)
            (let*-values
                (((width args1)
                  (%cat-extract (lambda (x) (and (integer? x) (exact? x))) 0 args0))
                 ((port-raw args2)
                  (%cat-extract (lambda (x) (or (boolean? x) (output-port? x))) #f args1))
                 ((char args3)
                  (%cat-extract char? #\space args2))
                 ((converter args4)
                  (%cat-extract %converter-directive? #f args3))
                 ((precision args5)
                  (%cat-extract (lambda (x) (and (integer? x) (inexact? x))) #f args4))
                 ((sign args6)
                  (%cat-extract (lambda (x) (eq? x 'sign)) #f args5))
                 ((radix args7)
                  (%cat-extract (lambda (x) (memq x '(decimal octal binary hexadecimal))) 'decimal args6))
                 ((exactness args8)
                  (%cat-extract (lambda (x) (memq x '(exact inexact))) #f args7))
                 ((separator args9)
                  (%cat-extract %separator-directive? #f args8))
                 ((writer args10)
                  (%cat-extract procedure? #f args9))
                 ((pipe args11)
                  (%cat-extract %pipe-directive? #f args10))
                 ((take args12)
                  (%cat-extract %take-directive? #f args11)))
              (if (not (null? args12))
                  (error "cat: too many arguments" args12)
                  (let* ((port (if (eq? port-raw #t) (current-output-port) port-raw))
                         (core (cond
                                 ((and converter ((car converter) object))
                                  (%format-converted object converter width char))
                                 ((number? object)
                                  (%format-number object width char precision sign radix exactness separator))
                                 (else
                                  (%format-other object width char writer pipe take))))
                         (result (apply string-append core str-list)))
                    (if port (display result port))
                    result))))))))
