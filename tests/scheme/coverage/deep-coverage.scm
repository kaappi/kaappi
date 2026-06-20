(import (scheme base) (scheme write) (scheme read) (scheme char)
        (scheme lazy) (scheme case-lambda) (scheme cxr)
        (scheme inexact) (scheme complex) (scheme file)
        (srfi 1) (srfi 13) (srfi 27) (srfi 69) (srfi 170))

(define pass 0)
(define fail 0)
(define (check name got expected)
  (if (equal? got expected) (set! pass (+ pass 1))
      (begin (set! fail (+ fail 1))
             (display "FAIL: ") (display name)
             (display " expected ") (write expected)
             (display " got ") (write got) (newline))))
(define (check-true name val)
  (if val (set! pass (+ pass 1))
      (begin (set! fail (+ fail 1)) (display "FAIL: ") (display name) (newline))))
(define (check-false name val)
  (if (not val) (set! pass (+ pass 1))
      (begin (set! fail (+ fail 1)) (display "FAIL: ") (display name) (newline))))

;;; =====================================================
;;; vm.zig coverage — uncommon opcodes and paths
;;; =====================================================

;;; ---- call_global optimization ----
(define (global-add a b) (+ a b))
(check "call_global" (global-add 3 4) 7)

;;; ---- Variadic function with apply ----
(define (variadic-fn . xs) (length xs))
(check "variadic apply" (apply variadic-fn '(1 2 3)) 3)
(check "variadic mixed" (apply variadic-fn 1 '(2 3)) 3)

;;; ---- Multiple return values via receive ----
(define (multi-ret) (values 'a 'b 'c))
(call-with-values multi-ret
  (lambda (x y z) (check "multi-values" (list x y z) '(a b c))))

;;; ---- Dynamic-wind with exception ----
(let ((log '()))
  (guard (e (#t #f))
    (dynamic-wind
      (lambda () (set! log (cons 'in log)))
      (lambda () (error "boom"))
      (lambda () (set! log (cons 'out log)))))
  (check-true "dw exception out" (memq 'out log))
  (check-true "dw exception in" (memq 'in log)))

;;; ---- Dynamic-wind with call/cc escape ----
(let ((k-saved #f)
      (log '()))
  (dynamic-wind
    (lambda () (set! log (cons 'in log)))
    (lambda ()
      (call-with-current-continuation
        (lambda (k) (set! k-saved k)))
      (set! log (cons 'body log)))
    (lambda () (set! log (cons 'out log))))
  (check-true "dw callcc first" (memq 'body log))
  ;; Re-invoke continuation
  (when (< (length log) 10)
    (k-saved #f))
  (check-true "dw callcc re-entry" (> (length log) 3)))

;;; ---- error in tail position ----
(define (error-tail n)
  (if (= n 0)
      (guard (e (#t 'caught)) (error "tail"))
      (error-tail (- n 1))))
(check "error in tail" (error-tail 100) 'caught)

;;; ---- Recursive closures ----
(define make-fib
  (lambda ()
    (letrec ((fib (lambda (n)
                    (if (< n 2) n
                        (+ (fib (- n 1)) (fib (- n 2)))))))
      fib)))
(check "recursive closure" ((make-fib) 10) 55)

;;; =====================================================
;;; vm_library.zig / library.zig coverage
;;; =====================================================

;;; ---- Load various SRFIs to exercise library loading paths ----
(import (srfi 14))
(check-true "srfi 14 loaded" (char-set? char-set:letter))

(import (srfi 26))
(check "srfi 26 cut" ((cut + 1 <>) 2) 3)

(import (srfi 8))
(receive (a b c) (values 1 2 3)
  (check "srfi 8 receive" (+ a b c) 6))

;;; ---- include top-level form ----
(include "tests/scheme/coverage/_include-helper.scm")
(check "include" include-helper-value 99)

;;; ---- cond-expand features ----
(check "ce ieee-float" (cond-expand (ieee-float 'yes) (else 'no)) 'yes)
(check "ce exact-closed" (cond-expand (exact-closed 'yes) (else 'no)) 'yes)
(check "ce ratios" (cond-expand (ratios 'yes) (else 'no)) 'no)

;;; =====================================================
;;; primitives_io.zig coverage — deeper paths
;;; =====================================================

;;; ---- write-string edge cases ----
(let ((p (open-output-string)))
  (write-string "" p)
  (check "write-string empty" (get-output-string p) ""))

(let ((p (open-output-string)))
  (write-string "hello" p 5 5)
  (check "write-string zero range" (get-output-string p) ""))

;;; ---- Binary port operations ----
(let ((p (open-input-bytevector #u8())))
  (check-true "empty bv eof" (eof-object? (read-u8 p))))

(let ((p (open-output-bytevector)))
  (write-bytevector #u8() p)
  (check "write empty bv" (get-output-bytevector p) #u8()))

;;; ---- read various S-expressions ----
(let ((p (open-input-string "#| nested #| comment |# |# 42")))
  (check "nested block comment" (read p) 42))

(let ((p (open-input-string "#;(skip) 99")))
  (check "datum comment" (read p) 99))

;;; ---- write-shared on non-shared ----
(let ((p (open-output-string)))
  (write-shared '(1 2 3) p)
  (check "write-shared no sharing" (get-output-string p) "(1 2 3)"))

;;; =====================================================
;;; printer.zig coverage — special types
;;; =====================================================

;;; ---- Print hash tables ----
(let ((ht (make-hash-table))
      (p (open-output-string)))
  (hash-table-set! ht 'a 1)
  (display ht p)
  (check-true "display hash-table" (string? (get-output-string p))))

;;; ---- Print channels ----
(import (kaappi fibers))
(let ((ch (make-channel))
      (p (open-output-string)))
  (display ch p)
  (check-true "display channel" (string? (get-output-string p))))

;;; ---- Print random source ----
(let ((rs (make-random-source))
      (p (open-output-string)))
  (display rs p)
  (check-true "display random-source" (string? (get-output-string p))))

;;; =====================================================
;;; primitives_control.zig coverage
;;; =====================================================

;;; ---- raise-continuable with handler ----
(check "raise-continuable result"
  (with-exception-handler
    (lambda (e) (* e 10))
    (lambda () (+ 1 (raise-continuable 5))))
  51)

;;; ---- dynamic-wind normal ----
(let ((result '()))
  (dynamic-wind
    (lambda () (set! result (cons 'before result)))
    (lambda () (set! result (cons 'during result)) 42)
    (lambda () (set! result (cons 'after result))))
  (check "dw normal order" (reverse result) '(before during after)))

;;; ---- values with different arities ----
(check "values 0"
  (call-with-values (lambda () (values)) (lambda () 'zero))
  'zero)
(check "values 1" (call-with-values (lambda () (values 42)) values) 42)
(check "values 2" (call-with-values (lambda () (values 1 2)) +) 3)
(check "values 5" (call-with-values (lambda () (values 1 2 3 4 5)) +) 15)

;;; =====================================================
;;; primitives_arithmetic.zig — remaining gaps
;;; =====================================================

;;; ---- abs on various types ----
(check "abs fixnum neg" (abs -42) 42)
(check "abs fixnum pos" (abs 42) 42)
(check "abs flonum neg" (abs -3.14) 3.14)
(check "abs flonum pos" (abs 3.14) 3.14)
(check "abs zero" (abs 0) 0)

;;; ---- number? / complex? / real? / rational? / integer? ----
(check-true "number? fixnum" (number? 42))
(check-true "number? flonum" (number? 3.14))
(check-true "number? complex" (number? 1+2i))
(check-true "number? rational" (number? 1/3))
(check-true "complex? fixnum" (complex? 42))
(check-true "complex? complex" (complex? 1+2i))
(check-true "real? fixnum" (real? 42))
(check-true "real? flonum" (real? 3.14))
(check-false "real? complex" (real? 1+2i))
(check-true "rational? fixnum" (rational? 42))
(check-true "rational? rational" (rational? 1/3))
(check-true "integer? fixnum" (integer? 42))
(check-false "integer? rational" (integer? 1/3))
(check-true "integer? 1.0" (integer? 1.0))
(check-false "integer? 1.5" (integer? 1.5))

;;; ---- square ----
(check "square 5" (square 5) 25)
(check "square -3" (square -3) 9)
(check "square 0" (square 0) 0)

;;; =====================================================
;;; memory.zig / types.zig coverage
;;; =====================================================

;;; ---- GC stress with many types ----
(let loop ((i 0))
  (when (< i 1000)
    (cons i (make-list 5 i))
    (vector i i i)
    (string-append "a" (number->string i))
    (loop (+ i 1))))
(check-true "GC stress" #t)

;;; ---- Symbol interning ----
(check-true "symbol eq?" (eq? 'hello 'hello))
(check-true "symbol eq? string->symbol"
  (eq? 'hello (string->symbol "hello")))
(check "symbol->string" (symbol->string 'hello) "hello")

;;; =====================================================
;;; primitives_list.zig — remaining
;;; =====================================================
(check "memq" (memq 'b '(a b c)) '(b c))
(check-false "memq miss" (memq 'z '(a b c)))
(check "memv" (memv 2 '(1 2 3)) '(2 3))
(check "assq" (assq 'b '((a . 1) (b . 2) (c . 3))) '(b . 2))
(check-false "assq miss" (assq 'z '((a . 1))))
(check "list-set!" (let ((l (list 1 2 3))) (list-set! l 1 99) l) '(1 99 3))

;;; =====================================================
;;; primitives_lazy.zig — delay-force
;;; =====================================================
(check "delay-force simple"
  (force (delay-force (delay 42)))
  42)

(let ((p (delay-force (delay (+ 1 2)))))
  (check "delay-force chain" (force p) 3))

;;; =====================================================
;;; reader_tokens.zig — edge cases
;;; =====================================================
(let ((p (open-input-string "#| comment |# hello")))
  (check "block comment before symbol" (read p) 'hello))
(let ((p (open-input-string "(a . b)")))
  (check "dotted pair read" (read p) '(a . b)))
(let ((p (open-input-string "#\\x3BB")))
  (check "unicode hex char" (read p) #\λ))

;;; =====================================================
;;; More cxr compositions
;;; =====================================================
(check "caadr" (caadr '(1 (2 3))) 2)
(check "cdadr" (cdadr '(1 (2 3))) '(3))
(check "cddar" (cddar '((1 2 3))) '(3))
(check "cdddr" (cdddr '(1 2 3 4 5)) '(4 5))
(check "caaaar" (caaaar '((((1))))) 1)
(check "cdaaar" (cdaaar '((((1 2))))) '(2))
(check "cadaar" (cadaar '(((1 2)))) 2)
(check "cddaar" (cddaar '(((1 2 3)))) '(3))
(check "caadar" (caadar '((1 (2 3)))) 2)
(check "cdadar" (cdadar '((1 (2 3)))) '(3))
(check "caddar" (caddar '((1 2 3))) 3)
(check "cdddar" (cdddar '((1 2 3 4))) '(4))
(check "caaadr" (caaadr '(1 ((2)))) 2)
(check "cdaadr" (cdaadr '(1 ((2 3)))) '(3))
(check "cadadr" (cadadr '(1 (2 3))) 3)
(check "cddadr" (cddadr '(1 (2 3 4))) '(4))
(check "caaddr" (caaddr '(1 2 (3 4))) 3)
(check "cdaddr" (cdaddr '(1 2 (3 4))) '(4))
(check "cadddr" (cadddr '(1 2 3 4 5)) 4)
(check "cddddr" (cddddr '(1 2 3 4 5)) '(5))

;;; =====================================================
;;; Various compiler forms coverage
;;; =====================================================

;;; ---- letrec* ----
(check "letrec*" (letrec* ((x 1) (y (+ x 1))) (+ x y)) 3)

;;; ---- do loop ----
(check "do loop"
  (do ((i 0 (+ i 1))
       (sum 0 (+ sum i)))
      ((= i 10) sum))
  45)

;;; ---- case with => ----
(check "case =>"
  (case (* 2 3)
    ((6) => (lambda (v) (* v 10)))
    (else 'no))
  60)

;;; ---- when/unless ----
(check "when true" (when #t 42) 42)
(check "unless false" (unless #f 42) 42)

;;; ---- guard with cond-like clauses ----
(check "guard multi clause"
  (guard (e
          ((string? e) 'string)
          ((number? e) 'number)
          (#t 'other))
    (raise 42))
  'number)

;;; ---- define-values edge cases ----
;; define-values with rest formals
(define-values (dvr-a dvr-b . dvr-rest) (values 10 20 30 40 50))
(check "define-values rest a" dvr-a 10)
(check "define-values rest b" dvr-b 20)
(check "define-values rest rest" dvr-rest '(30 40 50))

;; define-values with single symbol (collects to list)
(define-values dvr-all (values 1 2 3))
(check "define-values single sym" dvr-all '(1 2 3))

;; define-values single value, single formals
(define-values (dvr-q) 42)
(check "define-values single val" dvr-q 42)

;;; ---- Nested quasiquote ----
(let ((x 1) (y '(2 3)))
  (check "nested quasi" `(,x ,@y 4) '(1 2 3 4)))

;;; ---- String mutation ----
(let ((s (string-copy "hello")))
  (string-set! s 0 #\H)
  (check "string-set!" s "Hello"))

(let ((s (string-copy "hello world")))
  (string-copy! s 0 "HELLO" 0 5)
  (check "string-copy! range" s "HELLO world"))

;;; ---- Bytevector operations ----
(let ((bv (bytevector-copy #u8(1 2 3 4 5))))
  (bytevector-copy! bv 1 #u8(10 20) 0 2)
  (check "bytevector-copy!" bv #u8(1 10 20 4 5)))

;;; Summary
(display pass) (display " passed, ") (display fail) (display " failed")
(newline)
(if (> fail 0) (error "Deep coverage tests failed" fail))
