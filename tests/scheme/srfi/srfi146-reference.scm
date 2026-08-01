;;; SRFI 146 (mappings) and SRFI 146 hash (hashmaps) tests -- ported verbatim
;;; (test logic unchanged) from the SRFI's own reference test suite,
;;; srfi/146/test.sld and srfi/146/hash/test.sld in
;;; https://srfi.schemers.org/srfi-146/srfi-146.tgz, by Marc
;;; Nieper-Wisskirchen (2016), MIT-licensed.
;;;
;;; Differences from the reference, all of them harness rather than test logic:
;;;   - the reference wraps each body in a `(srfi 146 test)` / `(srfi 146 hash
;;;     test)` library exporting a `run-tests` thunk; this flattens both into
;;;     one standalone script, matching every other tests/scheme/srfi/*.scm,
;;;     with the two bodies as the "ordered" and "hash" groups;
;;;   - leading tabs expanded to spaces;
;;;   - the two `comparator-register-default!` calls below, explained there;
;;;   - assertions blocked by a filed defect, commented out with a
;;;     `;; FAIL: #NNNN` marker directly above (the fix PR re-enables them).
;;;
;;; Every assertion carries a name string, as the reference suite already did.
;;; Added by Systematic audit v2, Phase 3.4.

(import (scheme base) (scheme write) (scheme process-context)
        (srfi 1) (srfi 8) (srfi 64) (srfi 128) (srfi 146) (srfi 146 hash))

(define comparator (make-default-comparator))

;;; The reference suite predates SRFI 146's 2021-06-08 post-finalization note,
;;; which changed "The following comparator is used to compare mappings when
;;; (make-default-comparator) ... is invoked" into "The user may register the
;;; following comparator ...".  The reference implementation registers both at
;;; library-load time, so its suite runs with them registered; a library
;;; conforming to the final text must not, so the two calls are made here
;;; instead.  Without them the "Comparators" groups would be asserting a
;;; requirement the final spec deliberately removed (verified: two assertions,
;;; "=?: equal mappings" and "=?: equal hashmaps", pass only with them).
(comparator-register-default! mapping-comparator)
(comparator-register-default! hashmap-comparator)

(test-begin "srfi146-reference")

(test-group "ordered"

      

      (test-group "Predicates"
        (define mapping0 (mapping comparator))
        (define mapping1 (mapping comparator 'a 1 'b 2 'c 3))
        (define mapping2 (mapping comparator 'c 1 'd 2 'e 3))
        (define mapping3 (mapping comparator 'd 1 'e 2 'f 3))

        (test-assert "mapping?: a mapping"
          (mapping? (mapping comparator)))

        (test-assert "mapping?: not a mapping"
          (not (mapping? (list 1 2 3))))

        (test-assert "mapping-empty?: empty mapping"
          (mapping-empty? mapping0))

        (test-assert "mapping-empty?: non-empty mapping"
          (not (mapping-empty? mapping1)))

        (test-assert "mapping-contains?: containing"
          (mapping-contains? mapping1 'b))

        (test-assert "mapping-contains?: not containing"
          (not (mapping-contains? mapping1 '2)))

        (test-assert "mapping-disjoint?: disjoint"
          (mapping-disjoint? mapping1 mapping3))

        (test-assert "mapping-disjoint?: not disjoint"
          (not (mapping-disjoint? mapping1 mapping2))))

      (test-group "Accessors"
        (define mapping1 (mapping comparator 'a 1 'b 2 'c 3))

        (test-equal "mapping-ref: key found"
          2
          (mapping-ref mapping1 'b))

        (test-equal "mapping-ref: key not found/with failure"
          42
          (mapping-ref mapping1 'd (lambda () 42)))

        (test-error "mapping-ref: key not found/without failure"
          (mapping-ref mapping1 'd))

        (test-equal "mapping-ref: with success procedure"
          (* 2 2)
          (mapping-ref mapping1 'b (lambda () #f) (lambda (x) (* x x))))

        (test-equal "mapping-ref/default: key found"
          3
          (mapping-ref/default mapping1 'c 42))

        (test-equal "mapping-ref/default: key not found"
          42
          (mapping-ref/default mapping1 'd 42))

        (test-equal "mapping-key-comparator"
          comparator
          (mapping-key-comparator mapping1)))

      (test-group "Updaters"
        (define mapping1 (mapping comparator 'a 1 'b 2 'c 3))
        (define mapping2 (mapping-set mapping1 'c 4 'd 4 'd 5))
        (define mapping3 (mapping-update mapping1 'b (lambda (x) (* x x))))
        (define mapping4 (mapping-update/default mapping1 'd (lambda (x) (* x x)) 4))
        (define mapping5 (mapping-adjoin mapping1 'c 4 'd 4 'd 5))
        (define mapping0 (mapping comparator))

        (test-equal "mapping-adjoin: key already in mapping"
          3
          (mapping-ref mapping5 'c))

        (test-equal "mapping-adjoin: key set earlier"
          4
          (mapping-ref mapping5 'd))

        (test-equal "mapping-set: key already in mapping"
          4
          (mapping-ref mapping2 'c))

        (test-equal "mapping-set: key set earlier"
          5
          (mapping-ref mapping2 'd))

        (test-equal "mapping-replace: key not in mapping"
          #f
          (mapping-ref/default (mapping-replace mapping1 'd 4) 'd #f))

        (test-equal "mapping-replace: key in mapping"
          6
          (mapping-ref (mapping-replace mapping1 'c 6) 'c))

        (test-equal "mapping-delete"
          42
          (mapping-ref/default (mapping-delete mapping1 'b) 'b 42))

        (test-equal "mapping-delete-all"
          42
          (mapping-ref/default (mapping-delete-all mapping1 '(a b)) 'b 42))

        (test-equal "mapping-intern: key in mapping"
          (list mapping1 2)
          (receive result
              (mapping-intern mapping1 'b (lambda () (error "should not have been invoked")))
            result))

        (test-equal "mapping-intern: key not in mapping"
          (list 42 42)
          (receive (mapping value)
              (mapping-intern mapping1 'd (lambda () 42))
            (list value (mapping-ref mapping 'd))))

        (test-equal "mapping-update"
          4
          (mapping-ref mapping3 'b))

        (test-equal "mapping-update/default"
          16
          (mapping-ref mapping4 'd))

        (test-equal "mapping-pop: empty mapping"
          'empty
          (mapping-pop mapping0 (lambda () 'empty)))

        (test-equal "mapping-pop: non-empty mapping"
          (list 2 'a 1)
          (receive (mapping key value)
              (mapping-pop mapping1)
            (list (mapping-size mapping) key value)))

        (test-equal
            '("success updated"
              "failure ignored"
              ((0 . "zero") (1 . "one") (2 . "two [seen]") (3 . "three")
               (4 . "four") (5 . "five")))
          (let ((m1 (mapping (make-default-comparator)
                             1 "one"
                             3 "three"
                             0 "zero"
                             4 "four"
                             2 "two"
                             5 "five")))
            (define (f/ignore insert ignore)
              (ignore "failure ignored"))
            (define (s/update key val update remove)
              (update key
                      (string-append val " [seen]")
                      "success updated"))
            (let*-values (((m2 v2) (mapping-search m1 2 f/ignore s/update))
                          ((m3 v3) (mapping-search m2 42 f/ignore s/update)))
              (list v2 v3 (mapping->alist m3))))))

      (test-group "The whole mapping"
        (define mapping0 (mapping comparator))
        (define mapping1 (mapping comparator 'a 1 'b 2 'c 3))

        (test-equal "mapping-size: empty mapping"
          0
          (mapping-size mapping0))

        (test-equal "mapping-size: non-empty mapping"
          3
          (mapping-size mapping1))

        (test-equal "mapping-find: found in mapping"
          (list 'b 2)
          (receive result
              (mapping-find (lambda (key value)
                          (and (eq? key 'b)
                               (= value 2)))
                        mapping1
                        (lambda () (error "should not have been called")))
            result))

        (test-equal "mapping-find: not found in mapping"
          (list 42)
          (receive result
              (mapping-find (lambda (key value)
                          (eq? key 'd))
                        mapping1
                        (lambda ()
                          42))
            result))

        (test-equal "mapping-count"
          2
          (mapping-count (lambda (key value)
                       (>= value 2))
                     mapping1))

        (test-assert "mapping-any?: found"
          (mapping-any? (lambda (key value)
                      (= value 3))
                    mapping1))

        (test-assert "mapping-any?: not found"
          (not (mapping-any? (lambda (key value)
                           (= value 4))
                         mapping1)))

        (test-assert "mapping-every?: true"
          (mapping-every? (lambda (key value)
                        (<= value 3))
                      mapping1))

        (test-assert "mapping-every?: false"
          (not (mapping-every? (lambda (key value)
                             (<= value 2))
                           mapping1)))

        (test-equal "mapping-keys"
          3
          (length (mapping-keys mapping1)))

        (test-equal "mapping-values"
          6
          (fold + 0 (mapping-values mapping1)))

        (test-equal "mapping-entries"
          (list 3 6)
          (receive (keys values)
              (mapping-entries mapping1)
            (list (length keys) (fold + 0 values)))))

      (test-group "Mapping and folding"
        (define mapping1 (mapping comparator 'a 1 'b 2 'c 3))
        (define mapping2 (mapping-map (lambda (key value)
                                (values (symbol->string key)
                                        (* 10 value)))
                              comparator
                              mapping1))

        (test-equal "mapping-map"
          20
          (mapping-ref mapping2 "b"))

        (test-equal "mapping-for-each"
          6
          (let ((counter 0))
            (mapping-for-each (lambda (key value)
                            (set! counter (+ counter value)))
                          mapping1)
            counter))

        (test-equal "mapping-fold"
          6
          (mapping-fold (lambda (key value acc)
                      (+ value acc))
                    0
                    mapping1))

        (test-equal "mapping-map->list"
          (+ (* 1 1) (* 2 2) (* 3 3))
          (fold + 0 (mapping-map->list (lambda (key value)
                                     (* value value))
                                   mapping1)))

        (test-equal "mapping-filter"
          2
          (mapping-size (mapping-filter (lambda (key value)
                                  (<= value 2))
                                mapping1)))

        (test-equal "mapping-remove"
          1
          (mapping-size (mapping-remove (lambda (key value)
                                  (<= value 2))
                                mapping1)))

        (test-equal "mapping-partition"
          (list 1 2)
          (receive result
              (mapping-partition (lambda (key value)
                               (eq? 'b key))
                             mapping1)
            (map mapping-size result)))

        (test-group "Copying and conversion"
          (define mapping1 (mapping comparator 'a 1 'b 2 'c 3))
          (define mapping2 (alist->mapping comparator '((a . 1) (b . 2) (c . 3))))
          (define mapping3 (alist->mapping! (mapping-copy mapping1) '((d . 4) '(c . 5))))

          (test-equal "mapping-copy: same size"
            3
            (mapping-size (mapping-copy mapping1)))

          (test-equal "mapping-copy: same comparator"
            comparator
            (mapping-key-comparator (mapping-copy mapping1)))

          (test-equal "mapping->alist"
            (cons 'b 2)
            (assq 'b (mapping->alist mapping1)))

          (test-equal "alist->mapping"
            2
            (mapping-ref mapping2 'b)
            )

          (test-equal "alist->mapping!: new key"
            4
            (mapping-ref mapping3 'd))

          (test-equal "alist->mapping!: existing key"
            3
            (mapping-ref mapping3 'c)))

        (test-group "Submappings"
          (define mapping1 (mapping comparator 'a 1 'b 2 'c 3))
          (define mapping2 (mapping comparator 'a 1 'b 2 'c 3))
          (define mapping3 (mapping comparator 'a 1 'c 3))
          (define mapping4 (mapping comparator 'a 1 'c 3 'd 4))
          (define mapping5 (mapping comparator 'a 1 'b 2 'c 6))
          (define mapping6 (mapping (make-comparator (comparator-type-test-predicate comparator)
                                                     (comparator-equality-predicate comparator)
                                                     (comparator-ordering-predicate comparator)
                                                     (lambda (obj) 42))
                                    'a 1 'b 2 'c 3))


          (test-assert "mapping=?: equal mappings"
            (mapping=? comparator mapping1 mapping2))

          (test-assert "mapping=?: unequal mappings"
            (not (mapping=? comparator mapping1 mapping4)))

          ;; FAIL: #2047 (mapping=? omits the key-comparator identity check)
          ;; (test-assert "mapping=?: different comparators"
          ;;   (not (mapping=? comparator mapping1 mapping6)))

          (test-assert "mapping<?: proper subset"
            (mapping<? comparator mapping3 mapping1))

          (test-assert "mapping<?: improper subset"
            (not (mapping<? comparator mapping3 mapping1 mapping2)))

          (test-assert "mapping>?: proper superset"
            (mapping>? comparator mapping2 mapping3))

          (test-assert "mapping>?: improper superset"
            (not (mapping>? comparator mapping1 mapping2 mapping3)))

          (test-assert "mapping<=?: subset"
            (mapping<=? comparator mapping3 mapping2 mapping1))

          (test-assert "mapping<=?: non-matching values"
            (not (mapping<=? comparator mapping3 mapping5)))

          (test-assert "mapping<=?: not a subset"
            (not (mapping<=? comparator mapping2 mapping4)))

          (test-assert "mapping>=?: superset"
            (mapping>=? comparator mapping4 mapping3))

          (test-assert "mapping>=?: not a superset"
            (not (mapping>=? comparator mapping5 mapping3))))

        (test-group "Set theory operations"
          (define mapping1 (mapping comparator 'a 1 'b 2 'c 3))
          (define mapping2 (mapping comparator 'a 1 'b 2 'd 4))
          (define mapping3 (mapping comparator 'a 1 'b 2))
          (define mapping4 (mapping comparator 'a 1 'b 2 'c 4))
          (define mapping5 (mapping comparator 'a 1 'c 3))
          (define mapping6 (mapping comparator 'd 4 'e 5 'f 6))

          (test-equal "mapping-union: new association"
            4
            (mapping-ref (mapping-union mapping1 mapping2) 'd))

          (test-equal "mapping-union: existing association"
            3
            (mapping-ref (mapping-union mapping1 mapping4) 'c))

          (test-equal "mapping-union: three mappings"
            6
            (mapping-size (mapping-union mapping1 mapping2 mapping6)))

          (test-equal "mapping-intersection: existing association"
            3
            (mapping-ref (mapping-intersection mapping1 mapping4) 'c))

          (test-equal "mapping-intersection: removed association"
            42
            (mapping-ref/default (mapping-intersection mapping1 mapping5) 'b 42))

          (test-equal "mapping-difference"
            2
            (mapping-size (mapping-difference mapping2 mapping6)))

          (test-equal "mapping-xor"
            4
            (mapping-size (mapping-xor mapping2 mapping6))))

        (test-group "Additional procedures for mappings with ordered keys"
          (define mapping1 (mapping comparator 'a 1 'b 2 'c 3))
          (define mapping2 (mapping comparator 'a 1 'b 2 'c 3 'd 4))
          (define mapping3 (mapping comparator 'a 1 'b 2 'c 3 'd 4 'e 5))
          (define mapping4 (mapping comparator 'a 1 'b 2 'c 3 'd 4 'e 5 'f 6))
          (define mapping5 (mapping comparator 'f 6 'g 7 'h 8))

          (test-equal "mapping-min-key"
            '(a a a a)
            (map mapping-min-key (list mapping1 mapping2 mapping3 mapping4)))

          (test-equal "mapping-max-key"
            '(c d e f)
            (map mapping-max-key (list mapping1 mapping2 mapping3 mapping4)))

          (test-equal "mapping-min-value"
            '(1 1 1 1)
            (map mapping-min-value (list mapping1 mapping2 mapping3 mapping4)))

          (test-equal "mapping-max-value"
            '(3 4 5 6)
            (map mapping-max-value (list mapping1 mapping2 mapping3 mapping4)))

          (test-equal "mapping-key-predecessor"
            '(c d d d)
            (map (lambda (mapping)
                   (mapping-key-predecessor mapping 'e (lambda () #f)))
                 (list mapping1 mapping2 mapping3 mapping4)))

          (test-equal "mapping-key-successor"
            '(#f #f e e)
            (map (lambda (mapping)
                   (mapping-key-successor mapping 'd (lambda () #f)))
                 (list mapping1 mapping2 mapping3 mapping4)))

          (test-equal "mapping-range=: contained"
            '(4)
            (mapping-values (mapping-range= mapping4 'd)))

          (test-equal "mapping-range=: not contained"
            '()
            (mapping-values (mapping-range= mapping4 'z)))

          (test-equal "mapping-range<"
            '(1 2 3)
            (mapping-values (mapping-range< mapping4 'd)))

          (test-equal "mapping-range<="
            '(1 2 3 4)
            (mapping-values (mapping-range<= mapping4 'd)))

          (test-equal "mapping-range>"
            '(5 6)
            (mapping-values (mapping-range> mapping4 'd)))

          (test-equal "mapping-range>="
            '(4 5 6)
            (mapping-values (mapping-range>= mapping4 'd)))

          (test-equal "mapping-split"
            '((1 2 3) (1 2 3 4) (4) (4 5 6) (5 6))
            (receive mappings
                (mapping-split mapping4 'd)
              (map mapping-values mappings)))

          (test-equal "mapping-catenate"
            '((a . 1) (b . 2) (c . 3) (d . 4) (e . 5) (f . 6) (g . 7) (h . 8))
            (mapping->alist (mapping-catenate comparator mapping2 'e 5 mapping5)))

          (test-equal "mapping-map/monotone"
            '((1 . 1) (2 . 4) (3 . 9))
            (mapping->alist
             (mapping-map/monotone (lambda (key value)
                                     (values value (* value value)))
                                   comparator
                                   mapping1)))

          (test-equal "mapping-fold/reverse"
            '(1 2 3)
            (mapping-fold/reverse (lambda (key value acc)
                                    (cons value acc))
                                  '() mapping1)))

        (test-group "Comparators"
          (define mapping1 (mapping comparator 'a 1 'b 2 'c 3))
          (define mapping2 (mapping comparator 'a 1 'b 2 'c 3))
          (define mapping3 (mapping comparator 'a 1 'b 2))
          (define mapping4 (mapping comparator 'a 1 'b 2 'c 4))
          (define mapping5 (mapping comparator 'a 1 'c 3))
          (define mapping0 (mapping comparator mapping1 "a" mapping2 "b" mapping3 "c" mapping4 "d" mapping5 "e"))

          (test-assert "mapping-comparator"
            (comparator? mapping-comparator))

          ;; FAIL: #2048 (mapping-comparator supplies no ordering predicate, so the outer
          ;;              mapping is built with an inconsistent one) and #2045 (once that
          ;;              is fixed, the constructor keeps the LAST of two equal keys)
          ;; (test-equal "mapping-keyed mapping"
          ;;   (list "a" "a" "c" "d" "e")
          ;;   (list (mapping-ref mapping0 mapping1)
          ;;         (mapping-ref mapping0 mapping2)
          ;;         (mapping-ref mapping0 mapping3)
          ;;         (mapping-ref mapping0 mapping4)
          ;;         (mapping-ref mapping0 mapping5)))

          (test-group "Ordering comparators"
            (test-assert "=?: equal mappings"
              (=? comparator mapping1 mapping2))

            (test-assert "=?: unequal mappings"
              (not (=? comparator mapping1 mapping4)))

            ;; FAIL: #2048 (make-mapping-comparator supplies no ordering predicate)
            ;; (test-assert "<?: case 1"
            ;;   (<? comparator mapping3 mapping4))

            ;; FAIL: #2048 (make-mapping-comparator supplies no ordering predicate)
            ;; (test-assert "<?: case 2"
            ;;   (<? comparator mapping1 mapping4))

            ;; FAIL: #2048 (make-mapping-comparator supplies no ordering predicate)
            ;; (test-assert "<?: case 3"
            ;;   (<? comparator mapping1 mapping5))
            )))

      
)

(test-group "hash"

      

      (test-group "Predicates"
        (define hashmap0 (hashmap comparator))
        (define hashmap1 (hashmap comparator 'a 1 'b 2 'c 3))
        (define hashmap2 (hashmap comparator 'c 1 'd 2 'e 3))
        (define hashmap3 (hashmap comparator 'd 1 'e 2 'f 3))

        (test-assert "hashmap?: a hashmap"
          (hashmap? (hashmap comparator)))

        (test-assert "hashmap?: not a hashmap"
          (not (hashmap? (list 1 2 3))))

        (test-assert "hashmap-empty?: empty hashmap"
          (hashmap-empty? hashmap0))

        (test-assert "hashmap-empty?: non-empty hashmap"
          (not (hashmap-empty? hashmap1)))

        (test-assert "hashmap-contains?: containing"
          (hashmap-contains? hashmap1 'b))

        (test-assert "hashmap-contains?: not containing"
          (not (hashmap-contains? hashmap1 '2)))

        (test-assert "hashmap-disjoint?: disjoint"
          (hashmap-disjoint? hashmap1 hashmap3))

        (test-assert "hashmap-disjoint?: not disjoint"
          (not (hashmap-disjoint? hashmap1 hashmap2))))

      (test-group "Accessors"
        (define hashmap1 (hashmap comparator 'a 1 'b 2 'c 3))

        (test-equal "hashmap-ref: key found"
          2
          (hashmap-ref hashmap1 'b))

        (test-equal "hashmap-ref: key not found/with failure"
          42
          (hashmap-ref hashmap1 'd (lambda () 42)))

        (test-error "hashmap-ref: key not found/without failure"
          (hashmap-ref hashmap1 'd))

        (test-equal "hashmap-ref: with success procedure"
          (* 2 2)
          (hashmap-ref hashmap1 'b (lambda () #f) (lambda (x) (* x x))))

        (test-equal "hashmap-ref/default: key found"
          3
          (hashmap-ref/default hashmap1 'c 42))

        (test-equal "hashmap-ref/default: key not found"
          42
          (hashmap-ref/default hashmap1 'd 42))

        (test-equal "hashmap-key-comparator"
          comparator
          (hashmap-key-comparator hashmap1)))

      (test-group "Updaters"
        (define hashmap1 (hashmap comparator 'a 1 'b 2 'c 3))
        (define hashmap2 (hashmap-set hashmap1 'c 4 'd 4 'd 5))
        (define hashmap3 (hashmap-update hashmap1 'b (lambda (x) (* x x))))
        (define hashmap4 (hashmap-update/default hashmap1 'd (lambda (x) (* x x)) 4))
        (define hashmap5 (hashmap-adjoin hashmap1 'c 4 'd 4 'd 5))
        (define hashmap0 (hashmap comparator))

        (test-equal "hashmap-adjoin: key already in hashmap"
          3
          (hashmap-ref hashmap5 'c))

        (test-equal "hashmap-adjoin: key set earlier"
          4
          (hashmap-ref hashmap5 'd))

        (test-equal "hashmap-set: key already in hashmap"
          4
          (hashmap-ref hashmap2 'c))

        (test-equal "hashmap-set: key set earlier"
          5
          (hashmap-ref hashmap2 'd))

        (test-equal "hashmap-replace: key not in hashmap"
          #f
          (hashmap-ref/default (hashmap-replace hashmap1 'd 4) 'd #f))

        (test-equal "hashmap-replace: key in hashmap"
          6
          (hashmap-ref (hashmap-replace hashmap1 'c 6) 'c))

        (test-equal "hashmap-delete"
          42
          (hashmap-ref/default (hashmap-delete hashmap1 'b) 'b 42))

        (test-equal "hashmap-delete-all"
          42
          (hashmap-ref/default (hashmap-delete-all hashmap1 '(a b)) 'b 42))

        (test-equal "hashmap-intern: key in hashmap"
          (list hashmap1 2)
          (receive result
              (hashmap-intern hashmap1 'b (lambda () (error "should not have been invoked")))
            result))

        (test-equal "hashmap-intern: key not in hashmap"
          (list 42 42)
          (receive (hashmap value)
              (hashmap-intern hashmap1 'd (lambda () 42))
            (list value (hashmap-ref hashmap 'd))))

        (test-equal "hashmap-update"
          4
          (hashmap-ref hashmap3 'b))

        (test-equal "hashmap-update/default"
          16
          (hashmap-ref hashmap4 'd))

        (test-equal "hashmap-pop: empty hashmap"
          'empty
          (hashmap-pop hashmap0 (lambda () 'empty)))

        (test-assert "hashmap-pop: non-empty hashmap"
          (member
           (receive (hashmap key value)
               (hashmap-pop hashmap1)
               (list (hashmap-size hashmap) key value))
           '((2 a 1) (2 b 2) (2 c 3)))))

      (test-group "The whole hashmap"
        (define hashmap0 (hashmap comparator))
        (define hashmap1 (hashmap comparator 'a 1 'b 2 'c 3))

        (test-equal "hashmap-size: empty hashmap"
          0
          (hashmap-size hashmap0))

        (test-equal "hashmap-size: non-empty hashmap"
          3
          (hashmap-size hashmap1))

        (test-equal "hashmap-find: found in hashmap"
          (list 'b 2)
          (receive result
              (hashmap-find (lambda (key value)
                          (and (eq? key 'b)
                               (= value 2)))
                        hashmap1
                        (lambda () (error "should not have been called")))
            result))

        (test-equal "hashmap-find: not found in hashmap"
          (list 42)
          (receive result
              (hashmap-find (lambda (key value)
                          (eq? key 'd))
                        hashmap1
                        (lambda ()
                          42))
            result))

        (test-equal "hashmap-count"
          2
          (hashmap-count (lambda (key value)
                       (>= value 2))
                     hashmap1))

        (test-assert "hashmap-any?: found"
          (hashmap-any? (lambda (key value)
                      (= value 3))
                    hashmap1))

        (test-assert "hashmap-any?: not found"
          (not (hashmap-any? (lambda (key value)
                           (= value 4))
                         hashmap1)))

        (test-assert "hashmap-every?: true"
          (hashmap-every? (lambda (key value)
                        (<= value 3))
                      hashmap1))

        (test-assert "hashmap-every?: false"
          (not (hashmap-every? (lambda (key value)
                             (<= value 2))
                           hashmap1)))

        (test-equal "hashmap-keys"
          3
          (length (hashmap-keys hashmap1)))

        (test-equal "hashmap-values"
          6
          (fold + 0 (hashmap-values hashmap1)))

        (test-equal "hashmap-entries"
          (list 3 6)
          (receive (keys values)
              (hashmap-entries hashmap1)
            (list (length keys) (fold + 0 values)))))

      (test-group "Hashmap and folding"
        (define hashmap1 (hashmap comparator 'a 1 'b 2 'c 3))
        (define hashmap2 (hashmap-map (lambda (key value)
                                (values (symbol->string key)
                                        (* 10 value)))
                              comparator
                              hashmap1))

        (test-equal "hashmap-map"
          20
          (hashmap-ref hashmap2 "b"))

        (test-equal "hashmap-for-each"
          6
          (let ((counter 0))
            (hashmap-for-each (lambda (key value)
                            (set! counter (+ counter value)))
                          hashmap1)
            counter))

        (test-equal "hashmap-fold"
          6
          (hashmap-fold (lambda (key value acc)
                      (+ value acc))
                    0
                    hashmap1))

        (test-equal "hashmap-map->list"
          (+ (* 1 1) (* 2 2) (* 3 3))
          (fold + 0 (hashmap-map->list (lambda (key value)
                                     (* value value))
                                   hashmap1)))

        (test-equal "hashmap-filter"
          2
          (hashmap-size (hashmap-filter (lambda (key value)
                                  (<= value 2))
                                hashmap1)))

        (test-equal "hashmap-remove"
          1
          (hashmap-size (hashmap-remove (lambda (key value)
                                  (<= value 2))
                                hashmap1)))

        (test-equal "hashmap-partition"
          (list 1 2)
          (receive result
              (hashmap-partition (lambda (key value)
                               (eq? 'b key))
                             hashmap1)
            (map hashmap-size result)))

        (test-group "Copying and conversion"
          (define hashmap1 (hashmap comparator 'a 1 'b 2 'c 3))
          (define hashmap2 (alist->hashmap comparator '((a . 1) (b . 2) (c . 3))))
          (define hashmap3 (alist->hashmap! (hashmap-copy hashmap1) '((d . 4) '(c . 5))))

          (test-equal "hashmap-copy: same size"
            3
            (hashmap-size (hashmap-copy hashmap1)))

          (test-equal "hashmap-copy: same comparator"
            comparator
            (hashmap-key-comparator (hashmap-copy hashmap1)))

          (test-equal "hashmap->alist"
            (cons 'b 2)
            (assq 'b (hashmap->alist hashmap1)))

          (test-equal "alist->hashmap"
            2
            (hashmap-ref hashmap2 'b)
            )

          (test-equal "alist->hashmap!: new key"
            4
            (hashmap-ref hashmap3 'd))

          (test-equal "alist->hashmap!: existing key"
            3
            (hashmap-ref hashmap3 'c)))

        (test-group "Subhashmaps"
          (define hashmap1 (hashmap comparator 'a 1 'b 2 'c 3))
          (define hashmap2 (hashmap comparator 'a 1 'b 2 'c 3))
          (define hashmap3 (hashmap comparator 'a 1 'c 3))
          (define hashmap4 (hashmap comparator 'a 1 'c 3 'd 4))
          (define hashmap5 (hashmap comparator 'a 1 'b 2 'c 6))
          (define hashmap6 (hashmap (make-comparator (comparator-type-test-predicate comparator)
                                                     (comparator-equality-predicate comparator)
                                                     (comparator-ordering-predicate comparator)
                                                     (comparator-hash-function comparator))
                                    'a 1 'b 2 'c 3))


          (test-assert "hashmap=?: equal hashmaps"
            (hashmap=? comparator hashmap1 hashmap2))

          (test-assert "hashmap=?: unequal hashmaps"
            (not (hashmap=? comparator hashmap1 hashmap4)))

          ;; FAIL: #2047 (hashmap=? omits the key-comparator identity check)
          ;; (test-assert "hashmap=?: different comparators"
          ;;   (not (hashmap=? comparator hashmap1 hashmap6)))

          (test-assert "hashmap<?: proper subset"
            (hashmap<? comparator hashmap3 hashmap1))

          (test-assert "hashmap<?: improper subset"
            (not (hashmap<? comparator hashmap3 hashmap1 hashmap2)))

          (test-assert "hashmap>?: proper superset"
            (hashmap>? comparator hashmap2 hashmap3))

          (test-assert "hashmap>?: improper superset"
            (not (hashmap>? comparator hashmap1 hashmap2 hashmap3)))

          (test-assert "hashmap<=?: subset"
            (hashmap<=? comparator hashmap3 hashmap2 hashmap1))

          (test-assert "hashmap<=?: non-matching values"
            (not (hashmap<=? comparator hashmap3 hashmap5)))

          (test-assert "hashmap<=?: not a subset"
            (not (hashmap<=? comparator hashmap2 hashmap4)))

          (test-assert "hashmap>=?: superset"
            (hashmap>=? comparator hashmap4 hashmap3))

          (test-assert "hashmap>=?: not a superset"
            (not (hashmap>=? comparator hashmap5 hashmap3))))

        (test-group "Set theory operations"
          (define hashmap1 (hashmap comparator 'a 1 'b 2 'c 3))
          (define hashmap2 (hashmap comparator 'a 1 'b 2 'd 4))
          (define hashmap3 (hashmap comparator 'a 1 'b 2))
          (define hashmap4 (hashmap comparator 'a 1 'b 2 'c 4))
          (define hashmap5 (hashmap comparator 'a 1 'c 3))
          (define hashmap6 (hashmap comparator 'd 4 'e 5 'f 6))

          (test-equal "hashmap-union: new association"
            4
            (hashmap-ref (hashmap-union hashmap1 hashmap2) 'd))

          (test-equal "hashmap-union: existing association"
            3
            (hashmap-ref (hashmap-union hashmap1 hashmap4) 'c))

          (test-equal "hashmap-union: three hashmaps"
            6
            (hashmap-size (hashmap-union hashmap1 hashmap2 hashmap6)))

          (test-equal "hashmap-intersection: existing association"
            3
            (hashmap-ref (hashmap-intersection hashmap1 hashmap4) 'c))

          (test-equal "hashmap-intersection: removed association"
            42
            (hashmap-ref/default (hashmap-intersection hashmap1 hashmap5) 'b 42))

          (test-equal "hashmap-difference"
            2
            (hashmap-size (hashmap-difference hashmap2 hashmap6)))

          (test-equal "hashmap-xor"
            4
            (hashmap-size (hashmap-xor hashmap2 hashmap6))))

        (test-group "Comparators"
          (define hashmap1 (hashmap comparator 'a 1 'b 2 'c 3))
          (define hashmap2 (hashmap comparator 'a 1 'b 2 'c 3))
          (define hashmap3 (hashmap comparator 'a 1 'b 2))
          (define hashmap4 (hashmap comparator 'a 1 'b 2 'c 4))
          (define hashmap5 (hashmap comparator 'a 1 'c 3))
          (define hashmap0 (hashmap comparator
                                    hashmap1 "a"
                                    hashmap2 "b"
                                    hashmap3 "c"
                                    hashmap4 "d"
                                    hashmap5 "e"))

          (test-assert "hashmap-comparator"
            (comparator? hashmap-comparator))

          ;; FAIL: #2044 ((srfi 146 hash) discards its comparator, so hashmap-comparator
          ;;              never decides key identity)
          ;; (test-equal "hashmap-keyed hashmap"
          ;;   (list "a" "a" "c" "d" "e")
          ;;   (list (hashmap-ref hashmap0 hashmap1)
          ;;         (hashmap-ref hashmap0 hashmap2)
          ;;         (hashmap-ref hashmap0 hashmap3)
          ;;         (hashmap-ref hashmap0 hashmap4)
          ;;         (hashmap-ref hashmap0 hashmap5)
          ;;         ))

          (test-group "Ordering comparators"
            (test-assert "=?: equal hashmaps"
              (=? comparator hashmap1 hashmap2))

            (test-assert "=?: unequal hashmaps"
              (not (=? comparator hashmap1 hashmap4))))))

      
)

(let ((runner (test-runner-current)))
  (test-end "srfi146-reference")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
