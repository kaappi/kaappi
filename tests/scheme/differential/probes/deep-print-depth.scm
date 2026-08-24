;; Probe: printing depth across execution tiers (kaappi#2107).
;;
;; write/display of an 848-deep car-nested structure aborted the whole wasm32
;; module (out-of-bounds shadow-stack access) while native printed it fine:
;; the printer recursed on the native stack and its depth guard was
;; calibrated to the native 64 MB stack, which the wasm module did not have.
;; The printer is iterative now and the wasm module carries the same 64 MB
;; stack, so both tiers must produce byte-identical output at every depth
;; here — 847/848 straddle the old wasm cliff, 1023/1024/1025 the old
;; MAX_PRINT_DEPTH truncation cliff, and 20000 is far past both.
;;
;; No imports: (scheme base)/(scheme write) bindings are ambient in a main
;; script, and this probe must stay runnable on every execution tier.

(define (nest n acc) (if (= n 0) acc (nest (- n 1) (list acc))))

(define (probe n)
  (let ((p (open-output-string)))
    (write (nest n '()) p)
    (let ((s (get-output-string p)))
      (display n) (display " -> len=") (display (string-length s)) (newline))))

(probe 10)
(probe 847)
(probe 848)
(probe 1023)
(probe 1024)
(probe 1025)
(probe 20000)

;; The guard-visibility half of the finding: on wasm the abort was
;; uncatchable, so this printed nothing past "before".  Both tiers must
;; agree on the full transcript now.
(display "before") (newline)
(display (guard (e (#t "CAUGHT"))
  (let ((p (open-output-string))) (write (nest 2000 '()) p) "no-error")))
(newline)
(display "after") (newline)

;; Cyclic structure through an error object (kaappi#1954) — same output on
;; both tiers, and terminates on both.
(define c (list 1 2 3))
(set-cdr! (cddr c) c)
(write (guard (e (#t e)) (error "boom" c))) (newline)
