; call/ec (escape continuation) correctness checks.
; Note: nested *capture* of an outer continuation while an inner one escapes is
; a pre-existing limitation of the continuation machinery (call/cc has it too),
; so these tests exercise escape-only usage, which is what call/ec is for.

; 1. Simple escape
(display (+ 1 (call/ec (lambda (k) (k 10)))))        ; expect 11
(newline)

; 2. proc returns normally (no escape)
(display (call/ec (lambda (k) 42)))                  ; expect 42
(newline)

; 3. Escape out of deep non-tail nesting
(define (sum-to n k)
  (if (= n 0) (k 'done) (+ n (sum-to (- n 1) k))))
(display (call/ec (lambda (k) (sum-to 20 k))))       ; expect done
(newline)

; 4. Escape short-circuits surrounding computation
(display (call/ec (lambda (k) (* 2 (+ 3 (k 99))))))  ; expect 99
(newline)

; 5. dynamic-wind after-thunk runs on escape (before/during/after, not 'never)
(define trace '())
(define (note x) (set! trace (cons x trace)))
(call/ec
 (lambda (k)
   (dynamic-wind
     (lambda () (note 'before))
     (lambda () (note 'during) (k 'out) (note 'never))
     (lambda () (note 'after)))))
(display (reverse trace))                             ; expect (before during after)
(newline)

; 6. Escape as an early-exit "return" from a recursive search
(define (first-even lst)
  (call/ec
   (lambda (return)
     (let loop ((xs lst))
       (cond ((null? xs) #f)
             ((even? (car xs)) (return (car xs)))
             (else (loop (cdr xs))))))))
(display (first-even '(1 3 5 8 9)))                   ; expect 8
(newline)

; 7. Invoking an escape continuation outside its extent raises an error
(define saved #f)
(call/ec (lambda (k) (set! saved k)))                ; capture, then extent ends
(display
 (with-exception-handler
   (lambda (e) 'caught-escape-error)
   (lambda () (saved 'too-late))))                    ; expect caught-escape-error
(newline)
