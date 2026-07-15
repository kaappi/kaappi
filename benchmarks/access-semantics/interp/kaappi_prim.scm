;; Real-Kaappi primitive throughput for the P1 interpreter-tier control
;; (memo §9.4). Measures ns per bytevector-u8-ref / -set! call on the actual VM
;; -- establishing the true dispatch-cost scale. The plain-vs-unordered access
;; annotation changes only the single machine load/store inside the primitive
;; body (asm proves an aligned unordered access is the *same instruction* as
;; plain), so the annotation's cost is a sub-nanosecond fraction of the ns/call
;; measured here. Run: kaappi kaappi_prim.scm
(import (scheme base) (scheme time) (scheme write))

(define n 200000)
(define reps 100)
(define bv (make-bytevector n 0))

(define (bench-ref)
  (let loop ((r 0) (acc 0))
    (if (= r reps)
        acc
        (loop (+ r 1)
              (let iloop ((i 0) (a acc))
                (if (= i n)
                    a
                    (iloop (+ i 1) (+ a (bytevector-u8-ref bv i)))))))))

(define (bench-set)
  (let loop ((r 0))
    (if (= r reps)
        'done
        (begin
          (let iloop ((i 0))
            (if (= i n)
                #t
                (begin
                  (bytevector-u8-set! bv i (modulo i 256))
                  (iloop (+ i 1)))))
          (loop (+ r 1))))))

;; warm up the caches / any lazy state
(bench-ref)
(bench-set)

(define jps (exact->inexact (jiffies-per-second)))
(define calls (* n reps))

(define t0 (current-jiffy))
(define guard (bench-ref))
(define t1 (current-jiffy))
(bench-set)
(define t2 (current-jiffy))

(define (ns-per-call j0 j1)
  (/ (* 1e9 (exact->inexact (- j1 j0))) jps calls))

(display "bytevector-u8-ref  ns/call: ")
(display (ns-per-call t0 t1))
(newline)
(display "bytevector-u8-set! ns/call: ")
(display (ns-per-call t1 t2))
(newline)
(display "calls-per-measurement: ")
(display calls)
(newline)
;; keep the ref result live so nothing is elided (interpreter: belt-and-braces)
(if (< guard 0) (display "unreachable"))
