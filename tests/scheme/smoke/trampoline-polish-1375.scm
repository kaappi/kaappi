;; Regression test for #1375: follow-up polish for the Scheme-bootstrapped
;; map/for-each/vector-map/vector-for-each/string-map/string-for-each/
;; dynamic-wind/force family (PR #1374).
;;
;; Covers:
;;   1. zero-sequence misuse raises clean arity errors (not leaked internals)
;;      and non-procedure proc raises a type error naming the procedure
;;   2. the %-helpers (%push-wind, %promise-*, ...) are not globally callable
;;   3. iteration procedures are immune to top-level redefinition of the
;;      base procedures they use internally
;;   4. dynamic-wind validates all arguments before running `before`
(import (scheme base) (scheme char) (scheme lazy) (scheme write)
        (scheme process-context) (srfi 13) (srfi 64))

(test-begin "trampoline-polish-1375")

;; --- 1. arity errors -------------------------------------------------------

(define (error-message thunk)
  (guard (e (#t (if (error-object? e) (error-object-message e) 'not-error-object)))
    (thunk)
    'no-error))

(test-assert "(map car) raises an arity error"
  (string-contains (error-message (lambda () (map car)))
                   "expected at least 2 arguments"))

(test-assert "(for-each car) raises an arity error"
  (string-contains (error-message (lambda () (for-each car)))
                   "expected at least 2 arguments"))

(test-assert "(vector-map +) raises an arity error"
  (string-contains (error-message (lambda () (vector-map +)))
                   "expected at least 2 arguments"))

(test-assert "(vector-for-each +) raises an arity error"
  (string-contains (error-message (lambda () (vector-for-each +)))
                   "expected at least 2 arguments"))

(test-assert "(string-map char-upcase) raises an arity error"
  (string-contains (error-message (lambda () (string-map char-upcase)))
                   "expected at least 2 arguments"))

(test-assert "(string-for-each write-char) raises an arity error"
  (string-contains (error-message (lambda () (string-for-each write-char)))
                   "expected at least 2 arguments"))

;; --- 1b. non-procedure first argument names the procedure ------------------

(test-assert "(map 5 ...) type error names map"
  (string-contains (error-message (lambda () (map 5 '(1 2 3)))) "'map'"))

(test-assert "(for-each 5 ...) type error names for-each"
  (string-contains (error-message (lambda () (for-each 5 '(1)))) "'for-each'"))

(test-assert "(vector-map 5 ...) type error names vector-map"
  (string-contains (error-message (lambda () (vector-map 5 #(1)))) "'vector-map'"))

(test-assert "(vector-for-each 5 ...) type error names vector-for-each"
  (string-contains (error-message (lambda () (vector-for-each 5 #(1))))
                   "'vector-for-each'"))

(test-assert "(string-map 5 ...) type error names string-map"
  (string-contains (error-message (lambda () (string-map 5 "a"))) "'string-map'"))

(test-assert "(string-for-each 5 ...) type error names string-for-each"
  (string-contains (error-message (lambda () (string-for-each 5 "a")))
                   "'string-for-each'"))

;; --- 2. %-helpers are not reachable without an import ----------------------

(define-syntax unbound?
  (syntax-rules ()
    ((_ name) (guard (e (#t 'unbound)) name))))

(test-equal "%push-wind is unbound" 'unbound (unbound? %push-wind))
(test-equal "%pop-wind is unbound" 'unbound (unbound? %pop-wind))
(test-equal "%promise-forced? is unbound" 'unbound (unbound? %promise-forced?))
(test-equal "%promise-forcing? is unbound" 'unbound (unbound? %promise-forcing?))
(test-equal "%promise-value is unbound" 'unbound (unbound? %promise-value))
(test-equal "%promise-complete! is unbound" 'unbound (unbound? %promise-complete!))
(test-equal "%promise-set-forcing! is unbound" 'unbound (unbound? %promise-set-forcing!))
(test-equal "%promise-merge! is unbound" 'unbound (unbound? %promise-merge!))

;; --- 3. immunity to top-level redefinition ---------------------------------

;; map uses reverse internally; a top-level redefinition must not change
;; map's behavior (the bootstrap captures its dependencies at install time).
(define %original-reverse reverse)
(define reverse (lambda (x) 'HIJACKED))
(define hijacked-map-result (map (lambda (x) (* 2 x)) '(1 2 3)))
(set! reverse %original-reverse)
(test-equal "map immune to reverse redefinition" '(2 4 6) hijacked-map-result)

(define %original-apply apply)
(define apply (lambda args 'HIJACKED))
(define hijacked-multi-map (map + '(1 2) '(10 20)))
(set! apply %original-apply)
(test-equal "multi-list map immune to apply redefinition"
            '(11 22) hijacked-multi-map)

;; --- 4. dynamic-wind validates arguments before running before -------------

(define before-ran #f)
(define dw-error
  (error-message
   (lambda ()
     (dynamic-wind (lambda () (set! before-ran #t)) (lambda () 1) 42))))
(test-equal "dynamic-wind rejects bad after without running before"
            #f before-ran)
(test-assert "dynamic-wind bad-argument error names dynamic-wind"
  (string-contains dw-error "'dynamic-wind'"))
(test-assert "dynamic-wind error does not leak %push-wind"
  (not (string-contains dw-error "%push-wind")))

(define dw-thunk-error
  (error-message (lambda () (dynamic-wind (lambda () #t) 7 (lambda () #t)))))
(test-assert "dynamic-wind bad thunk names dynamic-wind"
  (string-contains dw-thunk-error "'dynamic-wind'"))

;; --- behavior spot checks (multi-sequence paths were restructured) ---------

(test-equal "single-list map" '(2 4 6) (map (lambda (x) (* 2 x)) '(1 2 3)))
(test-equal "two-list map" '(11 22 33) (map + '(1 2 3) '(10 20 30)))
(test-equal "three-list map" '(111 222) (map + '(1 2) '(10 20) '(100 200)))
(test-equal "map stops at shortest list" '(11) (map + '(1) '(10 20 30)))
(test-equal "map on empty list" '() (map car '()))

(define fe-acc '())
(for-each (lambda (a b) (set! fe-acc (cons (+ a b) fe-acc))) '(1 2) '(10 20))
(test-equal "two-list for-each" '(22 11) fe-acc)

(test-equal "single-vector vector-map" #(2 4) (vector-map (lambda (x) (* 2 x)) #(1 2)))
(test-equal "two-vector vector-map" #(11 22) (vector-map + #(1 2) #(10 20)))
(test-equal "vector-map stops at shortest" #(11) (vector-map + #(1 2 3) #(10)))
(test-equal "vector-map on empty vector" #() (vector-map + #()))

(define vfe-acc '())
(vector-for-each (lambda (a b) (set! vfe-acc (cons (+ a b) vfe-acc))) #(1 2) #(10 20))
(test-equal "two-vector vector-for-each" '(22 11) vfe-acc)

(test-equal "single-string string-map" "ABC" (string-map char-upcase "abc"))
(test-equal "two-string string-map stops at shortest"
            "ab" (string-map (lambda (a b) a) "abc" "xy"))
(test-equal "string-map on empty string" "" (string-map char-upcase ""))

(define sfe-acc '())
(string-for-each (lambda (a b) (set! sfe-acc (cons (cons a b) sfe-acc))) "ab" "xyz")
(test-equal "two-string string-for-each" '((#\b . #\y) (#\a . #\x)) sfe-acc)

(test-assert "improper list error names map"
  (string-contains
   (error-message (lambda () (map (lambda (x) x) '(1 2 . 3)))) "map"))

;; dynamic-wind and force still work normally
(define dw-order '())
(dynamic-wind
  (lambda () (set! dw-order (cons 'before dw-order)))
  (lambda () (set! dw-order (cons 'during dw-order)))
  (lambda () (set! dw-order (cons 'after dw-order))))
(test-equal "dynamic-wind runs before/during/after"
            '(after during before) dw-order)

(test-equal "force of delay" 42 (force (delay 42)))
(test-equal "force of non-promise" 7 (force 7))

;; string-map/string-for-each must be linear in string length: an
;; index-driven (string-ref s i) loop is O(n^2) because UTF-8 codepoint
;; indexing rescans from byte 0. Quadratic behavior takes minutes on
;; 300k chars and trips the suite's per-file timeout; linear is instant.
(define big-string (make-string 300000 #\x))
(define sfe-count 0)
(string-for-each (lambda (c) (set! sfe-count (+ sfe-count 1))) big-string)
(test-equal "string-for-each over 300k chars is linear" 300000 sfe-count)
(test-equal "string-map over 300k chars is linear"
            300000 (string-length (string-map char-upcase big-string)))

(let ((runner (test-runner-current)))
  (test-end "trampoline-polish-1375")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
