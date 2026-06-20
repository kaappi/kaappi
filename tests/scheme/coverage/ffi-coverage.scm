(import (scheme base) (scheme write))

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
(define (check-approx name got expected eps)
  (if (< (abs (- got expected)) eps) (set! pass (+ pass 1))
      (begin (set! fail (+ fail 1))
             (display "FAIL: ") (display name)
             (display " expected ~") (write expected)
             (display " got ") (write got) (newline))))

(define lib (ffi-open "tests/ffi/libtest_kaappi"))
(check-true "ffi-open" lib)

;;; ==============================================================
;;; 0-arg functions (callFfi0)
;;; ==============================================================

;; void -> void
(define c-noop (ffi-fn lib "do_nothing" '() 'void))
(c-noop)
(check-true "ffi 0-arg void" #t)

;; void -> int
(define c-get-zero (ffi-fn lib "get_zero" '() 'int))
(check "ffi 0-arg int 0" (c-get-zero) 0)
(define c-get-42 (ffi-fn lib "get_fortytwo" '() 'int))
(check "ffi 0-arg int 42" (c-get-42) 42)

;; void -> long
(define c-get-long (ffi-fn lib "get_long_max" '() 'long))
(check "ffi 0-arg long" (c-get-long) 9999999)

;; void -> double
(define c-get-pi (ffi-fn lib "get_pi" '() 'double))
(check-approx "ffi 0-arg double" (c-get-pi) 3.14159265 0.001)

;; void -> string
(define c-greeting (ffi-fn lib "get_greeting" '() 'string))
(check "ffi 0-arg string" (c-greeting) "hello from C")

;;; ==============================================================
;;; 1-arg functions (callFfi1)
;;; ==============================================================

;; int -> int
(define c-negate (ffi-fn lib "negate" '(int) 'int))
(check "ffi 1i-i negate" (c-negate 5) -5)
(check "ffi 1i-i abs" ((ffi-fn lib "abs_val" '(int) 'int) -7) 7)

;; int -> long
(define c-itol (ffi-fn lib "int_to_long" '(int) 'long))
(check "ffi 1i-l" (c-itol 42) 42)

;; int -> double — not a supported dispatch combo, skip

;; int -> void
(define c-ci (ffi-fn lib "consume_int" '(int) 'void))
(c-ci 42)
(check-true "ffi 1i-v" #t)

;; long -> long
(define c-idlong (ffi-fn lib "identity_long" '(long) 'long))
(check "ffi 1l-l" (c-idlong 99) 99)

;; long -> void
(define c-cl (ffi-fn lib "consume_long" '(long) 'void))
(c-cl 99)
(check-true "ffi 1l-v" #t)

;; double -> double
(define c-idd (ffi-fn lib "identity_double" '(double) 'double))
(check "ffi 1d-d" (c-idd 3.14) 3.14)

;; double -> int
(define c-dtoi (ffi-fn lib "double_to_int" '(double) 'int))
(check "ffi 1d-i" (c-dtoi 3.7) 3)

;; double -> void
(define c-cd (ffi-fn lib "consume_double" '(double) 'void))
(c-cd 1.5)
(check-true "ffi 1d-v" #t)

;; float -> float
(define c-idf (ffi-fn lib "identity_float" '(float) 'float))
(check-approx "ffi 1f-f" (c-idf 2.5) 2.5 0.01)

;; string -> int
(define c-strlen (ffi-fn lib "string_length" '(string) 'int))
(check "ffi 1s-i" (c-strlen "hello") 5)

;; string -> long
(define c-strl (ffi-fn lib "string_length_long" '(string) 'long))
(check "ffi 1s-l" (c-strl "abc") 3)

;; string -> void
(define c-cs (ffi-fn lib "consume_string" '(string) 'void))
(c-cs "test")
(check-true "ffi 1s-v" #t)

;; string -> double
(define c-stod (ffi-fn lib "string_to_double" '(string) 'double))
(check-approx "ffi 1s-d" (c-stod "3.14") 3.14 0.01)

;;; ==============================================================
;;; 2-arg functions (callFfi2)
;;; ==============================================================

;; (int, int) -> int
(define c-add (ffi-fn lib "add_ints" '(int int) 'int))
(check "ffi 2ii-i" (c-add 3 4) 7)

;; (int, int) -> long
(define c-add-il (ffi-fn lib "add_ints_long" '(int int) 'long))
(check "ffi 2ii-l" (c-add-il 100 200) 300)

;; (int, int) -> void
(define c-c2i (ffi-fn lib "consume_two_ints" '(int int) 'void))
(c-c2i 1 2)
(check-true "ffi 2ii-v" #t)

;; (double, double) -> double
(define c-add-dd (ffi-fn lib "add_doubles" '(double double) 'double))
(check "ffi 2dd-d" (c-add-dd 1.5 2.5) 4.0)

;; (double, double) -> int
(define c-cmp-dd (ffi-fn lib "compare_doubles" '(double double) 'int))
(check "ffi 2dd-i less" (c-cmp-dd 1.0 2.0) -1)
(check "ffi 2dd-i greater" (c-cmp-dd 2.0 1.0) 1)
(check "ffi 2dd-i equal" (c-cmp-dd 1.0 1.0) 0)

;; (double, double) -> void
(define c-c2d (ffi-fn lib "consume_two_doubles" '(double double) 'void))
(c-c2d 1.0 2.0)
(check-true "ffi 2dd-v" #t)

;; (long, long) -> long
(define c-add-ll (ffi-fn lib "add_longs" '(long long) 'long))
(check "ffi 2ll-l" (c-add-ll 100 200) 300)

;; (string, string) -> int
(define c-strcmp (ffi-fn lib "strcmp_wrap" '(string string) 'int))
(check "ffi 2ss-i equal" (c-strcmp "abc" "abc") 0)
(check-true "ffi 2ss-i less" (< (c-strcmp "abc" "def") 0))

;; (string, string) -> long
(define c-slensum (ffi-fn lib "strlen_sum" '(string string) 'long))
(check "ffi 2ss-l" (c-slensum "abc" "defgh") 8)

;; (string, string) -> void
(define c-c2s (ffi-fn lib "consume_two_strings" '(string string) 'void))
(c-c2s "a" "b")
(check-true "ffi 2ss-v" #t)

;;; ==============================================================
;;; 3-arg functions (callFfi3)
;;; ==============================================================

;; (int, int, int) -> int
(define c-sum3 (ffi-fn lib "sum3" '(int int int) 'int))
(check "ffi 3iii-i" (c-sum3 1 2 3) 6)

;; 3-arg long and double combos not in dispatch table, skip

;; (int, int, int) -> int (different function)
(define c-clamp (ffi-fn lib "clamp" '(int int int) 'int))
(check "ffi clamp low" (c-clamp 0 5 10) 5)
(check "ffi clamp high" (c-clamp 15 5 10) 10)
(check "ffi clamp mid" (c-clamp 7 5 10) 7)

;; (double, double, double) -> double
(define c-sum3d (ffi-fn lib "sum3_double" '(double double double) 'double))
(check "ffi 3ddd-d" (c-sum3d 1.0 2.0 3.0) 6.0)

;; (string, int, int) -> int
(define c-substr (ffi-fn lib "substr_char" '(string int int) 'int))
(check "ffi 3sii-i" (c-substr "hello" 0 0) 104) ;; 'h' = 104

;; (string, string, int) -> int
(define c-strncmp (ffi-fn lib "strncmp_wrap" '(string string int) 'int))
(check "ffi 3ssi-i equal" (c-strncmp "abc" "abc" 3) 0)
(check-true "ffi 3ssi-i diff" (not (= (c-strncmp "abc" "xyz" 3) 0)))

;;; ==============================================================
;;; 4-arg functions (callFfi4)
;;; ==============================================================

;; (int, int, int, int) -> int
(define c-sum4 (ffi-fn lib "sum4" '(int int int int) 'int))
(check "ffi 4iiii-i" (c-sum4 1 2 3 4) 10)

;; (double, double, double, double) -> double
(define c-sum4d (ffi-fn lib "sum4_double" '(double double double double) 'double))
(check "ffi 4dddd-d" (c-sum4d 1.0 2.0 3.0 4.0) 10.0)

;;; ==============================================================
;;; Pointer-type functions
;;; ==============================================================

;; pointer -> pointer
(define c-id-ptr (ffi-fn lib "identity_ptr" '(pointer) 'pointer))
(let ((bv #u8(1 2 3)))
  (let ((ptr (ffi-bytevector-ptr bv)))
    (check-true "ffi ptr->ptr" (number? (c-id-ptr ptr)))))

;; pointer -> int
(define c-ptr-null (ffi-fn lib "ptr_is_null" '(pointer) 'int))
(check "ffi ptr null" (c-ptr-null 0) 1)
(check "ffi ptr nonnull" (c-ptr-null (ffi-bytevector-ptr #u8(1))) 0)

;; pointer -> void
(define c-consume-ptr (ffi-fn lib "consume_ptr" '(pointer) 'void))
(c-consume-ptr 0)
(check-true "ffi ptr->void" #t)

;; pointer -> long — not in dispatch table
;; int -> pointer — not in dispatch table
;; long -> pointer — not in dispatch table

;; string -> pointer
(define c-str-ptr (ffi-fn lib "str_to_ptr" '(string) 'pointer))
(check-true "ffi str->ptr" (number? (c-str-ptr "hello")))

;; (pointer, pointer) -> int
(define c-pp-cmp (ffi-fn lib "ptr_ptr_cmp" '(pointer pointer) 'int))
(check "ffi pp->int same" (c-pp-cmp 0 0) 1)

;; (pointer, pointer) -> pointer
(define c-pp-first (ffi-fn lib "ptr_ptr_first" '(pointer pointer) 'pointer))
(check "ffi pp->ptr" (c-pp-first 0 0) 0)

;; (pointer, pointer) -> void
(define c-pp-void (ffi-fn lib "consume_ptr_ptr" '(pointer pointer) 'void))
(c-pp-void 0 0)
(check-true "ffi pp->void" #t)

;; (pointer, int) -> int
(define c-pi-sum (ffi-fn lib "ptr_int_sum" '(pointer int) 'int))
(check "ffi pi->int" (c-pi-sum 0 42) 42)

;; (pointer, int) -> void
(define c-pi-void (ffi-fn lib "ptr_int_noop" '(pointer int) 'void))
(c-pi-void 0 1)
(check-true "ffi pi->void" #t)

;; (int, pointer) -> int
(define c-ip-sum (ffi-fn lib "int_ptr_sum" '(int pointer) 'int))
(check "ffi ip->int" (c-ip-sum 99 0) 99)

;; (int, pointer) -> void
(define c-ip-void (ffi-fn lib "int_ptr_noop" '(int pointer) 'void))
(c-ip-void 1 0)
(check-true "ffi ip->void" #t)

;; (pointer, long) -> long
(define c-pl-sum (ffi-fn lib "ptr_long_sum" '(pointer long) 'long))
(check "ffi pl->long" (c-pl-sum 0 77) 77)

;; (string, string) -> pointer
(define c-ss-ptr (ffi-fn lib "str_str_ptr" '(string string) 'pointer))
(check-true "ffi ss->ptr" (number? (c-ss-ptr "a" "b")))

;;; ==============================================================
;;; ffi-open with #f (default process)
;;; ==============================================================
(define default-lib (ffi-open #f))
(define c-abs-libc (ffi-fn default-lib "abs" '(int) 'int))
(check "ffi libc abs" (c-abs-libc -42) 42)
(ffi-close default-lib)

;;; ==============================================================
;;; ffi-callback? predicate
;;; ==============================================================
(check-false "ffi-callback? num" (ffi-callback? 42))
(check-false "ffi-callback? str" (ffi-callback? "x"))

;;; ==============================================================
;;; ffi-bytevector-ptr
;;; ==============================================================
(check-true "ffi-bv-ptr" (> (ffi-bytevector-ptr #u8(1 2 3)) 0))
(check "ffi-bv-ptr empty" (ffi-bytevector-ptr #u8()) 0)

;;; ==============================================================
;;; Cleanup
;;; ==============================================================
(ffi-close lib)

;;; Summary
(display pass) (display " passed, ") (display fail) (display " failed")
(newline)
(if (> fail 0) (error "FFI coverage tests failed" fail))
