;; SRFI-209 (Enums and Enum Sets) conformance tests
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi209.scm
;;
;; The spec's own prose examples write bare names like `(enum-set color red
;; blue)`, implicitly assuming `red`/`blue` are already bound to enum
;; objects; enum-set itself is a procedure (its arguments are evaluated),
;; so those are adapted here to explicit (enum-name->enum color 'red) calls.

(import (scheme base) (scheme process-context) (srfi 128) (srfi 209) (srfi 64))

(test-begin "srfi-209")

;;; --- the SRFI's own example enum types ---

(define color (make-enum-type '(red orange yellow green cyan blue violet)))
(define us-traffic-light (make-enum-type '(red yellow green)))
(define pizza (make-enum-type '((margherita "tomato and mozzarella")
                                 (funghi "mushrooms")
                                 (chicago "deep-dish")
                                 (hawaiian "pineapple and ham"))))

;;; --- basic predicates and accessors ---

(test-equal #t (enum-type? color))
(test-equal #f (enum-type? 'red))
(test-equal #t (enum? (enum-name->enum color 'red)))
(test-equal #f (enum? 'red))

(test-equal #t (enum-type-contains? color (enum-name->enum color 'red)))
(test-equal #f (enum-type-contains? pizza (enum-name->enum color 'red)))

(define red (enum-name->enum color 'red))
(test-equal 'red (enum-name red))
(test-equal 0 (enum-ordinal red))
(test-equal 0 (enum-value red)) ;; no explicit value given: defaults to ordinal
(test-equal color (enum-type red))

(define margherita (enum-name->enum pizza 'margherita))
(test-equal "tomato and mozzarella" (enum-value margherita))

;;; --- finders ---

(test-equal #f (enum-name->enum color 'purple))
(test-equal #f (enum-ordinal->enum color 99))
(test-equal #f (enum-ordinal->enum color -1))
(test-equal 'orange (enum-ordinal->name color 1))
(test-equal 1 (enum-value (enum-ordinal->enum color 1)))

(test-equal 0 (enum-name->ordinal color 'red))
(test-equal "deep-dish" (enum-name->value pizza 'chicago))
(test-equal 'chicago (enum-ordinal->name pizza 2))
(test-equal "mushrooms" (enum-ordinal->value pizza 1))

(test-equal #t (guard (e (#t #t)) (enum-name->ordinal color 'purple) #f))
(test-equal #t (guard (e (#t #t)) (enum-ordinal->name color 99) #f))

;;; --- enum comparisons ---

(test-equal #t (enum=? red (enum-name->enum color 'red)))
(test-equal #t (enum<? red (enum-name->enum color 'orange)))
(test-equal #t (enum<? red (enum-name->enum color 'orange) (enum-name->enum color 'yellow)))
(test-equal #f (enum<? red (enum-name->enum color 'orange) (enum-name->enum color 'orange)))
(test-equal #t (enum>? (enum-name->enum color 'violet) red))
(test-equal #t (enum<=? red red))
(test-equal #t (enum>=? red red))
(test-equal #t (guard (e (#t #t)) (enum=? red (enum-name->enum pizza 'chicago)) #f))

;;; --- enum type operations ---

(test-equal 7 (enum-type-size color))
(test-equal 'red (enum-name (enum-min color)))
(test-equal 'violet (enum-name (enum-max color)))
(test-equal '(red orange yellow green cyan blue violet) (enum-type-names color))
(test-equal '(0 1 2 3 4 5 6) (enum-type-values color))
(test-equal 7 (length (enum-type-enums color)))

;;; --- navigation ---

(test-equal 'orange (enum-name (enum-next red)))
(test-equal #f (enum-prev red))
(test-equal #f (enum-next (enum-max color)))
(test-equal 'yellow (enum-name (enum-prev (enum-name->enum color 'green))))

;;; --- comparator (SRFI 128) ---

(define pizza-comparator (make-enum-comparator pizza))
(define pizza-margherita margherita)
(define pizza-chicago (enum-name->enum pizza 'chicago))
(test-equal #t (comparator-hashable? pizza-comparator))
(test-equal #t (<? pizza-comparator pizza-margherita pizza-chicago))
(test-equal #f (<? pizza-comparator pizza-chicago pizza-margherita))
(test-equal #t (=? pizza-comparator pizza-margherita pizza-margherita))

;;; --- enum sets: construction ---

(define color-set (enum-type->enum-set color))
(test-equal #t (enum-set? color-set))
(test-equal #f (enum-set? 'x))
(test-equal 7 (enum-set-size color-set))
(test-equal #t (enum-set-empty? (enum-empty-set color)))
(test-equal #f (enum-set-empty? color-set))

(define rb-set (enum-set color red (enum-name->enum color 'blue)))
(test-equal 2 (enum-set-size rb-set))
(test-equal #t (enum-set-contains? rb-set red))
(test-equal #f (enum-set-contains? rb-set (enum-name->enum color 'green)))
(test-equal #t (guard (e (#t #t)) (enum-set color red margherita) #f))

(define rb-set2 (list->enum-set color (list red (enum-name->enum color 'blue))))
(test-equal #t (enum-set=? rb-set rb-set2))

;;; --- enum-set-projection: maps by name into a (possibly different) type ---

(define traffic-red-green (enum-set us-traffic-light
                                     (enum-name->enum us-traffic-light 'red)
                                     (enum-name->enum us-traffic-light 'green)))
(define projected (enum-set-projection color traffic-red-green))
(test-equal #t (enum-set? projected))
(test-equal color (enum-set-type projected))
(test-equal 2 (enum-set-size projected))
(test-equal #t (enum-set-contains? projected red))
(test-equal #t (guard (e (#t #t)) (enum-set-projection us-traffic-light color-set) #f))

;;; --- enum-set-copy is a genuine copy, not the same object's membership ---

(define copy-of-rb (enum-set-copy rb-set))
(test-equal #t (enum-set=? rb-set copy-of-rb))
(define adjoined-copy (enum-set-adjoin copy-of-rb (enum-name->enum color 'green)))
(test-equal 2 (enum-set-size rb-set)) ;; original untouched
(test-equal 3 (enum-set-size adjoined-copy))

;;; --- R6RS-flavored constructors ---

(define days (make-enumeration '(mon tue wed thu fri sat sun)))
(test-equal #t (enum-set? days))
(test-equal 7 (enum-set-size days))
(test-equal 'mon (enum-name->value (enum-set-type days) 'mon)) ;; values equal names

(define full-days (enum-set-universe (enum-set (enum-set-type days) (enum-name->enum (enum-set-type days) 'mon))))
(test-equal 7 (enum-set-size full-days))

(define day-ctor (enum-set-constructor days))
(define weekend (day-ctor '(sat sun)))
(test-equal 2 (enum-set-size weekend))
(test-equal #t (enum-set-member? 'sat weekend))
(test-equal #f (enum-set-member? 'mon weekend))

;;; --- predicates ---

(test-equal #t (enum-set-disjoint? (enum-set color red) (enum-set color (enum-name->enum color 'blue))))
(test-equal #f (enum-set-disjoint? rb-set rb-set2))

;; enum-set=? / <? / >? / <=? / >=? compare membership directly (same type required)
(test-equal #t (enum-set=? color-set (enum-type->enum-set color)))
(test-equal #t (enum-set<? rb-set color-set))
(test-equal #f (enum-set<? color-set rb-set))
(test-equal #t (enum-set>? color-set rb-set))
(test-equal #t (enum-set<=? rb-set rb-set2))
(test-equal #t (enum-set>=? rb-set rb-set2))
(test-equal #t (guard (e (#t #t)) (enum-set=? rb-set (enum-type->enum-set pizza)) #f))

;; enum-set-subset? compares by NAME, so different types are fine
(test-equal #t (enum-set-subset?
                 (enum-set color red (enum-name->enum color 'blue))
                 (enum-set color red (enum-name->enum color 'green) (enum-name->enum color 'blue))))
(test-equal #t (enum-set-subset?
                 (enum-set us-traffic-light (enum-name->enum us-traffic-light 'red)
                                             (enum-name->enum us-traffic-light 'green))
                 (enum-set color red (enum-name->enum color 'green) (enum-name->enum color 'blue))))
(test-equal #f (enum-set-subset? color-set (enum-set us-traffic-light (enum-name->enum us-traffic-light 'red))))

(test-equal #t (enum-set-any? (lambda (e) (eq? (enum-name e) 'red)) rb-set))
(test-equal #f (enum-set-any? (lambda (e) (eq? (enum-name e) 'green)) rb-set))
(test-equal #t (enum-set-every? (lambda (e) (< (enum-ordinal e) 6)) rb-set))
(test-equal #f (enum-set-every? (lambda (e) (< (enum-ordinal e) 1)) rb-set))

;;; --- accessors ---

(test-equal color (enum-set-type color-set))
(define indexer (enum-set-indexer color-set))
(test-equal 0 (indexer 'red))
(test-equal #f (indexer 'nonexistent))

;;; --- mutators (functional; `!` names are the same procedures here) ---

(define with-green (enum-set-adjoin rb-set (enum-name->enum color 'green)))
(test-equal 3 (enum-set-size with-green))
(test-equal 2 (enum-set-size rb-set)) ;; unchanged

(define without-red (enum-set-delete with-green red))
(test-equal 2 (enum-set-size without-red))
(test-equal #f (enum-set-contains? without-red red))

(define almost-empty (enum-set-delete-all color-set (enum-type-enums color)))
(test-equal #t (enum-set-empty? almost-empty))
(test-equal 7 (enum-set-size color-set)) ;; unchanged

;;; --- whole-set operations ---

(test-equal '(red blue) (enum-set->list rb-set)) ;; ordinal order: red=0, blue=5
(test-equal 4 (enum-set-count (lambda (e) (< (enum-ordinal e) 4)) color-set)) ;; red,orange,yellow,green
(test-equal 0 (enum-set-count (lambda (e) (< (enum-ordinal e) 4)) (enum-empty-set color)))

;; the SRFI's own worked example
(test-equal '(cyan blue violet)
  (enum-set-map->list enum-name (enum-set-filter (lambda (e) (> (enum-ordinal e) 3)) color-set)))
(test-equal '(red orange yellow green)
  (enum-set-map->list enum-name (enum-set-remove (lambda (e) (> (enum-ordinal e) 3)) color-set)))

(define for-each-log '())
(enum-set-for-each (lambda (e) (set! for-each-log (cons (enum-name e) for-each-log))) rb-set)
(test-equal '(blue red) for-each-log) ;; ordinal order, then reversed by cons

(test-equal 5 (enum-set-fold (lambda (e acc) (+ acc (enum-ordinal e))) 0 rb-set)) ;; 0 (red) + 5 (blue)

;;; --- logical operations ---

(define red-only (enum-set color red))
(define blue-only (enum-set color (enum-name->enum color 'blue)))

(test-equal 5 (enum-set-size (enum-set-complement rb-set)))
(test-equal #f (enum-set-contains? (enum-set-complement rb-set) red))

(test-equal #t (enum-set=? rb-set (enum-set-union red-only blue-only)))
(test-equal #t (enum-set-empty? (enum-set-intersection red-only blue-only)))
(test-equal #t (enum-set=? red-only (enum-set-intersection rb-set red-only)))
(test-equal #t (enum-set=? blue-only (enum-set-difference rb-set red-only)))
(test-equal #t (enum-set-empty? (enum-set-difference red-only red-only)))
(test-equal #t (enum-set=? rb-set (enum-set-xor red-only blue-only)))
(test-equal #t (enum-set-empty? (enum-set-xor red-only red-only)))
(test-equal #t (guard (e (#t #t)) (enum-set-union rb-set (enum-type->enum-set pizza)) #f))

;;; --- define-enum ---

(define-enum fruit
  (apple banana cherry)
  fruit-set)

(test-equal #t (enum? (fruit apple)))
(test-equal 'apple (enum-name (fruit apple)))
(test-equal 0 (enum-ordinal (fruit apple)))
(test-equal 2 (enum-ordinal (fruit cherry)))
(test-equal #t (eq? (fruit apple) (fruit apple))) ;; stable identity, not a fresh enum each time

(define some-fruits (fruit-set apple cherry))
(test-equal #t (enum-set? some-fruits))
(test-equal 2 (enum-set-size some-fruits))
(test-equal #t (enum-set-contains? some-fruits (fruit apple)))
(test-equal #f (enum-set-contains? some-fruits (fruit banana)))
(test-equal #t (enum-set-empty? (fruit-set)))
;; duplicates in the constructor are allowed
(test-equal 1 (enum-set-size (fruit-set apple apple)))

;;; --- define-enumeration ---

(define-enumeration weekday
  (mon tue wed thu fri)
  weekday-set)

(test-equal 'mon (weekday mon)) ;; returns the symbol, not an enum object
(test-equal #t (enum-set=? (weekday-set mon tue) (weekday-set tue mon)))
(test-equal 5 (enum-set-size (weekday-set mon tue wed thu fri)))

(let ((runner (test-runner-current)))
  (test-end "srfi-209")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
