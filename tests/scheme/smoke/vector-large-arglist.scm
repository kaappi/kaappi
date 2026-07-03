;; Regression test for issue #802: >255 vector args overflow fixed
;; 256-slot arg buffers in vector-map/for-each/count/any/every/index/
;; index-right/unfold/unfold-right — interpreter aborts.
;;
;; All callbacks here are native functions (e.g. +) to avoid the
;; callWithArgs 255-arg closure limit.

(import (scheme base) (scheme write) (srfi 133))

;; Helper: build a list of n copies of x
(define (copies n x)
  (if (= n 0) '() (cons x (copies (- n 1) x))))

;; ---------- vector-map ----------
(let ((result (apply vector-map (cons + (copies 300 #(1 2))))))
  (unless (and (= (vector-ref result 0) 300)
               (= (vector-ref result 1) 600))
    (error "vector-map with 300 vectors failed" result)))

;; ---------- vector-for-each ----------
;; Use native + as callback (closures are limited to 255 args by callWithArgs).
;; Just verify no crash — result is discarded.
(apply vector-for-each (cons + (copies 300 #(1))))

;; ---------- vector-count ----------
(let ((n (apply vector-count (cons + (copies 300 #(1))))))
  (unless (= n 1)
    (error "vector-count with 300 vectors failed" n)))

;; ---------- vector-any ----------
(let ((r (apply vector-any (cons + (copies 300 #(1))))))
  (unless r
    (error "vector-any with 300 vectors failed")))

;; ---------- vector-every ----------
(let ((r (apply vector-every (cons + (copies 300 #(1))))))
  (unless r
    (error "vector-every with 300 vectors failed")))

;; ---------- vector-index ----------
(let ((r (apply vector-index (cons + (copies 300 #(1))))))
  (unless (= r 0)
    (error "vector-index with 300 vectors failed" r)))

;; ---------- vector-index-right ----------
(let ((r (apply vector-index-right (cons + (copies 300 #(1))))))
  (unless (= r 0)
    (error "vector-index-right with 300 vectors failed" r)))

;; ---------- vector-unfold ----------
;; (vector-unfold + 3 seed0 seed1 ... seed299)
;; + receives (index seed0 ... seed299), returns index + sum-of-seeds.
;; Seeds are all 0, so result is #(0 1 2).
(let ((result (apply vector-unfold (cons + (cons 3 (copies 300 0))))))
  (unless (and (= (vector-ref result 0) 0)
               (= (vector-ref result 1) 1)
               (= (vector-ref result 2) 2))
    (error "vector-unfold with 300 seeds failed" result)))

;; ---------- vector-unfold-right ----------
(let ((result (apply vector-unfold-right (cons + (cons 3 (copies 300 0))))))
  (unless (and (= (vector-ref result 0) 0)
               (= (vector-ref result 1) 1)
               (= (vector-ref result 2) 2))
    (error "vector-unfold-right with 300 seeds failed" result)))

(display "vector-large-arglist: all 9 functions passed")
(newline)
