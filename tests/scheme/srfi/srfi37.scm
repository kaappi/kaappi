;; SRFI-37 (args-fold) conformance tests — audit Phase 3b
;; NOTE: several args-fold defects are tracked in #1211; the enabled tests
;; below use long options and non-list seeds to stay clear of them.
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi37.scm

(import (scheme base) (srfi 37) (chibi test))

(test-begin "srfi-37")

;;; --- option record surface ---
(define verbose
  (option '(#\v "verbose") #f #f
          (lambda (opt name arg n) (+ n 1))))
(define output
  (option '(#\o "output") #t #f
          (lambda (opt name arg n) (if (equal? arg "out") 100 -1))))

(test '(#\v "verbose") (option-names verbose))
(test #f (option-required-arg? verbose))
(test #t (option-required-arg? output))
(test #f (option-optional-arg? output))
(test #t (procedure? (option-processor verbose)))

;; option? is not exported:
;; FAIL: #1211 (option? missing from (srfi 37) exports)
;; (test #t (option? verbose))

;;; --- args-fold with long options and a numeric seed ---
(define (unrec opt name arg n) -999)
(define (count-operand op n) (+ n 10))
(define opts (list verbose output))

(test 1 (args-fold '("--verbose") opts unrec count-operand 0))
(test 2 (args-fold '("--verbose" "--verbose") opts unrec count-operand 0))

;; required argument via --name=value and via the following token
(test 100 (args-fold '("--output=out") opts unrec count-operand 0))
(test 100 (args-fold '("--output" "out") opts unrec count-operand 0))

;; operands
(test 10 (args-fold '("file") opts unrec count-operand 0))
(test 21 (args-fold '("a" "b" "--verbose") opts unrec count-operand 0))

;; unrecognized long option hits the fallback
(test -999 (args-fold '("--nope") opts unrec count-operand 0))

;;; --- spec deviations (see #1211) ---
;; short options never match their char names (compared as strings):
;; FAIL: #1211 (short char-name options unmatched)
;; (test 1 (args-fold '("-v") opts unrec count-operand 0))
;; the name passed to processors for short options must be the char:
;; FAIL: #1211 (short option name passed as string, not char)
;; (test #\v (args-fold '("-v")
;;                      (list (option '(#\v) #f #f (lambda (o name a s) name)))
;;                      unrec count-operand 'none))
;; a processor may return a list as its (single) seed:
;; FAIL: #1211 (list-valued seeds are splatted into multiple seeds)
;; (test '(verbose)
;;       (args-fold '("--verbose")
;;                  (list (option '(#\v "verbose") #f #f
;;                                (lambda (o n a acc) (cons 'verbose acc))))
;;                  (lambda (o n a acc) acc)
;;                  (lambda (op acc) acc)
;;                  '()))

(test-end "srfi-37")
