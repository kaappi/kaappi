(define libm (ffi-open "libm"))
(define c-sqrt (ffi-fn libm "sqrt" '(double) 'double))
(display (c-sqrt 4.0))     ; 2.0
(newline)
(display (c-sqrt 2.0))     ; 1.4142135623730951
(newline)

(define c-ceil (ffi-fn libm "ceil" '(double) 'double))
(display (c-ceil 3.2))     ; 4.0
(newline)

(define c-pow (ffi-fn libm "pow" '(double double) 'double))
(display (c-pow 2.0 10.0)) ; 1024.0
(newline)

(ffi-close libm)
(display "FFI tests passed")
(newline)
