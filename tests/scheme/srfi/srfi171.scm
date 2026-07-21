(import (scheme base)
        (scheme read)
        (scheme write)
        (scheme case-lambda)
        (srfi 171)
        (srfi 171 meta)
        (srfi 64))

(test-begin "srfi-171")

;; Helper
(define (add1 x) (+ x 1))
(define numeric-list '(0 1 2 3 4))
(define numeric-vec (list->vector numeric-list))

;; compose is not exported from (srfi 171), define locally for testing
(define (compose . fns)
  (if (null? fns)
      values
      (let loop ((fs (cdr fns)) (acc (car fns)))
        (if (null? fs)
            acc
            (loop (cdr fs)
                  (let ((f (car fs)) (g acc))
                    (lambda args
                      (g (apply f args)))))))))

;; 1. tmap - basic mapping
(test-equal "tmap add1"
  '(1 2 3 4 5)
  (list-transduce (tmap add1) rcons numeric-list))

;; 2. tfilter - basic filtering
(test-equal "tfilter even?"
  '(0 2 4)
  (list-transduce (tfilter even?) rcons numeric-list))

;; 3. Composition of tfilter and tmap
(test-equal "compose tfilter+tmap"
  '(1 3 5)
  (list-transduce (compose (tfilter even?) (tmap add1)) rcons numeric-list))

;; 4. tfilter-map
(test-equal "tfilter-map"
  '(1 3 5)
  (list-transduce (tfilter-map
                   (lambda (x) (if (even? x) (+ x 1) #f)))
                  rcons numeric-list))

;; 5. tremove
(test-equal "tremove even?"
  '(1 3)
  (list-transduce (tremove even?) rcons numeric-list))

;; 6. treplace with alist
(test-equal "treplace alist"
  '(s c h e m e r o c k s)
  (list-transduce (treplace '((1 . s) (2 . c) (3 . h) (4 . e) (5 . m)))
                  rcons '(1 2 3 4 5 4 r o c k s)))

;; 7. treplace with procedure
(test-equal "treplace procedure"
  '(s c h e m e r o c k s)
  (list-transduce (treplace (lambda (val)
                              (case val
                                ((1) 's) ((2) 'c) ((3) 'h) ((4) 'e) ((5) 'm)
                                (else val))))
                  rcons '(1 2 3 4 5 4 r o c k s)))

;; 8. ttake
(test-equal "ttake 4 sum"
  6
  (list-transduce (ttake 4) + numeric-list))

;; 9. tdrop
(test-equal "tdrop 3 sum"
  7
  (list-transduce (tdrop 3) + numeric-list))

;; 10. tdrop-while
(test-equal "tdrop-while < 3"
  '(3 4)
  (list-transduce (tdrop-while (lambda (x) (< x 3))) rcons numeric-list))

;; 11. ttake-while
(test-equal "ttake-while < 3"
  '(0 1 2)
  (list-transduce (ttake-while (lambda (x) (< x 3))) rcons numeric-list))

;; 12. tconcatenate
(test-equal "tconcatenate"
  '(0 1 2 3 4)
  (list-transduce tconcatenate rcons '((0 1) (2 3) (4))))

;; 13. tappend-map
(test-equal "tappend-map"
  '(1 2 2 4 3 6)
  (list-transduce (tappend-map (lambda (x) (list x (* x 2)))) rcons '(1 2 3)))

;; 14. tdelete-neighbor-duplicates
(test-equal "tdelete-neighbor-duplicates"
  '(1 2 1 2 3)
  (list-transduce (tdelete-neighbor-duplicates) rcons '(1 1 1 2 2 1 2 3 3)))

;; 15. tdelete-duplicates
(test-equal "tdelete-duplicates"
  '(1 2 3 4)
  (list-transduce (tdelete-duplicates) rcons '(1 1 2 1 2 3 3 1 2 3 4 4)))

;; 16. tflatten
(test-equal "tflatten"
  '(1 2 3 4 5 6 7 8 9)
  (list-transduce tflatten rcons '((1 2) 3 (4 (5 6) 7) 8 (9))))

;; 17. tpartition
(test-equal "tpartition even?"
  '((1 1 1 1) (2 2 2 2) (3 3 3) (4 4 4 4))
  (list-transduce (tpartition even?) rcons '(1 1 1 1 2 2 2 2 3 3 3 4 4 4 4)))

;; 18. tsegment
(test-equal "tsegment 2"
  '((0 1) (2 3) (4))
  (vector-transduce (tsegment 2) rcons numeric-vec))

;; 19. tadd-between
(test-equal "tadd-between"
  '(0 and 1 and 2 and 3 and 4)
  (list-transduce (tadd-between 'and) rcons numeric-list))

;; 20. tenumerate
(test-equal "tenumerate from -1"
  '((-1 . 0) (0 . 1) (1 . 2) (2 . 3) (3 . 4))
  (list-transduce (tenumerate (- 1)) rcons numeric-list))

;; 21. rcount
(test-equal "rcount"
  2
  (list-transduce (tfilter odd?) rcount numeric-list))

;; 22. rany
(test-equal "rany found"
  #t
  (list-transduce (tmap values) (rany odd?) '(2 4 6 7 8)))

(test-equal "rany not found"
  #f
  (list-transduce (tmap values) (rany odd?) '(2 4 6 8)))

;; 23. revery
(test-equal "revery all pass"
  #t
  (list-transduce (tmap values) (revery even?) '(2 4)))

(test-equal "revery fails"
  #f
  (list-transduce (tmap values) (revery even?) '(2 3 4)))

;; 24. list-transduce with explicit init
(test-equal "list-transduce with init"
  15
  (list-transduce (tmap add1) + 0 numeric-list))

;; 25. vector-transduce
(test-equal "vector-transduce sum"
  15
  (vector-transduce (tmap add1) + numeric-vec))

(test-equal "vector-transduce with init"
  15
  (vector-transduce (tmap add1) + 0 numeric-vec))

;; 26. string-transduce
(test-equal "string-transduce char count"
  6
  (string-transduce (tfilter char-alphabetic?) rcount "0123456789abcdef"))

;; 27. string-transduce sum
(test-equal "string-transduce sum"
  15
  (string-transduce (tmap (lambda (x) (- (char->integer x) 47))) + "01234"))

;; 28. port-transduce
(test-equal "port-transduce"
  15
  (port-transduce (tmap add1) + read (open-input-string "0 1 2 3 4")))

(test-equal "port-transduce with init"
  15
  (port-transduce (tmap add1) + 0 read (open-input-string "0 1 2 3 4")))

;; 29. generator-transduce
(test-equal "generator-transduce"
  '(1 2 3)
  (parameterize ((current-input-port (open-input-string "1 2 3")))
    (generator-transduce (tmap (lambda (x) x)) rcons read)))

;; 30. reverse-rcons
(test-equal "reverse-rcons"
  '(4 3 2 1 0)
  (list-transduce (tmap values) reverse-rcons numeric-list))

;; 31. reduced / reduced? / unreduce from meta
(test-assert "reduced?"
  (reduced? (reduced 42)))

(test-equal "unreduce"
  42
  (unreduce (reduced 42)))

(test-assert "non-reduced is not reduced?"
  (not (reduced? 42)))

;; 32. ensure-reduced
(test-assert "ensure-reduced on non-reduced"
  (reduced? (ensure-reduced 42)))

(test-assert "ensure-reduced on reduced"
  (reduced? (ensure-reduced (reduced 42))))

;; 33. ttake early termination
(test-equal "ttake 0"
  '()
  (list-transduce (ttake 0) rcons '(1 2 3)))

;; 34. empty input
(test-equal "empty list-transduce"
  '()
  (list-transduce (tmap add1) rcons '()))

(test-equal "empty vector-transduce"
  0
  (vector-transduce (tmap add1) + (vector)))

;; 35. compose identity
(test-equal "compose no transducers"
  '(0 1 2 3 4)
  (list-transduce (tmap values) rcons numeric-list))

;; 36. bytevector-u8-transduce
(test-equal "bytevector-u8-transduce"
  '(1 2 3)
  (bytevector-u8-transduce (tmap add1) rcons (bytevector 0 1 2)))

;; 37. tdelete-neighbor-duplicates with custom equality
(test-equal "tdelete-neighbor-duplicates custom eq"
  '(1 2 1)
  (list-transduce (tdelete-neighbor-duplicates =) rcons '(1 1 2 2 1 1)))

;; 38. multi-step composition
(test-equal "triple compose"
  '(1 3 5)
  (list-transduce (compose (tfilter even?) (tmap add1) (tfilter odd?))
                  rcons numeric-list))

;; 39. tlog (just make sure it doesn't crash, output goes to stdout)
(test-equal "tlog passthrough"
  '(1 2 3)
  (let ((port (open-output-string)))
    (parameterize ((current-output-port port))
      (list-transduce (tlog) rcons '(1 2 3)))))

;; 40. preserving-reduced from meta
(test-assert "preserving-reduced wraps"
  (let ((pr (preserving-reduced (lambda (a b)
                                  (if (= b 3)
                                      (reduced (+ a b))
                                      (+ a b))))))
    (reduced? (pr 0 3))))

(let ((runner (test-runner-current)))
  (test-end "srfi-171")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
