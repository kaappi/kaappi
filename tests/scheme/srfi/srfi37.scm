;; SRFI-37 (args-fold) conformance tests — audit Phase 3b
;; Regression tests for #1211: short char-name matching, seed threading, option? export
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi37.scm

(import (scheme base) (scheme process-context) (srfi 37) (srfi 64))

(test-begin "srfi-37")

;;; --- option record surface ---
(define verbose
  (option '(#\v "verbose") #f #f
          (lambda (opt name arg n) (+ n 1))))
(define output
  (option '(#\o "output") #t #f
          (lambda (opt name arg n) (if (equal? arg "out") 100 -1))))

(test-equal "option-names" '(#\v "verbose") (option-names verbose))
(test-equal "required-arg? false" #f (option-required-arg? verbose))
(test-equal "required-arg? true" #t (option-required-arg? output))
(test-equal "optional-arg? false" #f (option-optional-arg? output))
(test-assert "processor is procedure" (procedure? (option-processor verbose)))

;; option? is exported (#1211 fix)
(test-assert "option? positive" (option? verbose))
(test-assert "option? negative" (not (option? 42)))

;;; --- args-fold with long options and a numeric seed ---
(define (unrec opt name arg n) -999)
(define (count-operand op n) (+ n 10))
(define opts (list verbose output))

(test-equal "long verbose" 1 (args-fold '("--verbose") opts unrec count-operand 0))
(test-equal "long verbose x2" 2 (args-fold '("--verbose" "--verbose") opts unrec count-operand 0))

;; required argument via --name=value and via the following token
(test-equal "long --output=out" 100 (args-fold '("--output=out") opts unrec count-operand 0))
(test-equal "long --output out" 100 (args-fold '("--output" "out") opts unrec count-operand 0))

;; operands
(test-equal "single operand" 10 (args-fold '("file") opts unrec count-operand 0))
(test-equal "operands + long" 21 (args-fold '("a" "b" "--verbose") opts unrec count-operand 0))

;; unrecognized long option hits the fallback
(test-equal "unrecognized long" -999 (args-fold '("--nope") opts unrec count-operand 0))

;;; --- short options (#1211 fix: char-name matching) ---
(test-equal "short -v" 1 (args-fold '("-v") opts unrec count-operand 0))
(test-equal "short -v -v" 2 (args-fold '("-v" "-v") opts unrec count-operand 0))

;; combined short options: -vv
(test-equal "combined -vv" 2 (args-fold '("-vv") opts unrec count-operand 0))

;; short option with required arg: -o out
(test-equal "short -o out" 100 (args-fold '("-o" "out") opts unrec count-operand 0))

;; short option with required arg attached: -oout
(test-equal "short -oout" 100 (args-fold '("-oout") opts unrec count-operand 0))

;; mixed short and long (output processor replaces seed with 100)
(test-equal "mixed -v --output=out" 100
  (args-fold '("-v" "--output=out") opts unrec count-operand 0))

;; the name passed to processors for short options must be the char
(test-equal "short name is char" #\v
  (args-fold '("-v")
             (list (option '(#\v) #f #f (lambda (o name a s) name)))
             unrec count-operand 'none))

;; unrecognized short option
(test-equal "unrecognized short" -999 (args-fold '("-x") opts unrec count-operand 0))

;;; --- list-valued seeds (#1211 fix: call-with-values threading) ---
(test-equal "list seed via long opt" '(verbose)
  (args-fold '("--verbose")
             (list (option '(#\v "verbose") #f #f
                           (lambda (o n a acc) (cons 'verbose acc))))
             (lambda (o n a acc) acc)
             (lambda (op acc) acc)
             '()))

;; accumulate into a list seed with short options
(test-equal "list seed via combined short" '(b a)
  (args-fold '("-ab")
             (list (option '(#\a) #f #f (lambda (o n a acc) (cons 'a acc)))
                   (option '(#\b) #f #f (lambda (o n a acc) (cons 'b acc))))
             (lambda (o n a acc) acc)
             (lambda (op acc) acc)
             '()))

;; operands accumulate into a list seed
(test-equal "list seed via operands" '("z" "y")
  (args-fold '("y" "z")
             '()
             (lambda (o n a acc) acc)
             (lambda (op acc) (cons op acc))
             '()))

;;; --- multiple seeds ---
(test-assert "multiple seeds"
  (let-values (((a b) (args-fold '("--verbose")
                                 (list (option '("verbose") #f #f
                                               (lambda (o n a x y) (values (+ x 1) (+ y 10)))))
                                 (lambda (o n a x y) (values x y))
                                 (lambda (op x y) (values x y))
                                 0 0)))
    (and (= a 1) (= b 10))))

;;; --- -- separator ---
(test-equal "-- separator" 20 (args-fold '("--" "a" "b") opts unrec count-operand 0))
(test-equal "option then --" 11 (args-fold '("--verbose" "--" "x") opts unrec count-operand 0))

;;; --- empty args ---
(test-equal "empty args" 0 (args-fold '() opts unrec count-operand 0))

(let ((runner (test-runner-current)))
  (test-end "srfi-37")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
