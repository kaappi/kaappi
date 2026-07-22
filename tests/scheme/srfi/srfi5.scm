;;; Tests for SRFI 5 — A compatible let form with signatures and rest arguments

(import (scheme base) (scheme process-context) (srfi 5) (srfi 64))

(test-begin "srfi-5")

;; Backward compatibility: plain unnamed let still works.
(test-equal "unnamed let, no bindings" 42 (let () 42))
(test-equal "unnamed let, standard bindings" 3 (let ((x 1) (y 2)) (+ x y)))
(test-equal "nested let shadowing" 5
  (let ((x 1))
    (let ((x 2) (y 3))
      (+ x y))))

;; Backward compatibility: classic named let (non-signature, no rest).
(test-equal "classic named let (fibonacci)" 55
  (let fibonacci ((n 10) (i 0) (f0 0) (f1 1))
    (if (= i n) f0 (fibonacci n (+ i 1) f1 (+ f0 f1)))))

;; New: signature-style named let, no rest — same fibonacci, spec example.
(test-equal "signature-style named let (fibonacci)" 55
  (let (fibonacci (n 10) (i 0) (f0 0) (f1 1))
    (if (= i n) f0 (fibonacci n (+ i 1) f1 (+ f0 f1)))))

;; New: unnamed let with one standard binding plus a rest binding.
(test-equal "unnamed let with rest binding" '(1 2 3)
  (let ((x 1) . (rest 2 3))
    (cons x rest)))

;; New: named, non-signature style, with rest argument (spec "blast" shape,
;; adapted to return a value instead of writing to a port).
(test-equal "named let (non-signature) with rest" '(3 4 5)
  (let blast ((acc '()) . (x 3 4 5))
    (if (null? x)
        (reverse acc)
        (apply blast (cons (car x) acc) (cdr x)))))

;; New: named, signature style, with rest argument — the spec's own example.
(test-equal "named let (signature-style) with rest" '(3 4 5)
  (let (blast (acc '()) . (x 3 4 5))
    (if (null? x)
        (reverse acc)
        (apply blast (cons (car x) acc) (cdr x)))))

;; Rest binding with zero extra arguments still collects an empty list.
(test-equal "named let with rest binding and no extra args" '()
  (let (collect (acc '()) . (x))
    (if (null? x) (reverse acc) 'unreachable)))

;; Rest-only named let (no fixed parameters at all).
(test-equal "named let with only a rest binding" '(1 2 3)
  (let (sum-all . (items 1 2 3))
    items))

;; Multi-expression body still works (internal sequencing, not just one form).
(test-equal "signature-style let with multi-expression body" 6
  (let (acc (n 3))
    (define total 0)
    (set! total (+ total n))
    (set! total (+ total n))
    (* total 1)))

(let ((runner (test-runner-current)))
  (test-end "srfi-5")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
