;;; SRFI 14 (Character-set Library) conformance suite.
;;;
;;; Written against the spec at https://srfi.schemers.org/srfi-14/srfi-14.html,
;;; not against the implementation.  Covers the three defects filed as #1895 —
;;; the library was a multiset, was ASCII-only including char-set:full, and
;;; exported 23 of the SRFI's 64 names — plus the whole export surface.
;;; Against the pre-#1895 library it reports 17 passes and 144 failures.
;;;
;;; Order of iteration over a char set is explicitly unspecified by the spec
;;; ("The order in which ... characters appear ... is not defined, and may be
;;; different from one call to another"), so every assertion here either
;;; compares with char-set= / char-set-size or sorts first.

(import (scheme base) (scheme char) (scheme process-context)
        (srfi 18) (srfi 64) (srfi 14))

(test-begin "srfi-14")

;;; ---------------------------------------------------------------- helpers

;; Insertion sort — (scheme base) has no list-sort and the suite must not
;; depend on char-set->list's (unspecified) ordering.
(define (sort-chars lst)
  (define (insert c sorted)
    (cond ((null? sorted) (list c))
          ((char<? c (car sorted)) (cons c sorted))
          (else (cons (car sorted) (insert c (cdr sorted))))))
  (let loop ((l lst) (acc '()))
    (if (null? l) acc (loop (cdr l) (insert (car l) acc)))))

(define (cs-chars cs) (sort-chars (char-set->list cs)))
(define (cs-string cs) (list->string (cs-chars cs)))
(define (cp n) (integer->char n))
(define (has? cs n) (char-set-contains? cs (cp n)))

;;; ------------------------------------------------- 1. it is a SET (#1895)

(test-equal "char-set drops duplicate arguments"
  2 (char-set-size (char-set #\a #\a #\b)))
(test-equal "char-set->list of a duplicated construction"
  '(#\a #\b) (cs-chars (char-set #\a #\a #\b)))
(test-assert "duplicated construction equals the deduplicated one"
  (char-set= (char-set #\a #\a #\b) (char-set #\a #\b)))
(test-equal "adjoining a member is idempotent"
  1 (char-set-size (char-set-adjoin (char-set #\a) #\a)))
(test-equal "union with self is idempotent"
  2 (char-set-size (char-set-union (char-set #\a #\b) (char-set #\a #\b))))
(test-assert "union with self equals self"
  (let ((cs (char-set #\a #\b)))
    (char-set= (char-set-union cs cs) cs)))
(test-equal "list->char-set deduplicates"
  2 (char-set-size (list->char-set (list #\b #\a #\a #\b))))
(test-equal "string->char-set deduplicates"
  3 (char-set-size (string->char-set "banana")))
(test-equal "char-set-map may collapse its results"
  1 (char-set-size (char-set-map (lambda (c) #\x) (string->char-set "abc"))))

;;; ------------------------------------------ 2. Unicode membership (#1895)

(test-assert "char-set:full contains a non-ASCII char"
  (char-set-contains? char-set:full #\x3bb))       ; GREEK SMALL LETTER LAMDA
(test-assert "char-set:full contains the last code point"
  (has? char-set:full #x10FFFF))
(test-assert "char-set:letter contains lambda"
  (char-set-contains? char-set:letter #\x3bb))
(test-assert "char-set:lower-case contains lambda"
  (char-set-contains? char-set:lower-case #\x3bb))
(test-assert "char-set:upper-case contains capital lambda"
  (char-set-contains? char-set:upper-case #\x39b))
(test-assert "char-set:digit contains ARABIC-INDIC DIGIT ZERO"
  (has? char-set:digit #x660))
(test-assert "char-set:digit excludes CIRCLED DIGIT ONE (category No)"
  (not (has? char-set:digit #x2460)))
(test-assert "char-set:whitespace contains NO-BREAK SPACE"
  (has? char-set:whitespace #xA0))
(test-assert "char-set:whitespace contains LINE SEPARATOR"
  (has? char-set:whitespace #x2028))
(test-assert "char-set:punctuation contains EM DASH (Pd)"
  (has? char-set:punctuation #x2014))
(test-assert "char-set:symbol contains EURO SIGN (Sc)"
  (has? char-set:symbol #x20AC))
(test-assert "char-set:title-case contains U+01C5 (Lt)"
  (has? char-set:title-case #x1C5))
(test-assert "char-set:title-case excludes a plain lower-case letter"
  (not (char-set-contains? char-set:title-case #\a)))
(test-assert "char-set:ascii excludes lambda"
  (not (char-set-contains? char-set:ascii #\x3bb)))
(test-assert "char-set:graphic contains lambda"
  (char-set-contains? char-set:graphic #\x3bb))

;;; ------------------------------------------------- 3. standard set shapes

(test-equal "char-set:empty is empty" 0 (char-set-size char-set:empty))
(test-equal "char-set:ascii has 128 elements" 128 (char-set-size char-set:ascii))
;; 0x110000 code points minus the 2048 surrogates, which integer->char rejects.
(test-equal "char-set:full covers every representable code point"
  1112064 (char-set-size char-set:full))
;; "[U+0000,U+001F] and [U+007F,U+009F]" -- 32 + 33
(test-equal "char-set:iso-control has 65 elements"
  65 (char-set-size char-set:iso-control))
(test-assert "char-set:iso-control endpoints"
  (and (has? char-set:iso-control #x00) (has? char-set:iso-control #x1F)
       (has? char-set:iso-control #x7F) (has? char-set:iso-control #x9F)
       (not (has? char-set:iso-control #x20))
       (not (has? char-set:iso-control #xA0))))
;; "The only hex digits are 0123456789abcdefABCDEF."
(test-equal "char-set:hex-digit is exactly 0-9 a-f A-F"
  "0123456789ABCDEFabcdef" (cs-string char-set:hex-digit))
(test-assert "char-set:ascii is [0,127]"
  (char-set= char-set:ascii (ucs-range->char-set 0 128)))

;; "Blank chars are horizontal whitespace": Zs plus tab.
(test-assert "blank contains tab, space, NBSP, EN QUAD"
  (and (char-set-contains? char-set:blank #\tab)
       (char-set-contains? char-set:blank #\space)
       (has? char-set:blank #xA0) (has? char-set:blank #x2000)))
(test-assert "blank excludes vertical whitespace"
  (and (not (char-set-contains? char-set:blank #\newline))
       (not (char-set-contains? char-set:blank #\return))
       (not (has? char-set:blank #x2028))))
(test-assert "blank is a subset of whitespace"
  (char-set<= char-set:blank char-set:whitespace))

;; "The union of char-set:letter and char-set:digit"
(test-assert "letter+digit is the union of letter and digit"
  (char-set= char-set:letter+digit
             (char-set-union char-set:letter char-set:digit)))
;; "the union of letter, digit, punctuation, and symbol"
(test-assert "graphic covers letter, digit, punctuation and symbol"
  (and (char-set<= char-set:letter char-set:graphic)
       (char-set<= char-set:digit char-set:graphic)
       (char-set<= char-set:punctuation char-set:graphic)
       (char-set<= char-set:symbol char-set:graphic)))
;; "a graphic character or a space character"
(test-assert "printing covers graphic and whitespace"
  (and (char-set<= char-set:graphic char-set:printing)
       (char-set<= char-set:whitespace char-set:printing)))
(test-assert "space prints but is not graphic"
  (and (char-set-contains? char-set:printing #\space)
       (not (char-set-contains? char-set:graphic #\space))))
(test-assert "lower-case and upper-case are subsets of letter"
  (and (char-set<= char-set:lower-case char-set:letter)
       (char-set<= char-set:upper-case char-set:letter)))
(test-assert "the ASCII letters are all letters"
  (char-set<= (string->char-set "abcXYZ") char-set:letter))

;;; ------------------------------------------------------- 4. char-set? etc.

(test-assert "char-set? on a char set" (char-set? (char-set #\a)))
(test-assert "char-set? on the constants" (char-set? char-set:full))
(test-assert "char-set? on a non-char-set"
  (not (or (char-set? 'a) (char-set? "a") (char-set? #\a) (char-set? '()))))

;;; ------------------------------------------------------- 5. char-set= / <=

;; "(char-set=) => true", "(char-set= cs) => true"
(test-assert "char-set= with no arguments" (char-set=))
(test-assert "char-set= with one argument" (char-set= (char-set #\a)))
(test-assert "char-set= is n-ary"
  (char-set= (char-set #\a #\b) (string->char-set "ba")
             (list->char-set (list #\b #\a))))
(test-assert "char-set= detects a difference"
  (not (char-set= (char-set #\a) (char-set #\a #\b))))
(test-assert "char-set<= with no arguments" (char-set<=))
(test-assert "char-set<= with one argument" (char-set<= (char-set #\a)))
(test-assert "char-set<= chain"
  (char-set<= char-set:empty (char-set #\a) char-set:full))
(test-assert "char-set<= rejects a non-subset"
  (not (char-set<= (char-set #\a) char-set:empty)))
(test-assert "char-set<= is reflexive"
  (char-set<= char-set:letter char-set:letter))

;;; ---------------------------------------------------------- 6. char-set-hash

(test-assert "hash of a char set is a non-negative exact integer"
  (let ((h (char-set-hash (char-set #\a #\b))))
    (and (exact-integer? h) (>= h 0))))
(test-equal "equal char sets hash equally"
  (char-set-hash (string->char-set "abc"))
  (char-set-hash (list->char-set (list #\c #\b #\a #\a))))
(test-assert "hash respects an explicit bound"
  (let loop ((n 0))
    (or (= n 40)
        (and (< (char-set-hash (ucs-range->char-set 65 (+ 66 n)) 13) 13)
             (loop (+ n 1))))))
(test-assert "a zero bound is treated as absent"
  (exact-integer? (char-set-hash char-set:ascii 0)))

;;; ------------------------------------------------------- 7. cursor protocol

;; The spec's own worked example, compared as a set since order is unspecified.
(test-equal "cursor walk collects every element"
  '(#\G #\T #\a #\c #\e #\h)
  (sort-chars
    (let ((cs (char-set #\G #\a #\T #\e #\c #\h)))
      (let lp ((cur (char-set-cursor cs)) (ans '()))
        (if (end-of-char-set? cur)
            ans
            (lp (char-set-cursor-next cs cur)
                (cons (char-set-ref cs cur) ans)))))))
(test-assert "a fresh cursor on the empty set is already at the end"
  (end-of-char-set? (char-set-cursor char-set:empty)))
(test-assert "a fresh cursor on a non-empty set is not at the end"
  (not (end-of-char-set? (char-set-cursor (char-set #\a)))))
(test-assert "stepping the last element reaches the end"
  (let* ((cs (char-set #\a))
         (cur (char-set-cursor cs)))
    (end-of-char-set? (char-set-cursor-next cs cur))))
(test-assert "a cursor crosses a gap between ranges"
  (let ((cs (char-set #\a #\z)))
    (let lp ((cur (char-set-cursor cs)) (n 0))
      (if (end-of-char-set? cur) (= n 2)
          (lp (char-set-cursor-next cs cur) (+ n 1))))))

;;; -------------------------------------------------- 8. fold / unfold

(test-equal "fold over a singleton"
  '(#\a) (char-set-fold cons '() (char-set #\a)))
(test-equal "fold sees every element once"
  3 (char-set-fold (lambda (c n) (+ n 1)) 0 (string->char-set "abca")))
(test-equal "fold threads its seed"
  '(#\a #\b #\c) (sort-chars (char-set-fold cons '() (string->char-set "cab"))))

;; The spec's identity: (list->char-set lis) = (char-set-unfold null? car cdr lis)
(test-assert "char-set-unfold reproduces list->char-set"
  (char-set= (char-set-unfold null? car cdr (list #\a #\b #\c))
             (list->char-set (list #\a #\b #\c))))
(test-equal "char-set-unfold with a numeric seed"
  "ABCDE"
  (cs-string (char-set-unfold (lambda (i) (= i 5))
                              (lambda (i) (integer->char (+ 65 i)))
                              (lambda (i) (+ i 1))
                              0)))
(test-equal "char-set-unfold adds to base-cs"
  "ABz"
  (cs-string (char-set-unfold (lambda (i) (= i 2))
                              (lambda (i) (integer->char (+ 65 i)))
                              (lambda (i) (+ i 1))
                              0
                              (char-set #\z))))
(test-equal "char-set-unfold! adds to base-cs"
  "ABz"
  (cs-string (char-set-unfold! (lambda (i) (= i 2))
                               (lambda (i) (integer->char (+ 65 i)))
                               (lambda (i) (+ i 1))
                               0
                               (char-set #\z))))
(test-equal "char-set-unfold terminating immediately yields base-cs"
  0 (char-set-size (char-set-unfold (lambda (i) #t) values values 0)))

;;; ------------------------------------------- 9. size / count / every / any

(test-equal "char-set-size of a literal set" 3 (char-set-size (char-set #\a #\b #\c)))
(test-equal "char-set-count" 2 (char-set-count char-alphabetic? (string->char-set "a1b2")))
(test-equal "char-set-count matching nothing"
  0 (char-set-count char-numeric? (string->char-set "abc")))
(test-assert "char-set-every true" (char-set-every char-lower-case? (string->char-set "abc")))
(test-assert "char-set-every false"
  (not (char-set-every char-lower-case? (string->char-set "abC"))))
(test-assert "char-set-every on the empty set is true"
  (char-set-every (lambda (c) #f) char-set:empty))
(test-assert "char-set-any true" (char-set-any char-numeric? (string->char-set "ab1")))
(test-assert "char-set-any false"
  (not (char-set-any char-numeric? (string->char-set "abc"))))
(test-assert "char-set-any on the empty set is false"
  (not (char-set-any (lambda (c) #t) char-set:empty)))
;; "returns the first true value it finds"
(test-equal "char-set-any returns the predicate's value"
  'yes (char-set-any (lambda (c) (and (char=? c #\b) 'yes)) (string->char-set "ab")))

;;; -------------------------------------------------------- 10. conversions

(test-equal "char-set->string round trip" "abc" (cs-string (string->char-set "cba")))
(test-equal "char-set->list length" 3 (length (char-set->list (string->char-set "abc"))))
(test-assert "->char-set on a string"
  (char-set= (->char-set "abc") (char-set #\a #\b #\c)))
(test-assert "->char-set on a character"
  (char-set= (->char-set #\a) (char-set #\a)))
(test-assert "->char-set on a char set is the identity relation"
  (char-set= (->char-set char-set:hex-digit) char-set:hex-digit))
(test-equal "string->char-set with base-cs" "abz"
  (cs-string (string->char-set "ab" (char-set #\z))))
(test-equal "string->char-set! with base-cs" "abz"
  (cs-string (string->char-set! "ab" (char-set #\z))))
(test-equal "list->char-set with base-cs" "abz"
  (cs-string (list->char-set (list #\a #\b) (char-set #\z))))
(test-equal "list->char-set! with base-cs" "abz"
  (cs-string (list->char-set! (list #\a #\b) (char-set #\z))))
(test-assert "char-set-copy is equal to its source"
  (char-set= (char-set-copy char-set:hex-digit) char-set:hex-digit))
(test-assert "char-set-copy of a lazily built constant"
  (char-set= (char-set-copy char-set:digit) char-set:digit))
(test-assert "a copy is a distinct object"
  (let ((cs (char-set #\a))) (not (eq? cs (char-set-copy cs)))))

;;; ------------------------------------------------ 11. ucs-range->char-set

;; "every character whose ... code lies in the half-open range [lower,upper)"
(test-equal "ucs-range->char-set is half-open" "ABCDE" (cs-string (ucs-range->char-set 65 70)))
(test-equal "an empty range yields the empty set" 0 (char-set-size (ucs-range->char-set 65 65)))
(test-equal "ucs-range->char-set with base-cs" "ABz"
  (cs-string (ucs-range->char-set 65 67 #f (char-set #\z))))
(test-equal "ucs-range->char-set! with base-cs" "ABz"
  (cs-string (ucs-range->char-set! 65 67 #f (char-set #\z))))
;; "the code is ignored if error? is false (the default)" -- surrogates have no
;; representative in this implementation's character type.
(test-equal "a range spanning the surrogate block silently skips it"
  4 (char-set-size (ucs-range->char-set #xD7FE #xE002)))
(test-assert "the surrogates really are absent"
  (not (char-set-any (lambda (c) (let ((n (char->integer c)))
                                   (and (>= n #xD800) (<= n #xDFFF))))
                     (ucs-range->char-set #xD7FE #xE002))))
;; "an error is raised if error? is true"
(test-error "error? = #t rejects an unrepresentable code point"
  (ucs-range->char-set #xD7FE #xE002 #t))
(test-assert "error? = #t is fine when every code point is representable"
  (char-set= (ucs-range->char-set 65 68 #t) (char-set #\A #\B #\C)))
(test-error "a descending range is an error" (ucs-range->char-set 70 65))
(test-assert "a range above the last code point is clipped"
  (char-set= (ucs-range->char-set #x10FFFF #x110000) (char-set (cp #x10FFFF))))

;;; -------------------------------------------------- 12. adjoin / delete

(test-equal "adjoin is variadic"
  3 (char-set-size (char-set-adjoin (char-set #\a) #\b #\c)))
(test-equal "adjoin with no characters is the identity"
  1 (char-set-size (char-set-adjoin (char-set #\a))))
(test-equal "adjoin!" "abc" (cs-string (char-set-adjoin! (char-set #\a) #\b #\c)))
(test-equal "delete is variadic"
  "c" (cs-string (char-set-delete (char-set #\a #\b #\c) #\a #\b)))
(test-equal "deleting an absent character changes nothing"
  "abc" (cs-string (char-set-delete (string->char-set "abc") #\z)))
(test-equal "delete!" "c" (cs-string (char-set-delete! (string->char-set "abc") #\a #\b)))
(test-assert "adjoin does not mutate its argument"
  (let ((cs (char-set #\a)))
    (char-set-adjoin cs #\b)
    (char-set= cs (char-set #\a))))
(test-assert "adjoining a non-ASCII character"
  (char-set-contains? (char-set-adjoin (char-set #\a) #\x3bb) #\x3bb))
(test-equal "adjoin splits and rejoins ranges correctly"
  "ABC" (cs-string (char-set-adjoin (char-set #\A #\C) #\B)))
(test-equal "delete splits a range"
  "AC" (cs-string (char-set-delete (ucs-range->char-set 65 68) #\B)))

;;; ---------------------------------------------------------- 13. set algebra

;; "(char-set-union) => char-set:empty"
(test-assert "empty union" (char-set= (char-set-union) char-set:empty))
;; "(char-set-intersection) => char-set:full"
(test-assert "empty intersection" (char-set= (char-set-intersection) char-set:full))
;; "(char-set-xor) => char-set:empty"
(test-assert "empty xor" (char-set= (char-set-xor) char-set:empty))
;; "(char-set-difference cs) => cs"
(test-assert "one-argument difference"
  (char-set= (char-set-difference (char-set #\a #\b)) (char-set #\a #\b)))

(test-equal "union is n-ary"
  "abc" (cs-string (char-set-union (char-set #\a) (char-set #\b) (char-set #\c))))
(test-equal "intersection"
  "b" (cs-string (char-set-intersection (string->char-set "ab") (string->char-set "bc"))))
(test-equal "intersection is n-ary"
  "b" (cs-string (char-set-intersection (string->char-set "abc") (string->char-set "bcd")
                                        (string->char-set "abz") (string->char-set "b"))))
(test-equal "difference associates to the left"
  "a" (cs-string (char-set-difference (string->char-set "abc")
                                      (string->char-set "b")
                                      (string->char-set "c"))))
(test-equal "xor"
  "ac" (cs-string (char-set-xor (string->char-set "ab") (string->char-set "bc"))))
(test-equal "xor is n-ary"
  "ad" (cs-string (char-set-xor (string->char-set "ab") (string->char-set "bc")
                                (string->char-set "cd"))))
(test-equal "union coalesces adjacent ranges"
  10 (char-set-size (char-set-union (ucs-range->char-set 65 70)
                                    (ucs-range->char-set 70 75))))
;; Two routes to the same set must be indistinguishable, not merely equal
;; element-by-element: char-set= and char-set-hash both read the range list.
(test-assert "a coalesced range equals the same set built one char at a time"
  (char-set= (ucs-range->char-set 65 68) (char-set #\A #\B #\C)))
(test-equal "and hashes the same"
  (char-set-hash (ucs-range->char-set 65 68))
  (char-set-hash (char-set #\A #\B #\C)))
;; {A,B} ∪ {D,E}, then adjoin the one character in the gap: the result must be
;; the single range A–E, not three pieces that merely enumerate the same way.
(test-assert "adjoining across a gap coalesces both sides"
  (char-set= (char-set-adjoin (char-set-union (ucs-range->char-set 65 67)
                                              (ucs-range->char-set 68 70))
                              #\C)
             (ucs-range->char-set 65 70)))
(test-equal "union merges overlapping ranges"
  10 (char-set-size (char-set-union (ucs-range->char-set 65 72)
                                    (ucs-range->char-set 68 75))))

(test-equal "union!" "abc"
  (cs-string (char-set-union! (char-set #\a) (char-set #\b) (char-set #\c))))
(test-equal "intersection!" "b"
  (cs-string (char-set-intersection! (string->char-set "ab") (string->char-set "bc"))))
(test-equal "difference!" "a"
  (cs-string (char-set-difference! (string->char-set "ab") (string->char-set "b"))))
(test-equal "xor!" "ac"
  (cs-string (char-set-xor! (string->char-set "ab") (string->char-set "bc"))))

(call-with-values
  (lambda () (char-set-diff+intersection (string->char-set "abc")
                                         (string->char-set "bcd")))
  (lambda (diff isect)
    (test-equal "diff+intersection: difference" "a" (cs-string diff))
    (test-equal "diff+intersection: intersection" "bc" (cs-string isect))))
(call-with-values
  (lambda () (char-set-diff+intersection! (string->char-set "abc")
                                          (string->char-set "bcd")))
  (lambda (diff isect)
    (test-equal "diff+intersection!: difference" "a" (cs-string diff))
    (test-equal "diff+intersection!: intersection" "bc" (cs-string isect))))
(call-with-values
  (lambda () (char-set-diff+intersection (string->char-set "abcd")
                                         (string->char-set "b")
                                         (string->char-set "c")))
  (lambda (diff isect)
    (test-equal "diff+intersection is n-ary: difference" "ad" (cs-string diff))
    (test-equal "diff+intersection is n-ary: intersection" "bc" (cs-string isect))))

;;; ----------------------------------------------------------- 14. complement

(test-assert "complement of empty is full"
  (char-set= (char-set-complement char-set:empty) char-set:full))
(test-assert "complement of full is empty"
  (char-set= (char-set-complement char-set:full) char-set:empty))
(test-assert "complement excludes its argument's members"
  (not (char-set-contains? (char-set-complement (char-set #\a)) #\a)))
(test-assert "complement includes everything else"
  (and (char-set-contains? (char-set-complement (char-set #\a)) #\b)
       (char-set-contains? (char-set-complement (char-set #\a)) #\x3bb)))
(test-assert "complement is an involution"
  (let ((cs (string->char-set "aeiou")))
    (char-set= (char-set-complement (char-set-complement cs)) cs)))
(test-equal "complement counts correctly"
  1112063 (char-set-size (char-set-complement (char-set #\a))))
;; The surrogate block is a hole in the representation, so the code points on
;; either side of it are the ones a two-segment complement could lose.
(test-assert "a complement keeps both sides of the surrogate hole"
  (let ((c (char-set-complement (char-set #\a))))
    (and (has? c #xD7FF) (has? c #xE000))))
(test-assert "a complement stays inside char-set:full"
  (char-set<= (char-set-complement (char-set #\a)) char-set:full))
(test-equal "complement!" 1112063
  (char-set-size (char-set-complement! (char-set #\a))))
(test-assert "complement of ascii excludes ASCII and includes lambda"
  (let ((c (char-set-complement char-set:ascii)))
    (and (not (char-set-contains? c #\a)) (char-set-contains? c #\x3bb))))

;;; ------------------------------------------------- 15. filter / map / each

(test-equal "char-set-filter" "12"
  (cs-string (char-set-filter char-numeric? (string->char-set "a1b2"))))
(test-equal "char-set-filter with base-cs" "12z"
  (cs-string (char-set-filter char-numeric? (string->char-set "a1b2") (char-set #\z))))
(test-equal "char-set-filter!" "12z"
  (cs-string (char-set-filter! char-numeric? (string->char-set "a1b2") (char-set #\z))))
(test-equal "char-set-map" "ABC"
  (cs-string (char-set-map char-upcase (string->char-set "abc"))))
(test-equal "char-set-for-each visits every element"
  '(#\a #\b #\c)
  (let ((acc '()))
    (char-set-for-each (lambda (c) (set! acc (cons c acc))) (string->char-set "cab"))
    (sort-chars acc)))
(test-equal "for-each over the empty set does nothing"
  0 (let ((n 0))
      (char-set-for-each (lambda (c) (set! n (+ n 1))) char-set:empty)
      n))

;;; ---------------------------------------------- 16. purity of non-! forms

(test-assert "char-set-union does not mutate its arguments"
  (let ((a (char-set #\a)) (b (char-set #\b)))
    (char-set-union a b)
    (and (char-set= a (char-set #\a)) (char-set= b (char-set #\b)))))
(test-assert "char-set-delete does not mutate its argument"
  (let ((cs (string->char-set "abc")))
    (char-set-delete cs #\a)
    (char-set= cs (string->char-set "abc"))))
(test-assert "the standard constants survive being operated on"
  (begin (char-set-adjoin char-set:hex-digit #\z)
         (char-set-union char-set:hex-digit (char-set #\z))
         (char-set-delete char-set:hex-digit #\0)
         (= 22 (char-set-size char-set:hex-digit))))

;;; ----------------------------------------------------- 17. type checking

;;; ------------------------- 18. category sizes, so a bad table regeneration
;;;                                cannot land silently (UCD 15.1.0)

(test-equal "char-set:letter is Lu+Ll+Lt+Lm+Lo" 136726 (char-set-size char-set:letter))
(test-equal "char-set:lower-case is Ll" 2233 (char-set-size char-set:lower-case))
(test-equal "char-set:upper-case is Lu" 1831 (char-set-size char-set:upper-case))
(test-equal "char-set:title-case is Lt" 31 (char-set-size char-set:title-case))
(test-equal "char-set:digit is Nd" 680 (char-set-size char-set:digit))
(test-equal "char-set:whitespace is Zs+Zl+Zp plus U+0009..U+000D"
  24 (char-set-size char-set:whitespace))
(test-equal "char-set:blank is Zs plus tab" 18 (char-set-size char-set:blank))
(test-equal "char-set:punctuation is P*" 842 (char-set-size char-set:punctuation))
(test-equal "char-set:symbol is S*" 7775 (char-set-size char-set:symbol))

;;; ---------------------- 19. deliberate disagreements with (scheme char)
;;;
;;; SRFI 14 defines its sets by Unicode general category; R7RS defines its
;;; character predicates by Unicode property.  Those are different questions,
;;; so these two answers differ on purpose.  See the library header.

;; U+2160 ROMAN NUMERAL ONE is category Nl: Alphabetic, but not a letter.
(test-assert "char-alphabetic? is broader than char-set:letter"
  (and (char-alphabetic? (cp #x2160))
       (not (has? char-set:letter #x2160))))
;; char-numeric? misses every supplementary-plane Nd digit; the char set does
;; not.  If char-numeric? is ever fixed, this assertion still holds.
(test-assert "char-set:digit covers supplementary-plane Nd digits"
  (and (has? char-set:digit #x104A0)      ; OSMANYA DIGIT ZERO
       (has? char-set:digit #x1D7CE)      ; MATHEMATICAL BOLD DIGIT ZERO
       (has? char-set:digit #x1E950)))    ; ADLAM DIGIT ZERO

;;; ------------------------------------------- 20. no mutation after construction
;;;
;;; Char sets are immutable once built, and the standard constants are plain
;;; literals rather than lazily memoised thunks.  That is what lets a child
;;; thread touch one first: globals are shared between SRFI-18 threads by
;;; pointer while heaps are per-thread, so any write a child made into a
;;; shared char set would dangle for the parent after the join.

(test-equal "a constant read first from a child thread is still sound in the parent"
  (list 136726 136726)
  (let ((t (make-thread (lambda () (char-set-size char-set:letter)))))
    (thread-start! t)
    (let ((child (thread-join! t)))
      (list child (char-set-size char-set:letter)))))

;;; ----------------------------------------------------- 21. type checking

(test-error "char-set-contains? rejects a non-char-set" (char-set-contains? "abc" #\a))
(test-error "char-set-contains? rejects a non-char" (char-set-contains? (char-set #\a) "a"))
(test-error "char-set-size rejects a non-char-set" (char-set-size '(#\a)))
(test-error "->char-set rejects a symbol" (->char-set 'abc))

;;; ------------------------------------------- 22. randomized model check
;;;
;;; The range algebra's real risk is the overlap/adjacency corner cases —
;;; a range that straddles another's start, one that is wholly contained,
;;; two that abut exactly — which hand-written cases hit only by luck.  So
;;; check every operation against a brute-force list-of-code-points model
;;; over a 121-character alphabet, on pseudo-random inputs built from
;;; overlapping runs.

(define %alphabet-hi 120)

(define (msort l)                       ; sort and deduplicate
  (define (ins x s)
    (cond ((null? s) (list x))
          ((< x (car s)) (cons x s))
          ((= x (car s)) s)
          (else (cons (car s) (ins x (cdr s))))))
  (let loop ((l l) (acc '()))
    (if (null? l) acc (loop (cdr l) (ins (car l) acc)))))

(define (m-union a b) (msort (append a b)))
(define (m-keep a keep?)
  (msort (let go ((x a))
           (cond ((null? x) '())
                 ((keep? (car x)) (cons (car x) (go (cdr x))))
                 (else (go (cdr x)))))))
(define (m-inter a b) (m-keep a (lambda (v) (and (memv v b) #t))))
(define (m-diff a b) (m-keep a (lambda (v) (not (memv v b)))))
(define (m-xor a b) (m-union (m-diff a b) (m-diff b a)))
(define (m-full) (let go ((i 0)) (if (> i %alphabet-hi) '() (cons i (go (+ i 1))))))

(define %seed 12345)
(define (rnd n)
  (set! %seed (modulo (+ (* %seed 1103515245) 12345) 2147483648))
  (modulo (quotient %seed 65536) n))

(define (rand-model)                    ; a few overlapping runs
  (let go ((k (rnd 12)) (acc '()))
    (if (= k 0)
        (msort acc)
        (let ((lo (rnd (+ %alphabet-hi 1))) (len (rnd 15)))
          (go (- k 1)
              (append acc (let r ((i lo) (n len))
                            (if (or (= n 0) (> i %alphabet-hi))
                                '()
                                (cons i (r (+ i 1) (- n 1)))))))))))

(define %universe (ucs-range->char-set 0 (+ %alphabet-hi 1)))
(define (model->cs m) (list->char-set (map integer->char m)))
(define (cs->model cs)
  (map char->integer (char-set->list (char-set-intersection cs %universe))))

(define (model-mismatches trials)
  (let trial ((t 0) (bad '()))
    (if (= t trials)
        (reverse bad)
        (let* ((ma (rand-model)) (mb (rand-model))
               (ca (model->cs ma)) (cb (model->cs mb))
               (ch (integer->char (rnd (+ %alphabet-hi 1))))
               (cases
                 (list
                   (list 'round-trip ma (cs->model ca))
                   (list 'size (length ma) (char-set-size ca))
                   (list 'union (m-union ma mb) (cs->model (char-set-union ca cb)))
                   (list 'intersection (m-inter ma mb)
                         (cs->model (char-set-intersection ca cb)))
                   (list 'difference (m-diff ma mb)
                         (cs->model (char-set-difference ca cb)))
                   (list 'xor (m-xor ma mb) (cs->model (char-set-xor ca cb)))
                   (list 'complement (m-diff (m-full) ma)
                         (cs->model (char-set-complement ca)))
                   (list 'subset (null? (m-diff ma mb)) (char-set<= ca cb))
                   (list 'equal (equal? ma mb) (char-set= ca cb))
                   (list 'adjoin (m-union ma (list (char->integer ch)))
                         (cs->model (char-set-adjoin ca ch)))
                   (list 'delete (m-diff ma (list (char->integer ch)))
                         (cs->model (char-set-delete ca ch)))
                   (list 'filter (m-keep ma even?)
                         (cs->model (char-set-filter
                                      (lambda (c) (even? (char->integer c))) ca)))
                   (list 'cursor ma
                         (let lp ((cur (char-set-cursor ca)) (acc '()))
                           (if (end-of-char-set? cur)
                               (msort acc)
                               (lp (char-set-cursor-next ca cur)
                                   (cons (char->integer (char-set-ref ca cur)) acc)))))
                   ;; Canonicity: the same set reached by a different route
                   ;; must be indistinguishable.  char-set= and char-set-hash
                   ;; both read the range list directly, so a set that failed
                   ;; to coalesce two abutting ranges would answer wrongly
                   ;; here while still enumerating the right characters.
                   (list 'canonical-equal #t
                         (char-set= ca (let adj ((m ma) (cs char-set:empty))
                                         (if (null? m)
                                             cs
                                             (adj (cdr m)
                                                  (char-set-adjoin
                                                    cs (integer->char (car m))))))))
                   (list 'canonical-hash (char-set-hash ca)
                         (char-set-hash (char-set-union
                                          (model->cs (m-keep ma even?))
                                          (model->cs (m-keep ma odd?)))))
                   (list 'hash (char-set-hash ca) (char-set-hash (model->cs ma))))))
          (trial (+ t 1)
                 (let scan ((c cases) (bad bad))
                   (cond ((null? c) bad)
                         ((equal? (cadr (car c)) (caddr (car c))) (scan (cdr c) bad))
                         (else (scan (cdr c) (cons (cons t (car c)) bad))))))))))

(test-equal "200 randomized trials agree with a brute-force set model"
  '() (model-mismatches 200))

(let ((runner (test-runner-current)))
  (test-end "srfi-14")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
