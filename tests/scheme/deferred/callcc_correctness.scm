; call/cc correctness checks (escape, multi-shot re-entry, dynamic-wind)

; 1. Simple escape continuation
(display (+ 1 (call/cc (lambda (k) (k 10)))))   ; expect 11
(newline)

; 2. call/cc that is NOT invoked (proc returns normally)
(display (call/cc (lambda (k) 42)))             ; expect 42
(newline)

; 3. Deep non-tail context, escaping out of nested calls
(define (sum-to n k)
  (if (= n 0)
      (k 'done)
      (+ n (sum-to (- n 1) k))))
(display (call/cc (lambda (k) (sum-to 20 k))))  ; expect done
(newline)

; 4. Multi-shot re-entry: classic generator-style counter using a saved cont
(define k-saved #f)
(define count 0)
(define result
  (+ 1 (call/cc (lambda (k) (set! k-saved k) 0))))
(set! count (+ count 1))
(if (< count 4) (k-saved count))               ; re-enter 3 times
(display (list 'count count 'result result))   ; expect (count 4 result 4)
(newline)

; 5. dynamic-wind ordering with continuation escape
(define trace '())
(define (note x) (set! trace (cons x trace)))
(call/cc
 (lambda (k)
   (dynamic-wind
     (lambda () (note 'before))
     (lambda () (note 'during) (k 'out) (note 'never))
     (lambda () (note 'after)))))
(display (reverse trace))                       ; expect (before during after)
(newline)
